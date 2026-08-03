-- M4.1A: reconcile internal tracking RPC contracts against the deployed schema.
-- Local preparation only. Applying this migration requires a separately authorized rollout.

-- -----------------------------------------------------------------------------
-- 1) Fail-fast contract prechecks. No token data is read or printed.
-- -----------------------------------------------------------------------------
DO $m4_precheck$
DECLARE
    v_missing_columns text[];
    v_missing_roles text[];
BEGIN
    IF to_regclass('public.tracking_tokens') IS NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: public.tracking_tokens is missing';
    END IF;

    IF to_regclass('public.tracking_events') IS NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: public.tracking_events is missing';
    END IF;

    IF to_regclass('public.memberships') IS NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: public.memberships is missing';
    END IF;

    IF to_regclass('public.operations') IS NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: public.operations is missing';
    END IF;

    SELECT array_agg(required_column ORDER BY required_column)
    INTO v_missing_columns
    FROM unnest(ARRAY[
        'id', 'state', 'revoked_at', 'revoked_by',
        'tenant_id', 'operation_id', 'scope', 'token_hash',
        'created_at', 'created_by', 'expires_at', 'rotated_into', 'last_used_at'
    ]) AS required(required_column)
    WHERE NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute a
        WHERE a.attrelid = 'public.tracking_tokens'::regclass
          AND a.attname = required.required_column
          AND a.attnum > 0
          AND NOT a.attisdropped
    );

    IF v_missing_columns IS NOT NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: tracking_tokens missing columns: %',
            array_to_string(v_missing_columns, ', ');
    END IF;

    SELECT array_agg(required_column ORDER BY required_column)
    INTO v_missing_columns
    FROM unnest(ARRAY['user_id', 'tenant_id', 'role']) AS required(required_column)
    WHERE NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute a
        WHERE a.attrelid = 'public.memberships'::regclass
          AND a.attname = required.required_column
          AND a.attnum > 0
          AND NOT a.attisdropped
    );

    IF v_missing_columns IS NOT NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: memberships missing columns: %',
            array_to_string(v_missing_columns, ', ');
    END IF;

    SELECT array_agg(required_column ORDER BY required_column)
    INTO v_missing_columns
    FROM unnest(ARRAY[
        'id', 'tenant_id', 'reference_code', 'route_summary',
        'client_display_name', 'status'
    ]) AS required(required_column)
    WHERE NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute a
        WHERE a.attrelid = 'public.operations'::regclass
          AND a.attname = required.required_column
          AND a.attnum > 0
          AND NOT a.attisdropped
    );

    IF v_missing_columns IS NOT NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: operations missing columns: %',
            array_to_string(v_missing_columns, ', ');
    END IF;

    SELECT array_agg(required_column ORDER BY required_column)
    INTO v_missing_columns
    FROM unnest(ARRAY[
        'operation_id', 'event_type', 'server_timestamp',
        'municipality', 'state_name'
    ]) AS required(required_column)
    WHERE NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute a
        WHERE a.attrelid = 'public.tracking_events'::regclass
          AND a.attname = required.required_column
          AND a.attnum > 0
          AND NOT a.attisdropped
    );

    IF v_missing_columns IS NOT NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: tracking_events missing columns: %',
            array_to_string(v_missing_columns, ', ');
    END IF;

    IF to_regprocedure('auth.uid()') IS NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: auth.uid() is missing';
    END IF;

    IF to_regprocedure('public.tracking_hash_token(text)') IS NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: tracking_hash_token(text) is missing';
    END IF;

    IF to_regprocedure('public.rpc_revoke_tracking_token(uuid)') IS NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: rpc_revoke_tracking_token(uuid) is missing';
    END IF;

    IF to_regprocedure('public.rpc_create_tracking_token(uuid,uuid,text)') IS NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: legacy rpc_create_tracking_token(uuid,uuid,text) is missing';
    END IF;

    IF to_regprocedure('public.rpc_create_tracking_token(uuid,uuid,text,integer,boolean)') IS NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: current rpc_create_tracking_token signature is missing';
    END IF;

    IF to_regprocedure('public.rpc_list_tracking_tokens(uuid)') IS NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: rpc_list_tracking_tokens(uuid) is missing';
    END IF;

    SELECT array_agg(required_role ORDER BY required_role)
    INTO v_missing_roles
    FROM unnest(ARRAY['anon', 'authenticated', 'service_role']) AS required(required_role)
    WHERE NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles r
        WHERE r.rolname = required.required_role
    );

    IF v_missing_roles IS NOT NULL THEN
        RAISE EXCEPTION 'M4.1 precheck failed: required database roles missing: %',
            array_to_string(v_missing_roles, ', ');
    END IF;

    -- status/updated_at may exist in an unexpected environment, but this migration
    -- intentionally never reads or writes either legacy column.
END;
$m4_precheck$;

