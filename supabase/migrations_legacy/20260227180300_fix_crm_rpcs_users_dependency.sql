-- Migration: Fix CRM RPCs — remove phantom 'users' table dependency
-- All audit_log inserts now use real schema (actor_user_id, metadata)
-- All JOINs on users replaced with LEFT JOIN auth.users + raw_user_meta_data
-- Created: 2026-02-27 18:03

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. rpc_add_deal_note — fix audit_log INSERT
-- ═══════════════════════════════════════════════════════════════════════════════
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

    -- Audit (real schema: actor_user_id + metadata)
    INSERT INTO audit_log (tenant_id, actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (
        v_tenant_id,
        auth.uid(),
        'note_added',
        'deal',
        p_deal_id,
        jsonb_build_object('note_preview', left(p_note, 50))
    );

    RETURN jsonb_build_object('success', true);
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. rpc_list_deal_notes — fix JOIN users → LEFT JOIN auth.users
-- ═══════════════════════════════════════════════════════════════════════════════
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
                'author_name', COALESCE(
                    au.raw_user_meta_data->>'full_name',
                    au.raw_user_meta_data->>'name',
                    split_part(au.email, '@', 1),
                    'Usuario'
                ),
                'author_email', au.email,
                'created_at', n.created_at
            ) ORDER BY n.created_at DESC
        ), '[]'::jsonb)
        FROM crm_deal_notes n
        LEFT JOIN auth.users au ON au.id = n.author_user_id
        WHERE n.deal_id = p_deal_id
    );
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. rpc_toggle_deal_checklist_item — fix audit_log INSERT
-- ═══════════════════════════════════════════════════════════════════════════════
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

    -- Audit (real schema)
    INSERT INTO audit_log (tenant_id, actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (
        v_tenant_id,
        auth.uid(),
        'checklist_updated',
        'deal',
        v_deal_id,
        jsonb_build_object('item_id', p_item_id, 'is_done', p_is_done)
    );

    RETURN jsonb_build_object('success', true);
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. rpc_move_deal — fix audit_log INSERT
-- ═══════════════════════════════════════════════════════════════════════════════
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

    -- Seed checklist for the new stage
    PERFORM public.rpc_seed_checklist_for_deal(p_deal_id);

    -- Audit (real schema)
    INSERT INTO audit_log (tenant_id, actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (
        cur_tenant_id,
        auth.uid(),
        'stage_changed',
        'deal',
        p_deal_id,
        jsonb_build_object('old_stage', cur_stage, 'new_stage', p_new_stage)
    );

    RETURN jsonb_build_object('success', true);
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. rpc_get_deal — fix LEFT JOIN users → LEFT JOIN auth.users
-- ═══════════════════════════════════════════════════════════════════════════════
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
        'owner_name', COALESCE(
            au.raw_user_meta_data->>'full_name',
            au.raw_user_meta_data->>'name',
            split_part(au.email, '@', 1),
            'Usuario'
        ),
        'notes', d.notes,
        'last_touch_at', d.last_touch_at,
        'created_at', d.created_at,
        'updated_at', d.updated_at
    ) INTO res
    FROM crm_deals d
    LEFT JOIN auth.users au ON au.id = d.owner_user_id
    WHERE d.id = p_deal_id;

    RETURN res;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. rpc_list_deal_activities — fix LEFT JOIN users → LEFT JOIN auth.users
-- ═══════════════════════════════════════════════════════════════════════════════
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
                'creator_name', COALESCE(
                    au.raw_user_meta_data->>'full_name',
                    au.raw_user_meta_data->>'name',
                    split_part(au.email, '@', 1),
                    'Usuario'
                ),
                'created_at', a.created_at
            ) ORDER BY a.created_at DESC
        ), '[]'::jsonb)
        FROM crm_deal_activity a
        LEFT JOIN auth.users au ON au.id = a.created_by
        WHERE a.deal_id = p_deal_id
    );
END;
$$;


-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
