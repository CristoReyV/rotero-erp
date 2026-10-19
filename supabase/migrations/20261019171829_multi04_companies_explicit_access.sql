-- MULTI-04: closed company roots. No seeds, module grants or business backfill.
BEGIN;

-- This non-login owner can reach only the new roots. It is not
-- granted to application roles and cannot read existing business tables.
-- Roles survive a database-only local reset. Reuse only our tagged, unprivileged
-- owner; never silently adopt an unrelated role with the same name.
DO $owner_role$
DECLARE v_owner oid; v_api text;
BEGIN
    SELECT oid INTO v_owner FROM pg_catalog.pg_roles WHERE rolname='rotero_company_access_owner';
    IF v_owner IS NULL THEN
        CREATE ROLE rotero_company_access_owner
            NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOREPLICATION;
        COMMENT ON ROLE rotero_company_access_owner IS 'ROTERO MULTI-04 company roots owner v1';
        SELECT oid INTO v_owner FROM pg_catalog.pg_roles WHERE rolname='rotero_company_access_owner';
    ELSIF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_roles
        WHERE oid=v_owner AND NOT rolcanlogin AND NOT rolinherit AND NOT rolsuper
          AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolbypassrls AND NOT rolreplication
          AND pg_catalog.shobj_description(oid,'pg_authid')='ROTERO MULTI-04 company roots owner v1'
    ) THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='multi04_owner_role_collision';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members WHERE member=v_owner) THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='multi04_owner_role_membership';
    END IF;
    FOREACH v_api IN ARRAY ARRAY['anon','authenticated','service_role','authenticator'] LOOP
        IF pg_catalog.pg_has_role(v_api,v_owner,'MEMBER') THEN
            RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='multi04_owner_role_exposed';
        END IF;
    END LOOP;
END;
$owner_role$;
-- Ownership transfer must also work for a non-superuser migration administrator
-- on the project's PostgreSQL 17 baseline. Never grant this role to API roles.
GRANT rotero_company_access_owner TO CURRENT_USER WITH SET TRUE;
GRANT rotero_company_access_owner TO CURRENT_USER WITH INHERIT FALSE;

CREATE TABLE public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
    display_name text NOT NULL,
    legal_name text NOT NULL,
    rfc_normalized text NOT NULL,
    status text NOT NULL DEFAULT 'draft',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT companies_tenant_id_key UNIQUE (tenant_id, id),
    CONSTRAINT companies_tenant_rfc_key UNIQUE (tenant_id, rfc_normalized),
    CONSTRAINT companies_display_name_check CHECK (
        display_name = btrim(display_name) AND char_length(display_name) BETWEEN 1 AND 160
    ),
    CONSTRAINT companies_legal_name_check CHECK (
        legal_name = btrim(legal_name) AND char_length(legal_name) BETWEEN 1 AND 300
    ),
    -- Structural validation only: this does not establish fiscal readiness.
    CONSTRAINT companies_rfc_check CHECK (rfc_normalized ~ '^[A-ZÑ&]{3,4}[0-9]{6}[A-Z0-9]{3}$'),
    CONSTRAINT companies_status_check CHECK (status IN ('draft', 'active', 'inactive'))
);

CREATE INDEX companies_tenant_status_idx ON public.companies (tenant_id, status);

