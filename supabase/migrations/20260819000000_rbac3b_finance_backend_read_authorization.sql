-- RBAC.3B: Finance remains a reporting/financial role and cannot invoke
-- frontend-hidden administrative module reads directly through PostgREST.
--
-- The product-level operator/viewer contracts are intentionally preserved.
-- Only the membership-only Finance path is removed from these read RPCs.

CREATE OR REPLACE FUNCTION public.rpc_list_deals(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(to_jsonb(d) ORDER BY d.updated_at DESC)
        FROM public.crm_deals AS d
        WHERE d.tenant_id = p_tenant_id
          AND (NOT (p_filters ? 'stage') OR d.stage = p_filters ->> 'stage')
          AND (NOT (p_filters ? 'owner') OR d.owner_user_id = (p_filters ->> 'owner')::uuid)
          AND (NOT (p_filters ? 'priority') OR d.priority = p_filters ->> 'priority')
          AND (
              NOT (p_filters ? 'searchText')
              OR d.title ILIKE '%' || (p_filters ->> 'searchText') || '%'
              OR d.company ILIKE '%' || (p_filters ->> 'searchText') || '%'
          )
    ), '[]'::jsonb);
EXCEPTION
    WHEN invalid_text_representation THEN
        RETURN jsonb_build_object('error', 'invalid_filters');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_deal(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_tenant_id uuid;
BEGIN
    SELECT d.tenant_id INTO v_tenant_id
    FROM public.crm_deals AS d
    WHERE d.id = p_deal_id;

    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN (
        SELECT to_jsonb(d) || jsonb_build_object('owner_name', u.raw_user_meta_data ->> 'full_name')
        FROM public.crm_deals AS d
        LEFT JOIN auth.users AS u ON u.id = d.owner_user_id
        WHERE d.id = p_deal_id
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_deal_activities(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_tenant_id uuid;
BEGIN
    SELECT d.tenant_id INTO v_tenant_id
    FROM public.crm_deals AS d
    WHERE d.id = p_deal_id;

    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(
            to_jsonb(a) || jsonb_build_object('creator_name', u.raw_user_meta_data ->> 'full_name')
            ORDER BY a.created_at DESC
        )
        FROM public.crm_deal_activity AS a
        LEFT JOIN auth.users AS u ON u.id = a.created_by
        WHERE a.deal_id = p_deal_id
    ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_deal_notes(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_tenant_id uuid;
BEGIN
    SELECT d.tenant_id INTO v_tenant_id
    FROM public.crm_deals AS d
    WHERE d.id = p_deal_id;

    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(
            jsonb_build_object(
                'id', n.id,
                'note', n.note,
                'author_name', u.raw_user_meta_data ->> 'full_name',
                'created_at', n.created_at
            )
            ORDER BY n.created_at DESC
        )
        FROM public.crm_deal_notes AS n
        LEFT JOIN auth.users AS u ON u.id = n.author_id
        WHERE n.deal_id = p_deal_id
    ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_deal_checklist(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_tenant_id uuid;
BEGIN
    SELECT d.tenant_id INTO v_tenant_id
    FROM public.crm_deals AS d
    WHERE d.id = p_deal_id;

    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(
            jsonb_build_object(
                'id', c.id,
                'stage', c.stage,
                'label', c.label,
                'is_done', c.is_done,
                'updated_at', c.created_at
            )
            ORDER BY c.created_at
        )
        FROM public.crm_deal_checklist_items AS c
        WHERE c.deal_id = p_deal_id
    ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_inventory_lots(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(to_jsonb(i) ORDER BY i.received_at)
        FROM public.inventory_lots AS i
        WHERE i.tenant_id = p_tenant_id
          AND (NOT (p_filters ? 'sku') OR i.sku ILIKE '%' || (p_filters ->> 'sku') || '%')
    ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_pedimentos(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(to_jsonb(p) ORDER BY p.created_at DESC)
        FROM public.customs_pedimentos AS p
        WHERE p.tenant_id = p_tenant_id
          AND (
              NOT (p_filters ? 'pedimento_number')
              OR p.pedimento_number ILIKE '%' || (p_filters ->> 'pedimento_number') || '%'
          )
    ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_descargo_lines(p_pedimento_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_tenant_id uuid;
BEGIN
    SELECT p.tenant_id INTO v_tenant_id
    FROM public.customs_pedimentos AS p
    WHERE p.id = p_pedimento_id;

    IF v_tenant_id IS NULL THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(to_jsonb(d) ORDER BY d.sequence_no)
        FROM public.customs_descargo_lines AS d
        WHERE d.pedimento_id = p_pedimento_id
    ), '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_tenant_settings(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE(
        (SELECT to_jsonb(s) FROM public.tenant_settings AS s WHERE s.tenant_id = p_tenant_id),
        jsonb_build_object(
            'tenant_id', p_tenant_id,
            'brand_name', 'ROTERO',
            'primary_color', '#0F2B5B',
            'logo_url', NULL,
            'timezone', 'America/Mexico_City',
            'notifications_enabled', true,
            'allow_demo_mode', false,
            'created_at', now(),
            'updated_at', now()
        )
    );
END;
$function$;

-- CREATE OR REPLACE preserves the existing ACLs. RBAC.3B neither widens nor
-- repairs grants; canonical ACL drift remains a separate RBAC.3C concern.
NOTIFY pgrst, 'reload schema';
