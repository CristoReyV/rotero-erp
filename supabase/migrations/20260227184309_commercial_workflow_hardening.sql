-- Migration: Commercial Workflow Hardening (RPCs for Detail View)

-- RPC: rpc_get_deal
-- Retrieves a single deal with enriched information, ensuring tenant isolation.
CREATE OR REPLACE FUNCTION public.rpc_get_deal(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    cur_tenant_id uuid;
    res jsonb;
BEGIN
    SELECT tenant_id INTO cur_tenant_id FROM crm_deals WHERE id = p_deal_id;
    IF cur_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = cur_tenant_id
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    SELECT jsonb_build_object(
        'id', d.id,
        'title', d.title,
        'company', d.company,
        'contact_name', d.contact_name,
        'contact_email', d.contact_email,
        'contact_phone', d.contact_phone,
        'value', d.value,
        'currency', d.currency,
        'stage', d.stage,
        'priority', d.priority,
        'owner_user_id', d.owner_user_id,
        'owner_name', u.name,
        'notes', d.notes,
        'last_touch_at', d.last_touch_at,
        'created_at', d.created_at,
        'updated_at', d.updated_at
    ) INTO res
    FROM crm_deals d
    LEFT JOIN users u ON u.id = d.owner_user_id
    WHERE d.id = p_deal_id;

    RETURN res;
END;
$$;


-- RPC: rpc_list_deal_activities
-- Retrieves the history of activities/comments for a given deal.
CREATE OR REPLACE FUNCTION public.rpc_list_deal_activities(p_deal_id uuid)
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
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', a.id,
                'deal_id', a.deal_id,
                'type', a.type,
                'body', a.body,
                'created_by', a.created_by,
                'creator_name', u.name,
                'created_at', a.created_at
            ) ORDER BY a.created_at DESC
        ), '[]'::jsonb)
        FROM crm_deal_activity a
        LEFT JOIN users u ON u.id = a.created_by
        WHERE a.deal_id = p_deal_id
    );
END;
$$;
