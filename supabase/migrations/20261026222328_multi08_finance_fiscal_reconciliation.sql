-- MULTI-08: reviewed MULTI-07 candidate composed with installed fiscal02 filters.
-- The original uncommitted migration remains untouched at its source.
-- MULTI-07: explicit financial ownership; closed new APIs; guarded legacy reads.
BEGIN;
-- Normalize ONLY the reviewed fiscal02 source redirections, retaining original
-- expected hashes. All other body drift remains a hard failure.
CREATE FUNCTION pg_temp.multi08_pre_fiscal_reader_source(value text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $normalizer$
DECLARE result text:=value; name text;
BEGIN
 FOREACH name IN ARRAY ARRAY['finance_invoices','finance_payments','billing_documents','billing_credit_notes','billing_payment_complements'] LOOP
  result:=replace(result,'private.fiscal02_legacy_'||name,'public.'||name);
 END LOOP;
 RETURN replace(result,'private.fiscal02_readable_cfdis','public.billing_cfdis');
END $normalizer$;
DO $roles$
DECLARE r text; api text; actor text:=current_user; missing text;
BEGIN
    FOREACH r IN ARRAY ARRAY['rotero_finance_scope_owner','rotero_finance_read_owner'] LOOP
        IF NOT EXISTS(SELECT FROM pg_catalog.pg_roles WHERE rolname=r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOREPLICATION',r);
            EXECUTE format('COMMENT ON ROLE %I IS %L',r,'ROTERO MULTI-07 limited owner v1');
        END IF;
        IF NOT EXISTS(SELECT FROM pg_catalog.pg_roles WHERE rolname=r AND NOT rolcanlogin AND NOT rolinherit
            AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolbypassrls AND NOT rolreplication
            AND pg_catalog.shobj_description(oid,'pg_authid')='ROTERO MULTI-07 limited owner v1')
            OR EXISTS(SELECT FROM pg_catalog.pg_auth_members a JOIN pg_catalog.pg_roles p ON p.oid=a.member WHERE p.rolname=r) THEN
            RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='multi07_owner_collision';
        END IF;
        FOREACH api IN ARRAY ARRAY['anon','authenticated','service_role','authenticator'] LOOP
            IF pg_catalog.pg_has_role(api,r,'MEMBER') THEN
                RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='multi07_owner_exposed';
            END IF;
        END LOOP;
        EXECUTE format('GRANT %I TO %I WITH SET TRUE',r,actor);
        EXECUTE format('GRANT %I TO %I WITH INHERIT FALSE',r,actor);
        EXECUTE format('GRANT USAGE ON SCHEMA public,private TO %I',r);
    END LOOP;
    SELECT string_agg(pg_catalog.quote_ident(c),',') INTO missing FROM unnest(ARRAY['tenant_id','id']) q(c)
    WHERE NOT pg_catalog.has_column_privilege(actor,'public.companies',c,'REFERENCES');
    PERFORM pg_catalog.set_config('multi07.actor',actor,true);
    PERFORM pg_catalog.set_config('multi07.refs',COALESCE(missing,''),true);
    SET LOCAL ROLE rotero_company_access_owner;
    IF missing IS NOT NULL THEN EXECUTE format('GRANT REFERENCES (%s) ON public.companies TO %I',missing,actor); END IF;
    GRANT EXECUTE ON FUNCTION private.multi05_has_company_capability(uuid,uuid,text),private.multi05_can_consolidate(uuid,uuid[])
        TO rotero_finance_scope_owner,rotero_finance_read_owner;
    EXECUTE format('SET LOCAL ROLE %I',actor);
END;
$roles$;

-- Three roots. Payments and complements inherit their invoice: no second owner.
DO $roots$
DECLARE root text; evidence text;
BEGIN
    FOREACH root IN ARRAY ARRAY['finance_invoices','billing_documents','billing_credit_notes'] LOOP
        evidence:=root||'_company_evidence';
        EXECUTE format('ALTER TABLE public.%I ADD COLUMN company_id uuid,
            ADD COLUMN company_classification_status text NOT NULL DEFAULT ''pending_classification'',
            ADD COLUMN company_classification_event_id uuid,
            ADD UNIQUE(tenant_id,id), ADD UNIQUE(tenant_id,company_id,id),
            ADD FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id) ON DELETE RESTRICT,
            ADD CHECK((company_classification_status=''resolved'' AND company_id IS NOT NULL AND company_classification_event_id IS NOT NULL)
                OR (company_classification_status IN (''pending_classification'',''conflict'') AND company_id IS NULL))',root);
        EXECUTE format('CREATE TABLE private.%I (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tenant_id uuid NOT NULL,entity_id uuid NOT NULL,company_id uuid,
            decision text NOT NULL,evidence_kind text NOT NULL,evidence_reference text NOT NULL,
            recorded_by uuid NOT NULL,recorded_at timestamptz NOT NULL DEFAULT now(),
            CHECK(evidence_reference=btrim(evidence_reference) AND char_length(evidence_reference) BETWEEN 1 AND 400),
            CHECK((decision=''resolved'' AND company_id IS NOT NULL AND evidence_kind IN (''verified_source_record'',''verified_parent'',''approved_resolution''))
                OR (decision=''pending_classification'' AND company_id IS NULL AND evidence_kind=''insufficient_evidence'')
                OR (decision=''conflict'' AND company_id IS NULL AND evidence_kind=''conflicting_evidence'')),
            FOREIGN KEY(tenant_id,entity_id) REFERENCES public.%I(tenant_id,id) ON DELETE RESTRICT,
            FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id) ON DELETE RESTRICT,
            UNIQUE(tenant_id,entity_id,id),UNIQUE(tenant_id,entity_id,decision,id),
            UNIQUE(tenant_id,entity_id,company_id,decision,id))',evidence,root);
        EXECUTE format('ALTER TABLE public.%I
            ADD FOREIGN KEY(tenant_id,id,company_classification_event_id) REFERENCES private.%I(tenant_id,entity_id,id),
            ADD FOREIGN KEY(tenant_id,id,company_classification_status,company_classification_event_id)
                REFERENCES private.%I(tenant_id,entity_id,decision,id),
            ADD FOREIGN KEY(tenant_id,id,company_id,company_classification_status,company_classification_event_id)
                REFERENCES private.%I(tenant_id,entity_id,company_id,decision,id)',root,evidence,evidence,evidence);
        EXECUTE format('CREATE INDEX ON public.%I(tenant_id,company_id,id) WHERE company_classification_status=''resolved''',root);
        EXECUTE format('CREATE INDEX ON private.%I(tenant_id,entity_id,recorded_at,id)',evidence);
        EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',evidence);
        EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated,service_role',evidence);
    END LOOP;
END;
$roots$;
ALTER TABLE public.finance_payments ADD CONSTRAINT finance_payments_multi07_identity UNIQUE(tenant_id,invoice_id,id);
DO $relations$
DECLARE root text; parent text; column_name text; key_name text;
BEGIN
    FOR root,column_name,parent IN SELECT * FROM (VALUES
        ('finance_invoices','operation_id','operations'),('finance_invoices','billing_document_id','billing_documents'),
        ('billing_documents','operation_id','operations'),('billing_credit_notes','operation_id','operations'),
        ('billing_credit_notes','finance_invoice_id','finance_invoices'),
        ('billing_credit_notes','source_billing_document_id','billing_documents'),
        ('billing_credit_notes','credit_billing_document_id','billing_documents')) v(a,b,c) LOOP
        key_name:=root||'_'||column_name||'_m07';
        EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY(tenant_id,%I) REFERENCES public.%I(tenant_id,id) NOT VALID',
            root,key_name,column_name,parent);
        EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY(tenant_id,company_id,%I)
            REFERENCES public.%I(tenant_id,company_id,id) NOT VALID',root,key_name||'_co',column_name,parent);
    END LOOP;
END;
$relations$;
ALTER TABLE public.finance_payments ADD CONSTRAINT finance_payments_m07_parent FOREIGN KEY(tenant_id,invoice_id)
    REFERENCES public.finance_invoices(tenant_id,id) ON DELETE CASCADE NOT VALID;
ALTER TABLE public.billing_payment_complements ADD CONSTRAINT complements_m07_invoice FOREIGN KEY(tenant_id,finance_invoice_id)
    REFERENCES public.finance_invoices(tenant_id,id) ON DELETE CASCADE NOT VALID,
    ADD CONSTRAINT complements_m07_payment FOREIGN KEY(tenant_id,finance_invoice_id,finance_payment_id)
        REFERENCES public.finance_payments(tenant_id,invoice_id,id) NOT VALID,
    ADD CONSTRAINT complements_m07_invoice_doc FOREIGN KEY(tenant_id,invoice_billing_document_id)
        REFERENCES public.billing_documents(tenant_id,id) NOT VALID,
    ADD CONSTRAINT complements_m07_complement_doc FOREIGN KEY(tenant_id,complement_billing_document_id)
        REFERENCES public.billing_documents(tenant_id,id) NOT VALID;

-- Metadata-only owner sees identifiers/ownership across rows, never money.
GRANT SELECT(id,tenant_id,company_id) ON public.operations TO rotero_finance_scope_owner;
GRANT SELECT(id,tenant_id,company_id,operation_id,billing_document_id,payroll_period_id) ON public.finance_invoices TO rotero_finance_scope_owner;
GRANT SELECT(id,tenant_id,company_id,operation_id) ON public.billing_documents TO rotero_finance_scope_owner;
GRANT SELECT(id,tenant_id,company_id,operation_id,finance_invoice_id,source_billing_document_id,credit_billing_document_id)
    ON public.billing_credit_notes TO rotero_finance_scope_owner;
GRANT SELECT(id,tenant_id,invoice_id) ON public.finance_payments TO rotero_finance_scope_owner;
GRANT SELECT(id,tenant_id,finance_invoice_id,finance_payment_id,invoice_billing_document_id,complement_billing_document_id)
    ON public.billing_payment_complements TO rotero_finance_scope_owner;
DO $metadata_policies$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['operations','finance_invoices','billing_documents','billing_credit_notes','finance_payments','billing_payment_complements'] LOOP
        EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO rotero_finance_scope_owner USING(true)',t||'_m07_metadata',t);
    END LOOP;
END;
$metadata_policies$;

-- Fixed acyclic parent graph; parent company constrains authorization without
-- assigning/backfilling an ambiguous root. Missing/cross-tenant parents fail shut.
CREATE FUNCTION private.multi07_entity_scope(p_kind text,p_id uuid)
RETURNS TABLE(tenant_id uuid,company_ids uuid[],coherent boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE d jsonb; links jsonb:='[]'; link jsonb; parent record; ids uuid[]:='{}';
BEGIN
    CASE p_kind
    WHEN 'operation' THEN SELECT jsonb_build_object('tenant',o.tenant_id,'company',o.company_id) INTO d FROM public.operations o WHERE o.id=p_id;
    WHEN 'invoice' THEN
        SELECT jsonb_build_object('tenant',i.tenant_id,'company',i.company_id) INTO d FROM public.finance_invoices i WHERE i.id=p_id;
        SELECT jsonb_build_array(jsonb_build_object('kind','operation','id',i.operation_id),
            jsonb_build_object('kind','document','id',i.billing_document_id)) INTO links FROM public.finance_invoices i WHERE i.id=p_id;
    WHEN 'document' THEN
        SELECT jsonb_build_object('tenant',b.tenant_id,'company',b.company_id) INTO d FROM public.billing_documents b WHERE b.id=p_id;
        SELECT jsonb_build_array(jsonb_build_object('kind','operation','id',b.operation_id)) INTO links FROM public.billing_documents b WHERE b.id=p_id;
    WHEN 'credit' THEN
        SELECT jsonb_build_object('tenant',c.tenant_id,'company',c.company_id) INTO d FROM public.billing_credit_notes c WHERE c.id=p_id;
        SELECT jsonb_build_array(jsonb_build_object('kind','operation','id',c.operation_id),jsonb_build_object('kind','invoice','id',c.finance_invoice_id),
            jsonb_build_object('kind','document','id',c.source_billing_document_id),jsonb_build_object('kind','document','id',c.credit_billing_document_id))
            INTO links FROM public.billing_credit_notes c WHERE c.id=p_id;
    WHEN 'payment' THEN
        SELECT jsonb_build_object('tenant',p.tenant_id) INTO d FROM public.finance_payments p WHERE p.id=p_id;
        SELECT jsonb_build_array(jsonb_build_object('kind','invoice','id',p.invoice_id)) INTO links FROM public.finance_payments p WHERE p.id=p_id;
    WHEN 'complement' THEN
        SELECT jsonb_build_object('tenant',c.tenant_id) INTO d FROM public.billing_payment_complements c WHERE c.id=p_id;
        SELECT jsonb_build_array(jsonb_build_object('kind','invoice','id',c.finance_invoice_id),jsonb_build_object('kind','payment','id',c.finance_payment_id),
            jsonb_build_object('kind','document','id',c.invoice_billing_document_id),jsonb_build_object('kind','document','id',c.complement_billing_document_id))
            INTO links FROM public.billing_payment_complements c WHERE c.id=p_id;
    ELSE RETURN;
    END CASE;
    IF d IS NULL THEN RETURN; END IF;
    tenant_id:=(d->>'tenant')::uuid; coherent:=true;
    IF d->>'company' IS NOT NULL THEN ids:=ARRAY[(d->>'company')::uuid]; END IF;
    FOR link IN SELECT value FROM pg_catalog.jsonb_array_elements(COALESCE(links,'[]')) LOOP
        IF link->>'id' IS NULL THEN CONTINUE; END IF;
        SELECT * INTO parent FROM private.multi07_entity_scope(link->>'kind',(link->>'id')::uuid);
        IF NOT FOUND OR parent.tenant_id<>tenant_id OR NOT parent.coherent THEN coherent:=false;
        ELSE ids:=ids||parent.company_ids; END IF;
    END LOOP;
    SELECT COALESCE(array_agg(DISTINCT x ORDER BY x),'{}'::uuid[]) INTO company_ids FROM unnest(ids) q(x);
    coherent:=coherent AND cardinality(company_ids)<=1;
    RETURN NEXT;
END;
$fn$;

CREATE FUNCTION private.multi07_scope_allowed(p_tenant uuid,p_companies uuid[],p_consolidated boolean,p_export boolean)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
    SELECT COALESCE(cardinality(p_companies)>0 AND array_ndims(p_companies)=1 AND array_lower(p_companies,1)=1
        AND p_consolidated IS NOT NULL AND p_export IS NOT NULL
        AND cardinality(p_companies)=(SELECT count(DISTINCT x) FROM unnest(p_companies) q(x))
        AND NOT EXISTS(SELECT FROM unnest(p_companies) q(x) WHERE x IS NULL
            OR NOT private.multi05_has_company_capability(p_tenant,x,'financial.full.read')
            OR (p_export AND NOT private.multi05_has_company_capability(p_tenant,x,'export.financial')))
        AND (NOT p_consolidated AND cardinality(p_companies)=1
            OR p_consolidated AND private.multi05_can_consolidate(p_tenant,p_companies)),false);
$fn$;
CREATE FUNCTION private.multi07_invoice_graph_coherent(p_invoice_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
    SELECT EXISTS(SELECT FROM private.multi07_entity_scope('invoice',p_invoice_id) parent WHERE parent.coherent
        AND NOT EXISTS(SELECT FROM (
            SELECT 'payment' kind,id FROM public.finance_payments WHERE invoice_id=p_invoice_id
            UNION ALL SELECT 'credit',id FROM public.billing_credit_notes WHERE finance_invoice_id=p_invoice_id
            UNION ALL SELECT 'complement',id FROM public.billing_payment_complements WHERE finance_invoice_id=p_invoice_id
        ) q CROSS JOIN LATERAL private.multi07_entity_scope(q.kind,q.id) child
        WHERE NOT child.coherent OR child.tenant_id<>parent.tenant_id OR NOT child.company_ids<@parent.company_ids));
$fn$;
GRANT EXECUTE ON FUNCTION private.fiscal02_is_lab_entity(text,uuid) TO rotero_finance_scope_owner;
CREATE FUNCTION private.multi07_row_allowed(p_kind text,p_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
    SELECT NOT private.fiscal02_is_lab_entity(p_kind,p_id) AND EXISTS(SELECT FROM private.multi07_entity_scope(p_kind,p_id) s WHERE s.coherent
        AND private.multi07_scope_allowed(s.tenant_id,s.company_ids,false,false)
        AND (p_kind<>'invoice' OR (private.multi07_invoice_graph_coherent(p_id)
            AND NOT EXISTS(SELECT FROM public.finance_invoices i WHERE i.id=p_id AND i.payroll_period_id IS NOT NULL))));
$fn$;
CREATE FUNCTION private.multi07_legacy_visible(p_kind text,p_id uuid,p_mode text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE s record; companies uuid[];
BEGIN
    IF private.fiscal02_is_lab_entity(p_kind,p_id) THEN RETURN false; END IF;
    IF p_mode NOT IN ('single','set','export') THEN RETURN false; END IF;
    SELECT * INTO s FROM private.multi07_entity_scope(p_kind,p_id);
    IF NOT FOUND OR NOT s.coherent THEN RETURN false; END IF;
    IF p_kind='invoice' AND NOT private.multi07_invoice_graph_coherent(p_id) THEN RETURN false; END IF;
    -- Only genuinely unknown ownership keeps its existing legacy role contract.
    IF cardinality(s.company_ids)=0 THEN RETURN true; END IF;
    -- MULTI-03 explicitly reserves individual payroll; full.read is not that grant.
    IF p_kind='invoice' AND EXISTS(SELECT FROM public.finance_invoices i WHERE i.id=p_id AND i.payroll_period_id IS NOT NULL) THEN RETURN false; END IF;
    IF NOT private.multi07_scope_allowed(s.tenant_id,s.company_ids,false,p_mode='export') THEN RETURN false; END IF;
    IF p_mode='single' THEN RETURN true; END IF;
    SELECT array_agg(DISTINCT company_id ORDER BY company_id) INTO companies FROM (
        SELECT company_id FROM public.operations WHERE tenant_id=s.tenant_id AND company_id IS NOT NULL
        UNION SELECT company_id FROM public.finance_invoices WHERE tenant_id=s.tenant_id AND company_id IS NOT NULL
        UNION SELECT company_id FROM public.billing_documents WHERE tenant_id=s.tenant_id AND company_id IS NOT NULL
        UNION SELECT company_id FROM public.billing_credit_notes WHERE tenant_id=s.tenant_id AND company_id IS NOT NULL
    ) q;
    RETURN private.multi07_scope_allowed(s.tenant_id,companies,cardinality(companies)>1,p_mode='export');
END;
$fn$;

-- AFTER constraint trigger checks the complete financial graph, including a
-- changed parent. It never sets company, changes amounts, FX, status or balances.
CREATE FUNCTION private.multi07_check_relations() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE bad boolean;
BEGIN
    WITH RECURSIVE edges(kind,id,parent_kind,parent_id) AS (
        SELECT 'invoice',id,'operation',operation_id FROM public.finance_invoices
        UNION ALL SELECT 'invoice',id,'document',billing_document_id FROM public.finance_invoices
        UNION ALL SELECT 'document',id,'operation',operation_id FROM public.billing_documents
        UNION ALL SELECT 'credit',id,'operation',operation_id FROM public.billing_credit_notes
        UNION ALL SELECT 'credit',id,'invoice',finance_invoice_id FROM public.billing_credit_notes
        UNION ALL SELECT 'credit',id,'document',source_billing_document_id FROM public.billing_credit_notes
        UNION ALL SELECT 'credit',id,'document',credit_billing_document_id FROM public.billing_credit_notes
        UNION ALL SELECT 'payment',id,'invoice',invoice_id FROM public.finance_payments
        UNION ALL SELECT 'complement',id,'invoice',finance_invoice_id FROM public.billing_payment_complements
        UNION ALL SELECT 'complement',id,'payment',finance_payment_id FROM public.billing_payment_complements
        UNION ALL SELECT 'complement',id,'document',invoice_billing_document_id FROM public.billing_payment_complements
        UNION ALL SELECT 'complement',id,'document',complement_billing_document_id FROM public.billing_payment_complements
    ), affected(kind,id) AS (
        SELECT CASE TG_TABLE_NAME WHEN 'operations' THEN 'operation' WHEN 'finance_invoices' THEN 'invoice'
            WHEN 'billing_documents' THEN 'document' WHEN 'billing_credit_notes' THEN 'credit'
            WHEN 'finance_payments' THEN 'payment' ELSE 'complement' END,NEW.id
        UNION SELECT 'invoice',COALESCE(to_jsonb(NEW)->>'finance_invoice_id',to_jsonb(NEW)->>'invoice_id')::uuid
            WHERE TG_TABLE_NAME IN ('billing_credit_notes','finance_payments','billing_payment_complements')
                AND COALESCE(to_jsonb(NEW)->>'finance_invoice_id',to_jsonb(NEW)->>'invoice_id') IS NOT NULL
        UNION SELECT e.kind,e.id FROM edges e JOIN affected a ON e.parent_kind=a.kind AND e.parent_id=a.id
    ) SELECT EXISTS(SELECT FROM affected a CROSS JOIN LATERAL private.multi07_entity_scope(a.kind,a.id) s
        WHERE NOT s.coherent OR a.kind='invoice' AND NOT private.multi07_invoice_graph_coherent(a.id)) INTO bad;
    IF bad THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='multi07_incompatible_financial_relation'; END IF;
    RETURN NULL;
END;
$fn$;
CREATE FUNCTION private.multi07_lock_relations() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $fn$
BEGIN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(NEW.tenant_id::text,7007));
    RETURN NEW;
END;
$fn$;
-- Only the affected graph is checked; unrelated historical drift must not block
-- all modules. Amounts, tax states, FX and ordinary operation status are untouched.
DO $checks$
DECLARE t text; cols text;
BEGIN
    FOREACH t IN ARRAY ARRAY['operations','finance_invoices','billing_documents','billing_credit_notes','finance_payments','billing_payment_complements'] LOOP
        cols:=CASE t WHEN 'operations' THEN 'tenant_id,company_id'
            WHEN 'finance_invoices' THEN 'tenant_id,company_id,operation_id,billing_document_id'
            WHEN 'billing_documents' THEN 'tenant_id,company_id,operation_id'
            WHEN 'billing_credit_notes' THEN 'tenant_id,company_id,operation_id,finance_invoice_id,source_billing_document_id,credit_billing_document_id'
            WHEN 'finance_payments' THEN 'tenant_id,invoice_id'
            ELSE 'tenant_id,finance_invoice_id,finance_payment_id,invoice_billing_document_id,complement_billing_document_id' END;
        EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE OF %s ON public.%I
            FOR EACH ROW EXECUTE FUNCTION private.multi07_lock_relations()',t||'_m07_lock',cols,t);
        EXECUTE format('CREATE TRIGGER %I AFTER INSERT OR UPDATE OF %s ON public.%I
            FOR EACH ROW EXECUTE FUNCTION private.multi07_check_relations()',t||'_m07_coherence',cols,t);
    END LOOP;
END;
$checks$;

-- New reader: only the explicit DTO columns, no notes/bank/PII snapshots/files.
GRANT SELECT(id,tenant_id,company_id,company_classification_status,operation_id,direction,reference,counterparty_name,
    amount,currency,status,due_date,created_at) ON public.finance_invoices TO rotero_finance_read_owner;
GRANT SELECT(id,tenant_id,invoice_id,amount,currency,paid_at,method) ON public.finance_payments TO rotero_finance_read_owner;
GRANT SELECT(id,tenant_id,company_id,finance_invoice_id,total,currency,status,created_at)
    ON public.billing_credit_notes TO rotero_finance_read_owner;
GRANT SELECT(id,tenant_id,finance_invoice_id,finance_payment_id,amount,currency,status,payment_date)
    ON public.billing_payment_complements TO rotero_finance_read_owner;
CREATE POLICY finance_invoices_m07_reader ON public.finance_invoices FOR SELECT TO rotero_finance_read_owner
    USING(company_classification_status='resolved' AND private.multi07_row_allowed('invoice',id));
CREATE POLICY finance_payments_m07_reader ON public.finance_payments FOR SELECT TO rotero_finance_read_owner
    USING(private.multi07_row_allowed('payment',id));
CREATE POLICY credits_m07_reader ON public.billing_credit_notes FOR SELECT TO rotero_finance_read_owner
    USING(private.multi07_row_allowed('credit',id));
CREATE POLICY complements_m07_reader ON public.billing_payment_complements FOR SELECT TO rotero_finance_read_owner
    USING(private.multi07_row_allowed('complement',id));

-- Existing APIs are RPC-first and already revoke raw tables. A restrictive
-- policy also keeps an accidental table/column grant from reopening role-only
-- reads or self-classification. Existing definer write contracts are unchanged.
DO $raw_api_guard$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['finance_invoices','finance_payments','billing_documents','billing_credit_notes','billing_payment_complements'] LOOP
        EXECUTE format('CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING(false) WITH CHECK(false)',t||'_m07_no_raw_api',t);
    END LOOP;
END;
$raw_api_guard$;

CREATE FUNCTION private.multi07_invoice_rows(p_tenant uuid,p_companies uuid[])
RETURNS TABLE(id uuid,company_id uuid,operation_id uuid,direction text,reference text,counterparty_name text,
    currency text,status text,due_date date,amount numeric,paid_amount numeric,credit_amount numeric,balance_amount numeric,created_at timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $fn$
    SELECT i.id,i.company_id,i.operation_id,i.direction,i.reference,i.counterparty_name,i.currency,i.status,i.due_date,i.amount,
        COALESCE(p.total,0),COALESCE(c.total,0),GREATEST(i.amount-COALESCE(p.total,0)-COALESCE(c.total,0),0),i.created_at
    FROM public.finance_invoices i
    LEFT JOIN LATERAL(SELECT sum(amount) total FROM public.finance_payments WHERE tenant_id=i.tenant_id AND invoice_id=i.id) p ON true
    LEFT JOIN LATERAL(SELECT sum(total) total FROM public.billing_credit_notes
        WHERE tenant_id=i.tenant_id AND finance_invoice_id=i.id AND status='applied') c ON true
    WHERE i.tenant_id=p_tenant AND i.company_id=ANY(p_companies) AND i.company_classification_status='resolved';
$fn$;

CREATE FUNCTION public.rpc_multi07_list_invoices(p_tenant_id uuid,p_company_ids uuid[],p_search text DEFAULT '',
    p_direction text DEFAULT '',p_currency text DEFAULT '',p_after_id uuid DEFAULT NULL,p_limit integer DEFAULT 50,p_consolidated boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE result jsonb; total bigint; next_id uuid; needle text:=lower(btrim(p_search));
BEGIN
    IF NOT private.multi07_scope_allowed(p_tenant_id,p_company_ids,p_consolidated,false) THEN
        RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR needle IS NULL OR length(needle)>160
        OR p_direction IS NULL OR p_direction NOT IN ('','ar','ap') OR p_currency IS NULL OR p_currency NOT IN ('','MXN','USD') THEN
        RETURN jsonb_build_object('error','invalid_filters'); END IF;
    IF p_after_id IS NOT NULL AND NOT EXISTS(SELECT FROM private.multi07_invoice_rows(p_tenant_id,p_company_ids) r WHERE r.id=p_after_id) THEN
        RETURN jsonb_build_object('error','invalid_cursor'); END IF;
    WITH scoped AS MATERIALIZED (
        SELECT r.* FROM private.multi07_invoice_rows(p_tenant_id,p_company_ids) r
        WHERE (p_direction='' OR r.direction=p_direction) AND (p_currency='' OR r.currency=p_currency)
            AND (needle='' OR position(needle IN lower(concat_ws(' ',r.reference,r.counterparty_name)))>0)
    ), page AS (SELECT * FROM scoped WHERE p_after_id IS NULL OR id>p_after_id ORDER BY id LIMIT p_limit)
    SELECT (SELECT count(*) FROM scoped),COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM page p),'[]'),
        CASE WHEN EXISTS(SELECT FROM scoped s WHERE s.id>(SELECT id FROM page ORDER BY id DESC LIMIT 1))
            THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END INTO total,result,next_id;
    RETURN jsonb_build_object('items',result,'total',total,'next_cursor',next_id,
        'scope',jsonb_build_object('tenant_id',p_tenant_id,'company_ids',p_company_ids,'consolidated',p_consolidated),
        'classification_notice','resolved_only; payroll and unclassified legacy remain outside this protection');
END;
$fn$;
CREATE FUNCTION public.rpc_multi07_get_invoice(p_tenant_id uuid,p_company_id uuid,p_invoice_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE item jsonb; payments jsonb; credits jsonb; complements jsonb;
BEGIN
    IF NOT private.multi07_scope_allowed(p_tenant_id,ARRAY[p_company_id],false,false) THEN
        RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT to_jsonb(r) INTO item FROM private.multi07_invoice_rows(p_tenant_id,ARRAY[p_company_id]) r WHERE r.id=p_invoice_id;
    IF item IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'invoice_id',invoice_id,'amount',amount,'currency',currency,
        'paid_at',paid_at,'method',method) ORDER BY paid_at,id),'[]') INTO payments FROM public.finance_payments
        WHERE tenant_id=p_tenant_id AND invoice_id=p_invoice_id;
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'invoice_id',finance_invoice_id,'amount',total,'currency',currency,
        'status',status) ORDER BY id),'[]') INTO credits FROM public.billing_credit_notes WHERE tenant_id=p_tenant_id AND finance_invoice_id=p_invoice_id;
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'invoice_id',finance_invoice_id,'payment_id',finance_payment_id,
        'amount',amount,'currency',currency,'status',status) ORDER BY id),'[]') INTO complements FROM public.billing_payment_complements
        WHERE tenant_id=p_tenant_id AND finance_invoice_id=p_invoice_id;
    RETURN jsonb_build_object('item',item,'payments',payments,'credit_notes',credits,'complements',complements);
