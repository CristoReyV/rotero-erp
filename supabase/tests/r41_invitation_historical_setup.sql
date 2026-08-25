\set ON_ERROR_STOP on

-- Disposable-local fixture matching the invitation catalog observed on staging
-- after F10 and before BH1/R4.1. It deliberately contains no business or Auth
-- rows and must only run after a reset capped at 20260830000000.
DO $fixture$
BEGIN
    IF (SELECT count(*) FROM public.invitations) <> 0 THEN
        RAISE EXCEPTION 'R4.1 historical fixture requires zero invitations';
    END IF;
END
$fixture$;

DROP TABLE public.invitations;

CREATE TABLE public.invitations (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    email text NOT NULL,
    role text NOT NULL,
    token_hash text NOT NULL,
    expires_at timestamptz NOT NULL,
    accepted_at timestamptz,
    created_by uuid,
    created_at timestamptz DEFAULT now(),
    CONSTRAINT invitations_pkey PRIMARY KEY (id),
    CONSTRAINT invitations_created_by_fkey
        FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
    CONSTRAINT invitations_role_check
        CHECK (role IN ('admin', 'operator', 'finance', 'viewer')),
    CONSTRAINT invitations_tenant_id_fkey
        FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE,
    CONSTRAINT unique_tenant_email UNIQUE (tenant_id, email, accepted_at)
);

CREATE INDEX idx_invitations_token_hash
    ON public.invitations (token_hash);

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.invitations FROM PUBLIC, anon, authenticated, service_role;

CREATE POLICY "Admins and Operators can view invitations" ON public.invitations
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.memberships AS m
            WHERE m.user_id = auth.uid()
              AND m.tenant_id = invitations.tenant_id
              AND m.role IN ('admin', 'operator')
        )
    );
CREATE POLICY "Admins can insert invitations" ON public.invitations
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.memberships AS m
            WHERE m.user_id = auth.uid()
              AND m.tenant_id = invitations.tenant_id
              AND m.role = 'admin'
        )
    );
CREATE POLICY "Admins can update invitations (revoke)" ON public.invitations
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM public.memberships AS m
            WHERE m.user_id = auth.uid()
              AND m.tenant_id = invitations.tenant_id
              AND m.role = 'admin'
        )
    );

DROP FUNCTION IF EXISTS public.rpc_accept_invitation(text);
DROP FUNCTION IF EXISTS public.rpc_list_invitations(uuid);
DROP FUNCTION IF EXISTS public.rpc_revoke_invitation(uuid);

-- Safe fixture bodies reproduce only the staging identities and unsafe grants;
-- they intentionally do not reproduce or execute historical Auth writes/deletes.
CREATE FUNCTION public.rpc_accept_invitation(
    p_token text,
    p_password text,
    p_full_name text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, extensions
AS $function$
BEGIN
    RETURN jsonb_build_object('fixture', 'legacy_accept');
END
$function$;

CREATE FUNCTION public.rpc_revoke_invitation(
    p_tenant_id uuid,
    p_invitation_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
    RETURN jsonb_build_object('fixture', 'legacy_revoke');
END
$function$;

DROP TABLE IF EXISTS private.r41_invitation_rpc_snapshot;
CREATE TABLE private.r41_invitation_rpc_snapshot (
    identity text PRIMARY KEY,
    function_oid oid NOT NULL,
    arg_names text[] NOT NULL,
    result_type text NOT NULL
);

INSERT INTO private.r41_invitation_rpc_snapshot(identity, function_oid, arg_names, result_type)
SELECT p.oid::regprocedure::text, p.oid, p.proargnames, pg_catalog.pg_get_function_result(p.oid)
FROM pg_catalog.pg_proc AS p
WHERE p.oid = ANY (ARRAY[
    'public.rpc_create_invitation(uuid,text,text)'::regprocedure::oid,
    'public.rpc_accept_invitation(text,text,text)'::regprocedure::oid,
    'public.rpc_revoke_invitation(uuid,uuid)'::regprocedure::oid
]);

REVOKE ALL ON TABLE private.r41_invitation_rpc_snapshot
    FROM PUBLIC, anon, authenticated, service_role;

DO $fixture$
DECLARE
    v_columns text[];
BEGIN
    SELECT array_agg(a.attname ORDER BY a.attnum)
    INTO v_columns
    FROM pg_catalog.pg_attribute AS a
    WHERE a.attrelid = 'public.invitations'::regclass
      AND a.attnum > 0
      AND NOT a.attisdropped;

    IF v_columns IS DISTINCT FROM ARRAY[
        'id', 'tenant_id', 'email', 'role', 'token_hash', 'expires_at',
        'accepted_at', 'created_by', 'created_at'
    ]::text[] THEN
        RAISE EXCEPTION 'R4.1 historical fixture column mismatch: %', v_columns;
    END IF;
    IF (SELECT count(*) FROM private.r41_invitation_rpc_snapshot) <> 3 THEN
        RAISE EXCEPTION 'R4.1 historical RPC snapshot incomplete';
    END IF;
END
$fixture$;
