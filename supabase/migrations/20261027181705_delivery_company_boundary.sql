-- Delivery candidate: company scope is a selector, never an authorization grant.
-- No real company/identity assignments, backfill or cutover is performed here.
BEGIN;
DO $role$ DECLARE actor text:=current_user; BEGIN
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='rotero_delivery_scope_owner') THEN
  CREATE ROLE rotero_delivery_scope_owner NOLOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION;
  COMMENT ON ROLE rotero_delivery_scope_owner IS 'ROTERO delivery metadata scope owner v1';
 END IF;
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='rotero_delivery_scope_owner' AND NOT rolcanlogin AND NOT rolinherit AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND shobj_description(oid,'pg_authid')='ROTERO delivery metadata scope owner v1')
 OR EXISTS(SELECT FROM pg_auth_members WHERE member='rotero_delivery_scope_owner'::regrole)
 OR EXISTS(SELECT FROM unnest(ARRAY['anon','authenticated','service_role','authenticator']) r WHERE pg_has_role(r,'rotero_delivery_scope_owner','MEMBER')) THEN RAISE EXCEPTION 'delivery_owner_collision'; END IF;
 EXECUTE format('GRANT rotero_delivery_scope_owner TO %I WITH SET TRUE',actor);
 EXECUTE format('GRANT rotero_delivery_scope_owner TO %I WITH INHERIT FALSE',actor);
 PERFORM set_config('delivery.migration_actor',actor,true);
END $role$;
GRANT USAGE ON SCHEMA public,private TO rotero_delivery_scope_owner;
SET LOCAL ROLE rotero_company_access_owner;
GRANT EXECUTE ON FUNCTION private.multi04_has_company_access(uuid,uuid),private.multi05_request_actor(),private.multi05_has_company_capability(uuid,uuid,text),private.multi05_can_consolidate(uuid,uuid[]) TO rotero_delivery_scope_owner;
DO $$ BEGIN EXECUTE format('SET LOCAL ROLE %I',current_setting('delivery.migration_actor')); END $$;
SET LOCAL ROLE rotero_finance_scope_owner;
GRANT EXECUTE ON FUNCTION private.multi07_entity_scope(text,uuid),private.multi07_invoice_graph_coherent(uuid) TO rotero_delivery_scope_owner;
DO $$ BEGIN EXECUTE format('SET LOCAL ROLE %I',current_setting('delivery.migration_actor')); END $$;