END;
$fn$;
CREATE FUNCTION public.rpc_multi07_finance_summary(p_tenant_id uuid,p_company_ids uuid[],p_consolidated boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE groups jsonb;
BEGIN
    IF NOT private.multi07_scope_allowed(p_tenant_id,p_company_ids,p_consolidated,false) THEN
        RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.company_id,x.currency,x.direction),'[]') INTO groups FROM (
        SELECT CASE WHEN p_consolidated THEN NULL::uuid ELSE company_id END company_id,currency,direction,count(*) invoice_count,
            sum(amount) amount,sum(paid_amount) paid_amount,sum(credit_amount) credit_amount,sum(balance_amount) balance_amount
        FROM private.multi07_invoice_rows(p_tenant_id,p_company_ids) WHERE status<>'void'
        GROUP BY CASE WHEN p_consolidated THEN NULL::uuid ELSE company_id END,currency,direction
    ) x;
    RETURN jsonb_build_object('groups',groups,'currency_policy','separate',
        'scope',jsonb_build_object('tenant_id',p_tenant_id,'company_ids',p_company_ids,'consolidated',p_consolidated),
        'classification_notice','resolved_only; payroll and unclassified legacy remain outside this protection');
END;
$fn$;
CREATE FUNCTION public.rpc_multi07_export_invoices_page(p_tenant_id uuid,p_company_ids uuid[],p_search text DEFAULT '',
    p_direction text DEFAULT '',p_currency text DEFAULT '',p_after_id uuid DEFAULT NULL,p_limit integer DEFAULT 50,p_consolidated boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
BEGIN
    IF NOT private.multi07_scope_allowed(p_tenant_id,p_company_ids,p_consolidated,true) THEN
        RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN public.rpc_multi07_list_invoices(p_tenant_id,p_company_ids,p_search,p_direction,p_currency,p_after_id,p_limit,p_consolidated);
END;
$fn$;

-- Private transitional sources for existing financial READS, not for writes.
-- Unknown rows keep the old contract; known rows require the verified grants.
DO $views$
DECLARE t text; kind text; mode text; source_relation text;
BEGIN
    FOR t,kind IN SELECT * FROM (VALUES ('operations','operation'),('finance_invoices','invoice'),
        ('billing_documents','document'),('billing_credit_notes','credit'),('finance_payments','payment'),
        ('billing_payment_complements','complement')) q(t,k) LOOP
        FOREACH mode IN ARRAY ARRAY['single','set','export'] LOOP
            EXECUTE format('CREATE VIEW private.%I WITH (security_invoker=true,security_barrier=true) AS
                SELECT r.* FROM %s r WHERE private.multi07_legacy_visible(%L,r.id,%L)',
                'm07_'||mode||'_'||t,CASE WHEN t='operations' THEN 'public.operations' ELSE 'private.fiscal02_legacy_'||t END,kind,mode);
            EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated,service_role','m07_'||mode||'_'||t);
        END LOOP;
    END LOOP;
END;
$views$;

-- MULTI07_LEGACY_READS: ten existing read bodies, explicit and reviewable.

DO $legacy_source_guard$
BEGIN
    IF NOT EXISTS(SELECT FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.rpc_finance_overview(uuid,jsonb)') AND pg_catalog.md5(pg_temp.multi08_pre_fiscal_reader_source(prosrc))='2e2bb2dc1bef64913efbc4e927624116' AND proowner=current_user::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN
        RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='multi07_legacy_source_drift';
    END IF;
    IF NOT EXISTS(SELECT FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.rpc_list_finance_invoices(uuid,jsonb)') AND pg_catalog.md5(pg_temp.multi08_pre_fiscal_reader_source(prosrc))='7a2c91bcf13ef5ea24fac5e60670abd1' AND proowner=current_user::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN
        RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='multi07_legacy_source_drift';
    END IF;
    IF NOT EXISTS(SELECT FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.rpc_get_finance_invoice_detail(uuid,uuid)') AND pg_catalog.md5(pg_temp.multi08_pre_fiscal_reader_source(prosrc))='0aafe20547b2a4775550449bc1b997b7' AND proowner=current_user::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN
        RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='multi07_legacy_source_drift';
    END IF;
    IF NOT EXISTS(SELECT FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.rpc_list_finance_payments(uuid,jsonb)') AND pg_catalog.md5(pg_temp.multi08_pre_fiscal_reader_source(prosrc))='cd9eaceac369d8b167a0357e5249cb31' AND proowner=current_user::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN
        RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='multi07_legacy_source_drift';
    END IF;
    IF NOT EXISTS(SELECT FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.rpc_list_finance_due_alerts(uuid,jsonb)') AND pg_catalog.md5(pg_temp.multi08_pre_fiscal_reader_source(prosrc))='db9e13e2d1aea4075dd316b32249aa4f' AND proowner=current_user::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN
        RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='multi07_legacy_source_drift';
    END IF;
    IF NOT EXISTS(SELECT FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.rpc_get_operation_finance_summary(uuid,uuid)') AND pg_catalog.md5(pg_temp.multi08_pre_fiscal_reader_source(prosrc))='3e84030145bc3d10c33924d921094e0b' AND proowner=current_user::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN
        RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='multi07_legacy_source_drift';
    END IF;
    IF NOT EXISTS(SELECT FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.rpc_finance_profitability(uuid,jsonb)') AND pg_catalog.md5(pg_temp.multi08_pre_fiscal_reader_source(prosrc))='5361fbe6771a3796c173369a33231e76' AND proowner=current_user::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN
        RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='multi07_legacy_source_drift';
    END IF;
    IF NOT EXISTS(SELECT FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.rpc_export_finance_ledger(uuid,jsonb)') AND pg_catalog.md5(pg_temp.multi08_pre_fiscal_reader_source(prosrc))='e4e4fdd3b92c22caa67909cd0dbd5178' AND proowner=current_user::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN
        RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='multi07_legacy_source_drift';
    END IF;
    IF NOT EXISTS(SELECT FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.rpc_list_payment_complements(uuid,jsonb)') AND pg_catalog.md5(pg_temp.multi08_pre_fiscal_reader_source(prosrc))='6b918c255fc48754aded0155a3e80962' AND proowner=current_user::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN
        RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='multi07_legacy_source_drift';
    END IF;
    IF NOT EXISTS(SELECT FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.rpc_export_data_page(uuid,text,jsonb,jsonb,integer)') AND pg_catalog.md5(pg_temp.multi08_pre_fiscal_reader_source(prosrc))='5b0a4ef121291b4874894d94a17d4800' AND proowner=current_user::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN
        RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='multi07_legacy_source_drift';
    END IF;
END;
$legacy_source_guard$;

-- Existing F4 read: rpc_finance_overview; ownership and EXECUTE retained.
CREATE OR REPLACE FUNCTION public.rpc_finance_overview(p_tenant_id uuid, p_filters jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_start date; v_end date; v_result jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    BEGIN
        v_start := NULLIF(p_filters->>'date_from', '')::date;
        v_end := NULLIF(p_filters->>'date_to', '')::date;
    EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error', 'invalid_filters'); END;

    WITH invoice_totals AS (
        SELECT i.*, t.paid_amount, t.credit_amount, t.balance_amount,
            CASE WHEN i.status = 'open' AND i.due_date < current_date THEN 'overdue' ELSE i.status END AS effective_status
        FROM private.m07_set_finance_invoices i
        CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
        WHERE i.tenant_id = p_tenant_id
          AND (v_start IS NULL OR i.created_at::date >= v_start)
          AND (v_end IS NULL OR i.created_at::date <= v_end)
    ), by_currency AS (
        SELECT currency,
            COALESCE(sum(balance_amount) FILTER (WHERE direction = 'ar' AND effective_status IN ('open','overdue')), 0) ar_open,
            COALESCE(sum(balance_amount) FILTER (WHERE direction = 'ap' AND effective_status IN ('open','overdue')), 0) ap_open,
            COALESCE(sum(balance_amount) FILTER (WHERE direction = 'ar' AND effective_status = 'overdue'), 0) ar_overdue,
            COALESCE(sum(balance_amount) FILTER (WHERE direction = 'ap' AND effective_status = 'overdue'), 0) ap_overdue,
            count(*) FILTER (WHERE effective_status IN ('open','overdue')) open_count
        FROM invoice_totals GROUP BY currency
    )
    SELECT jsonb_build_object(
        'currencies', COALESCE(jsonb_agg(to_jsonb(by_currency) ORDER BY currency), '[]'::jsonb),
        'total_ar_open', COALESCE(sum(ar_open) FILTER (WHERE currency = 'MXN'), 0),
        'total_ap_open', COALESCE(sum(ap_open) FILTER (WHERE currency = 'MXN'), 0),
        'total_overdue', COALESCE(sum(ar_overdue) FILTER (WHERE currency = 'MXN'), 0),
        'count_open_invoices', COALESCE(sum(open_count), 0),
        'paid_this_month', COALESCE((SELECT sum(amount) FROM private.m07_set_finance_payments WHERE tenant_id = p_tenant_id AND currency = 'MXN' AND paid_at >= date_trunc('month', now())), 0),
        'chart', jsonb_build_object('labels', '[]'::jsonb, 'values', '[]'::jsonb)
    ) INTO v_result FROM by_currency;
    RETURN COALESCE(v_result, jsonb_build_object('currencies','[]'::jsonb,'total_ar_open',0,'total_ap_open',0,'total_overdue',0,'paid_this_month',0,'count_open_invoices',0,'chart',jsonb_build_object('labels','[]'::jsonb,'values','[]'::jsonb)));
END;
$function$;

-- Existing F4 read: rpc_list_finance_invoices; ownership and EXECUTE retained.
CREATE OR REPLACE FUNCTION public.rpc_list_finance_invoices(p_tenant_id uuid, p_filters jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_limit integer := LEAST(GREATEST(COALESCE(NULLIF(p_filters->>'limit','')::integer, 100), 1), 200);
    v_status text := NULLIF(p_filters->>'status',''); v_direction text := NULLIF(p_filters->>'direction','');
    v_currency text := NULLIF(upper(p_filters->>'currency'),''); v_search text := NULLIF(lower(trim(p_filters->>'search')),'');
    v_operation uuid; v_customer uuid; v_provider uuid; v_due_from date; v_due_to date; v_items jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    BEGIN
        v_operation := NULLIF(p_filters->>'operation_id','')::uuid;
        v_customer := NULLIF(p_filters->>'customer_id','')::uuid;
        v_provider := NULLIF(p_filters->>'provider_id','')::uuid;
        v_due_from := NULLIF(p_filters->>'due_from','')::date;
        v_due_to := NULLIF(p_filters->>'due_to','')::date;
    EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_filters'); END;
    IF v_status IS NOT NULL AND v_status NOT IN ('draft','open','paid','overdue','void') THEN RETURN jsonb_build_object('error','invalid_filters'); END IF;
    IF v_direction IS NOT NULL AND v_direction NOT IN ('ar','ap') THEN RETURN jsonb_build_object('error','invalid_filters'); END IF;

    WITH rows AS (
        SELECT i.*, t.paid_amount, t.credit_amount,
            t.balance_amount,
            CASE WHEN i.status = 'open' AND i.due_date < current_date THEN 'overdue' ELSE i.status END effective_status,
            o.reference_code operation_reference,
            bd.fiscal_uuid billing_fiscal_uuid,
            COALESCE(NULLIF(concat_ws('-', bd.serie, bd.folio), ''), bd.fiscal_uuid) billing_reference
        FROM private.m07_set_finance_invoices i
        CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
        LEFT JOIN private.m07_set_operations o ON o.id = i.operation_id AND o.tenant_id = i.tenant_id
        LEFT JOIN private.m07_set_billing_documents bd ON bd.id = i.billing_document_id AND bd.tenant_id = i.tenant_id
        WHERE i.tenant_id = p_tenant_id
          AND (v_direction IS NULL OR i.direction = v_direction)
          AND (v_currency IS NULL OR i.currency = v_currency)
          AND (v_operation IS NULL OR i.operation_id = v_operation)
          AND (v_customer IS NULL OR i.customer_id = v_customer)
          AND (v_provider IS NULL OR i.provider_id = v_provider)
          AND (v_due_from IS NULL OR i.due_date >= v_due_from)
          AND (v_due_to IS NULL OR i.due_date <= v_due_to)
          AND (v_status IS NULL OR (CASE WHEN i.status = 'open' AND i.due_date < current_date THEN 'overdue' ELSE i.status END) = v_status)
          AND (v_search IS NULL OR lower(concat_ws(' ', i.counterparty_name, i.reference, o.reference_code, bd.fiscal_uuid, bd.serie, bd.folio)) LIKE '%' || v_search || '%')
        ORDER BY i.created_at DESC LIMIT v_limit
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(rows) ORDER BY created_at DESC), '[]'::jsonb) INTO v_items FROM rows;
    RETURN jsonb_build_object('items', v_items, 'count', jsonb_array_length(v_items));
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_filters');
END;
$function$;

-- Existing F4 read: rpc_get_finance_invoice_detail; ownership and EXECUTE retained.
CREATE OR REPLACE FUNCTION public.rpc_get_finance_invoice_detail(p_tenant_id uuid,p_invoice_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_invoice jsonb; v_payments jsonb; v_credits jsonb; v_complements jsonb; v_timeline jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT to_jsonb(x) INTO v_invoice FROM (
        SELECT i.*,t.paid_amount,t.credit_amount,t.balance_amount,
            CASE WHEN i.status='open' AND i.due_date<current_date THEN 'overdue' ELSE i.status END effective_status,
            o.reference_code operation_reference,
            COALESCE(NULLIF(concat_ws('-',bd.serie,bd.folio),''),bd.fiscal_uuid) billing_reference,
            bd.fiscal_uuid billing_fiscal_uuid
        FROM private.m07_single_finance_invoices i CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
        LEFT JOIN private.m07_single_operations o ON o.id=i.operation_id AND o.tenant_id=i.tenant_id
        LEFT JOIN private.m07_single_billing_documents bd ON bd.id=i.billing_document_id AND bd.tenant_id=i.tenant_id
        WHERE i.id=p_invoice_id AND i.tenant_id=p_tenant_id
    ) x;
    IF v_invoice IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.paid_at DESC),'[]'::jsonb) INTO v_payments FROM private.m07_single_finance_payments p WHERE p.invoice_id=p_invoice_id AND p.tenant_id=p_tenant_id;
    SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.issue_date DESC,c.created_at DESC),'[]'::jsonb) INTO v_credits FROM private.m07_single_billing_credit_notes c WHERE c.finance_invoice_id=p_invoice_id AND c.tenant_id=p_tenant_id;
    SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.payment_date DESC),'[]'::jsonb) INTO v_complements FROM private.m07_single_billing_payment_complements c WHERE c.finance_invoice_id=p_invoice_id AND c.tenant_id=p_tenant_id;
    SELECT COALESCE(jsonb_agg(to_jsonb(e) ORDER BY e.occurred_at DESC),'[]'::jsonb) INTO v_timeline FROM (
        SELECT 'invoice_created'::text event_type,i.created_at occurred_at,jsonb_build_object('status',i.status,'amount',i.amount,'currency',i.currency) details FROM private.m07_single_finance_invoices i WHERE i.id=p_invoice_id
        UNION ALL SELECT 'payment_recorded',p.paid_at,jsonb_build_object('payment_id',p.id,'amount',p.amount,'method',p.method) FROM private.m07_single_finance_payments p WHERE p.invoice_id=p_invoice_id
        UNION ALL SELECT 'credit_note_'||c.status,c.created_at,jsonb_build_object('credit_note_id',c.id,'total',c.total,'folio',c.folio) FROM private.m07_single_billing_credit_notes c WHERE c.finance_invoice_id=p_invoice_id
        UNION ALL SELECT 'complement_'||c.status,c.created_at,jsonb_build_object('complement_id',c.id,'payment_id',c.finance_payment_id) FROM private.m07_single_billing_payment_complements c WHERE c.finance_invoice_id=p_invoice_id
    ) e;
    RETURN jsonb_build_object('invoice',v_invoice,'payments',v_payments,'credit_notes',v_credits,'payment_complements',v_complements,'timeline',v_timeline);
END;
$function$;

-- Existing F4 read: rpc_list_finance_payments; ownership and EXECUTE retained.
CREATE OR REPLACE FUNCTION public.rpc_list_finance_payments(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_direction text:=NULLIF(p_filters->>'direction',''); v_method text:=NULLIF(p_filters->>'method',''); v_limit integer:=LEAST(GREATEST(COALESCE(NULLIF(p_filters->>'limit','')::integer,100),1),200); v_items jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.paid_at DESC),'[]'::jsonb) INTO v_items FROM (
        SELECT p.*,i.direction,i.counterparty_name,i.reference,i.operation_id,i.status invoice_status
        FROM private.m07_set_finance_payments p JOIN private.m07_set_finance_invoices i ON i.id=p.invoice_id AND i.tenant_id=p.tenant_id
        WHERE p.tenant_id=p_tenant_id AND (v_direction IS NULL OR i.direction=v_direction) AND (v_method IS NULL OR p.method=v_method)
        ORDER BY p.paid_at DESC LIMIT v_limit
    ) x;
    RETURN jsonb_build_object('items',v_items,'count',jsonb_array_length(v_items));
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_filters');
END;
$function$;

-- Existing F4 read: rpc_list_finance_due_alerts; ownership and EXECUTE retained.
CREATE OR REPLACE FUNCTION public.rpc_list_finance_due_alerts(p_tenant_id uuid,p_filters jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_days integer:=LEAST(GREATEST(COALESCE(NULLIF(p_filters->>'days_ahead','')::integer,14),0),90); v_direction text:=NULLIF(p_filters->>'direction',''); v_items jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.due_date,x.direction,x.counterparty_name),'[]'::jsonb) INTO v_items FROM (
        SELECT i.id,i.direction,i.counterparty_name,i.reference,i.amount,i.currency,i.due_date,t.balance_amount,
            CASE WHEN i.due_date<current_date THEN 'overdue' ELSE 'due_soon' END alert_type,
            i.due_date-current_date days_to_due,i.operation_id,o.reference_code operation_reference
        FROM private.m07_set_finance_invoices i CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
        LEFT JOIN private.m07_set_operations o ON o.id=i.operation_id
        WHERE i.tenant_id=p_tenant_id AND i.status='open' AND t.balance_amount>0 AND i.due_date IS NOT NULL
          AND i.due_date<=current_date+v_days AND (v_direction IS NULL OR i.direction=v_direction)
    ) x;
    RETURN jsonb_build_object('items',v_items,'days_ahead',v_days);
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_filters');
END;
$function$;

-- Existing F4 read: rpc_get_operation_finance_summary; ownership and EXECUTE retained.
CREATE OR REPLACE FUNCTION public.rpc_get_operation_finance_summary(p_tenant_id uuid,p_operation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_result jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT jsonb_build_object(
        'operation_id',o.id,'operation_reference',o.reference_code,'currency',o.pricing_currency,
        'expected_revenue',COALESCE(o.customer_price_amount,0),'expected_cost',COALESCE(o.provider_cost_amount,0),
        'expected_margin',COALESCE(o.customer_price_amount,0)-COALESCE(o.provider_cost_amount,0),
        'registered_ar',COALESCE(sum(i.amount) FILTER(WHERE i.direction='ar' AND i.status<>'void'),0),
        'registered_ap',COALESCE(sum(i.amount) FILTER(WHERE i.direction='ap' AND i.status<>'void'),0),
        'remaining_ar_to_register',GREATEST(COALESCE(o.customer_price_amount,0)-COALESCE(sum(i.amount) FILTER(WHERE i.direction='ar' AND i.status<>'void'),0),0),
        'remaining_ap_to_register',GREATEST(COALESCE(o.provider_cost_amount,0)-COALESCE(sum(i.amount) FILTER(WHERE i.direction='ap' AND i.status<>'void'),0),0)
    ) INTO v_result FROM private.m07_single_operations o LEFT JOIN private.m07_single_finance_invoices i ON i.operation_id=o.id AND i.tenant_id=o.tenant_id
    WHERE o.id=p_operation_id AND o.tenant_id=p_tenant_id GROUP BY o.id,o.reference_code,o.pricing_currency,o.customer_price_amount,o.provider_cost_amount;
    RETURN COALESCE(v_result,jsonb_build_object('error','not_found'));
END;
$function$;

-- Existing F4 read: rpc_finance_profitability; ownership and EXECUTE retained.
CREATE OR REPLACE FUNCTION public.rpc_finance_profitability(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_items jsonb; v_customers jsonb; v_providers jsonb; v_currency text:=NULLIF(upper(p_filters->>'currency'),'');
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    WITH per_operation AS (
        SELECT o.id operation_id,o.reference_code,o.customer_id,o.provider_id,o.pricing_currency currency,
            COALESCE(o.customer_price_amount,0) expected_revenue,COALESCE(o.provider_cost_amount,0) expected_cost,
            COALESCE(i.registered_ar,0) registered_ar,COALESCE(i.registered_ap,0) registered_ap,
            COALESCE(c.cash_in,0) cash_in,COALESCE(c.cash_out,0) cash_out,
            COALESCE(n.credit_ar,0) credit_ar,COALESCE(n.credit_ap,0) credit_ap
        FROM private.m07_set_operations o
        LEFT JOIN LATERAL (
            SELECT sum(amount) FILTER(WHERE direction='ar' AND status<>'void') registered_ar,
                   sum(amount) FILTER(WHERE direction='ap' AND status<>'void') registered_ap
            FROM private.m07_set_finance_invoices WHERE operation_id=o.id AND tenant_id=o.tenant_id
        ) i ON true
        LEFT JOIN LATERAL (
            SELECT sum(fp.amount) FILTER(WHERE fi.direction='ar') cash_in,
                   sum(fp.amount) FILTER(WHERE fi.direction='ap') cash_out
            FROM private.m07_set_finance_payments fp JOIN private.m07_set_finance_invoices fi ON fi.id=fp.invoice_id AND fi.tenant_id=fp.tenant_id
            WHERE fi.operation_id=o.id AND fi.tenant_id=o.tenant_id
        ) c ON true
        LEFT JOIN LATERAL (
            SELECT sum(cn.total) FILTER(WHERE fi.direction='ar') credit_ar,
                   sum(cn.total) FILTER(WHERE fi.direction='ap') credit_ap
            FROM private.m07_set_billing_credit_notes cn JOIN private.m07_set_finance_invoices fi ON fi.id=cn.finance_invoice_id AND fi.tenant_id=cn.tenant_id
            WHERE fi.operation_id=o.id AND fi.tenant_id=o.tenant_id AND cn.status='applied'
        ) n ON true
        WHERE o.tenant_id=p_tenant_id AND (v_currency IS NULL OR o.pricing_currency=v_currency)
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.reference_code),'[]'::jsonb) INTO v_items FROM (
        SELECT *,expected_revenue-expected_cost expected_margin,registered_ar-registered_ap registered_margin,
            cash_in-cash_out cash_margin,GREATEST(registered_ar-cash_in-credit_ar,0) outstanding_ar,GREATEST(registered_ap-cash_out-credit_ap,0) outstanding_ap
        FROM per_operation
    ) x;
    WITH totals AS (
        SELECT c.id,c.display_name,o.currency,o.operations,o.expected_revenue,COALESCE(i.registered_ar,0) registered_ar
        FROM public.customers c
        JOIN LATERAL (
            SELECT pricing_currency currency,count(*) operations,COALESCE(sum(customer_price_amount),0) expected_revenue
            FROM private.m07_set_operations WHERE tenant_id=c.tenant_id AND customer_id=c.id
              AND (v_currency IS NULL OR pricing_currency=v_currency) GROUP BY pricing_currency
        ) o ON true
        LEFT JOIN LATERAL (
            SELECT COALESCE(sum(fi.amount),0) registered_ar FROM private.m07_set_finance_invoices fi
            WHERE fi.tenant_id=c.tenant_id AND fi.customer_id=c.id AND fi.direction='ar' AND fi.status<>'void' AND fi.currency=o.currency
        ) i ON true
        WHERE c.tenant_id=p_tenant_id
    ) SELECT COALESCE(jsonb_agg(to_jsonb(totals) ORDER BY display_name,currency),'[]'::jsonb) INTO v_customers FROM totals;
    WITH totals AS (
        SELECT p.id,p.display_name,o.currency,o.operations,o.expected_cost,COALESCE(i.registered_ap,0) registered_ap
        FROM public.logistics_providers p
        JOIN LATERAL (
            SELECT pricing_currency currency,count(*) operations,COALESCE(sum(provider_cost_amount),0) expected_cost
            FROM private.m07_set_operations WHERE tenant_id=p.tenant_id AND provider_id=p.id
              AND (v_currency IS NULL OR pricing_currency=v_currency) GROUP BY pricing_currency
        ) o ON true
        LEFT JOIN LATERAL (
            SELECT COALESCE(sum(fi.amount),0) registered_ap FROM private.m07_set_finance_invoices fi
            WHERE fi.tenant_id=p.tenant_id AND fi.provider_id=p.id AND fi.direction='ap' AND fi.status<>'void' AND fi.currency=o.currency
        ) i ON true
        WHERE p.tenant_id=p_tenant_id
    ) SELECT COALESCE(jsonb_agg(to_jsonb(totals) ORDER BY display_name,currency),'[]'::jsonb) INTO v_providers FROM totals;
    RETURN jsonb_build_object('operations',v_items,'customers',v_customers,'providers',v_providers,'currency_policy','separate');
END;
$function$;

-- Existing F4 read: rpc_export_finance_ledger; ownership and EXECUTE retained.
CREATE OR REPLACE FUNCTION public.rpc_export_finance_ledger(p_tenant_id uuid,p_filters jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_result jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'reference',i.reference,'direction',i.direction,'counterparty',i.counterparty_name,'operation_reference',o.reference_code,
        'currency',i.currency,'amount',i.amount,'paid_amount',t.paid_amount,'credit_amount',t.credit_amount,'balance',t.balance_amount,
        'status',CASE WHEN i.status='open' AND i.due_date<current_date THEN 'overdue' ELSE i.status END,'due_date',i.due_date,'created_at',i.created_at
    ) ORDER BY i.created_at DESC),'[]'::jsonb) INTO v_result
    FROM private.m07_export_finance_invoices i CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t LEFT JOIN private.m07_export_operations o ON o.id=i.operation_id
    WHERE i.tenant_id=p_tenant_id
      AND (NULLIF(p_filters->>'direction','') IS NULL OR i.direction=p_filters->>'direction')
      AND (NULLIF(p_filters->>'currency','') IS NULL OR i.currency=upper(p_filters->>'currency'))
      AND (NULLIF(p_filters->>'date_from','') IS NULL OR i.created_at::date >= (p_filters->>'date_from')::date)
      AND (NULLIF(p_filters->>'date_to','') IS NULL OR i.created_at::date <= (p_filters->>'date_to')::date);
    RETURN v_result;
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_filters');
END;
$function$;

-- Existing F4 read: rpc_list_payment_complements; ownership and EXECUTE retained.
CREATE OR REPLACE FUNCTION public.rpc_list_payment_complements(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_items jsonb;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.payment_date DESC),'[]'::jsonb) INTO v_items FROM (
        SELECT c.*,i.counterparty_name,i.reference,i.operation_id FROM private.m07_set_billing_payment_complements c
        JOIN private.m07_set_finance_invoices i ON i.id=c.finance_invoice_id AND i.tenant_id=c.tenant_id
        WHERE c.tenant_id=p_tenant_id AND (NULLIF(p_filters->>'status','') IS NULL OR c.status=p_filters->>'status')
    ) x;
    RETURN jsonb_build_object('items',v_items,'count',jsonb_array_length(v_items),'handoff','billing');
END;
$function$;

-- Existing F6: guard financial AR/AP source only; other entities unchanged.
CREATE OR REPLACE FUNCTION public.rpc_export_data_page(
    p_tenant_id uuid,p_entity_type text,p_filters jsonb DEFAULT '{}'::jsonb,
    p_cursor jsonb DEFAULT NULL,p_limit integer DEFAULT 500
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,public
AS $function$
DECLARE v_role text; v_limit integer:=LEAST(GREATEST(COALESCE(p_limit,500),1),500); v_items jsonb:='[]'::jsonb; v_next jsonb;
    v_cursor_time timestamptz:='infinity'::timestamptz; v_cursor_id uuid:='ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid; v_from date; v_to date;
    v_search text:=lower(btrim(COALESCE(p_filters->>'search',''))); v_status text:=lower(btrim(COALESCE(p_filters->>'status','')));
BEGIN
    v_role:=private.f6_current_role(p_tenant_id);
    IF v_role IS NULL THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF p_entity_type NOT IN ('customers','providers','quotes','operations','documents','finance_ar','finance_ap')
       OR jsonb_typeof(COALESCE(p_filters,'{}'::jsonb))<>'object' OR (p_cursor IS NOT NULL AND jsonb_typeof(p_cursor)<>'object') THEN
        RETURN jsonb_build_object('error','invalid_contract');
    END IF;
    IF v_role='finance' AND p_entity_type NOT IN ('operations','documents','finance_ar','finance_ap') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF v_role IN ('operator','viewer') AND p_entity_type NOT IN ('customers','providers','quotes','operations','documents') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF v_role NOT IN ('admin','finance','operator','viewer') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    BEGIN
        IF p_cursor IS NOT NULL THEN v_cursor_time:=(p_cursor->>'created_at')::timestamptz; v_cursor_id:=(p_cursor->>'id')::uuid; END IF;
        v_from:=NULLIF(p_filters->>'date_from','')::date; v_to:=NULLIF(p_filters->>'date_to','')::date;
    EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow THEN RETURN jsonb_build_object('error','invalid_filters'); END;

    IF p_entity_type='customers' THEN
        SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC),'[]'::jsonb) INTO v_items FROM (
            SELECT c.id,c.external_key,c.display_name,c.legal_name,c.tax_id,c.contact_name,c.contact_email,c.contact_phone,c.billing_email,c.notes,c.is_active,c.preferred_currency,c.created_at
            FROM public.customers c WHERE c.tenant_id=p_tenant_id AND (c.created_at,c.id)<(v_cursor_time,v_cursor_id)
              AND (v_search='' OR position(v_search IN lower(concat_ws(' ',c.display_name,c.legal_name,c.tax_id,c.external_key)))>0)
              AND (v_from IS NULL OR c.created_at::date>=v_from) AND (v_to IS NULL OR c.created_at::date<=v_to)
            ORDER BY c.created_at DESC,c.id DESC LIMIT v_limit) x;
    ELSIF p_entity_type='providers' THEN
        SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC),'[]'::jsonb) INTO v_items FROM (
            SELECT p.id,p.external_key,p.display_name,p.legal_name,p.tax_id,p.contact_name,p.contact_email,p.contact_phone,p.billing_email,p.notes,p.is_active,p.created_at
            FROM public.logistics_providers p WHERE p.tenant_id=p_tenant_id AND (p.created_at,p.id)<(v_cursor_time,v_cursor_id)
              AND (v_search='' OR position(v_search IN lower(concat_ws(' ',p.display_name,p.legal_name,p.tax_id,p.external_key)))>0)
              AND (v_from IS NULL OR p.created_at::date>=v_from) AND (v_to IS NULL OR p.created_at::date<=v_to)
            ORDER BY p.created_at DESC,p.id DESC LIMIT v_limit) x;
    ELSIF p_entity_type='quotes' THEN
        SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC),'[]'::jsonb) INTO v_items FROM (
            SELECT d.id,d.quote_reference,d.title,c.display_name AS customer,d.quote_status,d.currency,d.value,
                d.quote_payload->>'provider_name' AS provider,d.created_at
            FROM public.crm_deals d LEFT JOIN public.customers c ON c.id=d.customer_id AND c.tenant_id=d.tenant_id
            WHERE d.tenant_id=p_tenant_id AND d.quote_reference IS NOT NULL AND (d.created_at,d.id)<(v_cursor_time,v_cursor_id)
              AND (v_search='' OR position(v_search IN lower(concat_ws(' ',d.quote_reference,d.title,c.display_name)))>0)
              AND (v_status='' OR d.quote_status=v_status) AND (v_from IS NULL OR d.created_at::date>=v_from) AND (v_to IS NULL OR d.created_at::date<=v_to)
            ORDER BY d.created_at DESC,d.id DESC LIMIT v_limit) x;
    ELSIF p_entity_type='operations' THEN
        SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC),'[]'::jsonb) INTO v_items FROM (
            SELECT o.id,o.external_key,o.reference_code,o.status,o.client_display_name AS customer,o.provider_name AS provider,o.service_type,
                o.operation_scope,o.execution_type,o.route_summary,o.operational_window_start,o.operational_window_end,o.pricing_currency,
                o.customer_price_amount,o.provider_cost_amount,o.notes,o.created_at
            FROM public.operations o WHERE o.tenant_id=p_tenant_id AND (o.created_at,o.id)<(v_cursor_time,v_cursor_id)
              AND (v_search='' OR position(v_search IN lower(concat_ws(' ',o.reference_code,o.external_key,o.client_display_name,o.provider_name,o.route_summary)))>0)
              AND (v_status='' OR o.status=v_status) AND (v_from IS NULL OR o.created_at::date>=v_from) AND (v_to IS NULL OR o.created_at::date<=v_to)
            ORDER BY o.created_at DESC,o.id DESC LIMIT v_limit) x;
    ELSIF p_entity_type='documents' THEN
        SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC),'[]'::jsonb) INTO v_items FROM (
            SELECT d.id,d.file_name,d.mime_type,d.size_bytes,d.file_kind,d.source_module,d.source_entity_type,
                private.f3_entity_reference(d.tenant_id,d.source_entity_type,d.source_entity_id) AS entity_reference,d.status,d.notes,d.created_at
            FROM public.document_files d WHERE d.tenant_id=p_tenant_id AND (d.created_at,d.id)<(v_cursor_time,v_cursor_id)
              AND private.f3_user_can_access_module(d.tenant_id,d.source_module,false)
              AND (v_search='' OR position(v_search IN lower(concat_ws(' ',d.file_name,d.notes,private.f3_entity_reference(d.tenant_id,d.source_entity_type,d.source_entity_id))))>0)
              AND (v_status='' OR d.status=v_status) AND (v_from IS NULL OR d.created_at::date>=v_from) AND (v_to IS NULL OR d.created_at::date<=v_to)
            ORDER BY d.created_at DESC,d.id DESC LIMIT v_limit) x;
    ELSE
        SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id DESC),'[]'::jsonb) INTO v_items FROM (
            SELECT i.id,i.direction,i.reference,i.counterparty_name,o.reference_code AS operation_reference,i.status,i.due_date,
                i.currency,i.amount,t.paid_amount,t.balance_amount,i.created_at
            FROM private.m07_export_finance_invoices i LEFT JOIN public.operations o ON o.id=i.operation_id
            CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
            WHERE i.tenant_id=p_tenant_id AND i.direction=CASE WHEN p_entity_type='finance_ar' THEN 'ar' ELSE 'ap' END
              AND (i.created_at,i.id)<(v_cursor_time,v_cursor_id)
              AND (v_search='' OR position(v_search IN lower(concat_ws(' ',i.reference,i.counterparty_name,o.reference_code)))>0)
              AND (v_status='' OR i.status=v_status) AND (v_from IS NULL OR i.created_at::date>=v_from) AND (v_to IS NULL OR i.created_at::date<=v_to)
            ORDER BY i.created_at DESC,i.id DESC LIMIT v_limit) x;
    END IF;
    IF jsonb_array_length(v_items)=v_limit THEN
        v_next:=jsonb_build_object('created_at',v_items->(jsonb_array_length(v_items)-1)->>'created_at','id',v_items->(jsonb_array_length(v_items)-1)->>'id');
    END IF;
    IF p_cursor IS NULL THEN
        PERFORM public.rpc_write_audit(p_tenant_id,'data_export_requested','data_export',NULL,
            jsonb_build_object('entity_type',p_entity_type,'page_limit',v_limit,'filters',jsonb_build_object('status',NULLIF(v_status,''),'has_search',v_search<>'','date_from',v_from,'date_to',v_to)));
    END IF;
    RETURN jsonb_build_object('items',v_items,'next_cursor',v_next,'page_size',jsonb_array_length(v_items),'max_sync_rows',5000);
