from pathlib import Path
import json,hashlib,re
import argparse
p=argparse.ArgumentParser(description='Reproduce the guarded adoption migration from a reviewed canonical 49-migration local catalog. Never connects to a database.')
p.add_argument('--catalog',required=True,type=Path)
p.add_argument('--column-order',required=True,type=Path)
p.add_argument('--manifest',required=True,type=Path)
a=p.parse_args()
R=Path(__file__).resolve().parents[2]
C=json.loads(a.catalog.read_text())
ORDER=json.loads(a.column_order.read_text())
sql=[]
def add(s):sql.append('\n'.join(line.rstrip() for line in s.strip().splitlines())+'\n')
def literal(s):return "'"+s.replace("'","''")+"'"
add('''-- Explicit company adoption. No historical classification, grants or tenant cutover.
BEGIN;
SET LOCAL ROLE rotero_company_access_owner;
GRANT REFERENCES(tenant_id,id) ON public.companies TO postgres;
SET LOCAL ROLE postgres;
CREATE TABLE private.delivery_classification_events(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL,
 entity_table text NOT NULL CHECK(entity_table IN ('crm_deals','inventory_lots','billing_cfdis','document_files','generated_documents','internal_notifications')),
 entity_id uuid NOT NULL,company_id uuid NOT NULL,
 access_class text CHECK((entity_table IN('document_files','generated_documents') AND access_class IS NOT NULL AND access_class IN('operational','receivable','financial'))
  OR (entity_table NOT IN('document_files','generated_documents') AND access_class IS NULL)),
 evidence_reference text NOT NULL CHECK(length(btrim(evidence_reference)) BETWEEN 1 AND 400),
 recorded_by uuid NOT NULL,recorded_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(entity_table,tenant_id,entity_id,company_id,id),
 UNIQUE(entity_table,tenant_id,entity_id,company_id,access_class,id),
 FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id)
);
ALTER TABLE private.delivery_classification_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.delivery_classification_events FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.delivery_immutable_evidence() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'classification_evidence_immutable'; END $$;
CREATE TRIGGER delivery_classification_immutable BEFORE UPDATE OR DELETE ON private.delivery_classification_events
FOR EACH ROW EXECUTE FUNCTION private.delivery_immutable_evidence();
''')
roots=['crm_deals','inventory_lots','billing_cfdis','document_files','generated_documents','internal_notifications']
for t in roots:
 add(f'''ALTER TABLE public.{t}
 ADD COLUMN company_id uuid,
 ADD COLUMN company_classification_event_id uuid,
 ADD COLUMN company_classification_status text NOT NULL DEFAULT 'pending_classification',
 ADD COLUMN company_entity_table text GENERATED ALWAYS AS ('{t}'::text) STORED,
 ADD CONSTRAINT {t}_delivery_company_fk FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id),
 ADD CONSTRAINT {t}_delivery_classification_fk FOREIGN KEY(company_entity_table,tenant_id,id,company_id,company_classification_event_id)
 REFERENCES private.delivery_classification_events(entity_table,tenant_id,entity_id,company_id,id),
 ADD CONSTRAINT {t}_delivery_classification_check CHECK(
 (company_id IS NOT NULL AND company_classification_event_id IS NOT NULL AND company_classification_status='resolved') OR
 (company_id IS NULL AND company_classification_event_id IS NULL AND company_classification_status IN('pending_classification','conflict')));
 CREATE INDEX {t}_delivery_company_idx ON public.{t}(tenant_id,company_id,id);
 CREATE INDEX {t}_delivery_evidence_fk_idx ON public.{t}(company_entity_table,tenant_id,id,company_id,company_classification_event_id);
 GRANT SELECT(id,tenant_id,company_id,company_classification_status) ON public.{t} TO rotero_delivery_scope_owner;
 CREATE POLICY {t}_delivery_metadata ON public.{t} FOR SELECT TO rotero_delivery_scope_owner USING(true);''')
