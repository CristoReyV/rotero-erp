-- RBAC.3C: reconcile Security authorization and exact EXECUTE ACLs for the
-- frontend-consumed authenticated ERP read surface. Private Tracking RPCs are
-- intentionally excluded because their service_role-only contract is correct.

DO $precheck$
DECLARE
    v_signature text;
BEGIN
    IF to_regprocedure('public.tanda1_user_has_role(uuid,text[])') IS NULL THEN
        RAISE EXCEPTION 'RBAC.3C precheck failed: canonical role helper is missing';
    END IF;

    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_dashboard_overview(uuid,timestamptz,timestamptz)',
        'public.rpc_dashboard_alerts(uuid,timestamptz,timestamptz)',
        'public.rpc_reports_pipeline_summary(uuid)',
        'public.rpc_reports_inventory_summary(uuid)',
        'public.rpc_reports_operations_summary(uuid)',
        'public.rpc_list_inventory_lots(uuid,jsonb)',
        'public.rpc_list_pedimentos(uuid,jsonb)',
        'public.rpc_list_descargo_lines(uuid)',
        'public.rpc_list_deals(uuid,jsonb)',
        'public.rpc_get_deal(uuid)',
        'public.rpc_list_deal_activities(uuid)',
        'public.rpc_list_deal_notes(uuid)',
        'public.rpc_list_deal_checklist(uuid)',
        'public.rpc_get_tenant_settings(uuid)',
        'public.rpc_list_members(uuid)',
        'public.rpc_list_audit_log(uuid,integer,integer,text,text,timestamptz,timestamptz)',
        'public.rpc_list_route_points(uuid,timestamptz,timestamptz,integer)',
        'public.rpc_list_tracking_tokens(uuid)',
        'public.tracking_hash_token(text)',
        'public.tracking_validate_token(text,text)',
        'public.rpc_get_public_tracking(text)',
        'public.rpc_get_driver_view(text)',
        'public.rpc_post_driver_event(text,text,text,numeric,numeric,numeric,text,text,character,text,text,timestamptz,boolean)'
    ] LOOP
        IF to_regprocedure(v_signature) IS NULL THEN
            RAISE EXCEPTION 'RBAC.3C precheck failed: required function is missing: %', v_signature;
        END IF;
    END LOOP;
END;
$precheck$;

