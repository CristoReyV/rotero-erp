-- MULTI-05: closed grants only. No seeds, public administration or consumers.
BEGIN;

DO $owner_guard$
DECLARE v_owner oid; v_api text;
BEGIN
    SELECT oid INTO STRICT v_owner FROM pg_catalog.pg_roles
    WHERE rolname = 'rotero_company_access_owner'
      AND NOT rolcanlogin AND NOT rolinherit AND NOT rolsuper
      AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolbypassrls AND NOT rolreplication
      AND pg_catalog.shobj_description(oid,'pg_authid') = 'ROTERO MULTI-04 company roots owner v1';
    IF EXISTS (SELECT FROM pg_catalog.pg_auth_members WHERE member = v_owner) THEN
        RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='multi05_owner_membership';
    END IF;
    FOREACH v_api IN ARRAY ARRAY['anon','authenticated','service_role','authenticator'] LOOP
        IF pg_catalog.pg_has_role(v_api,v_owner,'MEMBER') THEN
            RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='multi05_owner_exposed';
        END IF;
    END LOOP;
END;
$owner_guard$;

-- The migration administrator deliberately does not inherit the root owner.
-- Permit this FK lookup only inside the transaction, without a lasting grant.
-- Preserve any pre-existing REFERENCES instead of revoking somebody else's ACL.
DO $temporary_reference_grant$
DECLARE actor_name text:=current_user; missing_columns text;
BEGIN
    SELECT string_agg(pg_catalog.quote_ident(c),',') INTO missing_columns
    FROM unnest(ARRAY['tenant_id','user_id','company_id']) AS cols(c)
    WHERE NOT pg_catalog.has_column_privilege(actor_name,'public.membership_company_access',c,'REFERENCES');
    PERFORM pg_catalog.set_config('multi05.migration_role',actor_name,true);
    PERFORM pg_catalog.set_config('multi05.migration_reference_columns',COALESCE(missing_columns,''),true);
    IF missing_columns IS NOT NULL THEN
        EXECUTE 'SET LOCAL ROLE rotero_company_access_owner';
        EXECUTE format('GRANT REFERENCES (%s) ON public.membership_company_access TO %I',missing_columns,actor_name);
        EXECUTE format('SET LOCAL ROLE %I',actor_name);
    END IF;
END;
$temporary_reference_grant$;

-- Codes are stable approval slots, not names, emails, roles or Auth identities.
-- Only a separately authorized verification process may populate these rows.
CREATE TABLE private.financial_principal_bindings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    principal_code text NOT NULL CHECK (principal_code IN (
        'approved_financial_01','approved_financial_02','approved_financial_03'
    )),
    identity_kind text NOT NULL CHECK (identity_kind = 'verified_human'),
    identity_issuer text NOT NULL CHECK (
        identity_issuer ~ '^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]{1,5})?/auth/v1$'
        AND char_length(identity_issuer) <= 500
    ),
    approval_reference text NOT NULL CHECK (
        approval_reference = btrim(approval_reference) AND char_length(approval_reference) BETWEEN 1 AND 400
    ),
    verified_by uuid NOT NULL,
    verified_at timestamptz NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked')),
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_until timestamptz,
    revoked_at timestamptz,
    revoked_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT financial_bindings_membership_fk FOREIGN KEY (user_id,tenant_id)
        REFERENCES public.memberships(user_id,tenant_id) ON DELETE RESTRICT,
    CONSTRAINT financial_bindings_identity_key UNIQUE (tenant_id,user_id,id),
    CONSTRAINT financial_bindings_validity_check CHECK (valid_until IS NULL OR valid_until > valid_from),
    CONSTRAINT financial_bindings_revocation_check CHECK (
        (status='active' AND revoked_at IS NULL AND revoked_by IS NULL)
        OR (status='revoked' AND revoked_at IS NOT NULL AND revoked_by IS NOT NULL)
    )
);
CREATE UNIQUE INDEX financial_bindings_active_principal_key
    ON private.financial_principal_bindings(tenant_id,principal_code) WHERE status='active';
CREATE UNIQUE INDEX financial_bindings_active_user_key
    ON private.financial_principal_bindings(tenant_id,user_id) WHERE status='active';