add('''-- Preserve ambiguous history; enforce known-company relationships on new writes.
ALTER TABLE public.crm_deals ADD CONSTRAINT crm_deals_delivery_company_key UNIQUE(tenant_id,company_id,id);
ALTER TABLE public.billing_cfdis ADD CONSTRAINT billing_cfdis_delivery_company_key UNIQUE(tenant_id,company_id,id);
ALTER TABLE public.operations ADD CONSTRAINT operations_delivery_quote_company_fk FOREIGN KEY(tenant_id,company_id,source_deal_id)
 REFERENCES public.crm_deals(tenant_id,company_id,id) DEFERRABLE INITIALLY DEFERRED NOT VALID;
ALTER TABLE public.crm_deals ADD CONSTRAINT deals_delivery_operation_company_fk FOREIGN KEY(tenant_id,company_id,converted_operation_id)
 REFERENCES public.operations(tenant_id,company_id,id) DEFERRABLE INITIALLY DEFERRED NOT VALID;
ALTER TABLE public.billing_cfdis ADD CONSTRAINT cfdis_delivery_operation_company_fk FOREIGN KEY(tenant_id,company_id,operation_id)
 REFERENCES public.operations(tenant_id,company_id,id) NOT VALID;
ALTER TABLE public.finance_invoices ADD CONSTRAINT invoices_delivery_cfdi_company_fk FOREIGN KEY(tenant_id,company_id,linked_cfdi_id)
 REFERENCES public.billing_cfdis(tenant_id,company_id,id) NOT VALID;
ALTER TABLE public.billing_documents ADD CONSTRAINT documents_delivery_cfdi_company_fk FOREIGN KEY(tenant_id,company_id,linked_cfdi_id)
 REFERENCES public.billing_cfdis(tenant_id,company_id,id) NOT VALID;
ALTER TABLE public.billing_credit_notes ADD CONSTRAINT credits_delivery_cfdi_company_fk FOREIGN KEY(tenant_id,company_id,cfdi_id)
 REFERENCES public.billing_cfdis(tenant_id,company_id,id) NOT VALID;
REVOKE ALL ON FUNCTION private.delivery_immutable_evidence() FROM PUBLIC,anon,authenticated,service_role;
''')
add('''-- Metadata resolver never uses a display name, creator or default company.
CREATE FUNCTION private.delivery_root_company(p_tenant uuid,p_kind text,p_id uuid) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE c uuid;s record;
BEGIN
 CASE p_kind
 WHEN 'quote' THEN SELECT company_id INTO c FROM public.crm_deals WHERE tenant_id=p_tenant AND id=p_id AND company_classification_status='resolved';
 WHEN 'inventory' THEN SELECT company_id INTO c FROM public.inventory_lots WHERE tenant_id=p_tenant AND id=p_id AND company_classification_status='resolved';
 WHEN 'billing_cfdi' THEN SELECT company_id INTO c FROM public.billing_cfdis WHERE tenant_id=p_tenant AND id=p_id AND company_classification_status='resolved';
 WHEN 'file' THEN SELECT company_id INTO c FROM public.document_files WHERE tenant_id=p_tenant AND id=p_id AND company_classification_status='resolved';
 WHEN 'generated_document' THEN SELECT company_id INTO c FROM public.generated_documents WHERE tenant_id=p_tenant AND id=p_id AND company_classification_status='resolved';
 ELSE
  SELECT * INTO s FROM private.multi07_entity_scope(CASE p_kind WHEN 'finance_invoice' THEN 'invoice' WHEN 'billing_document' THEN 'document' ELSE p_kind END,p_id);
  IF FOUND AND s.tenant_id=p_tenant AND s.coherent AND cardinality(s.company_ids)=1 THEN c:=s.company_ids[1]; END IF;
 END CASE;RETURN c;
END $$;
GRANT CREATE ON SCHEMA private TO rotero_delivery_scope_owner;
ALTER FUNCTION private.delivery_root_company(uuid,text,uuid) OWNER TO rotero_delivery_scope_owner;
REVOKE CREATE ON SCHEMA private FROM rotero_delivery_scope_owner;
SET LOCAL ROLE rotero_delivery_scope_owner;
REVOKE ALL ON FUNCTION private.delivery_root_company(uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private.delivery_root_company(uuid,text,uuid) TO postgres;
SET LOCAL ROLE postgres;

CREATE FUNCTION private.delivery_assert_root_links() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE parent uuid; k text; root_id uuid; j jsonb:=to_jsonb(NEW);
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(NEW.tenant_id::text,7007));
 IF j->>'company_id' IS NULL THEN RETURN NEW; END IF;
 IF TG_TABLE_NAME='billing_cfdis' AND j->>'operation_id' IS NOT NULL THEN
  parent:=private.delivery_root_company(NEW.tenant_id,'operation',(j->>'operation_id')::uuid);
  IF parent IS DISTINCT FROM NEW.company_id THEN RAISE EXCEPTION 'company_parent_mismatch'; END IF;
 ELSIF TG_TABLE_NAME IN('document_files','generated_documents') THEN
  k:=COALESCE(j->>'source_entity_type',j->>'related_entity_type');
  root_id:=COALESCE(j->>'source_entity_id',j->>'related_entity_id')::uuid;
  IF root_id IS NULL OR k NOT IN('operation','finance_invoice','billing_document','billing_cfdi','quote') THEN RAISE EXCEPTION 'document_classification_pending'; END IF;
  parent:=private.delivery_root_company(NEW.tenant_id,k,root_id);
  IF parent IS DISTINCT FROM NEW.company_id THEN RAISE EXCEPTION 'company_parent_mismatch'; END IF;
 END IF;RETURN NEW;
END $$;
''')
for t in ['billing_cfdis','document_files','generated_documents']:
 add(f'CREATE TRIGGER {t}_delivery_parent BEFORE INSERT OR UPDATE ON public.{t} FOR EACH ROW EXECUTE FUNCTION private.delivery_assert_root_links();')
