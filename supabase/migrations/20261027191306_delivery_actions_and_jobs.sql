-- Work actions remain distinct from financial read/export/consolidation.
BEGIN;
SET LOCAL ROLE rotero_company_access_owner;
ALTER TABLE public.companies ADD COLUMN fiscal_address jsonb
 CHECK(fiscal_address IS NULL OR (jsonb_typeof(fiscal_address)='object'
 AND fiscal_address ?& ARRAY['country','postal_code'] AND fiscal_address->>'country' ~ '^[A-Z]{2}$'
 AND length(btrim(fiscal_address->>'postal_code')) BETWEEN 1 AND 20
 AND NOT jsonb_path_exists(fiscal_address,'$.* ? (@.type() != "string")')
 AND fiscal_address - ARRAY['street','exterior_number','interior_number','neighborhood','postal_code','city','state','country'] = '{}'::jsonb));
COMMENT ON COLUMN public.companies.fiscal_address IS 'Company-specific address; unverified values remain NULL. No real address seeded or inferred.';
ALTER TABLE public.membership_company_capabilities DROP CONSTRAINT membership_company_capabilities_capability_code_check;
ALTER TABLE public.membership_company_capabilities ADD CONSTRAINT membership_company_capabilities_capability_code_check CHECK(capability_code IN(
 'operations.read','operations.capture','billing.draft','billing.document.read','receivables.read',
 'export.operational','export.receivables','companies.manage','memberships.manage','company_access.manage',
 'financial.full.read','export.financial','fiscal.prepare','fiscal.issue','fiscal.read','fiscal.cancel','fiscal.payment',
 'receivables.collect','finance.write','pipeline.read','inventory.read'));
SET LOCAL ROLE postgres;

-- Classification is metadata, not a new delivery/commercial/accounting event.
-- Existing touch triggers must not change the historical metric based on updated_at.
CREATE FUNCTION private.delivery_preserve_metadata_clock() RETURNS trigger
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE excluded text[]:=ARRAY['company_id','company_classification_event_id','company_classification_status','company_entity_table','access_class','updated_at'];
BEGIN
 IF to_jsonb(NEW)-excluded=to_jsonb(OLD)-excluded
 AND (to_jsonb(NEW)-ARRAY['updated_at','company_entity_table']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['updated_at','company_entity_table'])
 THEN NEW.updated_at:=OLD.updated_at; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.delivery_preserve_metadata_clock() FROM PUBLIC,anon,authenticated,service_role;
DO $clocks$ DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['operations','finance_invoices','billing_documents','billing_credit_notes','crm_deals','inventory_lots','billing_cfdis','document_files'] LOOP
  IF EXISTS(SELECT FROM pg_trigger WHERE tgrelid=('public.'||t)::regclass AND NOT tgisinternal AND tgname>'zzz_delivery_metadata_clock')
  THEN RAISE EXCEPTION 'unreviewed_late_update_trigger'; END IF;
  EXECUTE format('CREATE TRIGGER zzz_delivery_metadata_clock BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION private.delivery_preserve_metadata_clock()',t);
 END LOOP;
END $clocks$;