CREATE OR REPLACE FUNCTION public.rpc_list_members(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'user_id', m.user_id,
            'role', m.role,
            'created_at', m.created_at,
            'email', u.email,
            'name', u.raw_user_meta_data ->> 'full_name'
        ) ORDER BY m.created_at)
        FROM public.memberships AS m
        JOIN auth.users AS u ON u.id = m.user_id
        WHERE m.tenant_id = p_tenant_id
    ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_audit_log(
    p_tenant_id uuid,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0,
    p_entity_type text DEFAULT NULL,
    p_action text DEFAULT NULL,
    p_start timestamptz DEFAULT NULL,
    p_end timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN jsonb_build_object(
        'items', COALESCE((
            SELECT jsonb_agg(x.row_json ORDER BY x.created_at DESC)
            FROM (
                SELECT
                    a.created_at,
                    jsonb_build_object(
                        'id', a.id,
                        'action', a.action,
                        'entity_type', a.entity_type,
                        'entity_id', a.entity_id,
                        'created_at', a.created_at,
                        'metadata', a.metadata,
                        'actor_id', a.actor_user_id,
                        'actor_email', a.actor_email,
                        'actor_name', a.actor_name
                    ) AS row_json
                FROM public.audit_log AS a
                WHERE a.tenant_id = p_tenant_id
                  AND (p_entity_type IS NULL OR a.entity_type = p_entity_type)
                  AND (p_action IS NULL OR a.action = p_action)
                  AND (p_start IS NULL OR a.created_at >= p_start)
                  AND (p_end IS NULL OR a.created_at <= p_end)
                ORDER BY a.created_at DESC
                LIMIT LEAST(GREATEST(p_limit, 1), 200)
                OFFSET GREATEST(p_offset, 0)
            ) AS x
        ), '[]'::jsonb),
        'total', (
            SELECT count(*)
            FROM public.audit_log AS a
            WHERE a.tenant_id = p_tenant_id
              AND (p_entity_type IS NULL OR a.entity_type = p_entity_type)
              AND (p_action IS NULL OR a.action = p_action)
              AND (p_start IS NULL OR a.created_at >= p_start)
              AND (p_end IS NULL OR a.created_at <= p_end)
        ),
        'distinct_entities', COALESCE((
            SELECT jsonb_agg(x.entity_type)
            FROM (
                SELECT DISTINCT a.entity_type
                FROM public.audit_log AS a
                WHERE a.tenant_id = p_tenant_id
            ) AS x
        ), '[]'::jsonb),
        'distinct_actions', COALESCE((
            SELECT jsonb_agg(x.action)
            FROM (
                SELECT DISTINCT a.action
                FROM public.audit_log AS a
                WHERE a.tenant_id = p_tenant_id
            ) AS x
        ), '[]'::jsonb)
    );
END;
$function$;

-- Normal authenticated ERP read RPCs: exact allowlist, no inherited PUBLIC or
-- service-role execution. Reasserting already-canonical RBAC.3A ACLs keeps the
-- migration explicit and deterministic on drifted staging.
REVOKE EXECUTE ON FUNCTION public.rpc_dashboard_overview(uuid, timestamptz, timestamptz) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_dashboard_alerts(uuid, timestamptz, timestamptz) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_reports_pipeline_summary(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_reports_inventory_summary(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_reports_operations_summary(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_inventory_lots(uuid, jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_pedimentos(uuid, jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_descargo_lines(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_deals(uuid, jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_deal(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_deal_activities(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_deal_notes(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_deal_checklist(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_tenant_settings(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_members(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_audit_log(uuid, integer, integer, text, text, timestamptz, timestamptz) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_route_points(uuid, timestamptz, timestamptz, integer) FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.rpc_dashboard_overview(uuid, timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_dashboard_alerts(uuid, timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_reports_pipeline_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_reports_inventory_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_reports_operations_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_inventory_lots(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_pedimentos(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_descargo_lines(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_deals(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_deal(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_deal_activities(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_deal_notes(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_deal_checklist(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_tenant_settings(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_members(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_audit_log(uuid, integer, integer, text, text, timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_route_points(uuid, timestamptz, timestamptz, integer) TO authenticated;

ALTER FUNCTION public.rpc_list_route_points(uuid, timestamptz, timestamptz, integer)
    SET search_path TO pg_catalog, public;

-- Staging-only overloads are not created on a fresh database. Ambiguous
-- Dashboard/Audit overloads are preserved but removed from PostgREST roles;
-- the non-ambiguous five-argument route reader remains authenticated-only.
DO $legacy_hardening$
BEGIN
    IF to_regprocedure('public.rpc_dashboard_overview(uuid)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_dashboard_overview(uuid) SET search_path TO pg_catalog, public;
        REVOKE EXECUTE ON FUNCTION public.rpc_dashboard_overview(uuid) FROM PUBLIC, anon, authenticated, service_role;
    END IF;

    IF to_regprocedure('public.rpc_dashboard_alerts(uuid)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_dashboard_alerts(uuid) SET search_path TO pg_catalog, public;
        REVOKE EXECUTE ON FUNCTION public.rpc_dashboard_alerts(uuid) FROM PUBLIC, anon, authenticated, service_role;
    END IF;

    IF to_regprocedure('public.rpc_list_audit_log(uuid,integer)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_list_audit_log(uuid, integer) SET search_path TO pg_catalog, public;
        REVOKE EXECUTE ON FUNCTION public.rpc_list_audit_log(uuid, integer) FROM PUBLIC, anon, authenticated, service_role;
    END IF;

    IF to_regprocedure('public.rpc_list_route_points(uuid,timestamptz,timestamptz,integer,integer)') IS NOT NULL THEN
        ALTER FUNCTION public.rpc_list_route_points(uuid, timestamptz, timestamptz, integer, integer)
            SET search_path TO pg_catalog, public;
        REVOKE EXECUTE ON FUNCTION public.rpc_list_route_points(uuid, timestamptz, timestamptz, integer, integer)
            FROM PUBLIC, anon, service_role;
        GRANT EXECUTE ON FUNCTION public.rpc_list_route_points(uuid, timestamptz, timestamptz, integer, integer)
            TO authenticated;
    END IF;
END;
$legacy_hardening$;

NOTIFY pgrst, 'reload schema';