add('''CREATE FUNCTION private.delivery_evidence_target() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE present boolean;
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(NEW.tenant_id::text,7007));
 IF NEW.entity_table NOT IN('crm_deals','inventory_lots','billing_cfdis','document_files','generated_documents','internal_notifications') THEN RAISE EXCEPTION 'classification_target_invalid'; END IF;
 EXECUTE format('SELECT EXISTS(SELECT FROM public.%I WHERE tenant_id=$1 AND id=$2)',NEW.entity_table) INTO present USING NEW.tenant_id,NEW.entity_id;
 IF NOT present THEN RAISE EXCEPTION 'classification_target_missing' USING ERRCODE='23503'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER delivery_evidence_target BEFORE INSERT ON private.delivery_classification_events FOR EACH ROW EXECUTE FUNCTION private.delivery_evidence_target();
CREATE FUNCTION private.delivery_retain_classified_root() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF EXISTS(SELECT FROM private.delivery_classification_events WHERE entity_table=TG_TABLE_NAME AND entity_id=OLD.id AND tenant_id=OLD.tenant_id)
 THEN RAISE EXCEPTION 'classification_history_retained' USING ERRCODE='23503'; END IF;RETURN OLD;
END $$;
GRANT SELECT(entity_table,entity_id,tenant_id) ON private.delivery_classification_events TO rotero_delivery_scope_owner;
CREATE POLICY delivery_evidence_metadata ON private.delivery_classification_events FOR SELECT TO rotero_delivery_scope_owner USING(true);
GRANT SELECT(source_entity_type,source_entity_id) ON public.document_files TO rotero_delivery_scope_owner;
GRANT SELECT(related_entity_type,related_entity_id) ON public.generated_documents TO rotero_delivery_scope_owner;
CREATE FUNCTION private.delivery_parent_documents_coherent() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE kind text:=CASE TG_TABLE_NAME WHEN 'operations' THEN 'operation' WHEN 'finance_invoices' THEN 'finance_invoice'
 WHEN 'billing_documents' THEN 'billing_document' WHEN 'billing_cfdis' THEN 'billing_cfdi' WHEN 'crm_deals' THEN 'quote' END;
 c uuid;
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(NEW.tenant_id::text,7007));
 c:=private.delivery_root_company(NEW.tenant_id,kind,NEW.id);
 IF EXISTS(SELECT FROM public.document_files f WHERE f.tenant_id=NEW.tenant_id AND f.source_entity_type=kind AND f.source_entity_id=NEW.id
  AND f.company_classification_status='resolved' AND f.company_id IS DISTINCT FROM c)
 OR EXISTS(SELECT FROM public.generated_documents g WHERE g.tenant_id=NEW.tenant_id AND g.related_entity_type=kind AND g.related_entity_id=NEW.id
  AND g.company_classification_status='resolved' AND g.company_id IS DISTINCT FROM c)
 THEN RAISE EXCEPTION 'classified_document_parent_mismatch'; END IF; RETURN NULL;
END $$;
''')
for t in roots:
 add(f'CREATE TRIGGER {t}_retain_classification BEFORE DELETE ON public.{t} FOR EACH ROW EXECUTE FUNCTION private.delivery_retain_classified_root();')
for t in ['operations','finance_invoices','billing_documents','billing_cfdis','crm_deals']:
 add(f'CREATE CONSTRAINT TRIGGER {t}_delivery_documents AFTER UPDATE ON public.{t} DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION private.delivery_parent_documents_coherent();')
add('''GRANT CREATE ON SCHEMA private TO rotero_delivery_scope_owner;
ALTER FUNCTION private.delivery_assert_root_links() OWNER TO rotero_delivery_scope_owner;
ALTER FUNCTION private.delivery_evidence_target() OWNER TO rotero_delivery_scope_owner;
ALTER FUNCTION private.delivery_retain_classified_root() OWNER TO rotero_delivery_scope_owner;
ALTER FUNCTION private.delivery_parent_documents_coherent() OWNER TO rotero_delivery_scope_owner;
REVOKE CREATE ON SCHEMA private FROM rotero_delivery_scope_owner;
SET LOCAL ROLE rotero_delivery_scope_owner;
REVOKE ALL ON FUNCTION private.delivery_assert_root_links(),private.delivery_evidence_target(),private.delivery_retain_classified_root(),private.delivery_parent_documents_coherent() FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE postgres;
''')
add('''-- Ordinary roles cannot reclassify or create permissions through direct writes.
-- Restrictive policies also protect accidental future table grants.
''')
tables=sorted(set(p['table_name'] for p in C['columns']))
exclude={'tenants','memberships','companies','user_company_access','user_company_capabilities'}
protected=[]
for t in tables:
 if t in exclude or not any(p['table_name']==t and p['column_name']=='tenant_id' for p in C['columns']):continue
 if t.startswith(('company_','user_company_','consolidation_','membership_company_','membership_consolidation_')):continue
 protected.append(t)
 add(f'''ALTER TABLE public.{t} ENABLE ROW LEVEL SECURITY;
 CREATE POLICY {t}_delivery_api_boundary ON public.{t} AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));''')
