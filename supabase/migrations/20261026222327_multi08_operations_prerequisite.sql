-- MULTI-08 selective prerequisite from MULTI-06 commit 4a61ce2acbdd50d4fe6a481b62d0cdd38dbe5d95.
-- New version after the applied fiscal delta; original worktree/version preserved.
-- MULTI-06 preparation only: legacy APIs remain unchanged; new APIs stay closed.
BEGIN;

DO $owner$
DECLARE r oid; api text;
BEGIN
    SELECT oid INTO r FROM pg_catalog.pg_roles WHERE rolname='rotero_operations_read_owner';
    IF r IS NULL THEN
        CREATE ROLE rotero_operations_read_owner NOLOGIN NOINHERIT NOSUPERUSER
            NOCREATEDB NOCREATEROLE NOBYPASSRLS NOREPLICATION;
        COMMENT ON ROLE rotero_operations_read_owner IS 'ROTERO MULTI-06 minimal operations reader v1';
        SELECT oid INTO r FROM pg_catalog.pg_roles WHERE rolname='rotero_operations_read_owner';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE oid=r AND NOT rolcanlogin AND NOT rolinherit
        AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolbypassrls AND NOT rolreplication
        AND pg_catalog.shobj_description(oid,'pg_authid')='ROTERO MULTI-06 minimal operations reader v1')
        OR EXISTS (SELECT FROM pg_catalog.pg_auth_members WHERE member=r) THEN
        RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='multi06_owner_collision';
    END IF;
    FOREACH api IN ARRAY ARRAY['anon','authenticated','service_role','authenticator'] LOOP
        IF pg_catalog.pg_has_role(api,r,'MEMBER') THEN
            RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='multi06_owner_exposed';
        END IF;
    END LOOP;
END;
$owner$;
GRANT rotero_operations_read_owner TO CURRENT_USER WITH SET TRUE;
GRANT rotero_operations_read_owner TO CURRENT_USER WITH INHERIT FALSE;
GRANT USAGE ON SCHEMA public,private TO rotero_operations_read_owner;

-- Preserve pre-existing column REFERENCES; remove only temporary additions.
DO $company_reference$
DECLARE actor text:=current_user; missing text;
BEGIN
    SELECT string_agg(pg_catalog.quote_ident(c),',') INTO missing
    FROM unnest(ARRAY['tenant_id','id']) cols(c)
    WHERE NOT pg_catalog.has_column_privilege(actor,'public.companies',c,'REFERENCES');
    PERFORM pg_catalog.set_config('multi06.migration_actor',actor,true);
    PERFORM pg_catalog.set_config('multi06.reference_columns',COALESCE(missing,''),true);
    SET LOCAL ROLE rotero_company_access_owner;
    IF missing IS NOT NULL THEN
        EXECUTE format('GRANT REFERENCES (%s) ON public.companies TO %I',missing,actor);
    END IF;
    GRANT EXECUTE ON FUNCTION private.multi05_has_company_capability(uuid,uuid,text)
        TO rotero_operations_read_owner;
    EXECUTE format('SET LOCAL ROLE %I',actor);
END;
$company_reference$;

ALTER TABLE public.operations
    ADD COLUMN company_id uuid,
    ADD COLUMN company_classification_status text NOT NULL DEFAULT 'pending_classification',
    ADD COLUMN company_classification_event_id uuid,
    ADD CONSTRAINT operations_tenant_id_key UNIQUE (tenant_id,id),
    ADD CONSTRAINT operations_company_id_key UNIQUE (tenant_id,company_id,id),
    ADD CONSTRAINT operations_company_fk FOREIGN KEY (tenant_id,company_id)
        REFERENCES public.companies(tenant_id,id) ON DELETE RESTRICT,
    ADD CONSTRAINT operations_company_classification_check CHECK (
        (company_classification_status='resolved' AND company_id IS NOT NULL AND company_classification_event_id IS NOT NULL)
        OR (company_classification_status IN ('pending_classification','conflict') AND company_id IS NULL)
    );
CREATE INDEX operations_company_page_idx ON public.operations(tenant_id,company_id,id)
    WHERE company_classification_status='resolved';