CREATE TABLE public.membership_company_capabilities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    capability_code text NOT NULL CHECK (capability_code IN (
        'operations.read','operations.capture','billing.draft','billing.document.read','receivables.read',
        'export.operational','export.receivables','companies.manage','memberships.manage','company_access.manage',
        'financial.full.read','export.financial'
    )),
    financial_binding_id uuid,
    approval_reference text NOT NULL CHECK (
        approval_reference = btrim(approval_reference) AND char_length(approval_reference) BETWEEN 1 AND 400
    ),
    granted_by uuid NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked')),
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_until timestamptz,
    revoked_at timestamptz,
    revoked_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT company_capabilities_access_fk FOREIGN KEY (tenant_id,user_id,company_id)
        REFERENCES public.membership_company_access(tenant_id,user_id,company_id) ON DELETE RESTRICT,
    CONSTRAINT company_capabilities_binding_fk FOREIGN KEY (tenant_id,user_id,financial_binding_id)
        REFERENCES private.financial_principal_bindings(tenant_id,user_id,id) ON DELETE RESTRICT,
    CONSTRAINT company_capabilities_identity_key UNIQUE (tenant_id,user_id,company_id,capability_code),
    CONSTRAINT company_capabilities_binding_check CHECK (
        (capability_code IN ('financial.full.read','export.financial') AND financial_binding_id IS NOT NULL)
        OR (capability_code NOT IN ('financial.full.read','export.financial') AND financial_binding_id IS NULL)
    ),
    CONSTRAINT company_capabilities_validity_check CHECK (valid_until IS NULL OR valid_until > valid_from),
    CONSTRAINT company_capabilities_revocation_check CHECK (
        (status='active' AND revoked_at IS NULL AND revoked_by IS NULL)
        OR (status='revoked' AND revoked_at IS NOT NULL AND revoked_by IS NOT NULL)
    )
);
CREATE INDEX company_capabilities_binding_idx
    ON public.membership_company_capabilities(tenant_id,user_id,financial_binding_id);

CREATE TABLE public.membership_consolidation_grants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    financial_binding_id uuid NOT NULL,
    capability_code text NOT NULL DEFAULT 'consolidated.read' CHECK (capability_code='consolidated.read'),
    approval_reference text NOT NULL CHECK (
        approval_reference = btrim(approval_reference) AND char_length(approval_reference) BETWEEN 1 AND 400
    ),
    granted_by uuid NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked')),
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_until timestamptz,
    revoked_at timestamptz,
    revoked_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT consolidation_grants_membership_fk FOREIGN KEY (user_id,tenant_id)
        REFERENCES public.memberships(user_id,tenant_id) ON DELETE RESTRICT,
    CONSTRAINT consolidation_grants_binding_fk FOREIGN KEY (tenant_id,user_id,financial_binding_id)
        REFERENCES private.financial_principal_bindings(tenant_id,user_id,id) ON DELETE RESTRICT,
    CONSTRAINT consolidation_grants_user_key UNIQUE (tenant_id,user_id),
    CONSTRAINT consolidation_grants_scope_key UNIQUE (tenant_id,user_id,id),
    CONSTRAINT consolidation_grants_validity_check CHECK (valid_until IS NULL OR valid_until > valid_from),
    CONSTRAINT consolidation_grants_revocation_check CHECK (
        (status='active' AND revoked_at IS NULL AND revoked_by IS NULL)
        OR (status='revoked' AND revoked_at IS NOT NULL AND revoked_by IS NOT NULL)
    )
);
CREATE INDEX consolidation_grants_binding_idx
    ON public.membership_consolidation_grants(tenant_id,user_id,financial_binding_id);

CREATE TABLE public.consolidation_grant_companies (
    tenant_id uuid NOT NULL,
    user_id uuid NOT NULL,
    consolidation_grant_id uuid NOT NULL,
    company_id uuid NOT NULL,
    required_capability text NOT NULL DEFAULT 'financial.full.read' CHECK (required_capability='financial.full.read'),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (consolidation_grant_id,company_id),
    CONSTRAINT consolidation_companies_grant_fk FOREIGN KEY (tenant_id,user_id,consolidation_grant_id)
        REFERENCES public.membership_consolidation_grants(tenant_id,user_id,id) ON DELETE RESTRICT,
    CONSTRAINT consolidation_companies_capability_fk FOREIGN KEY (tenant_id,user_id,company_id,required_capability)
        REFERENCES public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code) ON DELETE RESTRICT
);
CREATE INDEX consolidation_companies_capability_idx
    ON public.consolidation_grant_companies(tenant_id,user_id,company_id,required_capability);

