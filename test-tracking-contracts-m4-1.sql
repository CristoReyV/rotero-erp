-- M4.1A transactional contract tests.
-- Run only against an authorized disposable/local Supabase database after migrations.
-- The transaction is always rolled back and no token literal is printed.

BEGIN;

DO $m4_tests$
DECLARE
    v_tenant_a uuid;
    v_tenant_b uuid;
    v_operation_a uuid;
    v_operation_b uuid;
    v_admin_a uuid := gen_random_uuid();
    v_operator_a uuid := gen_random_uuid();
    v_viewer_a uuid := gen_random_uuid();
    v_admin_b uuid := gen_random_uuid();
    v_cross_token uuid;
    v_token_id uuid;
    v_rotated_token_id uuid;
    v_result jsonb;
    v_hash_before text;
    v_hash_after text;
    v_revoked_at timestamptz;
    v_suffix text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
BEGIN
    -- Fixtures are synthetic and live only inside this transaction.
    INSERT INTO public.tenants (name, slug)
    VALUES ('M4 TEST TENANT A', 'm4-test-a-' || v_suffix)
    RETURNING id INTO v_tenant_a;

    INSERT INTO public.tenants (name, slug)
    VALUES ('M4 TEST TENANT B', 'm4-test-b-' || v_suffix)
    RETURNING id INTO v_tenant_b;

    INSERT INTO public.operations (tenant_id, reference_code, status)
    VALUES (v_tenant_a, 'M4-TEST-OP-A-' || v_suffix, 'draft')
    RETURNING id INTO v_operation_a;

    INSERT INTO public.operations (tenant_id, reference_code, status)
    VALUES (v_tenant_b, 'M4-TEST-OP-B-' || v_suffix, 'draft')
    RETURNING id INTO v_operation_b;

    INSERT INTO public.memberships (tenant_id, user_id, role) VALUES
        (v_tenant_a, v_admin_a, 'admin'),
        (v_tenant_a, v_operator_a, 'operator'),
        (v_tenant_a, v_viewer_a, 'viewer'),
        (v_tenant_b, v_admin_b, 'admin');

    INSERT INTO public.tracking_tokens (
        tenant_id, operation_id, scope, token_hash, state, created_by, expires_at
    ) VALUES (
        v_tenant_b,
        v_operation_b,
        'public:read',
        public.tracking_hash_token('m4-cross-tenant-fixture-' || v_suffix),
        'active',
        v_admin_b,
        now() + interval '1 hour'
    ) RETURNING id INTO v_cross_token;

    -- Explicit grants: authenticated only for internal RPCs.
    IF NOT has_function_privilege(
        'authenticated',
        'public.rpc_create_tracking_token(uuid,uuid,text,integer,boolean)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'authenticated',
        'public.rpc_create_tracking_token(uuid,uuid,text)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'authenticated',
        'public.rpc_create_tracking_token(uuid,uuid,text,integer)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'authenticated',
        'public.rpc_create_tracking_token(uuid,uuid,text,boolean)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'authenticated',
        'public.rpc_revoke_tracking_token(uuid)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'authenticated',
        'public.rpc_list_tracking_tokens(uuid)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'M4 TEST FAILED: authenticated is missing an internal RPC grant';
    END IF;

    IF has_function_privilege('anon', 'public.rpc_create_tracking_token(uuid,uuid,text,integer,boolean)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.rpc_create_tracking_token(uuid,uuid,text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.rpc_create_tracking_token(uuid,uuid,text,integer)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.rpc_create_tracking_token(uuid,uuid,text,boolean)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.rpc_revoke_tracking_token(uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.rpc_list_tracking_tokens(uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'M4 TEST FAILED: anon can execute an internal tracking RPC';
    END IF;

    IF has_function_privilege('service_role', 'public.rpc_create_tracking_token(uuid,uuid,text,integer,boolean)', 'EXECUTE')
       OR has_function_privilege('service_role', 'public.rpc_create_tracking_token(uuid,uuid,text)', 'EXECUTE')
       OR has_function_privilege('service_role', 'public.rpc_create_tracking_token(uuid,uuid,text,integer)', 'EXECUTE')
       OR has_function_privilege('service_role', 'public.rpc_create_tracking_token(uuid,uuid,text,boolean)', 'EXECUTE')
       OR has_function_privilege('service_role', 'public.rpc_revoke_tracking_token(uuid)', 'EXECUTE')
       OR has_function_privilege('service_role', 'public.rpc_list_tracking_tokens(uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'M4 TEST FAILED: service_role can execute an ERP-only tracking RPC';
    END IF;

    -- Admin: create, list and revoke in own tenant.
    PERFORM set_config('request.jwt.claim.sub', v_admin_a::text, true);
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_admin_a, 'role', 'authenticated')::text,
        true
    );

    -- Historical four-argument TTL call shape delegates with force=false.
    v_result := public.rpc_create_tracking_token(
        v_tenant_a, v_operation_a, 'public:read', 1
    );
    IF v_result ? 'error' OR NOT (v_result ? 'token') OR NOT (v_result ? 'token_id') THEN
        RAISE EXCEPTION 'M4 TEST FAILED: admin create was not accepted';
    END IF;
    v_token_id := (v_result->>'token_id')::uuid;

    SELECT token_hash INTO v_hash_before
    FROM public.tracking_tokens
    WHERE id = v_token_id;

    v_result := public.rpc_list_tracking_tokens(v_tenant_a);
    IF jsonb_typeof(v_result) <> 'array' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: admin list was not accepted';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_result) item WHERE item ? 'token_hash'
    ) THEN
        RAISE EXCEPTION 'M4 TEST FAILED: list exposes token_hash material';
    END IF;

    v_result := public.rpc_revoke_tracking_token(v_token_id);
    IF v_result->>'status' <> 'revoked' OR (v_result->>'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'M4 TEST FAILED: admin revoke was not accepted';
    END IF;

    SELECT token_hash, revoked_at
    INTO v_hash_after, v_revoked_at
    FROM public.tracking_tokens
    WHERE id = v_token_id
      AND state = 'revoked'
      AND revoked_by = v_admin_a;

    IF v_hash_after IS NULL OR v_hash_after IS DISTINCT FROM v_hash_before OR v_revoked_at IS NULL THEN
        RAISE EXCEPTION 'M4 TEST FAILED: revoke changed hash or missed audit fields';
    END IF;

    v_result := public.rpc_revoke_tracking_token(v_token_id);
    IF v_result->>'status' <> 'already_revoked' OR (v_result->>'success')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'M4 TEST FAILED: repeated revoke is not idempotent';
    END IF;
    IF (SELECT revoked_at FROM public.tracking_tokens WHERE id = v_token_id) IS DISTINCT FROM v_revoked_at THEN
        RAISE EXCEPTION 'M4 TEST FAILED: repeated revoke changed revoked_at';
    END IF;

    -- Admin: scope, TTL, operation and tenant negative cases.
    v_result := public.rpc_create_tracking_token(v_tenant_a, v_operation_a, 'invalid', 1, false);
    IF v_result->>'error' <> 'invalid_scope' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: invalid scope was accepted';
    END IF;

    v_result := public.rpc_create_tracking_token(v_tenant_a, v_operation_a, 'public:read', 0, false);
    IF v_result->>'error' <> 'invalid_ttl' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: zero TTL was accepted';
    END IF;

    v_result := public.rpc_create_tracking_token(v_tenant_a, v_operation_a, 'public:read', -1, false);
    IF v_result->>'error' <> 'invalid_ttl' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: negative TTL was accepted';
    END IF;

    v_result := public.rpc_create_tracking_token(v_tenant_a, v_operation_a, 'public:read', 721, false);
    IF v_result->>'error' <> 'ttl_exceeds_max' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: public TTL above maximum was accepted';
    END IF;

    v_result := public.rpc_create_tracking_token(v_tenant_a, v_operation_a, 'driver:write', 73, false);
    IF v_result->>'error' <> 'ttl_exceeds_max' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: driver TTL above maximum was accepted';
    END IF;

    v_result := public.rpc_create_tracking_token(v_tenant_a, gen_random_uuid(), 'public:read', 1, false);
    IF v_result->>'error' <> 'not_found' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: nonexistent operation was not rejected';
    END IF;

    v_result := public.rpc_create_tracking_token(v_tenant_a, v_operation_b, 'public:read', 1, false);
    IF v_result->>'error' <> 'forbidden'
       OR v_result ?| ARRAY['token_id', 'tenant_id', 'operation_id', 'detail', 'message'] THEN
        RAISE EXCEPTION 'M4 TEST FAILED: tenant/operation mismatch was not rejected';
    END IF;

    v_result := public.rpc_create_tracking_token(v_tenant_b, v_operation_b, 'public:read', 1, false);
    IF v_result->>'error' <> 'unauthorized'
       OR v_result ?| ARRAY['token_id', 'tenant_id', 'operation_id', 'detail', 'message'] THEN
        RAISE EXCEPTION 'M4 TEST FAILED: cross-tenant create was not rejected';
    END IF;

    v_result := public.rpc_revoke_tracking_token(v_cross_token);
    IF v_result->>'status' <> 'forbidden'
       OR v_result ?| ARRAY['token_id', 'tenant_id', 'operation_id', 'detail', 'message'] THEN
        RAISE EXCEPTION 'M4 TEST FAILED: cross-tenant revoke was not rejected';
    END IF;

    v_result := public.rpc_revoke_tracking_token(gen_random_uuid());
    IF v_result->>'status' <> 'not_found' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: nonexistent token did not return not_found';
    END IF;

    -- Rotation remains explicit and a rotated predecessor cannot be revoked.
    -- Exercise the preserved three-argument wrapper before rotating via v5.
    v_result := public.rpc_create_tracking_token(
        v_tenant_a, v_operation_a, 'driver:write'
    );
    v_rotated_token_id := (v_result->>'token_id')::uuid;
    IF v_rotated_token_id IS NULL THEN
        RAISE EXCEPTION 'M4 TEST FAILED: driver token setup failed';
    END IF;

    v_result := public.rpc_create_tracking_token(
        v_tenant_a, v_operation_a, 'driver:write'
    );
    IF v_result ? 'token'
       OR (v_result->>'already_existed')::boolean IS NOT TRUE
       OR (v_result->>'token_id')::uuid IS DISTINCT FROM v_rotated_token_id THEN
        RAISE EXCEPTION 'M4 TEST FAILED: legacy wrapper forced rotation';
    END IF;

    v_result := public.rpc_create_tracking_token(
        v_tenant_a, v_operation_a, 'driver:write', 1, true
    );
    IF v_result ? 'error' OR (v_result->>'rotated_previous')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'M4 TEST FAILED: explicit rotation failed';
    END IF;

    v_result := public.rpc_revoke_tracking_token(v_rotated_token_id);
    IF v_result->>'status' <> 'rotated' OR (v_result->>'success')::boolean IS NOT FALSE THEN
        RAISE EXCEPTION 'M4 TEST FAILED: rotated token was treated as active';
    END IF;

    -- Operator: create/revoke/list permitted.
    PERFORM set_config('request.jwt.claim.sub', v_operator_a::text, true);
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_operator_a, 'role', 'authenticated')::text,
        true
    );

    -- Frontend four-argument force-rotate call shape remains compatible.
    v_result := public.rpc_create_tracking_token(
        v_tenant_a, v_operation_a, 'public:read', false
    );
    IF v_result ? 'error' OR NOT (v_result ? 'token_id') THEN
        RAISE EXCEPTION 'M4 TEST FAILED: operator create was not accepted';
    END IF;
    v_token_id := (v_result->>'token_id')::uuid;

    v_result := public.rpc_revoke_tracking_token(v_token_id);
    IF v_result->>'status' <> 'revoked' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: operator revoke was not accepted';
    END IF;

    IF jsonb_typeof(public.rpc_list_tracking_tokens(v_tenant_a)) <> 'array' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: operator list was not accepted';
    END IF;

    -- Viewer: list permitted; create/revoke/cross-tenant list denied.
    PERFORM set_config('request.jwt.claim.sub', v_viewer_a::text, true);
    PERFORM set_config(
        'request.jwt.claims',
        jsonb_build_object('sub', v_viewer_a, 'role', 'authenticated')::text,
        true
    );

    v_result := public.rpc_create_tracking_token(
        v_tenant_a, v_operation_a, 'public:read', 1, false
    );
    IF v_result->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: viewer create was not rejected';
    END IF;

    v_result := public.rpc_revoke_tracking_token((
        SELECT id FROM public.tracking_tokens
        WHERE operation_id = v_operation_a AND state = 'active'
        LIMIT 1
    ));
    IF v_result->>'status' <> 'forbidden' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: viewer revoke was not rejected';
    END IF;

    IF jsonb_typeof(public.rpc_list_tracking_tokens(v_tenant_a)) <> 'array' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: viewer list was not accepted';
    END IF;

    v_result := public.rpc_list_tracking_tokens(v_tenant_b);
    IF v_result->>'error' <> 'unauthorized'
       OR v_result ?| ARRAY['token_id', 'tenant_id', 'operation_id', 'detail', 'message'] THEN
        RAISE EXCEPTION 'M4 TEST FAILED: viewer cross-tenant list was not rejected';
    END IF;

    -- No-session/service-style invocation is denied by the function body too.
    PERFORM set_config('request.jwt.claim.sub', '', true);
    PERFORM set_config('request.jwt.claims', '{}', true);

    v_result := public.rpc_create_tracking_token(
        v_tenant_a, v_operation_a, 'public:read', 1, false
    );
    IF v_result->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: no-session create was not rejected';
    END IF;

    v_result := public.rpc_list_tracking_tokens(v_tenant_a);
    IF v_result->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: no-session list was not rejected';
    END IF;

    v_result := public.rpc_revoke_tracking_token(v_cross_token);
    IF v_result->>'status' <> 'forbidden' THEN
        RAISE EXCEPTION 'M4 TEST FAILED: no-session revoke was not rejected';
    END IF;

    RAISE NOTICE 'M4.1A tracking contract matrix passed; transaction will roll back';
END;
$m4_tests$;

ROLLBACK;
