-- Migration: CRM Advancement + Comments (Step 16)
-- Date: 2026-02-27

-- 1. Tables for Notes and Checklist
CREATE TABLE IF NOT EXISTS crm_deal_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    deal_id UUID NOT NULL REFERENCES crm_deals(id) ON DELETE CASCADE,
    author_user_id UUID NOT NULL,
    note TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS crm_deal_checklist_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    deal_id UUID NOT NULL REFERENCES crm_deals(id) ON DELETE CASCADE,
    stage TEXT NOT NULL,
    label TEXT NOT NULL,
    is_done BOOLEAN DEFAULT false,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Indices for performance
CREATE INDEX IF NOT EXISTS crm_deal_notes_deal_idx ON crm_deal_notes(deal_id);
CREATE INDEX IF NOT EXISTS crm_deal_checklist_deal_idx ON crm_deal_checklist_items(deal_id);

-- 2. RLS Hardening
ALTER TABLE crm_deal_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_deal_checklist_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view deal notes in their tenants" ON crm_deal_notes;
CREATE POLICY "Users can view deal notes in their tenants" 
    ON crm_deal_notes FOR SELECT 
    TO authenticated 
    USING (tenant_id IN (
        SELECT m.tenant_id FROM memberships m WHERE m.user_id = auth.uid()
    ));

DROP POLICY IF EXISTS "Users can view deal checklist in their tenants" ON crm_deal_checklist_items;
CREATE POLICY "Users can view deal checklist in their tenants" 
    ON crm_deal_checklist_items FOR SELECT 
    TO authenticated 
    USING (tenant_id IN (
        SELECT m.tenant_id FROM memberships m WHERE m.user_id = auth.uid()
    ));

-- Note: Mutators are blocked via PostgREST by default (no INSERT/UPDATE/DELETE policy)
-- and handled via SECURITY DEFINER RPCs below.

-- 3. RPCs

-- 3.1 rpc_add_deal_note
CREATE OR REPLACE FUNCTION public.rpc_add_deal_note(
    p_deal_id uuid,
    p_note text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM crm_deals WHERE id = p_deal_id;
    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = v_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    INSERT INTO crm_deal_notes (tenant_id, deal_id, author_user_id, note)
    VALUES (v_tenant_id, p_deal_id, auth.uid(), p_note);

    -- Audit
    INSERT INTO audit_log (tenant_id, entity_type, entity_id, action, actor_email, actor_name, details)
    VALUES (
        v_tenant_id,
        'deal',
        p_deal_id::text,
        'note_added',
        (SELECT email FROM users WHERE id = auth.uid()),
        (SELECT name FROM users WHERE id = auth.uid()),
        jsonb_build_object('note_preview', left(p_note, 50))
    );

    RETURN jsonb_build_object('success', true);
END;
$$;

-- 3.2 rpc_list_deal_notes
CREATE OR REPLACE FUNCTION public.rpc_list_deal_notes(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM crm_deals WHERE id = p_deal_id;
    
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = v_tenant_id
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', n.id,
                'note', n.note,
                'author_name', u.name,
                'created_at', n.created_at
            ) ORDER BY n.created_at DESC
        ), '[]'::jsonb)
        FROM crm_deal_notes n
        JOIN users u ON u.id = n.author_user_id
        WHERE n.deal_id = p_deal_id
    );
END;
$$;