-- No automatic inference or historical-row DML. A trusted evidence event must
-- precede an explicit resolution; ordinary users get no classification API.
CREATE TABLE private.operation_company_classification_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    operation_id uuid NOT NULL,
    company_id uuid,
    decision text NOT NULL,
    evidence_kind text NOT NULL CHECK (evidence_kind IN (
        'verified_source_record','verified_parent','approved_resolution','insufficient_evidence','conflicting_evidence'
    )),
    evidence_reference text NOT NULL CHECK (
        evidence_reference=btrim(evidence_reference) AND char_length(evidence_reference) BETWEEN 1 AND 400
    ),
    recorded_by uuid NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT operation_classification_decision_check CHECK (
        (decision='resolved' AND company_id IS NOT NULL
            AND evidence_kind IN ('verified_source_record','verified_parent','approved_resolution'))
        OR (decision='pending_classification' AND company_id IS NULL AND evidence_kind='insufficient_evidence')
        OR (decision='conflict' AND company_id IS NULL AND evidence_kind='conflicting_evidence')
    ),
    CONSTRAINT operation_classification_operation_fk FOREIGN KEY (tenant_id,operation_id)
        REFERENCES public.operations(tenant_id,id) ON DELETE RESTRICT,
    CONSTRAINT operation_classification_company_fk FOREIGN KEY (tenant_id,company_id)
        REFERENCES public.companies(tenant_id,id) ON DELETE RESTRICT,
    CONSTRAINT operation_classification_identity_key UNIQUE (tenant_id,operation_id,id),
    CONSTRAINT operation_classification_decision_key UNIQUE (tenant_id,operation_id,decision,id),
    CONSTRAINT operation_classification_resolution_key UNIQUE (tenant_id,operation_id,company_id,decision,id)
);
CREATE INDEX operation_classification_history_idx
    ON private.operation_company_classification_events(tenant_id,operation_id,recorded_at,id);
ALTER TABLE private.operation_company_classification_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.operation_company_classification_events FROM PUBLIC,anon,authenticated,service_role;

ALTER TABLE public.operations
    ADD CONSTRAINT operations_classification_event_fk FOREIGN KEY (tenant_id,id,company_classification_event_id)
        REFERENCES private.operation_company_classification_events(tenant_id,operation_id,id) ON DELETE RESTRICT,
    ADD CONSTRAINT operations_classification_decision_fk
        FOREIGN KEY (tenant_id,id,company_classification_status,company_classification_event_id)
        REFERENCES private.operation_company_classification_events(tenant_id,operation_id,decision,id) ON DELETE RESTRICT,
    ADD CONSTRAINT operations_classification_company_event_fk
        FOREIGN KEY (tenant_id,id,company_id,company_classification_status,company_classification_event_id)
        REFERENCES private.operation_company_classification_events(tenant_id,operation_id,company_id,decision,id) ON DELETE RESTRICT;

-- Parent-derived ownership: no independent company field on these children.
-- NOT VALID preserves uninspected history; new writes must already be coherent.
DO $children$
DECLARE child text;
BEGIN
    FOREACH child IN ARRAY ARRAY['operation_assignment_history','operation_incidents','operation_evidence',
        'operation_documents','operation_crossings','operation_billing','tracking_tokens','tracking_events','tracking_route_points'] LOOP
        EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (tenant_id,operation_id)
            REFERENCES public.operations(tenant_id,id) ON DELETE CASCADE NOT VALID',child,child||'_multi06_parent_fk');
    END LOOP;
END;
$children$;

-- This owner cannot read costs, pricing, snapshots, notes, tokens or documents.
GRANT SELECT (id,tenant_id,company_id,company_classification_status,reference_code,status,service_type,
    route_summary,client_display_name,provider_name,operation_scope,execution_type,priority,
    planned_departure,operational_window_start,operational_window_end,created_at)
    ON public.operations TO rotero_operations_read_owner;
CREATE POLICY operations_multi06_minimal_reader ON public.operations
    FOR SELECT TO rotero_operations_read_owner
    USING (company_classification_status='resolved'
        AND private.multi05_has_company_capability(tenant_id,company_id,'operations.read'));

