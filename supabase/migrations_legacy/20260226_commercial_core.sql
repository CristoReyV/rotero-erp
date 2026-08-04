-- Migration: Commercial / CRM Core (Pipeline Kanban)

CREATE TABLE IF NOT EXISTS crm_deals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    title text NOT NULL,
    company text,
    contact_name text,
    contact_email text,
    contact_phone text,
    value numeric,
    currency text DEFAULT 'MXN',
    stage text NOT NULL DEFAULT 'lead' CHECK (stage IN ('lead', 'qualified', 'proposal', 'won', 'lost')),
    priority text NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high')),
    owner_user_id uuid, -- Reference to auth.users or similar
    notes text,
    last_touch_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS crm_deals_tenant_stage_idx ON crm_deals(tenant_id, stage);
CREATE INDEX IF NOT EXISTS crm_deals_tenant_updated_idx ON crm_deals(tenant_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS crm_deals_tenant_owner_idx ON crm_deals(tenant_id, owner_user_id);
CREATE INDEX IF NOT EXISTS crm_deals_tenant_email_idx ON crm_deals(tenant_id, contact_email);

CREATE TABLE IF NOT EXISTS crm_deal_activity (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    deal_id uuid NOT NULL REFERENCES crm_deals(id) ON DELETE CASCADE,
    type text NOT NULL CHECK (type IN ('note', 'call', 'email', 'meeting', 'status_change')),
    body text,
    created_by uuid,
    created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS crm_deal_activity_tenant_deal_idx ON crm_deal_activity(tenant_id, deal_id, created_at DESC);

ALTER TABLE crm_deals ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_deal_activity ENABLE ROW LEVEL SECURITY;

-- RLS policies for crm_deals
CREATE POLICY "Users can read crm_deals in their tenants"
ON crm_deals FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = crm_deals.tenant_id
    )
);

CREATE POLICY "Users can insert crm_deals in their tenants"
ON crm_deals FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = crm_deals.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

CREATE POLICY "Users can update crm_deals in their tenants"
ON crm_deals FOR UPDATE
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = crm_deals.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

CREATE POLICY "Users can delete crm_deals in their tenants"
ON crm_deals FOR DELETE
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = crm_deals.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

-- RLS policies for crm_deal_activity
CREATE POLICY "Users can read crm_deal_activity in their tenants"
ON crm_deal_activity FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = crm_deal_activity.tenant_id
    )
);

CREATE POLICY "Users can insert crm_deal_activity in their tenants"
ON crm_deal_activity FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = crm_deal_activity.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

CREATE POLICY "Users can update crm_deal_activity in their tenants"
ON crm_deal_activity FOR UPDATE
USING (
    EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = crm_deal_activity.tenant_id
          AND m.role IN ('admin', 'operator')
    )
);

-- RPC: rpc_list_deals
CREATE OR REPLACE FUNCTION public.rpc_list_deals(p_tenant_id uuid, p_filters jsonb DEFAULT '{}')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', id,
                'title', title,
                'company', company,
                'contact_name', contact_name,
                'contact_email', contact_email,
                'contact_phone', contact_phone,
                'value', value,
                'currency', currency,
                'stage', stage,
                'priority', priority,
                'owner_user_id', owner_user_id,
                'notes', notes,
                'last_touch_at', last_touch_at,
                'created_at', created_at,
                'updated_at', updated_at
            ) ORDER BY updated_at DESC, created_at DESC
        ), '[]'::jsonb)
        FROM crm_deals
        WHERE tenant_id = p_tenant_id
          AND (p_filters->>'stage' IS NULL OR stage = (p_filters->>'stage'))
          AND (p_filters->>'owner' IS NULL OR owner_user_id::text = (p_filters->>'owner'))
          AND (p_filters->>'priority' IS NULL OR priority = (p_filters->>'priority'))
          AND (p_filters->>'searchText' IS NULL OR title ILIKE '%' || (p_filters->>'searchText') || '%' OR company ILIKE '%' || (p_filters->>'searchText') || '%')
    );
END;
$$;