END;
$function$;

-- No new API surface is activated. Existing reader signatures/ACL remain; only
-- the ten reviewed bodies above gain filtered sources before aggregation.
DO $close$
DECLARE function_row record; e text; actor text:=current_user;
BEGIN
    GRANT CREATE ON SCHEMA public,private TO rotero_finance_scope_owner,rotero_finance_read_owner;
    FOREACH e IN ARRAY ARRAY['finance_invoices_company_evidence','billing_documents_company_evidence','billing_credit_notes_company_evidence'] LOOP
        EXECUTE format('ALTER TABLE private.%I OWNER TO rotero_finance_scope_owner',e);
    END LOOP;
    FOR function_row IN SELECT n.nspname,p.proname,p.oid,pg_catalog.pg_get_function_identity_arguments(p.oid) args
        FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname IN ('public','private') AND (p.proname LIKE 'multi07_%' OR p.proname LIKE 'rpc_multi07_%') LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC,anon,authenticated,service_role',function_row.nspname,function_row.proname,function_row.args);
        IF function_row.proname='multi07_invoice_rows' OR function_row.proname LIKE 'rpc_multi07_%' THEN
            EXECUTE format('ALTER FUNCTION %I.%I(%s) OWNER TO rotero_finance_read_owner',function_row.nspname,function_row.proname,function_row.args);
        ELSE
            EXECUTE format('ALTER FUNCTION %I.%I(%s) OWNER TO rotero_finance_scope_owner',function_row.nspname,function_row.proname,function_row.args);
        END IF;
    END LOOP;
    SET LOCAL ROLE rotero_finance_scope_owner;
    GRANT EXECUTE ON FUNCTION private.multi07_entity_scope(text,uuid),private.multi07_row_allowed(text,uuid),
        private.multi07_scope_allowed(uuid,uuid[],boolean,boolean) TO rotero_finance_read_owner;
    EXECUTE format('GRANT EXECUTE ON FUNCTION private.multi07_entity_scope(text,uuid),private.multi07_row_allowed(text,uuid),
        private.multi07_scope_allowed(uuid,uuid[],boolean,boolean),private.multi07_legacy_visible(text,uuid,text) TO %I',actor);
    EXECUTE format('SET LOCAL ROLE %I',actor);
    REVOKE CREATE ON SCHEMA public,private FROM rotero_finance_scope_owner,rotero_finance_read_owner;
END;
$close$;
DO $cleanup_reference$
DECLARE actor text:=pg_catalog.current_setting('multi07.actor'); cols text:=pg_catalog.current_setting('multi07.refs');
BEGIN
    IF cols<>'' THEN
        SET LOCAL ROLE rotero_company_access_owner;
        EXECUTE format('REVOKE REFERENCES (%s) ON public.companies FROM %I',cols,actor);
        EXECUTE format('SET LOCAL ROLE %I',actor);
    END IF;
END;
$cleanup_reference$;
COMMIT;