SET LOCAL ROLE rotero_company_access_owner;
GRANT EXECUTE ON FUNCTION private.multi05_request_actor() TO rotero_finance_scope_owner;
SET LOCAL ROLE postgres;
CREATE FUNCTION private.delivery_finance_write_target(p_tenant uuid,p_kind text,p_id uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT (private.delivery_required(p_tenant) OR private.delivery_required(NULL))
 THEN RETURN private.multi08_legacy_write_target(p_tenant,p_kind,p_id); END IF;
 IF NOT private.delivery_cap(p_tenant,'financial.full.read') OR NOT private.delivery_cap(p_tenant,'finance.write')
 OR cardinality(private.delivery_company_ids())<>1 THEN RETURN false; END IF;
 IF p_id IS NULL THEN RETURN true; END IF;
 IF p_kind='cfdi' THEN RETURN COALESCE(private.delivery_root_company(p_tenant,'billing_cfdi',p_id)=(private.delivery_company_ids())[1]
  AND NOT private.fiscal02_is_lab_entity('cfdi',p_id),false); END IF;
 RETURN private.delivery_entity_allowed(p_tenant,p_kind,p_id) AND NOT private.fiscal02_is_lab_entity(p_kind,p_id);
END $$;
REVOKE ALL ON FUNCTION private.delivery_finance_write_target(uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;

GRANT UPDATE(company_id,company_classification_status,company_classification_event_id) ON public.finance_invoices TO rotero_finance_scope_owner;
CREATE POLICY delivery_invoice_classification ON public.finance_invoices FOR UPDATE TO rotero_finance_scope_owner USING(true) WITH CHECK(true);
CREATE FUNCTION private.delivery_classify_new_invoice(p_tenant uuid,p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE e uuid;c uuid;
BEGIN
 IF NOT private.delivery_cap(p_tenant,'financial.full.read') OR NOT private.delivery_cap(p_tenant,'finance.write')
 OR cardinality(private.delivery_company_ids())<>1 THEN RAISE EXCEPTION 'unauthorized' USING ERRCODE='42501'; END IF;
 c:=(private.delivery_company_ids())[1];
 INSERT INTO private.finance_invoices_company_evidence(tenant_id,entity_id,company_id,decision,evidence_kind,evidence_reference,recorded_by)
 VALUES(p_tenant,p_id,c,'resolved','verified_source_record','explicit-new-finance-capture:'||p_id::text,(SELECT user_id FROM private.multi05_request_actor())) RETURNING id INTO e;
 UPDATE public.finance_invoices SET company_id=c,company_classification_status='resolved',company_classification_event_id=e WHERE tenant_id=p_tenant AND id=p_id AND company_id IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'classification_target_mismatch'; END IF;
END $$;
SET LOCAL ROLE rotero_delivery_scope_owner;
GRANT EXECUTE ON FUNCTION private.delivery_cap(uuid,text),private.delivery_company_ids() TO rotero_finance_scope_owner;
SET LOCAL ROLE postgres;
GRANT CREATE ON SCHEMA private TO rotero_finance_scope_owner;
ALTER FUNCTION private.delivery_classify_new_invoice(uuid,uuid) OWNER TO rotero_finance_scope_owner;
REVOKE CREATE ON SCHEMA private FROM rotero_finance_scope_owner;
SET LOCAL ROLE rotero_finance_scope_owner;
REVOKE ALL ON FUNCTION private.delivery_classify_new_invoice(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.delivery_classify_new_invoice(uuid,uuid) TO postgres;
SET LOCAL ROLE postgres;

DO $role$ BEGIN
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='rotero_delivery_capture_owner') THEN
  CREATE ROLE rotero_delivery_capture_owner NOLOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION;
  COMMENT ON ROLE rotero_delivery_capture_owner IS 'ROTERO delivery operational capture v1';
 END IF;
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='rotero_delivery_capture_owner' AND NOT rolcanlogin AND NOT rolinherit
  AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication
  AND shobj_description(oid,'pg_authid')='ROTERO delivery operational capture v1')
 OR EXISTS(SELECT FROM pg_auth_members WHERE member='rotero_delivery_capture_owner'::regrole)
 OR EXISTS(SELECT FROM unnest(ARRAY['anon','authenticated','service_role','authenticator'])r WHERE pg_has_role(r,'rotero_delivery_capture_owner','MEMBER'))
 THEN RAISE EXCEPTION 'capture_owner_collision'; END IF;
END $role$;
GRANT rotero_delivery_capture_owner TO postgres WITH SET TRUE;
GRANT rotero_delivery_capture_owner TO postgres WITH INHERIT FALSE;
GRANT USAGE ON SCHEMA public,private TO rotero_delivery_capture_owner;
SET LOCAL ROLE rotero_company_access_owner;
GRANT EXECUTE ON FUNCTION private.multi05_request_actor() TO rotero_delivery_capture_owner;
SET LOCAL ROLE postgres;
GRANT EXECUTE ON FUNCTION public.tanda1_user_has_role(uuid,text[]) TO rotero_delivery_capture_owner;
SET LOCAL ROLE rotero_delivery_scope_owner;
GRANT EXECUTE ON FUNCTION private.delivery_cap(uuid,text),private.delivery_company_ids() TO rotero_delivery_capture_owner;
SET LOCAL ROLE postgres;
GRANT INSERT(tenant_id,reference_code,route_summary,client_display_name,destination_city,status),
 SELECT(id,tenant_id,company_id,company_classification_status),
 UPDATE(company_id,company_classification_status,company_classification_event_id) ON public.operations TO rotero_delivery_capture_owner;
CREATE POLICY operations_delivery_capture ON public.operations FOR ALL TO rotero_delivery_capture_owner
USING(private.delivery_cap(tenant_id,'operations.capture')) WITH CHECK(private.delivery_cap(tenant_id,'operations.capture'));
SET LOCAL ROLE rotero_operations_read_owner;
GRANT INSERT(tenant_id,operation_id,company_id,decision,evidence_kind,evidence_reference,recorded_by),
 SELECT(id) ON private.operation_company_classification_events TO rotero_delivery_capture_owner;
CREATE POLICY delivery_capture_evidence ON private.operation_company_classification_events FOR INSERT TO rotero_delivery_capture_owner
WITH CHECK(recorded_by=(SELECT user_id FROM private.multi05_request_actor()) AND company_id=ANY(private.delivery_company_ids()) AND private.delivery_cap(tenant_id,'operations.capture'));
CREATE POLICY delivery_capture_evidence_id ON private.operation_company_classification_events FOR SELECT TO rotero_delivery_capture_owner USING(true);
SET LOCAL ROLE postgres;

CREATE FUNCTION public.rpc_delivery_create_operation(p_tenant_id uuid,p_reference text,p_route text DEFAULT NULL,
 p_customer text DEFAULT NULL,p_destination_city text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE op uuid;e uuid;company uuid;
BEGIN
 IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','operator']) OR NOT private.delivery_cap(p_tenant_id,'operations.capture')
 OR cardinality(private.delivery_company_ids())<>1 THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 IF p_reference IS NULL OR length(btrim(p_reference)) NOT BETWEEN 1 AND 160 OR length(p_route)>500 OR length(p_customer)>200
 OR length(p_destination_city)>160 THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
 company:=(private.delivery_company_ids())[1];
 INSERT INTO public.operations(tenant_id,reference_code,route_summary,client_display_name,destination_city,status)
 VALUES(p_tenant_id,btrim(p_reference),p_route,p_customer,p_destination_city,'planned') RETURNING id INTO op;
 INSERT INTO private.operation_company_classification_events(tenant_id,operation_id,company_id,decision,evidence_kind,evidence_reference,recorded_by)
 VALUES(p_tenant_id,op,company,'resolved','verified_source_record','explicit-new-capture:'||op::text,(SELECT user_id FROM private.multi05_request_actor())) RETURNING id INTO e;
 UPDATE public.operations SET company_id=company,company_classification_status='resolved',company_classification_event_id=e WHERE id=op AND tenant_id=p_tenant_id;
 RETURN jsonb_build_object('id',op,'company_id',company);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('error','reference_conflict');
 WHEN check_violation OR foreign_key_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END $$;
GRANT CREATE ON SCHEMA public TO rotero_delivery_capture_owner;
ALTER FUNCTION public.rpc_delivery_create_operation(uuid,text,text,text,text) OWNER TO rotero_delivery_capture_owner;
REVOKE CREATE ON SCHEMA public FROM rotero_delivery_capture_owner;
SET LOCAL ROLE rotero_delivery_capture_owner;
REVOKE ALL ON FUNCTION public.rpc_delivery_create_operation(uuid,text,text,text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_create_operation(uuid,text,text,text,text) TO authenticated;
SET LOCAL ROLE postgres;

-- Scope and direction are checked before the F4 payment parser/errors. Collection
-- does not grant AP, profit, bank-history reads, voiding, fiscal issuance or full read.
CREATE FUNCTION private.delivery_ar_write_target(p_tenant uuid,p_kind text,p_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT p_kind='invoice' AND private.delivery_cap(p_tenant,'receivables.collect')
 AND private.delivery_cap(p_tenant,'receivables.read') AND private.delivery_entity_allowed(p_tenant,'invoice',p_id)
 AND EXISTS(SELECT FROM public.finance_invoices i WHERE i.id=p_id AND i.tenant_id=p_tenant AND i.direction='ar'
  AND i.payroll_period_id IS NULL AND NOT private.fiscal02_is_lab_entity('invoice',i.id));
$$;
REVOKE ALL ON FUNCTION private.delivery_ar_write_target(uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Clone the reviewed F4 payment arithmetic, changing only the MULTI-08 hold to
-- the explicit AR collection gate. Preserve original core for uncutover legacy.
DO $payment$ DECLARE f record;d text;BEGIN
 SELECT * INTO STRICT f FROM pg_proc p WHERE p.oid='public.rpc_record_payment(uuid,jsonb)'::regprocedure;
 SELECT p.* INTO STRICT f FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='private' AND p.proname LIKE 'delivery_scoped_%'
 AND p.prosrc LIKE '%IF NOT (private.delivery_finance_write_target(p_tenant_id,''invoice'',NULLIF(p_payload->>''invoice_id'','''')::uuid))%'
 AND p.prosrc LIKE '%payment_exceeds_balance%';
 d:=pg_get_functiondef(f.oid);
 d:=replace(d,'FUNCTION private.'||f.proname||'(','FUNCTION private.delivery_record_receivable_payment(');
 d:=replace(d,'private.delivery_finance_write_target','private.delivery_ar_write_target');
 EXECUTE d;
END $payment$;
REVOKE ALL ON FUNCTION private.delivery_record_receivable_payment(uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.rpc_delivery_record_receivable_payment(p_tenant_id uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE id uuid;
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'receivables.read') OR NOT private.delivery_cap(p_tenant_id,'receivables.collect')
 THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 BEGIN id:=(p_payload->>'invoice_id')::uuid; EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;
 IF NOT private.delivery_ar_write_target(p_tenant_id,'invoice',id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 IF jsonb_typeof(p_payload)<>'object' OR EXISTS(SELECT FROM jsonb_object_keys(p_payload)k
  WHERE k NOT IN('invoice_id','amount','currency','paid_at','method','note','bank_reference','exchange_rate','exchange_rate_date','exchange_rate_source'))
 THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
 RETURN private.delivery_record_receivable_payment(p_tenant_id,p_payload||jsonb_build_object('prepare_complement',false));
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_record_receivable_payment(uuid,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_record_receivable_payment(uuid,jsonb) TO authenticated;

-- Jobs have no implicit human financial authority. Until an approved job identity
-- and company contract exist, cutover tenants are skipped before any materialization.
DO $jobs$ DECLARE f record;d text;core text;call_args text;BEGIN
 FOR f IN SELECT p.*,pg_get_function_arguments(p.oid) full_args FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='private' AND p.proname IN('f7_generate_tenant_digests','f7_materialize_automation_notifications',
 'f9_materialize_notifications','f10_materialize_claim_notifications') LOOP
  IF NOT f.prosecdef OR f.proowner<>'postgres'::regrole OR f.prorettype<>'jsonb'::regtype THEN RAISE EXCEPTION 'job_contract_drift'; END IF;
  core:='delivery_job_'||f.proname;
  d:=replace(pg_get_functiondef(f.oid),'FUNCTION private.'||f.proname||'(','FUNCTION private.'||core||'(');EXECUTE d;
  EXECUTE format('REVOKE ALL ON FUNCTION private.%I(%s) FROM PUBLIC,anon,authenticated,service_role',core,pg_get_function_identity_arguments(f.oid));
  SELECT string_agg(quote_ident(a),',') INTO call_args FROM unnest(f.proargnames)a;
  EXECUTE format('CREATE OR REPLACE FUNCTION private.%I(%s) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $body$
   BEGIN IF EXISTS(SELECT FROM private.delivery_tenant_cutovers WHERE tenant_id=p_tenant_id AND enabled)
   THEN RETURN jsonb_build_object(''skipped'',true,''reason'',''company_job_authorization_pending'');END IF;
   RETURN private.%I(%s);END $body$',f.proname,f.full_args,core,call_args);
 END LOOP;
END $jobs$;

-- Preserve Facturama's sandbox allowlist, capabilities and immutable origin.
-- A scope header selects the company; it never replaces laboratory authorization.
DO $fiscal$ DECLARE d text;BEGIN
 SELECT pg_get_functiondef('private.fiscal01_authorized(uuid,uuid,text)'::regprocedure) INTO d;
 IF d NOT LIKE '%private.fiscal01_lab_actors%' OR d NOT LIKE '%private.fiscal01_company_bindings%'
 OR d NOT LIKE '%private.multi05_has_company_capability%' THEN RAISE EXCEPTION 'fiscal_authorization_drift'; END IF;
 EXECUTE replace(d,'FUNCTION private.fiscal01_authorized(','FUNCTION private.delivery_fiscal_authorized_legacy(');
END $fiscal$;
REVOKE ALL ON FUNCTION private.delivery_fiscal_authorized_legacy(uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.fiscal01_authorized(p_tenant uuid,p_company uuid,p_action text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT private.delivery_fiscal_authorized_legacy(p_tenant,p_company,p_action)
 AND (NOT(private.delivery_required(p_tenant) OR private.delivery_required(NULL))
 OR (private.delivery_scope_allowed(p_tenant) AND p_company=ANY(private.delivery_company_ids())
 AND (p_action='read' OR private.delivery_headers()->>'x-rotero-scope'='company')));
$$;
CREATE FUNCTION public.rpc_delivery_fiscal_documents(p_tenant_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'fiscal.read') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 RETURN jsonb_build_object('items',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'status',c.fiscal_status,
 'company_id',s.company_id,'document_type',CASE WHEN c.has_complemento_pago THEN 'payment' ELSE 'invoice' END) ORDER BY c.id)
 FROM(SELECT cfdi_id,tenant_id,company_id FROM private.fiscal01_documents UNION
 SELECT cfdi_id,tenant_id,company_id FROM private.fiscal01_draft_scope) s JOIN public.billing_cfdis c ON c.id=s.cfdi_id AND c.tenant_id=s.tenant_id
 WHERE s.tenant_id=p_tenant_id AND s.company_id=ANY(private.delivery_company_ids()) AND private.fiscal01_authorized(s.tenant_id,s.company_id,'read')),'[]'));
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_fiscal_documents(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_fiscal_documents(uuid) TO authenticated;

SET LOCAL ROLE rotero_delivery_scope_owner;
GRANT EXECUTE ON FUNCTION private.delivery_required(uuid),private.delivery_scope_allowed(uuid),private.delivery_company_ids() TO rotero_fiscal_policy_owner;
SET LOCAL ROLE postgres;
GRANT CREATE ON SCHEMA public,private TO rotero_fiscal_policy_owner;
SET LOCAL ROLE rotero_fiscal_policy_owner;
DO $provider_scope$ DECLARE f record;d text;core text;call_args text;extra text;BEGIN
 FOR f IN SELECT p.*,pg_get_function_arguments(p.oid) full_args FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN('rpc_get_company_fiscal_provider','rpc_configure_company_fiscal_provider') LOOP
  IF f.proowner<>'rotero_fiscal_policy_owner'::regrole OR NOT f.prosecdef THEN RAISE EXCEPTION 'provider_policy_owner_drift'; END IF;
  core:='delivery_legacy_'||f.proname;
  EXECUTE replace(pg_get_functiondef(f.oid),'FUNCTION public.'||f.proname||'(','FUNCTION private.'||core||'(');
  EXECUTE format('REVOKE ALL ON FUNCTION private.%I(%s) FROM PUBLIC,anon,authenticated,service_role',core,pg_get_function_identity_arguments(f.oid));
  SELECT string_agg(quote_ident(a),',') INTO call_args FROM unnest(f.proargnames)a;
  extra:=CASE WHEN f.proname='rpc_configure_company_fiscal_provider' THEN ' OR cardinality(private.delivery_company_ids())<>1' ELSE '' END;
  d:=format('CREATE OR REPLACE FUNCTION public.%I(%s) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='''' AS $body$
   BEGIN IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) AND
    (NOT private.delivery_scope_allowed(p_tenant_id) OR NOT COALESCE(p_company_id=ANY(private.delivery_company_ids()),false) %s)
   THEN RETURN jsonb_build_object(''error'',''unauthorized''); END IF;RETURN private.%I(%s);END $body$',f.proname,f.full_args,extra,core,call_args);
  EXECUTE d;
 END LOOP;
END $provider_scope$;
SET LOCAL ROLE postgres;
REVOKE CREATE ON SCHEMA public,private FROM rotero_fiscal_policy_owner;
COMMIT;