-- RPC: rpc_create_deal
CREATE OR REPLACE FUNCTION public.rpc_create_deal(p_tenant_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_id uuid;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    IF p_payload->>'title' IS NULL OR trim(p_payload->>'title') = '' THEN
        RETURN jsonb_build_object('error', 'title is required');
    END IF;

    INSERT INTO crm_deals (
        tenant_id,
        title,
        company,
        contact_name,
        contact_email,
        contact_phone,
        value,
        currency,
        stage,
        priority,
        notes,
        owner_user_id,
        last_touch_at
    ) VALUES (
        p_tenant_id,
        p_payload->>'title',
        p_payload->>'company',
        p_payload->>'contact_name',
        p_payload->>'contact_email',
        p_payload->>'contact_phone',
        (p_payload->>'value')::numeric,
        COALESCE(p_payload->>'currency', 'MXN'),
        COALESCE(p_payload->>'stage', 'lead'),
        COALESCE(p_payload->>'priority', 'medium'),
        p_payload->>'notes',
        (p_payload->>'owner_user_id')::uuid,
        (p_payload->>'last_touch_at')::timestamptz
    ) RETURNING id INTO new_id;

    RETURN jsonb_build_object('success', true, 'id', new_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- RPC: rpc_update_deal
CREATE OR REPLACE FUNCTION public.rpc_update_deal(p_deal_id uuid, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    cur_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO cur_tenant_id FROM crm_deals WHERE id = p_deal_id;
    IF cur_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = cur_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    IF p_patch ? 'title' THEN UPDATE crm_deals SET title = p_patch->>'title', updated_at = now() WHERE id = p_deal_id; END IF;
    IF p_patch ? 'company' THEN UPDATE crm_deals SET company = p_patch->>'company', updated_at = now() WHERE id = p_deal_id; END IF;
    IF p_patch ? 'contact_name' THEN UPDATE crm_deals SET contact_name = p_patch->>'contact_name', updated_at = now() WHERE id = p_deal_id; END IF;
    IF p_patch ? 'contact_email' THEN UPDATE crm_deals SET contact_email = p_patch->>'contact_email', updated_at = now() WHERE id = p_deal_id; END IF;
    IF p_patch ? 'contact_phone' THEN UPDATE crm_deals SET contact_phone = p_patch->>'contact_phone', updated_at = now() WHERE id = p_deal_id; END IF;
    IF p_patch ? 'value' THEN UPDATE crm_deals SET value = (p_patch->>'value')::numeric, updated_at = now() WHERE id = p_deal_id; END IF;
    IF p_patch ? 'currency' THEN UPDATE crm_deals SET currency = p_patch->>'currency', updated_at = now() WHERE id = p_deal_id; END IF;
    IF p_patch ? 'priority' THEN UPDATE crm_deals SET priority = p_patch->>'priority', updated_at = now() WHERE id = p_deal_id; END IF;
    IF p_patch ? 'notes' THEN UPDATE crm_deals SET notes = p_patch->>'notes', updated_at = now() WHERE id = p_deal_id; END IF;
    IF p_patch ? 'owner_user_id' THEN UPDATE crm_deals SET owner_user_id = (p_patch->>'owner_user_id')::uuid, updated_at = now() WHERE id = p_deal_id; END IF;
    IF p_patch ? 'last_touch_at' THEN UPDATE crm_deals SET last_touch_at = (p_patch->>'last_touch_at')::timestamptz, updated_at = now() WHERE id = p_deal_id; END IF;
    IF p_patch ? 'stage' THEN UPDATE crm_deals SET stage = p_patch->>'stage', updated_at = now() WHERE id = p_deal_id; END IF;

    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- RPC: rpc_move_deal
CREATE OR REPLACE FUNCTION public.rpc_move_deal(p_deal_id uuid, p_new_stage text, p_client_timestamp timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    cur_tenant_id uuid;
    cur_stage text;
BEGIN
    SELECT tenant_id, stage INTO cur_tenant_id, cur_stage FROM crm_deals WHERE id = p_deal_id;
    IF cur_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = cur_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    IF p_new_stage NOT IN ('lead', 'qualified', 'proposal', 'won', 'lost') THEN
        RETURN jsonb_build_object('error', 'invalid_stage');
    END IF;

    IF cur_stage = p_new_stage THEN
        RETURN jsonb_build_object('success', true, 'message', 'already in stage');
    END IF;

    -- Move the deal
    UPDATE crm_deals 
    SET stage = p_new_stage, 
        last_touch_at = COALESCE(p_client_timestamp, now()), 
        updated_at = now() 
    WHERE id = p_deal_id;

    -- Log activity
    INSERT INTO crm_deal_activity (tenant_id, deal_id, type, body, created_by, created_at)
    VALUES (cur_tenant_id, p_deal_id, 'status_change', 'Moved from ' || cur_stage || ' to ' || p_new_stage, auth.uid(), now());

    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;

-- RPC: rpc_add_deal_activity
CREATE OR REPLACE FUNCTION public.rpc_add_deal_activity(p_deal_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    cur_tenant_id uuid;
    new_id uuid;
BEGIN
    SELECT tenant_id INTO cur_tenant_id FROM crm_deals WHERE id = p_deal_id;
    IF cur_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = cur_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    INSERT INTO crm_deal_activity (
        tenant_id,
        deal_id,
        type,
        body,
        created_by
    ) VALUES (
        cur_tenant_id,
        p_deal_id,
        p_payload->>'type',
        p_payload->>'body',
        auth.uid()
    ) RETURNING id INTO new_id;
    
    -- touch the deal
    UPDATE crm_deals SET last_touch_at = now(), updated_at = now() WHERE id = p_deal_id;

    RETURN jsonb_build_object('success', true, 'id', new_id);
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('error', SQLERRM);
END;
$$;
