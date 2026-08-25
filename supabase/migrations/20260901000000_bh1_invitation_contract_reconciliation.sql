-- R4.1 reconciles the historical staging invitation table after BH1 exposed
-- its missing lifecycle columns. It is intentionally forward-only and leaves
-- invitation onboarding disabled in the current deployment.

BEGIN;

ALTER TABLE public.invitations
    ADD COLUMN IF NOT EXISTS accepted_by uuid,
    ADD COLUMN IF NOT EXISTS revoked_at timestamptz,
    ADD COLUMN IF NOT EXISTS revoked_by uuid,
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Refuse to invent lifecycle actors or rewrite historical business data. The
-- verified staging table is empty, while this guard keeps unexpected histories
-- intact and makes any incompatible state fail explicitly.
DO $migration$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.invitations AS i
        WHERE i.role IS NULL
           OR i.token_hash IS NULL
           OR i.created_by IS NULL
           OR i.created_at IS NULL
           OR (i.accepted_at IS NULL) <> (i.accepted_by IS NULL)
           OR (i.revoked_at IS NULL) <> (i.revoked_by IS NULL)
           OR (i.accepted_at IS NOT NULL AND i.revoked_at IS NOT NULL)
           OR i.email <> lower(btrim(i.email))
           OR i.email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = 'check_violation',
            MESSAGE = 'invitation_history_requires_manual_reconciliation';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.invitations AS i
        GROUP BY i.token_hash
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = 'unique_violation',
            MESSAGE = 'invitation_token_hash_history_is_not_unique';
    END IF;
END
$migration$;

ALTER TABLE public.invitations
    ALTER COLUMN role SET DEFAULT 'viewer',
    ALTER COLUMN created_by SET NOT NULL,
    ALTER COLUMN created_at SET DEFAULT now(),
    ALTER COLUMN created_at SET NOT NULL,
    ALTER COLUMN updated_at SET DEFAULT now(),
    ALTER COLUMN updated_at SET NOT NULL;

-- The canonical contract deliberately does not couple invitation actors to the
-- internal Auth schema. The historical FK also conflicted with NOT NULL because
-- it attempted SET NULL on Auth user deletion.
ALTER TABLE public.invitations
    DROP CONSTRAINT IF EXISTS invitations_created_by_fkey;

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
        WHERE conrelid = 'public.invitations'::pg_catalog.regclass
          AND conname = 'invitations_token_hash_key'
    ) THEN
        ALTER TABLE public.invitations
            ADD CONSTRAINT invitations_token_hash_key UNIQUE (token_hash);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
        WHERE conrelid = 'public.invitations'::pg_catalog.regclass
          AND conname = 'invitations_role_check'
    ) THEN
        ALTER TABLE public.invitations
            ADD CONSTRAINT invitations_role_check
            CHECK (role IN ('admin', 'operator', 'finance', 'viewer'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
        WHERE conrelid = 'public.invitations'::pg_catalog.regclass
          AND conname = 'invitations_email_check'
    ) THEN
        ALTER TABLE public.invitations
            ADD CONSTRAINT invitations_email_check CHECK (
                email = lower(btrim(email))
                AND email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
        WHERE conrelid = 'public.invitations'::pg_catalog.regclass
          AND conname = 'invitations_acceptance_pair_check'
    ) THEN
        ALTER TABLE public.invitations
            ADD CONSTRAINT invitations_acceptance_pair_check
            CHECK ((accepted_at IS NULL) = (accepted_by IS NULL));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
        WHERE conrelid = 'public.invitations'::pg_catalog.regclass
          AND conname = 'invitations_revocation_pair_check'
    ) THEN
        ALTER TABLE public.invitations
            ADD CONSTRAINT invitations_revocation_pair_check
            CHECK ((revoked_at IS NULL) = (revoked_by IS NULL));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
        WHERE conrelid = 'public.invitations'::pg_catalog.regclass
          AND conname = 'invitations_terminal_state_check'
    ) THEN
        ALTER TABLE public.invitations
            ADD CONSTRAINT invitations_terminal_state_check
            CHECK (accepted_at IS NULL OR revoked_at IS NULL);
    END IF;
END
$migration$;