CREATE TABLE public.membership_company_access (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'active',
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_until timestamptz,
    granted_by uuid NOT NULL,
    revoked_at timestamptz,
    revoked_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    -- Reuse the canonical membership key, without altering memberships.
    CONSTRAINT membership_company_access_membership_fkey FOREIGN KEY (user_id, tenant_id)
        REFERENCES public.memberships (user_id, tenant_id) ON DELETE RESTRICT,
    CONSTRAINT membership_company_access_company_fkey FOREIGN KEY (tenant_id, company_id)
        REFERENCES public.companies (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT membership_company_access_identity_key UNIQUE (tenant_id, user_id, company_id),
    CONSTRAINT membership_company_access_status_check CHECK (status IN ('active', 'revoked')),
    CONSTRAINT membership_company_access_validity_check CHECK (valid_until IS NULL OR valid_until > valid_from),
    CONSTRAINT membership_company_access_revocation_check CHECK (
        (status = 'active' AND revoked_at IS NULL AND revoked_by IS NULL)
        OR (status = 'revoked' AND revoked_at IS NOT NULL AND revoked_by IS NOT NULL)
    )
);

CREATE INDEX membership_company_access_company_idx
    ON public.membership_company_access (tenant_id, company_id);

CREATE TRIGGER companies_touch_updated_at
    BEFORE UPDATE ON public.companies
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER membership_company_access_touch_updated_at
    BEFORE UPDATE ON public.membership_company_access
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.membership_company_access ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.companies, public.membership_company_access
    FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.multi04_has_company_access(p_tenant_id uuid, p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
    -- Match auth.uid()'s subject/claims precedence without requiring a grant on
    -- the Auth-owned schema (the non-superuser migration role cannot give it).
    -- These are the gateway's authenticated request settings, never metadata.
    WITH actor AS (
        SELECT COALESCE(
            NULLIF(pg_catalog.current_setting('request.jwt.claim.sub', true), ''),
            (NULLIF(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
        )::uuid AS id
    )
    SELECT actor.id IS NOT NULL AND EXISTS (
        SELECT 1
        FROM public.membership_company_access AS a
        JOIN public.companies AS c ON c.tenant_id = a.tenant_id AND c.id = a.company_id
        WHERE a.tenant_id = p_tenant_id
          AND a.company_id = p_company_id
          AND a.user_id = actor.id
          AND a.status = 'active'
          AND a.revoked_at IS NULL
          AND a.valid_from <= pg_catalog.statement_timestamp()
          AND (a.valid_until IS NULL OR a.valid_until > pg_catalog.statement_timestamp())
          AND c.status = 'active'
    ) FROM actor;
$function$;

-- Defense in depth if a future reviewed block adds narrow SELECT grants.
-- There are deliberately no client write policies, public RPCs or table grants.
CREATE POLICY companies_select_explicit_access ON public.companies
    FOR SELECT TO authenticated
    USING ((SELECT private.multi04_has_company_access(tenant_id, id)));
CREATE POLICY membership_company_access_select_own ON public.membership_company_access
    FOR SELECT TO authenticated
    USING (
        user_id = (SELECT auth.uid())
        AND (SELECT private.multi04_has_company_access(tenant_id, company_id))
    );

-- Temporary CREATE is needed only to transfer object ownership. No application
-- role receives membership in this owner or any grant on the tables.
GRANT USAGE ON SCHEMA public, private TO rotero_company_access_owner;
GRANT CREATE ON SCHEMA public, private TO rotero_company_access_owner;
REVOKE ALL ON FUNCTION private.multi04_has_company_access(uuid, uuid)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.multi04_has_company_access(uuid, uuid) TO authenticated;

COMMENT ON TABLE public.companies IS
    'MULTI-04 closed roots; company membership does not grant financial, consolidated or module permissions.';
COMMENT ON TABLE public.membership_company_access IS
    'Explicit tenant membership to company relation. No role defaults or financial capabilities.';
COMMENT ON FUNCTION private.multi04_has_company_access(uuid, uuid) IS
    'Boolean check of the authenticated actor only; not a module or financial authorization and not a public RPC.';

ALTER TABLE public.companies OWNER TO rotero_company_access_owner;
ALTER TABLE public.membership_company_access OWNER TO rotero_company_access_owner;
ALTER FUNCTION private.multi04_has_company_access(uuid, uuid) OWNER TO rotero_company_access_owner;
REVOKE CREATE ON SCHEMA public, private FROM rotero_company_access_owner;

COMMIT;