# No ordinary table route is opened; the new RPCs project fields after checking scope.
add('''SET LOCAL ROLE rotero_delivery_scope_owner;
GRANT EXECUTE ON FUNCTION private.delivery_required(uuid) TO anon,authenticated;
SET LOCAL ROLE postgres;
CREATE FUNCTION public.rpc_delivery_context(p_tenant_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',c.id,'display_name',c.display_name,'legal_name',c.legal_name,'rfc',c.rfc_normalized,
 'capabilities',(SELECT COALESCE(jsonb_agg(cap),'[]') FROM unnest(ARRAY['operations.read','operations.capture','billing.draft','billing.document.read','receivables.read','export.receivables','export.operational','financial.full.read','export.financial','fiscal.prepare','fiscal.issue','fiscal.read','fiscal.cancel','fiscal.payment','receivables.collect','finance.write','pipeline.read','inventory.read']) cap WHERE private.multi05_has_company_capability(c.tenant_id,c.id,cap))) ORDER BY c.display_name),'[]') INTO result
 FROM public.companies c WHERE c.tenant_id=p_tenant_id AND private.multi04_has_company_access(c.tenant_id,c.id);
 RETURN jsonb_build_object('companies',result,'consolidations',COALESCE((SELECT jsonb_agg(ids) FROM (
 SELECT array_agg(company_id ORDER BY company_id) ids FROM public.consolidation_grant_companies
 WHERE tenant_id=p_tenant_id AND user_id=auth.uid() GROUP BY consolidation_grant_id) s
 WHERE cardinality(ids)>1 AND private.multi05_can_consolidate(p_tenant_id,ids)),'[]'::jsonb),
 'cutover_required',EXISTS(SELECT FROM private.delivery_tenant_cutovers WHERE tenant_id=p_tenant_id AND enabled),
 'classification_notice','Only evidence-resolved records are included. Unclassified history is pending reconciliation.');
END $$;
REVOKE ALL ON FUNCTION public.rpc_delivery_context(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_context(uuid) TO authenticated;
''')
# Scoped source views are server-only. They filter before aggregation; no masked costs used by writers.
sources={
 'operations':"private.delivery_entity_allowed(t.tenant_id,'operation',t.id) AND (private.delivery_cap(t.tenant_id,'operations.read') OR private.delivery_cap(t.tenant_id,'financial.full.read'))",
 'crm_deals':"t.company_classification_status='resolved' AND t.company_id=ANY(private.delivery_company_ids()) AND (private.delivery_cap(t.tenant_id,'financial.full.read') OR private.delivery_cap(t.tenant_id,'pipeline.read'))",
 'inventory_lots':"t.company_classification_status='resolved' AND t.company_id=ANY(private.delivery_company_ids()) AND (private.delivery_cap(t.tenant_id,'financial.full.read') OR private.delivery_cap(t.tenant_id,'inventory.read'))",
 'billing_cfdis':"t.company_classification_status='resolved' AND t.company_id=ANY(private.delivery_company_ids()) AND private.delivery_cap(t.tenant_id,'financial.full.read') AND private.fiscal02_cfdi_ordinary_visible(t.id)",
 'finance_invoices':"private.delivery_entity_allowed(t.tenant_id,'invoice',t.id) AND private.delivery_cap(t.tenant_id,'financial.full.read') AND t.payroll_period_id IS NULL",
 'finance_payments':"private.delivery_entity_allowed(t.tenant_id,'payment',t.id) AND private.delivery_cap(t.tenant_id,'financial.full.read')",
 'billing_documents':"private.delivery_entity_allowed(t.tenant_id,'document',t.id) AND private.delivery_cap(t.tenant_id,'financial.full.read')",
 'billing_credit_notes':"private.delivery_entity_allowed(t.tenant_id,'credit',t.id) AND private.delivery_cap(t.tenant_id,'financial.full.read')",
 'billing_payment_complements':"private.delivery_entity_allowed(t.tenant_id,'complement',t.id) AND private.delivery_cap(t.tenant_id,'financial.full.read')",
}
# Determine actual fiscal helper; do not guess a nonexistent contract.
for p in C['functions']:
 if p['name'].startswith('fiscal02') and 'ordinary' in p['name']:print('fiscal helper',p['name'],p['args'])