CREATE TRIGGER financial_bindings_touch_updated_at BEFORE UPDATE ON private.financial_principal_bindings
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER company_capabilities_touch_updated_at BEFORE UPDATE ON public.membership_company_capabilities
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER consolidation_grants_touch_updated_at BEFORE UPDATE ON public.membership_consolidation_grants
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

ALTER TABLE private.financial_principal_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.membership_company_capabilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.membership_consolidation_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consolidation_grant_companies ENABLE ROW LEVEL SECURITY;
-- No policies: even an accidental table grant must not open a data/admin path.
REVOKE ALL ON TABLE private.financial_principal_bindings,public.membership_company_capabilities,
    public.membership_consolidation_grants,public.consolidation_grant_companies
    FROM PUBLIC,anon,authenticated,service_role;

-- Shared request parser, executable only by the existing non-login owner.
-- It matches MULTI-04/auth.uid() subject precedence; issuer is gateway claims,
-- never a header, user_metadata or an identity supplied as a function argument.
CREATE FUNCTION private.multi05_request_actor()
RETURNS TABLE (user_id uuid,issuer text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $function$
    WITH claims AS (
        SELECT NULLIF(pg_catalog.current_setting('request.jwt.claims',true),'')::jsonb AS data
    )
    SELECT COALESCE(NULLIF(pg_catalog.current_setting('request.jwt.claim.sub',true),''),data->>'sub')::uuid,
        data->>'iss'
    FROM claims;
$function$;

CREATE FUNCTION private.multi05_has_company_capability(p_tenant_id uuid,p_company_id uuid,p_capability_code text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM public.membership_company_capabilities AS c
        CROSS JOIN private.multi05_request_actor() AS actor
        WHERE c.tenant_id=p_tenant_id AND c.company_id=p_company_id
          AND c.user_id=actor.user_id AND c.capability_code=p_capability_code
          AND c.status='active' AND c.revoked_at IS NULL
          AND c.valid_from<=pg_catalog.statement_timestamp()
          AND (c.valid_until IS NULL OR c.valid_until>pg_catalog.statement_timestamp())
          AND private.multi04_has_company_access(c.tenant_id,c.company_id)
          AND (c.capability_code NOT IN ('financial.full.read','export.financial') OR (
              EXISTS (
                  SELECT 1 FROM private.financial_principal_bindings AS b
                  WHERE b.id=c.financial_binding_id AND b.tenant_id=c.tenant_id AND b.user_id=c.user_id
                    AND b.identity_kind='verified_human' AND b.identity_issuer=actor.issuer
                    AND b.status='active' AND b.revoked_at IS NULL
                    AND b.verified_at<=pg_catalog.statement_timestamp()
                    AND b.valid_from<=pg_catalog.statement_timestamp()
                    AND (b.valid_until IS NULL OR b.valid_until>pg_catalog.statement_timestamp())
              )
              AND (c.capability_code='financial.full.read' OR EXISTS (
                  SELECT 1 FROM public.membership_company_capabilities AS f
                  WHERE f.tenant_id=c.tenant_id AND f.user_id=c.user_id AND f.company_id=c.company_id
                    AND f.capability_code='financial.full.read' AND f.financial_binding_id=c.financial_binding_id
                    AND f.status='active' AND f.revoked_at IS NULL
                    AND f.valid_from<=pg_catalog.statement_timestamp()
                    AND (f.valid_until IS NULL OR f.valid_until>pg_catalog.statement_timestamp())
              ))
          ))
    );
$function$;

CREATE FUNCTION private.multi05_can_consolidate(p_tenant_id uuid,p_company_ids uuid[])
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $function$
    SELECT COALESCE(
        pg_catalog.cardinality(p_company_ids)>0 AND pg_catalog.array_ndims(p_company_ids)=1
        AND pg_catalog.array_lower(p_company_ids,1)=1
        AND NOT EXISTS (SELECT 1 FROM pg_catalog.unnest(p_company_ids) AS q(id) WHERE q.id IS NULL)
        AND pg_catalog.cardinality(p_company_ids)=(SELECT count(DISTINCT q.id) FROM pg_catalog.unnest(p_company_ids) AS q(id))
        AND EXISTS (
            SELECT 1 FROM public.membership_consolidation_grants AS g
            CROSS JOIN private.multi05_request_actor() AS actor
            WHERE g.tenant_id=p_tenant_id AND g.user_id=actor.user_id
              AND g.status='active' AND g.revoked_at IS NULL
              AND g.valid_from<=pg_catalog.statement_timestamp()
              AND (g.valid_until IS NULL OR g.valid_until>pg_catalog.statement_timestamp())
              AND NOT EXISTS (
                  SELECT 1 FROM pg_catalog.unnest(p_company_ids) AS q(id)
                  WHERE NOT EXISTS (
                      SELECT 1 FROM public.consolidation_grant_companies AS s
                      JOIN public.membership_company_capabilities AS c
                        ON c.tenant_id=s.tenant_id AND c.user_id=s.user_id AND c.company_id=s.company_id
                        AND c.capability_code=s.required_capability
                      WHERE s.consolidation_grant_id=g.id AND s.tenant_id=g.tenant_id AND s.user_id=g.user_id
                        AND s.company_id=q.id AND c.financial_binding_id=g.financial_binding_id
                        AND private.multi05_has_company_capability(g.tenant_id,q.id,'financial.full.read')
                  )
              )
        ),false
    );
$function$;

REVOKE ALL ON FUNCTION private.multi05_request_actor(),
    private.multi05_has_company_capability(uuid,uuid,text),private.multi05_can_consolidate(uuid,uuid[])
    FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.multi05_has_company_capability(uuid,uuid,text),
    private.multi05_can_consolidate(uuid,uuid[]) TO authenticated;

COMMENT ON TABLE private.financial_principal_bindings IS
    'Verified approval slots only; no real assignments or technical/QA principals seeded. Not ordinary administration.';
COMMENT ON TABLE public.membership_company_capabilities IS
    'Explicit action grants; no role defaults, module activation or implicit financial access.';
COMMENT ON TABLE public.membership_consolidation_grants IS
    'Separate read-only consolidated permission, bound to the same verified principal as financial grants.';
COMMENT ON TABLE public.consolidation_grant_companies IS
    'Explicit non-expanding scope; every requested company also needs current access and financial.full.read.';

GRANT CREATE ON SCHEMA public,private TO rotero_company_access_owner;
ALTER TABLE private.financial_principal_bindings OWNER TO rotero_company_access_owner;
ALTER TABLE public.membership_company_capabilities OWNER TO rotero_company_access_owner;
ALTER TABLE public.membership_consolidation_grants OWNER TO rotero_company_access_owner;
ALTER TABLE public.consolidation_grant_companies OWNER TO rotero_company_access_owner;
ALTER FUNCTION private.multi05_request_actor() OWNER TO rotero_company_access_owner;
ALTER FUNCTION private.multi05_has_company_capability(uuid,uuid,text) OWNER TO rotero_company_access_owner;
ALTER FUNCTION private.multi05_can_consolidate(uuid,uuid[]) OWNER TO rotero_company_access_owner;
DO $temporary_reference_revoke$
DECLARE actor_name text:=pg_catalog.current_setting('multi05.migration_role');
    missing_columns text:=pg_catalog.current_setting('multi05.migration_reference_columns');
BEGIN
    IF missing_columns<>'' THEN
        EXECUTE 'SET LOCAL ROLE rotero_company_access_owner';
        EXECUTE format('REVOKE REFERENCES (%s) ON public.membership_company_access FROM %I',missing_columns,actor_name);
        EXECUTE format('SET LOCAL ROLE %I',actor_name);
    END IF;
END;
$temporary_reference_revoke$;
REVOKE CREATE ON SCHEMA public,private FROM rotero_company_access_owner;
COMMIT;