-- -----------------------------------------------------------------------------
-- 2) Current five-argument creator. Signature and successful response stay
-- compatible; authorization and tenant/operation validation are made explicit.
-- -----------------------------------------------------------------------------
-- PostgreSQL cannot remove argument defaults with CREATE OR REPLACE. Replace
-- only this exact signature (without CASCADE) so three-argument calls are no
-- longer ambiguous with the compatibility overload.
DROP FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, integer, boolean);

CREATE OR REPLACE FUNCTION public.rpc_create_tracking_token(
    p_tenant_id uuid,
    p_operation_id uuid,
    p_scope text,
    p_ttl_hours integer,
    p_force_rotate boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_operation_tenant uuid;
    v_token_literal text;
    v_token_hash text;
    v_ttl interval;
    v_new_id uuid;
    v_existing_id uuid;
    v_existing_exp timestamptz;
BEGIN
    -- Direct service-role/no-session calls are intentionally not an ERP session.
    IF v_actor IS NULL THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.memberships m
        WHERE m.user_id = v_actor
          AND m.tenant_id = p_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    IF p_scope IS NULL OR p_scope NOT IN ('public:read', 'driver:write') THEN
        RETURN jsonb_build_object('error', 'invalid_scope');
    END IF;

    IF p_ttl_hours IS NOT NULL AND p_ttl_hours <= 0 THEN
        RETURN jsonb_build_object('error', 'invalid_ttl');
    END IF;

    IF p_ttl_hours IS NOT NULL AND (
        (p_scope = 'public:read' AND p_ttl_hours > 720)
        OR (p_scope = 'driver:write' AND p_ttl_hours > 72)
    ) THEN
        RETURN jsonb_build_object('error', 'ttl_exceeds_max');
    END IF;

    -- Serialize token creation/rotation for one operation and verify ownership.
    SELECT o.tenant_id
    INTO v_operation_tenant
    FROM public.operations o
    WHERE o.id = p_operation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;

    IF v_operation_tenant IS DISTINCT FROM p_tenant_id THEN
        RETURN jsonb_build_object('error', 'forbidden');
    END IF;

    SELECT t.id, t.expires_at
    INTO v_existing_id, v_existing_exp
    FROM public.tracking_tokens t
    WHERE t.operation_id = p_operation_id
      AND t.tenant_id = p_tenant_id
      AND t.scope = p_scope
      AND t.state = 'active'
    FOR UPDATE;

    IF v_existing_id IS NOT NULL AND NOT COALESCE(p_force_rotate, false) THEN
        RETURN jsonb_build_object(
            'token_id', v_existing_id,
            'already_existed', true,
            'scope', p_scope,
            'expires_at', to_char(v_existing_exp, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        );
    END IF;

    v_ttl := CASE
        WHEN p_ttl_hours IS NOT NULL THEN make_interval(hours => p_ttl_hours)
        WHEN p_scope = 'public:read' THEN interval '7 days'
        ELSE interval '48 hours'
    END;

    IF v_existing_id IS NOT NULL THEN
        UPDATE public.tracking_tokens
        SET state = 'rotated',
            revoked_at = now(),
            revoked_by = v_actor
        WHERE id = v_existing_id;
    END IF;

    v_token_literal := gen_random_uuid()::text;
    v_token_hash := public.tracking_hash_token(v_token_literal);

    INSERT INTO public.tracking_tokens (
        tenant_id,
        operation_id,
        scope,
        token_hash,
        state,
        created_by,
        expires_at
    ) VALUES (
        p_tenant_id,
        p_operation_id,
        p_scope,
        v_token_hash,
        'active',
        v_actor,
        now() + v_ttl
    )
    RETURNING id INTO v_new_id;

    IF v_existing_id IS NOT NULL THEN
        UPDATE public.tracking_tokens
        SET rotated_into = v_new_id
        WHERE id = v_existing_id;
    END IF;

    -- The literal is returned only on creation/rotation and is never persisted.
    RETURN jsonb_build_object(
        'token_id', v_new_id,
        'token', v_token_literal,
        'scope', p_scope,
        'expires_at', to_char(now() + v_ttl, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'rotated_previous', v_existing_id IS NOT NULL,
        'already_existed', false
    );
EXCEPTION
    WHEN unique_violation THEN
        RETURN jsonb_build_object('error', 'conflict');
    WHEN OTHERS THEN
        RETURN jsonb_build_object('error', 'internal_error');
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3) Legacy three-argument overload. Kept because versioned SQL/tests still use
-- it; all authorization and validation is delegated to the current contract.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_create_tracking_token(
    p_tenant_id uuid,
    p_operation_id uuid,
    p_scope text DEFAULT 'public:read'::text
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT public.rpc_create_tracking_token(
        p_tenant_id,
        p_operation_id,
        p_scope,
        NULL::integer,
        false
    );
$function$;

-- Four-argument compatibility wrappers keep both existing call shapes
-- unambiguous after the five-argument core stops advertising defaults.
CREATE OR REPLACE FUNCTION public.rpc_create_tracking_token(
    p_tenant_id uuid,
    p_operation_id uuid,
    p_scope text,
    p_ttl_hours integer
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT public.rpc_create_tracking_token(
        p_tenant_id,
        p_operation_id,
        p_scope,
        p_ttl_hours,
        false
    );
$function$;

CREATE OR REPLACE FUNCTION public.rpc_create_tracking_token(
    p_tenant_id uuid,
    p_operation_id uuid,
    p_scope text,
    p_force_rotate boolean
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT public.rpc_create_tracking_token(
        p_tenant_id,
        p_operation_id,
        p_scope,
        NULL::integer,
        p_force_rotate
    );
$function$;

-- -----------------------------------------------------------------------------
-- 4) Revocation against the real state/revoked_at/revoked_by schema.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_revoke_tracking_token(p_token_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_tenant_id uuid;
    v_state text;
BEGIN
    -- service_role/no-session is deliberately denied: no Edge Function needs
    -- this RPC, and ERP revocation must retain an authenticated human actor.
    IF v_actor IS NULL THEN
        RETURN jsonb_build_object('success', false, 'status', 'forbidden');
    END IF;

    SELECT t.tenant_id, t.state
    INTO v_tenant_id, v_state
    FROM public.tracking_tokens t
    WHERE t.id = p_token_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'status', 'not_found');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.memberships m
        WHERE m.user_id = v_actor
          AND m.tenant_id = v_tenant_id
          AND m.role IN ('admin', 'operator')
    ) THEN
        RETURN jsonb_build_object('success', false, 'status', 'forbidden');
    END IF;

    IF v_state = 'revoked' THEN
        RETURN jsonb_build_object(
            'success', true,
            'status', 'already_revoked',
            'already_revoked', true
        );
    END IF;

    IF v_state = 'rotated' THEN
        RETURN jsonb_build_object('success', false, 'status', 'rotated');
    END IF;

    IF v_state IS DISTINCT FROM 'active' THEN
        RETURN jsonb_build_object('success', false, 'status', COALESCE(v_state, 'invalid_state'));
    END IF;

    UPDATE public.tracking_tokens
    SET state = 'revoked',
        revoked_at = now(),
        revoked_by = v_actor
    WHERE id = p_token_id
      AND state = 'active';

    RETURN jsonb_build_object('success', true, 'status', 'revoked');
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'status', 'internal_error');
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5) Internal list. Membership remains sufficient (viewer included), while the
-- unused token-hash prefix is removed from the response.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_list_tracking_tokens(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_actor uuid := auth.uid();
BEGIN
    IF v_actor IS NULL OR NOT EXISTS (
        SELECT 1
        FROM public.memberships m
        WHERE m.user_id = v_actor
          AND m.tenant_id = p_tenant_id
          AND m.role IN ('admin', 'operator', 'viewer')
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN (
        SELECT COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'id', t.id,
                    'operation_id', t.operation_id,
                    'scope', t.scope,
                    'state', t.state,
                    'created_at', t.created_at,
                    'expires_at', t.expires_at,
                    'last_used_at', t.last_used_at,
                    'reference_code', o.reference_code,
                    'route_summary', o.route_summary,
                    'client_display_name', o.client_display_name,
                    'operation_status', o.status,
                    'last_municipality', (
                        SELECT e.municipality || ', ' || e.state_name
                        FROM public.tracking_events e
                        WHERE e.operation_id = t.operation_id
                          AND e.municipality IS NOT NULL
                          AND e.event_type <> 'incident'
                        ORDER BY e.server_timestamp DESC
                        LIMIT 1
                    ),
                    'last_event_at', (
                        SELECT to_char(e.server_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                        FROM public.tracking_events e
                        WHERE e.operation_id = t.operation_id
                        ORDER BY e.server_timestamp DESC
                        LIMIT 1
                    )
                )
                ORDER BY t.created_at DESC
            ),
            '[]'::jsonb
        )
        FROM public.tracking_tokens t
        LEFT JOIN public.operations o ON o.id = t.operation_id
        WHERE t.tenant_id = p_tenant_id
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('error', 'internal_error');
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6) Explicit execution surface. Fine-grained authorization remains in each RPC.
-- Edge Functions do not use these internal admin RPCs.
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, integer, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, integer, boolean) FROM anon;
REVOKE ALL ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, integer, boolean) FROM service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, integer, boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, integer) FROM anon;
REVOKE ALL ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, integer) FROM service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, integer) TO authenticated;

REVOKE ALL ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, boolean) FROM anon;
REVOKE ALL ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, boolean) FROM service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.rpc_revoke_tracking_token(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_revoke_tracking_token(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.rpc_revoke_tracking_token(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.rpc_revoke_tracking_token(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.rpc_list_tracking_tokens(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_list_tracking_tokens(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.rpc_list_tracking_tokens(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_tracking_tokens(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