CREATE TABLE private.delivery_tenant_cutovers (
 tenant_id uuid PRIMARY KEY REFERENCES public.tenants(id),enabled boolean NOT NULL DEFAULT false,
 approval_reference text NOT NULL CHECK(length(trim(approval_reference))>0),
 approved_by uuid NOT NULL,approved_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private.delivery_tenant_cutovers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.delivery_tenant_cutovers FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON private.delivery_tenant_cutovers TO rotero_delivery_scope_owner;
CREATE POLICY delivery_cutover_metadata ON private.delivery_tenant_cutovers FOR SELECT TO rotero_delivery_scope_owner USING(true);
GRANT SELECT(user_id,tenant_id) ON public.memberships TO rotero_delivery_scope_owner;
CREATE POLICY memberships_delivery_metadata ON public.memberships FOR SELECT TO rotero_delivery_scope_owner USING(true);
GRANT SELECT(id,tenant_id,company_id,company_classification_status) ON public.finance_invoices,public.billing_documents,public.billing_credit_notes TO rotero_delivery_scope_owner;
GRANT SELECT(id,tenant_id,company_id,company_classification_status) ON public.operations TO rotero_delivery_scope_owner;
GRANT SELECT(operation_id,billing_document_id) ON public.finance_invoices TO rotero_delivery_scope_owner;
GRANT SELECT(finance_invoice_id) ON public.billing_credit_notes TO rotero_delivery_scope_owner;
GRANT SELECT(id,tenant_id,invoice_id) ON public.finance_payments TO rotero_delivery_scope_owner;
GRANT SELECT(id,tenant_id,finance_invoice_id,invoice_billing_document_id,complement_billing_document_id) ON public.billing_payment_complements TO rotero_delivery_scope_owner;
CREATE POLICY invoices_delivery_metadata ON public.finance_invoices FOR SELECT TO rotero_delivery_scope_owner USING(true);
CREATE POLICY documents_delivery_metadata ON public.billing_documents FOR SELECT TO rotero_delivery_scope_owner USING(true);
CREATE POLICY credits_delivery_metadata ON public.billing_credit_notes FOR SELECT TO rotero_delivery_scope_owner USING(true);
CREATE POLICY operations_delivery_metadata ON public.operations FOR SELECT TO rotero_delivery_scope_owner USING(true);
CREATE POLICY payments_delivery_metadata ON public.finance_payments FOR SELECT TO rotero_delivery_scope_owner USING(true);
CREATE POLICY complements_delivery_metadata ON public.billing_payment_complements FOR SELECT TO rotero_delivery_scope_owner USING(true);

CREATE FUNCTION private.delivery_headers() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $fn$
BEGIN RETURN COALESCE(NULLIF(current_setting('request.headers',true),'')::jsonb,'{}');
EXCEPTION WHEN invalid_text_representation THEN RETURN '{}'; END $fn$;
CREATE FUNCTION private.delivery_required(p_tenant uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT private.delivery_headers() ?| ARRAY['x-rotero-scope','x-rotero-company-id','x-rotero-company-ids']
  OR EXISTS(SELECT FROM private.delivery_tenant_cutovers WHERE tenant_id=p_tenant AND enabled)
  OR (p_tenant IS NULL AND EXISTS(SELECT FROM private.delivery_tenant_cutovers c JOIN public.memberships m ON m.tenant_id=c.tenant_id
   CROSS JOIN private.multi05_request_actor() a WHERE c.enabled AND m.user_id=a.user_id));
$fn$;
CREATE FUNCTION private.delivery_company_ids() RETURNS uuid[] LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE h jsonb:=private.delivery_headers(); result uuid[];
BEGIN
 IF h->>'x-rotero-scope'='consolidated' THEN
  IF jsonb_typeof((h->>'x-rotero-company-ids')::jsonb)<>'array' THEN RETURN NULL; END IF;
  SELECT array_agg(value::uuid ORDER BY value::uuid) INTO result FROM jsonb_array_elements_text((h->>'x-rotero-company-ids')::jsonb);
 ELSE result:=ARRAY[(h->>'x-rotero-company-id')::uuid]; END IF;
 IF cardinality(result) NOT BETWEEN 1 AND 50 OR array_position(result,NULL) IS NOT NULL
  OR cardinality(result)<>(SELECT count(DISTINCT v) FROM unnest(result) q(v)) THEN RETURN NULL; END IF;
 RETURN result;
EXCEPTION WHEN invalid_text_representation OR invalid_parameter_value THEN RETURN NULL; END $fn$;
CREATE FUNCTION private.delivery_scope_allowed(p_tenant uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT COALESCE(EXISTS(SELECT FROM private.delivery_tenant_cutovers WHERE tenant_id=p_tenant AND enabled)
  AND private.delivery_headers()->>'x-rotero-scope' IN ('company','consolidated')
  AND cardinality(private.delivery_company_ids())>0 AND (SELECT user_id IS NOT NULL FROM private.multi05_request_actor())
  AND NOT EXISTS(SELECT FROM unnest(private.delivery_company_ids()) c WHERE NOT private.multi04_has_company_access(p_tenant,c))
  AND (private.delivery_headers()->>'x-rotero-scope'<>'consolidated' OR private.multi05_can_consolidate(p_tenant,private.delivery_company_ids())),false);
$fn$;
CREATE FUNCTION private.delivery_cap(p_tenant uuid,p_cap text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
 SELECT private.delivery_scope_allowed(p_tenant)
  AND NOT EXISTS(SELECT FROM unnest(private.delivery_company_ids()) c WHERE NOT private.multi05_has_company_capability(p_tenant,c,p_cap));
$fn$;
CREATE FUNCTION private.delivery_entity_allowed(p_tenant uuid,p_kind text,p_id uuid) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE s record;explicit_company uuid;parent_id uuid;
BEGIN
 IF NOT private.delivery_scope_allowed(p_tenant) THEN RETURN false; END IF;
 SELECT * INTO s FROM private.multi07_entity_scope(p_kind,p_id);
 IF NOT FOUND OR s.tenant_id<>p_tenant OR NOT s.coherent OR cardinality(s.company_ids)<>1
  OR NOT s.company_ids<@private.delivery_company_ids() THEN RETURN false; END IF;
 CASE p_kind
 WHEN 'invoice' THEN
  SELECT company_id INTO explicit_company FROM public.finance_invoices WHERE id=p_id AND company_classification_status='resolved';
  RETURN COALESCE(explicit_company=s.company_ids[1] AND private.multi07_invoice_graph_coherent(p_id)
   AND NOT EXISTS(SELECT FROM public.finance_invoices i WHERE i.id=p_id AND (
    (i.operation_id IS NOT NULL AND NOT EXISTS(SELECT FROM public.operations o WHERE o.id=i.operation_id AND o.tenant_id=p_tenant AND o.company_id=explicit_company AND o.company_classification_status='resolved'))
    OR (i.billing_document_id IS NOT NULL AND NOT EXISTS(SELECT FROM public.billing_documents d WHERE d.id=i.billing_document_id AND d.tenant_id=p_tenant AND d.company_id=explicit_company AND d.company_classification_status='resolved'))))
   AND NOT EXISTS(SELECT FROM public.billing_credit_notes c WHERE c.finance_invoice_id=p_id
    AND (c.tenant_id<>p_tenant OR c.company_id IS DISTINCT FROM explicit_company OR c.company_classification_status<>'resolved'))
   AND NOT EXISTS(SELECT FROM public.billing_payment_complements c WHERE c.finance_invoice_id=p_id AND (
    (c.invoice_billing_document_id IS NOT NULL AND NOT EXISTS(SELECT FROM public.billing_documents d WHERE d.id=c.invoice_billing_document_id AND d.tenant_id=p_tenant AND d.company_id=explicit_company AND d.company_classification_status='resolved'))
    OR (c.complement_billing_document_id IS NOT NULL AND NOT EXISTS(SELECT FROM public.billing_documents d WHERE d.id=c.complement_billing_document_id AND d.tenant_id=p_tenant AND d.company_id=explicit_company AND d.company_classification_status='resolved')))),false);
 WHEN 'document' THEN SELECT company_id INTO explicit_company FROM public.billing_documents WHERE id=p_id AND company_classification_status='resolved';
 WHEN 'credit' THEN SELECT company_id INTO explicit_company FROM public.billing_credit_notes WHERE id=p_id AND company_classification_status='resolved';
 WHEN 'payment' THEN SELECT invoice_id INTO parent_id FROM public.finance_payments WHERE id=p_id AND tenant_id=p_tenant;
  RETURN private.delivery_entity_allowed(p_tenant,'invoice',parent_id);
 WHEN 'complement' THEN SELECT finance_invoice_id INTO parent_id FROM public.billing_payment_complements WHERE id=p_id AND tenant_id=p_tenant;
  RETURN private.delivery_entity_allowed(p_tenant,'invoice',parent_id);
 ELSE RETURN true;
 END CASE;
 RETURN COALESCE(explicit_company=s.company_ids[1],false);
END $fn$;

-- A backend flag protects the complete tenant even if a caller removes all scope
-- headers. WLS is not opted in before approved classification and assignments.
COMMENT ON TABLE private.delivery_tenant_cutovers IS 'Closed activation ledger. Synthetic QA only until real classification/assignment approval; no client-controlled legacy fallback.';

DO $owners$ DECLARE f record; actor text:=current_user; BEGIN
 GRANT CREATE ON SCHEMA private TO rotero_delivery_scope_owner;
 FOR f IN SELECT p.oid::regprocedure signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname IN('delivery_headers','delivery_required','delivery_company_ids','delivery_scope_allowed','delivery_cap','delivery_entity_allowed') LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO rotero_delivery_scope_owner',f.signature);
 END LOOP;
 REVOKE CREATE ON SCHEMA private FROM rotero_delivery_scope_owner;
 SET LOCAL ROLE rotero_delivery_scope_owner;
 FOR f IN SELECT p.oid::regprocedure signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname IN('delivery_headers','delivery_required','delivery_company_ids','delivery_scope_allowed','delivery_cap','delivery_entity_allowed') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO %I',f.signature,actor);
 END LOOP;
 EXECUTE format('SET LOCAL ROLE %I',actor);
END $owners$;
COMMIT;