CREATE FUNCTION private.multi06_operation_rows(p_tenant_id uuid,p_company_id uuid)
RETURNS TABLE (id uuid,company_id uuid,reference_code text,status text,service_type text,
    route_summary text,client_display_name text,provider_name text,operation_scope text,
    execution_type text,priority text,planned_departure timestamptz,
    operational_window_start timestamptz,operational_window_end timestamptz,created_at timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $fn$
    SELECT o.id,o.company_id,o.reference_code,o.status,o.service_type,o.route_summary,
        o.client_display_name,o.provider_name,o.operation_scope,o.execution_type,o.priority,
        o.planned_departure,o.operational_window_start,o.operational_window_end,o.created_at
    FROM public.operations o WHERE o.tenant_id=p_tenant_id AND o.company_id=p_company_id
        AND o.company_classification_status='resolved';
$fn$;

CREATE FUNCTION public.rpc_multi06_list_operations(p_tenant_id uuid,p_company_id uuid,
    p_search text DEFAULT '',p_after_id uuid DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE search_text text:=lower(btrim(p_search)); result jsonb; total bigint; next_id uuid;
BEGIN
    IF NOT private.multi05_has_company_capability(p_tenant_id,p_company_id,'operations.read') THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    IF p_limit IS NULL OR p_limit<1 OR p_limit>100 OR search_text IS NULL OR char_length(search_text)>160 THEN
        RETURN jsonb_build_object('error','invalid_filters');
    END IF;
    IF p_after_id IS NOT NULL AND NOT EXISTS (
        SELECT FROM private.multi06_operation_rows(p_tenant_id,p_company_id) o WHERE o.id=p_after_id
    ) THEN RETURN jsonb_build_object('error','invalid_cursor'); END IF;
    WITH scoped AS MATERIALIZED (
        SELECT o.* FROM private.multi06_operation_rows(p_tenant_id,p_company_id) o
        WHERE search_text='' OR position(search_text IN lower(concat_ws(' ',o.reference_code,o.route_summary,
            o.client_display_name,o.provider_name)))>0
    ), page AS (
        SELECT s.* FROM scoped s WHERE p_after_id IS NULL OR s.id>p_after_id ORDER BY s.id LIMIT p_limit
    )
    SELECT (SELECT count(*) FROM scoped),
        COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM page p),'[]'::jsonb),
        CASE WHEN EXISTS (SELECT FROM scoped s WHERE s.id>(SELECT p.id FROM page p ORDER BY p.id DESC LIMIT 1))
            THEN (SELECT p.id FROM page p ORDER BY p.id DESC LIMIT 1) END
        INTO total,result,next_id;
    RETURN jsonb_build_object('items',result,'total',total,'next_cursor',next_id,
        'scope',jsonb_build_object('tenant_id',p_tenant_id,'company_id',p_company_id),
        'classification_notice','resolved_only; pending/conflict remain in the unchanged legacy workflow');
END;
$fn$;

CREATE FUNCTION public.rpc_multi06_get_operation(p_tenant_id uuid,p_company_id uuid,p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE item jsonb;
BEGIN
    IF NOT private.multi05_has_company_capability(p_tenant_id,p_company_id,'operations.read') THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    SELECT to_jsonb(o) INTO item FROM private.multi06_operation_rows(p_tenant_id,p_company_id) o WHERE o.id=p_operation_id;
    IF item IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    RETURN jsonb_build_object('item',item);
END;
$fn$;

CREATE FUNCTION public.rpc_multi06_export_operations_page(p_tenant_id uuid,p_company_id uuid,
    p_search text DEFAULT '',p_after_id uuid DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
BEGIN
    IF NOT private.multi05_has_company_capability(p_tenant_id,p_company_id,'export.operational') THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    RETURN public.rpc_multi06_list_operations(p_tenant_id,p_company_id,p_search,p_after_id,p_limit);
END;
$fn$;

-- Backend activation gate, not a UI flag. Even authorized clients cannot call
-- these prepared endpoints until a later reviewed migration closes bypasses.
REVOKE ALL ON FUNCTION private.multi06_operation_rows(uuid,uuid),
    public.rpc_multi06_list_operations(uuid,uuid,text,uuid,integer),
    public.rpc_multi06_get_operation(uuid,uuid,uuid),
    public.rpc_multi06_export_operations_page(uuid,uuid,text,uuid,integer)
    FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE private.operation_company_classification_events IS
    'Closed trusted evidence ledger; no inference, public administration, seeds or backfill. Retain history.';
GRANT CREATE ON SCHEMA public,private TO rotero_operations_read_owner;
ALTER TABLE private.operation_company_classification_events OWNER TO rotero_operations_read_owner;
ALTER FUNCTION private.multi06_operation_rows(uuid,uuid) OWNER TO rotero_operations_read_owner;
ALTER FUNCTION public.rpc_multi06_list_operations(uuid,uuid,text,uuid,integer) OWNER TO rotero_operations_read_owner;
ALTER FUNCTION public.rpc_multi06_get_operation(uuid,uuid,uuid) OWNER TO rotero_operations_read_owner;
ALTER FUNCTION public.rpc_multi06_export_operations_page(uuid,uuid,text,uuid,integer) OWNER TO rotero_operations_read_owner;
REVOKE CREATE ON SCHEMA public,private FROM rotero_operations_read_owner;
DO $reference_cleanup$
DECLARE actor text:=pg_catalog.current_setting('multi06.migration_actor');
    missing text:=pg_catalog.current_setting('multi06.reference_columns');
BEGIN
    IF missing<>'' THEN
        SET LOCAL ROLE rotero_company_access_owner;
        EXECUTE format('REVOKE REFERENCES (%s) ON public.companies FROM %I',missing,actor);
        EXECUTE format('SET LOCAL ROLE %I',actor);
    END IF;
END;
$reference_cleanup$;
COMMENT ON COLUMN public.operations.company_id IS 'No inferred/default company. MULTI-06 remains prepared, not activated.';
COMMIT;