-- 3.3 rpc_seed_checklist_for_deal
CREATE OR REPLACE FUNCTION public.rpc_seed_checklist_for_deal(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id uuid;
    v_stage text;
BEGIN
    SELECT tenant_id, stage INTO v_tenant_id, v_stage FROM crm_deals WHERE id = p_deal_id;
    
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;

    -- Only proceed if checklist for this state doesn't exist already
    IF EXISTS (SELECT 1 FROM crm_deal_checklist_items WHERE deal_id = p_deal_id AND stage = v_stage) THEN
        RETURN jsonb_build_object('success', true, 'msg', 'already_exists');
    END IF;

    -- Seed based on stage
    IF v_stage = 'lead' THEN
        INSERT INTO crm_deal_checklist_items (tenant_id, deal_id, stage, label) VALUES
        (v_tenant_id, p_deal_id, 'lead', 'Identificar necesidades clave'),
        (v_tenant_id, p_deal_id, 'lead', 'Verificar viabilidad técnica/operativa');
    ELSIF v_stage = 'qualified' THEN
        INSERT INTO crm_deal_checklist_items (tenant_id, deal_id, stage, label) VALUES
        (v_tenant_id, p_deal_id, 'qualified', 'Enviar cotización formal'),
        (v_tenant_id, p_deal_id, 'qualified', 'Revisar términos comerciales con cliente');
    ELSIF v_stage = 'proposal' THEN
        INSERT INTO crm_deal_checklist_items (tenant_id, deal_id, stage, label) VALUES
        (v_tenant_id, p_deal_id, 'proposal', 'Realizar presentación ejecutiva'),
        (v_tenant_id, p_deal_id, 'proposal', 'Negociación final de precio y volumen');
    ELSIF v_stage = 'won' THEN
        INSERT INTO crm_deal_checklist_items (tenant_id, deal_id, stage, label) VALUES
        (v_tenant_id, p_deal_id, 'won', 'Recabar firma de contrato / orden de compra'),
        (v_tenant_id, p_deal_id, 'won', 'Alta de cuenta en sistema ERP');
    END IF;

    RETURN jsonb_build_object('success', true);
END;
$$;

-- 3.4 rpc_list_deal_checklist
CREATE OR REPLACE FUNCTION public.rpc_list_deal_checklist(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM crm_deals WHERE id = p_deal_id;
    
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = v_tenant_id
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', id,
                'stage', stage,
                'label', label,
                'is_done', is_done,
                'updated_at', updated_at
            ) ORDER BY stage, label
        ), '[]'::jsonb)
        FROM crm_deal_checklist_items
        WHERE deal_id = p_deal_id
    );
END;
$$;

-- 3.5 rpc_toggle_deal_checklist_item
CREATE OR REPLACE FUNCTION public.rpc_toggle_deal_checklist_item(
    p_item_id uuid,
    p_is_done boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tenant_id uuid;
    v_deal_id uuid;
BEGIN
    SELECT tenant_id, deal_id INTO v_tenant_id, v_deal_id FROM crm_deal_checklist_items WHERE id = p_item_id;
    
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = v_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    UPDATE crm_deal_checklist_items 
    SET is_done = p_is_done, updated_at = now() 
    WHERE id = p_item_id;

    -- Audit
    INSERT INTO audit_log (tenant_id, entity_type, entity_id, action, actor_email, actor_name, details)
    VALUES (
        v_tenant_id,
        'deal',
        v_deal_id::text,
        'checklist_updated',
        (SELECT email FROM users WHERE id = auth.uid()),
        (SELECT name FROM users WHERE id = auth.uid()),
        jsonb_build_object('item_id', p_item_id, 'is_done', p_is_done)
    );

    RETURN jsonb_build_object('success', true);
END;
$$;

-- 4. Hook checklist seeding into rpc_move_deal
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

    -- [NEW] Seed checklist for the new stage
    PERFORM public.rpc_seed_checklist_for_deal(p_deal_id);

    -- Audit
    INSERT INTO audit_log (tenant_id, entity_type, entity_id, action, actor_email, actor_name, details)
    VALUES (
        cur_tenant_id,
        'deal',
        p_deal_id::text,
        'status_changed',
        (SELECT email FROM users WHERE id = auth.uid()),
        (SELECT name FROM users WHERE id = auth.uid()),
        jsonb_build_object('old_stage', cur_stage, 'new_stage', p_new_stage)
    );

    RETURN jsonb_build_object('success', true);
END;
$$;
