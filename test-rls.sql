-- Test Script for RLS and RBAC
-- Run via: psql or `npx supabase db query -f test-rls.sql`

BEGIN;

DO $$
DECLARE
    tenant_a_id uuid;
    tenant_b_id uuid;
    admin_a_uid uuid;
    viewer_a_uid uuid;
    admin_b_uid uuid;
    op_a_id uuid;
    op_b_id uuid;
    tracking_token_a uuid;
    dummy_result jsonb;
    count_a int;
    count_b int;
BEGIN
    -- 1. Setup Test Data (Bypassing RLS because we are superuser here)
    -- Tenants
    INSERT INTO tenants (name) VALUES ('TEST_TENANT_A') RETURNING id INTO tenant_a_id;
    INSERT INTO tenants (name) VALUES ('TEST_TENANT_B') RETURNING id INTO tenant_b_id;

    -- Users (Mocking UUIDs for auth.users)
    admin_a_uid := gen_random_uuid();
    viewer_a_uid := gen_random_uuid();
    admin_b_uid := gen_random_uuid();

    -- Memberships
    INSERT INTO memberships (tenant_id, user_id, role) VALUES
        (tenant_a_id, admin_a_uid, 'admin'),
        (tenant_a_id, viewer_a_uid, 'viewer'),
        (tenant_b_id, admin_b_uid, 'admin');

    -- Operations
    INSERT INTO operations (tenant_id, internal_ref, status) VALUES
        (tenant_a_id, 'TEST-OP-A', 'draft') RETURNING id INTO op_a_id;
    INSERT INTO operations (tenant_id, internal_ref, status) VALUES
        (tenant_b_id, 'TEST-OP-B', 'draft') RETURNING id INTO op_b_id;

    -- Tracking Token
    INSERT INTO tracking_tokens (tenant_id, operation_id, token, scope) VALUES
        (tenant_a_id, op_a_id, 'TEST-TOKEN-A', 'public:read') RETURNING id INTO tracking_token_a;


    RAISE NOTICE '--- STARTING QA SECURITY TESTS ---';

    -- ======================================================================================
    -- TEST A: Admin Tenant A intenta leer data de Tenant B
    -- ESPERADO: 0 filas de Tenant B. Solo ve Tenant A.
    -- ======================================================================================
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', admin_a_uid), true);

    -- Verificar Operaciones
    SELECT COUNT(*) INTO count_a FROM operations WHERE internal_ref = 'TEST-OP-A';
    SELECT COUNT(*) INTO count_b FROM operations WHERE internal_ref = 'TEST-OP-B';

    IF count_a != 1 THEN RAISE EXCEPTION 'TEST A FAILED: Admin A cannot see their own operation'; END IF;
    IF count_b != 0 THEN RAISE EXCEPTION 'TEST A FAILED: Admin A CAN see Tenant B operation (RLS LEAK!)'; END IF;
    RAISE NOTICE '✅ TEST A PASSED: Cross-tenant RLS isolation works on operations';

    -- Verificar Memberships
    SELECT COUNT(*) INTO count_b FROM memberships WHERE tenant_id = tenant_b_id;
    IF count_b != 0 THEN RAISE EXCEPTION 'TEST A FAILED: Admin A CAN see Tenant B memberships (RLS LEAK!)'; END IF;
    RAISE NOTICE '✅ TEST A PASSED: Cross-tenant RLS isolation works on memberships';


    -- ======================================================================================
    -- TEST B: rpc_create_tracking_token inyectando ID del Tenant B siendo Admin Tenant A
    -- ESPERADO: error='unauthorized'
    -- ======================================================================================
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', admin_a_uid), true);

    SELECT rpc_create_tracking_token(tenant_b_id, op_b_id, 'driver:write') INTO dummy_result;
    IF dummy_result->>'error' != 'unauthorized' THEN
        RAISE EXCEPTION 'TEST B FAILED: Admin A created token for Tenant B! Result: %', dummy_result;
    END IF;
    RAISE NOTICE '✅ TEST B PASSED: RPC strictly blocks cross-tenant token creation';


    -- ======================================================================================
    -- TEST C: Insertar operación directamente en Tenant B como Admin A
    -- ESPERADO: Violación RLS o 0 rows affected
    -- ======================================================================================
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', admin_a_uid), true);

    BEGIN
        INSERT INTO operations (tenant_id, internal_ref, status) VALUES (tenant_b_id, 'HACK-OP', 'draft');
        RAISE EXCEPTION 'TEST C FAILED: Admin A was able to insert into Tenant B! (RLS LEAK!)';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '✅ TEST C PASSED: Admin A blocked from inserting into Tenant B (%)', SQLERRM;
    END;

    -- ======================================================================================
    -- TEST D: Viewer intenta llamar a rpc_revoke_tracking_token (Mismo Tenant)
    -- ESPERADO: error='unauthorized'
    -- ======================================================================================
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', viewer_a_uid), true);

    SELECT rpc_revoke_tracking_token(tracking_token_a) INTO dummy_result;
    IF dummy_result->>'error' != 'unauthorized' THEN
        RAISE EXCEPTION 'TEST D FAILED: Viewer A revoked token! Result: %', dummy_result;
    END IF;
    RAISE NOTICE '✅ TEST D PASSED: Viewer role is correctly blocked from revoking tokens';


    -- ======================================================================================
    -- TEST E: Viewer intenta llamar a rpc_create_tracking_token (Mismo Tenant)
    -- ESPERADO: error='unauthorized'
    -- ======================================================================================
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', viewer_a_uid), true);

    SELECT rpc_create_tracking_token(tenant_a_id, op_a_id, 'public:read') INTO dummy_result;
    IF dummy_result->>'error' != 'unauthorized' THEN
        RAISE EXCEPTION 'TEST E FAILED: Viewer A created token! Result: %', dummy_result;
    END IF;
    RAISE NOTICE '✅ TEST E PASSED: Viewer role is correctly blocked from creating tokens';


    -- Reset role
    PERFORM set_config('role', 'postgres', true);
    RAISE NOTICE '--- ALL SECURITY TESTS PASSED SUCCESSFULLY ---';

END $$;

ROLLBACK;