for t in sources:
 pred=sources[t]
 if t=='billing_cfdis':pred=pred.split(' AND private.fiscal02_cfdi_ordinary_visible')[0]
 lab={'billing_cfdis':'cfdi','finance_invoices':'invoice','finance_payments':'payment','billing_documents':'document','billing_credit_notes':'credit','billing_payment_complements':'complement'}.get(t)
 if lab:pred+=f" AND NOT private.fiscal02_is_lab_entity('{lab}',t.id)"
 columns=[x['column_name'] for x in C['columns'] if x['table_name']==t]
 if t in roots:columns+=['company_id','company_classification_event_id','company_classification_status','company_entity_table']
 columns=[x for x in ORDER[t] if x in columns]
 selected=','.join('t."'+x+'"' for x in columns)
 add(f'''CREATE VIEW private.delivery_{t} WITH(security_barrier=true) AS SELECT {selected} FROM public.{t} t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_scope_allowed(t.tenant_id) AND ({pred}) ELSE true END;
 REVOKE ALL ON private.delivery_{t} FROM PUBLIC,anon,authenticated,service_role;''')
# Child views filter both tenant and the actual parent, before COUNT/JOIN.
for t in ['operation_assignment_history','operation_incidents','operation_evidence','operation_documents','operation_crossings','operation_billing','tracking_events','tracking_route_points']:
 allowed={x['column_name'] for x in C['columns'] if x['table_name']==t}
 selected=','.join('t."'+x+'"' for x in ORDER[t] if x in allowed)
 add(f'''CREATE VIEW private.delivery_{t} WITH(security_barrier=true) AS SELECT {selected} FROM public.{t} t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_entity_allowed(t.tenant_id,'operation',t.operation_id) AND private.delivery_cap(t.tenant_id,'operations.read') ELSE true END;
 REVOKE ALL ON private.delivery_{t} FROM PUBLIC,anon,authenticated,service_role;''')
sources.update({t:'' for t in ['operation_assignment_history','operation_incidents','operation_evidence','operation_documents','operation_crossings','operation_billing','tracking_events','tracking_route_points']})
selected=','.join('t."'+x+'"' for x in ORDER['billing_carta_porte'] if any(c['table_name']=='billing_carta_porte' and c['column_name']==x for c in C['columns']))
add(f'''CREATE VIEW private.delivery_billing_carta_porte WITH(security_barrier=true) AS SELECT {selected} FROM public.billing_carta_porte t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN
 EXISTS(SELECT FROM private.delivery_billing_cfdis c WHERE c.id=t.cfdi_id AND c.tenant_id=t.tenant_id) ELSE true END;
 REVOKE ALL ON private.delivery_billing_carta_porte FROM PUBLIC,anon,authenticated,service_role;''')
