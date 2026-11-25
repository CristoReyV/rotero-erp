\set ON_ERROR_STOP on
-- Disposable local DB only. All identities, grants, rows and objects roll back.
BEGIN;
CREATE FUNCTION pg_temp.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'delivery assertion: %',label; END IF;
 PERFORM set_config('d.assertions',(COALESCE(NULLIF(current_setting('d.assertions',true),''),'0')::int+1)::text,true);
END $$;
CREATE FUNCTION pg_temp.denied(q text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE q;EXCEPTION WHEN insufficient_privilege THEN RETURN;END;
 RAISE EXCEPTION 'expected insufficient privilege';
END $$;
CREATE FUNCTION pg_temp.actor(u uuid,c uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 PERFORM set_config('request.jwt.claim.sub',COALESCE(u::text,''),true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated',
 'iss','https://synthetic-access.invalid/auth/v1','user_metadata',jsonb_build_object('financial_full',true))::text,true);
 PERFORM set_config('request.headers',CASE WHEN c IS NULL THEN '{}' ELSE jsonb_build_object('x-rotero-scope','company','x-rotero-company-id',c) END::text,true);
END $$;
SET LOCAL ROLE rotero_company_access_owner;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.companies,public.membership_company_access,
 public.membership_company_capabilities,private.financial_principal_bindings,public.membership_consolidation_grants,
 public.consolidation_grant_companies TO postgres;
RESET ROLE;
SET LOCAL ROLE rotero_operations_read_owner;
GRANT SELECT,INSERT ON private.operation_company_classification_events TO postgres;
RESET ROLE;
SET LOCAL ROLE rotero_finance_scope_owner;
GRANT SELECT,INSERT ON private.finance_invoices_company_evidence TO postgres;
RESET ROLE;
-- Fresh limited-role execution must not depend on a plan warmed by a privileged
-- caller. The UUID selector helper does not expose the complete request headers.
SET LOCAL ROLE rotero_delivery_capture_owner;
SELECT pg_temp.ok(private.delivery_company_ids() IS NULL,'limited capture selector helper');
SELECT pg_temp.denied('SELECT private.delivery_headers()');
RESET ROLE;
CREATE FUNCTION pg_temp.resolve(root text,entity uuid,c uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE t uuid;e uuid;ledger text;idcol text;
BEGIN
 IF root NOT IN('operations','finance_invoices') THEN RAISE EXCEPTION 'fixture root'; END IF;
 EXECUTE format('SELECT tenant_id FROM public.%I WHERE id=$1',root) INTO t USING entity;
 ledger:=CASE root WHEN 'operations' THEN 'operation_company_classification_events' ELSE 'finance_invoices_company_evidence' END;
 idcol:=CASE root WHEN 'operations' THEN 'operation_id' ELSE 'entity_id' END;
 EXECUTE format('INSERT INTO private.%I(tenant_id,%I,company_id,decision,evidence_kind,evidence_reference,recorded_by)
 VALUES($1,$2,$3,''resolved'',''verified_source_record'',''synthetic-only'',$4) RETURNING id',ledger,idcol)
 INTO e USING t,entity,c,current_setting('d.u')::uuid;
 EXECUTE format('UPDATE public.%I SET company_id=$1,company_classification_status=''resolved'',company_classification_event_id=$2 WHERE id=$3',root)
 USING c,e,entity;
END $$;
DO $$ DECLARE t uuid;x uuid;a uuid;b uuid;xc uuid;u uuid:=gen_random_uuid();ng uuid:=gen_random_uuid();op uuid;inv uuid;f uuid;e uuid;
BEGIN
 INSERT INTO public.tenants(name,slug) VALUES('Delivery synthetic','delivery-'||gen_random_uuid()) RETURNING id INTO t;
 INSERT INTO public.tenants(name,slug) VALUES('Delivery other','delivery-'||gen_random_uuid()) RETURNING id INTO x;
 INSERT INTO public.memberships(user_id,tenant_id,role) VALUES(u,t,'finance'),(ng,t,'admin');
 INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status) VALUES(t,'A','Synthetic A','AAA010101AA1','active') RETURNING id INTO a;
 INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status) VALUES(t,'B','Synthetic B','BBB010101BB1','active') RETURNING id INTO b;
 INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status) VALUES(x,'X','Synthetic X','XXX010101XX1','active') RETURNING id INTO xc;
 INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES(t,u,a,u),(t,u,b,u);
 INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
 SELECT t,u,a,c,'synthetic-only',u FROM unnest(ARRAY['operations.read','billing.document.read','receivables.read','export.operational','export.receivables'])c;
 PERFORM set_config('d.t',t::text,true);PERFORM set_config('d.x',x::text,true);PERFORM set_config('d.u',u::text,true);
 PERFORM set_config('d.a',a::text,true);PERFORM set_config('d.b',b::text,true);PERFORM set_config('d.xc',xc::text,true);PERFORM set_config('d.ng',ng::text,true);
 INSERT INTO private.delivery_tenant_cutovers(tenant_id,enabled,approval_reference,approved_by) VALUES(t,true,'synthetic-only',u);
 FOR i IN 1..3 LOOP
  INSERT INTO public.operations(tenant_id,reference_code,provider_cost_amount,customer_price_amount,notes,status,created_at,updated_at)
  VALUES(t,'A-'||i,12345,54321,'FINANCIAL_CANARY',CASE WHEN i=1 THEN 'delivered' ELSE 'planned' END,
   CASE WHEN i=1 THEN now()-interval '71.4 hours' ELSE now() END,now()) RETURNING id INTO op;
  PERFORM pg_temp.resolve('operations',op,a);IF i=1 THEN PERFORM set_config('d.op',op::text,true);END IF;
 END LOOP;
 INSERT INTO public.operations(tenant_id,reference_code) VALUES(t,'B') RETURNING id INTO op;PERFORM pg_temp.resolve('operations',op,b);PERFORM set_config('d.ob',op::text,true);
 INSERT INTO public.operations(tenant_id,reference_code) VALUES(x,'X') RETURNING id INTO op;PERFORM pg_temp.resolve('operations',op,xc);PERFORM set_config('d.ox',op::text,true);
 INSERT INTO public.operations(tenant_id,reference_code) VALUES(t,'UNCLASSIFIED') RETURNING id INTO op;PERFORM set_config('d.pending',op::text,true);
 INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,reference,amount,currency,status,operation_id)
 VALUES(t,'ar','Synthetic customer','AR-A',1000,'MXN','open',current_setting('d.op')::uuid) RETURNING id INTO inv;
 PERFORM pg_temp.resolve('finance_invoices',inv,a);PERFORM set_config('d.invoice',inv::text,true);
 INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,reference,amount,currency,status,operation_id)
 VALUES(t,'ap','Synthetic provider','AP-A',88888,'MXN','open',current_setting('d.op')::uuid) RETURNING id INTO inv;PERFORM pg_temp.resolve('finance_invoices',inv,a);
 INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,reference,amount,currency,status,operation_id)
 VALUES(t,'ar','Other customer','AR-B',77777,'MXN','open',current_setting('d.ob')::uuid) RETURNING id INTO inv;PERFORM pg_temp.resolve('finance_invoices',inv,b);
 INSERT INTO public.document_files(tenant_id,storage_bucket,storage_path,file_name,mime_type,size_bytes,file_kind,source_module,source_entity_type,source_entity_id,status,access_class)
 VALUES(t,'tenant-documents',t||'/operations/synthetic.txt','synthetic.txt','text/plain',12,'operation_evidence','operations','operation',current_setting('d.op')::uuid,'active','operational') RETURNING id INTO f;
 INSERT INTO private.delivery_classification_events(tenant_id,entity_table,entity_id,company_id,access_class,evidence_reference,recorded_by)
 VALUES(t,'document_files',f,a,'operational','synthetic-only',u) RETURNING id INTO e;
 UPDATE public.document_files SET company_id=a,company_classification_status='resolved',company_classification_event_id=e WHERE id=f;
 PERFORM set_config('d.file',f::text,true);