CREATE INDEX IF NOT EXISTS invitations_tenant_created_idx
    ON public.invitations (tenant_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS invitations_pending_tenant_email_uidx
    ON public.invitations (tenant_id, email)
    WHERE accepted_at IS NULL AND revoked_at IS NULL;

-- The historical three-column constraint does not prevent duplicate pending
-- rows because accepted_at is NULL. Once semantic pending uniqueness exists it
-- is redundant and misleading. The historical token index is likewise covered
-- by the canonical unique token constraint.
ALTER TABLE public.invitations
    DROP CONSTRAINT IF EXISTS unique_tenant_email;
DROP INDEX IF EXISTS public.idx_invitations_token_hash;

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_trigger AS t
        WHERE t.tgrelid = 'public.invitations'::pg_catalog.regclass
          AND t.tgname = 'invitations_touch_updated_at'
          AND NOT t.tgisinternal
    ) THEN
        IF to_regprocedure('public.touch_updated_at()') IS NOT NULL THEN
            EXECUTE 'CREATE TRIGGER invitations_touch_updated_at '
                 || 'BEFORE UPDATE ON public.invitations FOR EACH ROW '
                 || 'EXECUTE FUNCTION public.touch_updated_at()';
        ELSIF to_regprocedure('public.tanda1_touch_updated_at()') IS NOT NULL THEN
            EXECUTE 'CREATE TRIGGER invitations_touch_updated_at '
                 || 'BEFORE UPDATE ON public.invitations FOR EACH ROW '
                 || 'EXECUTE FUNCTION public.tanda1_touch_updated_at()';
        ELSE
            RAISE EXCEPTION USING
                ERRCODE = 'undefined_function',
                MESSAGE = 'invitation_updated_at_helper_missing';
        END IF;
    END IF;
END
$migration$;

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.invitations FROM PUBLIC, anon, authenticated, service_role;

DROP POLICY IF EXISTS "Admins and Operators can view invitations" ON public.invitations;
DROP POLICY IF EXISTS "Admins can insert invitations" ON public.invitations;
DROP POLICY IF EXISTS "Admins can update invitations (revoke)" ON public.invitations;

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'invitations'
          AND policyname = 'invitations_select_admin'
    ) THEN
        CREATE POLICY invitations_select_admin ON public.invitations
            FOR SELECT TO authenticated
            USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin']));
    END IF;
END
$migration$;

-- Preserve the exact modern create identity/OID and BH1 body. The schema fix is
-- sufficient to make it compile; only its security attributes are reconciled.
DO $migration$
BEGIN
    IF to_regprocedure('public.rpc_create_invitation(uuid,text,text)') IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = 'undefined_function',
            MESSAGE = 'rpc_create_invitation_contract_missing';
    END IF;
END
$migration$;

ALTER FUNCTION public.rpc_create_invitation(uuid, text, text)
    SECURITY DEFINER
    SET search_path TO pg_catalog, public, extensions;
REVOKE ALL ON FUNCTION public.rpc_create_invitation(uuid, text, text)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_invitation(uuid, text, text)
    TO authenticated;

-- Staging-only legacy overloads are retained by identity/OID but neutralized.
-- Their old bodies wrote Auth internals or hard-deleted invitation history;
-- neither behavior is part of the disabled beta invitation deployment.
DO $migration$
BEGIN
    IF to_regprocedure('public.rpc_accept_invitation(text,text,text)') IS NOT NULL THEN
        EXECUTE $sql$
            CREATE OR REPLACE FUNCTION public.rpc_accept_invitation(
                p_token text,
                p_password text,
                p_full_name text
            ) RETURNS jsonb
            LANGUAGE plpgsql
            SECURITY DEFINER
            SET search_path TO pg_catalog, public
            AS $function$
            BEGIN
                RETURN jsonb_build_object('accepted', false, 'state', 'disabled');
            END
            $function$
        $sql$;
        EXECUTE 'REVOKE ALL ON FUNCTION public.rpc_accept_invitation(text,text,text) '
             || 'FROM PUBLIC, anon, authenticated, service_role';
    END IF;

    IF to_regprocedure('public.rpc_revoke_invitation(uuid,uuid)') IS NOT NULL THEN
        EXECUTE $sql$
            CREATE OR REPLACE FUNCTION public.rpc_revoke_invitation(
                p_tenant_id uuid,
                p_invitation_id uuid
            ) RETURNS jsonb
            LANGUAGE plpgsql
            SECURITY DEFINER
            SET search_path TO pg_catalog, public
            AS $function$
            BEGIN
                RETURN jsonb_build_object('accepted', false, 'state', 'disabled');
            END
            $function$
        $sql$;
        EXECUTE 'REVOKE ALL ON FUNCTION public.rpc_revoke_invitation(uuid,uuid) '
             || 'FROM PUBLIC, anon, authenticated, service_role';
    END IF;
END
$migration$;

COMMIT;