sources['billing_carta_porte']=''
# Exact admitted legacy contracts; every other API is denied for a protected context.
ops=['rpc_list_operations','rpc_get_operation','rpc_reports_operations_summary','rpc_dashboard_recent_activity','rpc_reports_tanda1','rpc_get_operation_document_summary','rpc_get_operation_incident_summary','rpc_get_operation_billing_summary']
child_dtos={
 'rpc_list_operation_assignment_history':['id','operation_id','execution_type','provider_id','provider_name','driver_name','vehicle_ref','planned_departure','created_at'],
 'rpc_list_operation_incidents':['id','operation_id','category','title','is_blocking','status','created_at','updated_at','resolved_at'],
 'rpc_list_operation_evidence':['id','operation_id','incident_id','kind','created_at'],
 'rpc_list_operation_documents':['id','operation_id','document_type','display_label','requirement_level','status','created_at','updated_at'],
 'rpc_list_operation_crossings':['id','operation_id','crossing_type','status','planned_at','crossed_at','created_at','updated_at'],
 'rpc_list_operation_tracking_events':['id','operation_id','event_type','source','occurred_at','created_at'],
 'rpc_get_operation_dispatch_readiness':['operation_id','execution_type','is_minimum_planned_complete','is_assignment_complete','is_tracking_ready','has_driver_token','has_public_token','can_transition_to_assigned','can_transition_to_in_transit','blocking_reasons','provider_compliance_ready','provider_compliance_blocker_reasons'],
 'rpc_get_operation_billing':['operation_id','billing_status','is_billed','has_billing_record','pod_present','is_documentation_complete','billing_readiness','can_admin_close'],
}
ops+=list(child_dtos)
full=['rpc_reports_financial_summary','rpc_reports_pipeline_summary','rpc_reports_inventory_summary','rpc_dashboard_overview','rpc_dashboard_alerts','rpc_list_finance_invoices','rpc_list_finance_payments','rpc_list_finance_due_alerts','rpc_get_finance_invoice_detail','rpc_get_operation_finance_summary','rpc_finance_overview','rpc_finance_profitability','rpc_list_payment_complements','rpc_export_finance_ledger','rpc_list_cfdis','rpc_get_cfdi_detail','rpc_get_fiscal_readiness']
writers={'rpc_create_finance_invoice','rpc_record_payment','rpc_update_finance_invoice_status','rpc_void_finance_invoice','rpc_create_payment_complement'}
# Arrays with arbitrary historic text/snapshots are not forwarded; dedicated DTOs below.
admitted=set(ops+full)|writers
safe={'rpc_get_my_context','rpc_fiscal01_context'}
skip={'tanda1_user_is_member','tanda1_user_has_role','rpc_get_company_fiscal_provider','rpc_configure_company_fiscal_provider'}
manifest=[]
for p in C['functions']:
 if p['schema']!='public' or not p['authenticated'] or p['name'] in skip|safe:continue
 assert p['prosecdef'] and p['result']=='jsonb' and p['owner']=='postgres'
 name=p['name'];args=p['args'];argnames=re.findall(r'\b(p_[a-z0-9_]+)\s',args)
 signature=name+'('+args+')';core='delivery_core_'+hashlib.sha256(signature.encode()).hexdigest()[:20]
 scoped_core=core.replace('delivery_core_','delivery_scoped_') if name in admitted else core
 md5=hashlib.md5(p['prosrc'].encode()).hexdigest()
 crlf_md5=hashlib.md5(p['prosrc'].replace('\n','\r\n').encode()).hexdigest()
 ident=re.sub(r'\bp_[a-z0-9_]+\s+','',args)
 config='ARRAY['+','.join(literal(x) for x in (p['proconfig'] or []))+']::text[]'
 manifest.append({'function':name,'arguments':args,'source_md5':md5,'uniform_crlf_md5':crlf_md5,'admitted':name in admitted})
 # Copy implementation (not move): existing function OIDs keep going through the guard.
 definition=p['definition'].replace('FUNCTION public.'+name+'(', 'FUNCTION private.'+core+'(',1)
 if name in admitted-writers:
  # Replace read sources only. Admitted functions contain no root writes.
  assert not re.search(r'\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+public\.',p['prosrc'],re.I),name
  for t in sources:definition=re.sub(r'\bpublic\.'+t+r'\b','private.delivery_'+t,definition)
  # Fiscal02 aliases continue excluding the laboratory. Wrap their rows with the company filter too.
  for t in ['finance_invoices','finance_payments','billing_credit_notes','billing_payment_complements','billing_documents','billing_cfdis']:
   definition=re.sub(r'\bprivate\.(?:fiscal02_(?:legacy_|readable_)|multi07_)(?:'+t+r')\b','private.delivery_'+t,definition)
  for t in sources:definition=re.sub(r'\bprivate\.m07_(?:set_|row_|export_)?'+t+r'\b','private.delivery_'+t,definition)
 add(f'''DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname={literal(name)} AND pg_get_function_identity_arguments(p.oid)={literal(args)} AND md5(p.prosrc)=ANY(ARRAY[{literal(md5)},{literal(crlf_md5)}]) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig={config} AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: {name}'; END IF; END $guard$;''')
 # Clone only after checking the exact historical body. Avoid duplicating legacy SQL
 # in a new migration; replacements are explicit, confined to admitted read sources.
 clone="replace(pg_get_functiondef(p.oid),"+literal('FUNCTION public.'+name+'(')+','+literal('FUNCTION private.'+core+'(')+")"
 if name in admitted:
  add(f'''DO $legacy$ DECLARE d text;BEGIN SELECT {clone} INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname={literal(name)} AND pg_get_function_identity_arguments(p.oid)={literal(args)};EXECUTE d;END $legacy$;''')
  add(f'REVOKE ALL ON FUNCTION private.{core}({ident}) FROM PUBLIC,anon,authenticated,service_role;')
  clone="replace(pg_get_functiondef(p.oid),"+literal('FUNCTION public.'+name+'(')+','+literal('FUNCTION private.'+scoped_core+'(')+")"
 if name in admitted-writers:
  for t in sources:
   # Replace FROM/JOIN sources; keep public composite types and signatures intact.
   clone='regexp_replace('+clone+','+literal(r'(?i)\m(from|join)\s+public\.'+t+r'\M')+','+literal(r'\1 private.delivery_'+t)+",'g')"
  for t in sources:
   for prefix in ['private.m07_set_','private.m07_row_','private.m07_export_','private.m07_single_']:
    clone='replace('+clone+','+literal(prefix+t)+','+literal('private.delivery_'+t)+')'
  for t in ['finance_invoices','finance_payments','billing_credit_notes','billing_payment_complements','billing_documents','billing_cfdis']:
   for prefix in ['private.fiscal02_legacy_','private.fiscal02_readable_']:
    clone='replace('+clone+','+literal(prefix+t)+','+literal('private.delivery_'+t)+')'
  clone='replace('+clone+','+literal('private.fiscal02_readable_cfdis')+','+literal('private.delivery_billing_cfdis')+')'
 if name in writers:clone='replace('+clone+','+literal('private.multi08_legacy_write_target')+','+literal('private.delivery_finance_write_target')+')'
 add(f'''DO $clone$ DECLARE d text; BEGIN SELECT {clone} INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname={literal(name)} AND pg_get_function_identity_arguments(p.oid)={literal(args)};EXECUTE d; END $clone$;''')
 add(f'REVOKE ALL ON FUNCTION private.{scoped_core}({ident}) FROM PUBLIC,anon,authenticated,service_role;')
 tenant='p_tenant_id' if 'p_tenant_id' in argnames else 'NULL::uuid'
 required=f'(private.delivery_required({tenant}) OR private.delivery_required(NULL))'
 gate="RETURN jsonb_build_object('error','company_adoption_pending');"
 if name in admitted:
  cap='operations.read' if name in ops else 'financial.full.read'
  test=f"private.delivery_cap(v_tenant,{literal(cap)})"
  if name=='rpc_reports_pipeline_summary':test+=" OR private.delivery_cap(v_tenant,'pipeline.read')"
  if name=='rpc_reports_inventory_summary':test+=" OR private.delivery_cap(v_tenant,'inventory.read')"
  if name=='rpc_dashboard_overview':test="private.delivery_cap(v_tenant,'operations.read')"
  gate=f"IF NOT ({test}) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;"
  if name in writers:gate+="IF NOT private.delivery_cap(v_tenant,'finance.write') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;"
  if name=='rpc_create_payment_complement':gate+="IF NOT private.delivery_cap(v_tenant,'billing.draft') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;"
  if name=='rpc_export_finance_ledger':gate+="IF NOT private.delivery_cap(v_tenant,'export.financial') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;"
 # Known IDs resolved before all result/error handling. Same denial for missing/foreign.
 resolve=''
 if tenant.startswith('NULL') and name in admitted and 'p_operation_id' in argnames:
  resolve='SELECT tenant_id INTO v_tenant FROM public.operations WHERE id=p_operation_id;'
  gate="IF NOT private.delivery_entity_allowed(v_tenant,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;"+gate
 if tenant.startswith('NULL') and name in admitted and 'p_cfdi_id' in argnames:
  resolve='SELECT tenant_id INTO v_tenant FROM public.billing_cfdis WHERE id=p_cfdi_id;'
  gate="IF private.fiscal02_is_lab_entity('cfdi',p_cfdi_id) OR NOT COALESCE(private.delivery_root_company(v_tenant,'billing_cfdi',p_cfdi_id)=ANY(private.delivery_company_ids()),false) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;"+gate
 projection='RETURN result;'
 if name in full:projection="RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;"
 if name=='rpc_create_finance_invoice':projection="IF result->>'error' IS NULL AND result->>'id' IS NOT NULL THEN PERFORM private.delivery_classify_new_invoice(v_tenant,(result->>'id')::uuid); END IF; RETURN result;"
 if name in ['rpc_get_operation','rpc_list_operations']:
  projection="RETURN private.delivery_operation_dto(result);"
 if name=='rpc_get_operation':
  projection="RETURN private.delivery_operation_dto(result) || CASE WHEN private.delivery_cap(v_tenant,'financial.full.read') THEN private.delivery_pick_dto(result,ARRAY['provider_cost_amount','customer_price_amount','pricing_currency']) ELSE '{}'::jsonb END;"
 if name in child_dtos:
  projection='RETURN private.delivery_pick_dto(result,ARRAY['+','.join(literal(k) for k in child_dtos[name])+']);'
 if name=='rpc_get_operation_billing_summary':
  projection="RETURN private.delivery_pick_dto(result,ARRAY['operation_id','billing_status','is_billed','has_billing_record','pod_present','is_documentation_complete','billing_readiness','can_admin_close']);"
 if name=='rpc_reports_inventory_summary':
  projection="RETURN CASE WHEN private.delivery_cap(v_tenant,'financial.full.read') THEN result ELSE private.delivery_pick_dto(result,ARRAY['blocked_count','low_stock_count']) END;"
 if name=='rpc_dashboard_overview':
  projection="RETURN CASE WHEN private.delivery_cap(v_tenant,'financial.full.read') THEN result ELSE jsonb_build_object('kpis',private.delivery_pick_dto(result->'kpis',ARRAY['ops_total','ops_in_transit']),'financial_available',false) END;"
 # Definitions preserve signature/defaults/volatility/ACL, but secure the wrapper search_path.
 vol={'v':'VOLATILE','s':'STABLE','i':'IMMUTABLE'}[p['provolatile']]
 settings=' '.join(line.strip() for line in p['definition'].split('\nAS $',1)[0].splitlines() if line.strip().startswith('SET '))
 assert settings and 'search_path' in settings
 add(f'''CREATE OR REPLACE FUNCTION public.{name}({p['default_args']}) RETURNS jsonb LANGUAGE plpgsql {vol} SECURITY DEFINER {settings} AS $wrapper$
 DECLARE v_tenant uuid:={tenant};result jsonb;
 BEGIN
 IF {required} THEN
  {resolve}
  {gate}
  result:=private.{scoped_core}({','.join(argnames)});
  {projection}
 END IF;
 RETURN private.{core}({','.join(argnames)});
 END $wrapper$;''')