END $$;

INSERT INTO auth.users(id,email) VALUES(current_setting('d.u')::uuid,'child-'||current_setting('d.u')||'@example.test');
UPDATE public.memberships SET role='operator' WHERE user_id=current_setting('d.u')::uuid;
UPDATE public.operations SET operation_scope='international' WHERE id=current_setting('d.op')::uuid;
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by)
SELECT current_setting('d.t')::uuid,current_setting('d.u')::uuid,current_setting('d.a')::uuid,c,'local-C03',current_setting('d.u')::uuid
FROM unnest(ARRAY['operations.edit','operations.evidence.write'])c;
SELECT pg_temp.actor(current_setting('d.u')::uuid,current_setting('d.a')::uuid);
CREATE FUNCTION pg_temp.child(action text,payload jsonb,key uuid DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
SELECT public.rpc_delivery_operation_child_action(current_setting('d.t')::uuid,current_setting('d.op')::uuid,action,payload,
 COALESCE(key,gen_random_uuid()),(public.rpc_delivery_operation_workflow(current_setting('d.t')::uuid,current_setting('d.op')::uuid)->>'workflow_revision')::bigint);
$$;

-- Synthetic pre-adoption incidents: their old text has not been classified.
DO $$DECLARE a uuid;b uuid;c uuid;BEGIN
 INSERT INTO public.operation_incidents(tenant_id,operation_id,category,title,description,is_blocking,reported_by)
 VALUES(current_setting('d.t')::uuid,current_setting('d.op')::uuid,'general','FINANCIAL_CANARY_OLD_TITLE','FINANCIAL_CANARY_OLD_DETAIL',true,current_setting('d.u')::uuid) RETURNING id INTO a;
 INSERT INTO public.operation_incidents(tenant_id,operation_id,category,title,description,is_blocking,reported_by)
 VALUES(current_setting('d.t')::uuid,current_setting('d.op')::uuid,'general','FINANCIAL_CANARY_RESOLVE_TITLE','FINANCIAL_CANARY_RESOLVE_DETAIL',false,current_setting('d.u')::uuid) RETURNING id INTO b;
 INSERT INTO public.operation_incidents(tenant_id,operation_id,category,title,description,is_blocking,reported_by)
 VALUES(current_setting('d.t')::uuid,current_setting('d.op')::uuid,'general','FINANCIAL_CANARY_DISMISS_TITLE','FINANCIAL_CANARY_DISMISS_DETAIL',false,current_setting('d.u')::uuid) RETURNING id INTO c;
 -- Reproduce a pre-fix fact. Its description must not become creation provenance.
 UPDATE public.operation_incidents SET status='resolved',resolved_by=current_setting('d.u')::uuid,resolved_at=now(),resolution_note='Prior operational resolution' WHERE id=a;
 INSERT INTO private.c03_child_facts(tenant_id,operation_id,entity_kind,entity_id,actor_id,action,projection)
 VALUES(current_setting('d.t')::uuid,current_setting('d.op')::uuid,'incident',a,current_setting('d.u')::uuid,'incident.resolve','{"description":"FINANCIAL_CANARY_COPIED_OLD","resolution_note":"Prior operational resolution"}');
 PERFORM set_config('d.legacy',a::text,true);PERFORM set_config('d.resolve',b::text,true);PERFORM set_config('d.dismiss',c::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;BEGIN
 r:=public.rpc_delivery_operation_children(current_setting('d.t')::uuid,current_setting('d.op')::uuid);
 PERFORM pg_temp.ok(jsonb_array_length(r->'incidents')=3,'historical structural incidents remain available');
 PERFORM pg_temp.ok(r::text NOT LIKE '%FINANCIAL_CANARY%','old title/detail and old copied fact are not exposed');
 PERFORM pg_temp.ok(EXISTS(SELECT FROM jsonb_array_elements(r->'incidents')i WHERE i->>'id'=current_setting('d.legacy') AND i->>'resolution_note'='Prior operational resolution' AND NOT(i ? 'description')),'old action note remains without promoting its copied description');
END $$;
SELECT pg_temp.ok(pg_temp.child('incident.resolve',jsonb_build_object('id',current_setting('d.resolve'),'note','New operational resolution'))->>'success'='true','resolve historical incident without field reclassification');
SELECT pg_temp.ok(pg_temp.child('incident.dismiss',jsonb_build_object('id',current_setting('d.dismiss'),'note','New operational discard'))->>'success'='true','dismiss historical incident without field reclassification');
SELECT pg_temp.ok(public.rpc_delivery_operation_children(current_setting('d.t')::uuid,current_setting('d.op')::uuid)::text NOT LIKE '%FINANCIAL_CANARY%','legacy text stays unavailable after both actions');
SELECT set_config('d.new_incident',(pg_temp.child('incident.create','{"category":"general","title":"Typed operational title","description":"Typed operational detail","is_blocking":false}')->>'id'),true);
SELECT pg_temp.ok(pg_temp.child('incident.resolve',jsonb_build_object('id',current_setting('d.new_incident'),'note','Typed operational resolution'))->>'success'='true','new authorized incident resolves normally');
DO $$DECLARE i jsonb;BEGIN
 SELECT x INTO i FROM jsonb_array_elements(public.rpc_delivery_operation_children(current_setting('d.t')::uuid,current_setting('d.op')::uuid)->'incidents')x WHERE x->>'id'=current_setting('d.new_incident');
 PERFORM pg_temp.ok(i->>'title'='Typed operational title' AND i->>'description'='Typed operational detail' AND i->>'resolution_note'='Typed operational resolution','creation detail and later action note both survive');
END $$;
SELECT pg_temp.ok(public.rpc_delivery_operation_children(current_setting('d.t')::uuid,current_setting('d.ob')::uuid)->>'error'='unauthorized','foreign parent remains denied');
RESET ROLE;
SELECT pg_temp.ok(EXISTS(SELECT FROM private.c03_child_facts WHERE entity_id=current_setting('d.legacy')::uuid AND projection->>'description'='FINANCIAL_CANARY_COPIED_OLD'),'old immutable evidence preserved, not rewritten');
SELECT pg_temp.ok(NOT EXISTS(SELECT FROM private.c03_child_facts WHERE entity_id IN(current_setting('d.resolve')::uuid,current_setting('d.dismiss')::uuid) AND projection ? 'description'),'new action facts never copy historical description');
SELECT pg_temp.ok(NOT has_function_privilege('anon','public.rpc_delivery_operation_children(uuid,uuid)','EXECUTE') AND NOT has_function_privilege('service_role','public.rpc_delivery_operation_child_action(uuid,uuid,text,jsonb,uuid,bigint)','EXECUTE'),'effective API ACL unchanged');
SELECT 'C03_HISTORICAL_TEXT_ASSERTIONS='||current_setting('d.assertions');
ROLLBACK;