add('''-- Explicit DTO; unknown fields never enter a browser/CSV, even after a schema addition.
CREATE FUNCTION private.delivery_operation_dto(p_data jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE keys text[]:=ARRAY['id','tenant_id','company_id','reference_code','status','service_type','route_summary','client_display_name','provider_name','operation_scope','execution_type','priority','planned_departure','operational_window_start','operational_window_end','created_at','updated_at','destination_city','eta','eta_display'];r jsonb;
BEGIN
 IF jsonb_typeof(p_data)='array' THEN SELECT COALESCE(jsonb_agg(private.delivery_operation_dto(value)),'[]') INTO r FROM jsonb_array_elements(p_data);RETURN r; END IF;
 IF p_data ? 'error' THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 SELECT COALESCE(jsonb_object_agg(key,value),'{}') INTO r FROM jsonb_each(p_data) WHERE key=ANY(keys);RETURN r;
END $$;
REVOKE ALL ON FUNCTION private.delivery_operation_dto(jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.delivery_pick_dto(p_data jsonb,p_keys text[]) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE r jsonb;
BEGIN
 IF jsonb_typeof(p_data)='array' THEN SELECT COALESCE(jsonb_agg(private.delivery_pick_dto(value,p_keys)),'[]') INTO r FROM jsonb_array_elements(p_data);RETURN r; END IF;
 IF p_data ? 'error' THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 SELECT COALESCE(jsonb_object_agg(key,value),'{}') INTO r FROM jsonb_each(p_data) WHERE key=ANY(p_keys);RETURN r;
END $$;
REVOKE ALL ON FUNCTION private.delivery_pick_dto(jsonb,text[]) FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE rotero_company_access_owner;
REVOKE REFERENCES(tenant_id,id) ON public.companies FROM postgres;
SET LOCAL ROLE postgres;
COMMIT;
''')
# An unexpected staging RPC/view is a stop condition, not an unguarded fallback.
expected=[p['name']+'('+p['args']+')' for p in C['functions'] if p['schema']=='public' and p['authenticated']]
expected.append('rpc_delivery_context(p_tenant_id uuid)')
gate='''DO $surface$ DECLARE f record;BEGIN
 FOR f IN SELECT p.proname,pg_get_function_identity_arguments(p.oid) args FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND (p.proname LIKE 'rpc_%' OR p.proname LIKE 'tanda1_%') AND has_function_privilege('authenticated',p.oid,'EXECUTE') LOOP
 IF NOT (f.proname||'('||f.args||')'=ANY(ARRAY[EXPECTED])) THEN RAISE EXCEPTION 'unreviewed_authenticated_RPC: %',f.proname;END IF;
 END LOOP;
 IF EXISTS(SELECT FROM pg_class WHERE relnamespace='public'::regnamespace AND relkind IN('v','m')
  AND (has_table_privilege('authenticated',oid,'SELECT') OR has_table_privilege('anon',oid,'SELECT')))
 THEN RAISE EXCEPTION 'unreviewed_public_view'; END IF;
END $surface$;
'''.replace('EXPECTED',','.join(literal(x) for x in expected))
sql[-1]=sql[-1].replace('COMMIT;',gate+'COMMIT;')
(R/'supabase/migrations/20261027183712_delivery_scope_adoption.sql').write_bytes(('\n'.join(sql)).encode())
a.manifest.write_text(json.dumps({'functions':manifest,'direct_tables_closed':protected},indent=2))
print('Generated adoption:',len(manifest),'RPC guards;',len(protected),'direct-table boundaries')
