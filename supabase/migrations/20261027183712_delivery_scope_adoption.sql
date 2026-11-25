-- Explicit company adoption. No historical classification, grants or tenant cutover.
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

ALTER TABLE public.crm_deals
 ADD COLUMN company_id uuid,
 ADD COLUMN company_classification_event_id uuid,
 ADD COLUMN company_classification_status text NOT NULL DEFAULT 'pending_classification',
 ADD COLUMN company_entity_table text GENERATED ALWAYS AS ('crm_deals'::text) STORED,
 ADD CONSTRAINT crm_deals_delivery_company_fk FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id),
 ADD CONSTRAINT crm_deals_delivery_classification_fk FOREIGN KEY(company_entity_table,tenant_id,id,company_id,company_classification_event_id)
 REFERENCES private.delivery_classification_events(entity_table,tenant_id,entity_id,company_id,id),
 ADD CONSTRAINT crm_deals_delivery_classification_check CHECK(
 (company_id IS NOT NULL AND company_classification_event_id IS NOT NULL AND company_classification_status='resolved') OR
 (company_id IS NULL AND company_classification_event_id IS NULL AND company_classification_status IN('pending_classification','conflict')));
 CREATE INDEX crm_deals_delivery_company_idx ON public.crm_deals(tenant_id,company_id,id);
 CREATE INDEX crm_deals_delivery_evidence_fk_idx ON public.crm_deals(company_entity_table,tenant_id,id,company_id,company_classification_event_id);
 GRANT SELECT(id,tenant_id,company_id,company_classification_status) ON public.crm_deals TO rotero_delivery_scope_owner;
 CREATE POLICY crm_deals_delivery_metadata ON public.crm_deals FOR SELECT TO rotero_delivery_scope_owner USING(true);

ALTER TABLE public.inventory_lots
 ADD COLUMN company_id uuid,
 ADD COLUMN company_classification_event_id uuid,
 ADD COLUMN company_classification_status text NOT NULL DEFAULT 'pending_classification',
 ADD COLUMN company_entity_table text GENERATED ALWAYS AS ('inventory_lots'::text) STORED,
 ADD CONSTRAINT inventory_lots_delivery_company_fk FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id),
 ADD CONSTRAINT inventory_lots_delivery_classification_fk FOREIGN KEY(company_entity_table,tenant_id,id,company_id,company_classification_event_id)
 REFERENCES private.delivery_classification_events(entity_table,tenant_id,entity_id,company_id,id),
 ADD CONSTRAINT inventory_lots_delivery_classification_check CHECK(
 (company_id IS NOT NULL AND company_classification_event_id IS NOT NULL AND company_classification_status='resolved') OR
 (company_id IS NULL AND company_classification_event_id IS NULL AND company_classification_status IN('pending_classification','conflict')));
 CREATE INDEX inventory_lots_delivery_company_idx ON public.inventory_lots(tenant_id,company_id,id);
 CREATE INDEX inventory_lots_delivery_evidence_fk_idx ON public.inventory_lots(company_entity_table,tenant_id,id,company_id,company_classification_event_id);
 GRANT SELECT(id,tenant_id,company_id,company_classification_status) ON public.inventory_lots TO rotero_delivery_scope_owner;
 CREATE POLICY inventory_lots_delivery_metadata ON public.inventory_lots FOR SELECT TO rotero_delivery_scope_owner USING(true);

ALTER TABLE public.billing_cfdis
 ADD COLUMN company_id uuid,
 ADD COLUMN company_classification_event_id uuid,
 ADD COLUMN company_classification_status text NOT NULL DEFAULT 'pending_classification',
 ADD COLUMN company_entity_table text GENERATED ALWAYS AS ('billing_cfdis'::text) STORED,
 ADD CONSTRAINT billing_cfdis_delivery_company_fk FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id),
 ADD CONSTRAINT billing_cfdis_delivery_classification_fk FOREIGN KEY(company_entity_table,tenant_id,id,company_id,company_classification_event_id)
 REFERENCES private.delivery_classification_events(entity_table,tenant_id,entity_id,company_id,id),
 ADD CONSTRAINT billing_cfdis_delivery_classification_check CHECK(
 (company_id IS NOT NULL AND company_classification_event_id IS NOT NULL AND company_classification_status='resolved') OR
 (company_id IS NULL AND company_classification_event_id IS NULL AND company_classification_status IN('pending_classification','conflict')));
 CREATE INDEX billing_cfdis_delivery_company_idx ON public.billing_cfdis(tenant_id,company_id,id);
 CREATE INDEX billing_cfdis_delivery_evidence_fk_idx ON public.billing_cfdis(company_entity_table,tenant_id,id,company_id,company_classification_event_id);
 GRANT SELECT(id,tenant_id,company_id,company_classification_status) ON public.billing_cfdis TO rotero_delivery_scope_owner;
 CREATE POLICY billing_cfdis_delivery_metadata ON public.billing_cfdis FOR SELECT TO rotero_delivery_scope_owner USING(true);

ALTER TABLE public.document_files
 ADD COLUMN company_id uuid,
 ADD COLUMN company_classification_event_id uuid,
 ADD COLUMN company_classification_status text NOT NULL DEFAULT 'pending_classification',
 ADD COLUMN company_entity_table text GENERATED ALWAYS AS ('document_files'::text) STORED,
 ADD CONSTRAINT document_files_delivery_company_fk FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id),
 ADD CONSTRAINT document_files_delivery_classification_fk FOREIGN KEY(company_entity_table,tenant_id,id,company_id,company_classification_event_id)
 REFERENCES private.delivery_classification_events(entity_table,tenant_id,entity_id,company_id,id),
 ADD CONSTRAINT document_files_delivery_classification_check CHECK(
 (company_id IS NOT NULL AND company_classification_event_id IS NOT NULL AND company_classification_status='resolved') OR
 (company_id IS NULL AND company_classification_event_id IS NULL AND company_classification_status IN('pending_classification','conflict')));
 CREATE INDEX document_files_delivery_company_idx ON public.document_files(tenant_id,company_id,id);
 CREATE INDEX document_files_delivery_evidence_fk_idx ON public.document_files(company_entity_table,tenant_id,id,company_id,company_classification_event_id);
 GRANT SELECT(id,tenant_id,company_id,company_classification_status) ON public.document_files TO rotero_delivery_scope_owner;
 CREATE POLICY document_files_delivery_metadata ON public.document_files FOR SELECT TO rotero_delivery_scope_owner USING(true);

ALTER TABLE public.generated_documents
 ADD COLUMN company_id uuid,
 ADD COLUMN company_classification_event_id uuid,
 ADD COLUMN company_classification_status text NOT NULL DEFAULT 'pending_classification',
 ADD COLUMN company_entity_table text GENERATED ALWAYS AS ('generated_documents'::text) STORED,
 ADD CONSTRAINT generated_documents_delivery_company_fk FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id),
 ADD CONSTRAINT generated_documents_delivery_classification_fk FOREIGN KEY(company_entity_table,tenant_id,id,company_id,company_classification_event_id)
 REFERENCES private.delivery_classification_events(entity_table,tenant_id,entity_id,company_id,id),
 ADD CONSTRAINT generated_documents_delivery_classification_check CHECK(
 (company_id IS NOT NULL AND company_classification_event_id IS NOT NULL AND company_classification_status='resolved') OR
 (company_id IS NULL AND company_classification_event_id IS NULL AND company_classification_status IN('pending_classification','conflict')));
 CREATE INDEX generated_documents_delivery_company_idx ON public.generated_documents(tenant_id,company_id,id);
 CREATE INDEX generated_documents_delivery_evidence_fk_idx ON public.generated_documents(company_entity_table,tenant_id,id,company_id,company_classification_event_id);
 GRANT SELECT(id,tenant_id,company_id,company_classification_status) ON public.generated_documents TO rotero_delivery_scope_owner;
 CREATE POLICY generated_documents_delivery_metadata ON public.generated_documents FOR SELECT TO rotero_delivery_scope_owner USING(true);

ALTER TABLE public.internal_notifications
 ADD COLUMN company_id uuid,
 ADD COLUMN company_classification_event_id uuid,
 ADD COLUMN company_classification_status text NOT NULL DEFAULT 'pending_classification',
 ADD COLUMN company_entity_table text GENERATED ALWAYS AS ('internal_notifications'::text) STORED,
 ADD CONSTRAINT internal_notifications_delivery_company_fk FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id),
 ADD CONSTRAINT internal_notifications_delivery_classification_fk FOREIGN KEY(company_entity_table,tenant_id,id,company_id,company_classification_event_id)
 REFERENCES private.delivery_classification_events(entity_table,tenant_id,entity_id,company_id,id),
 ADD CONSTRAINT internal_notifications_delivery_classification_check CHECK(
 (company_id IS NOT NULL AND company_classification_event_id IS NOT NULL AND company_classification_status='resolved') OR
 (company_id IS NULL AND company_classification_event_id IS NULL AND company_classification_status IN('pending_classification','conflict')));
 CREATE INDEX internal_notifications_delivery_company_idx ON public.internal_notifications(tenant_id,company_id,id);
 CREATE INDEX internal_notifications_delivery_evidence_fk_idx ON public.internal_notifications(company_entity_table,tenant_id,id,company_id,company_classification_event_id);
 GRANT SELECT(id,tenant_id,company_id,company_classification_status) ON public.internal_notifications TO rotero_delivery_scope_owner;
 CREATE POLICY internal_notifications_delivery_metadata ON public.internal_notifications FOR SELECT TO rotero_delivery_scope_owner USING(true);

-- Preserve ambiguous history; enforce known-company relationships on new writes.
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

-- Metadata resolver never uses a display name, creator or default company.
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

CREATE TRIGGER billing_cfdis_delivery_parent BEFORE INSERT OR UPDATE ON public.billing_cfdis FOR EACH ROW EXECUTE FUNCTION private.delivery_assert_root_links();

CREATE TRIGGER document_files_delivery_parent BEFORE INSERT OR UPDATE ON public.document_files FOR EACH ROW EXECUTE FUNCTION private.delivery_assert_root_links();

CREATE TRIGGER generated_documents_delivery_parent BEFORE INSERT OR UPDATE ON public.generated_documents FOR EACH ROW EXECUTE FUNCTION private.delivery_assert_root_links();

CREATE FUNCTION private.delivery_evidence_target() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
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

CREATE TRIGGER crm_deals_retain_classification BEFORE DELETE ON public.crm_deals FOR EACH ROW EXECUTE FUNCTION private.delivery_retain_classified_root();

CREATE TRIGGER inventory_lots_retain_classification BEFORE DELETE ON public.inventory_lots FOR EACH ROW EXECUTE FUNCTION private.delivery_retain_classified_root();

CREATE TRIGGER billing_cfdis_retain_classification BEFORE DELETE ON public.billing_cfdis FOR EACH ROW EXECUTE FUNCTION private.delivery_retain_classified_root();

CREATE TRIGGER document_files_retain_classification BEFORE DELETE ON public.document_files FOR EACH ROW EXECUTE FUNCTION private.delivery_retain_classified_root();

CREATE TRIGGER generated_documents_retain_classification BEFORE DELETE ON public.generated_documents FOR EACH ROW EXECUTE FUNCTION private.delivery_retain_classified_root();

CREATE TRIGGER internal_notifications_retain_classification BEFORE DELETE ON public.internal_notifications FOR EACH ROW EXECUTE FUNCTION private.delivery_retain_classified_root();

CREATE CONSTRAINT TRIGGER operations_delivery_documents AFTER UPDATE ON public.operations DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION private.delivery_parent_documents_coherent();

CREATE CONSTRAINT TRIGGER finance_invoices_delivery_documents AFTER UPDATE ON public.finance_invoices DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION private.delivery_parent_documents_coherent();

CREATE CONSTRAINT TRIGGER billing_documents_delivery_documents AFTER UPDATE ON public.billing_documents DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION private.delivery_parent_documents_coherent();

CREATE CONSTRAINT TRIGGER billing_cfdis_delivery_documents AFTER UPDATE ON public.billing_cfdis DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION private.delivery_parent_documents_coherent();

CREATE CONSTRAINT TRIGGER crm_deals_delivery_documents AFTER UPDATE ON public.crm_deals DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION private.delivery_parent_documents_coherent();

GRANT CREATE ON SCHEMA private TO rotero_delivery_scope_owner;
ALTER FUNCTION private.delivery_assert_root_links() OWNER TO rotero_delivery_scope_owner;
ALTER FUNCTION private.delivery_evidence_target() OWNER TO rotero_delivery_scope_owner;
ALTER FUNCTION private.delivery_retain_classified_root() OWNER TO rotero_delivery_scope_owner;
ALTER FUNCTION private.delivery_parent_documents_coherent() OWNER TO rotero_delivery_scope_owner;
REVOKE CREATE ON SCHEMA private FROM rotero_delivery_scope_owner;
SET LOCAL ROLE rotero_delivery_scope_owner;
REVOKE ALL ON FUNCTION private.delivery_assert_root_links(),private.delivery_evidence_target(),private.delivery_retain_classified_root(),private.delivery_parent_documents_coherent() FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL ROLE postgres;

-- Ordinary roles cannot reclassify or create permissions through direct writes.
-- Restrictive policies also protect accidental future table grants.

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
 CREATE POLICY audit_log_delivery_api_boundary ON public.audit_log AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.automation_daily_digests ENABLE ROW LEVEL SECURITY;
 CREATE POLICY automation_daily_digests_delivery_api_boundary ON public.automation_daily_digests AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.automation_rules ENABLE ROW LEVEL SECURITY;
 CREATE POLICY automation_rules_delivery_api_boundary ON public.automation_rules AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.automation_runs ENABLE ROW LEVEL SECURITY;
 CREATE POLICY automation_runs_delivery_api_boundary ON public.automation_runs AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.billing_carta_porte ENABLE ROW LEVEL SECURITY;
 CREATE POLICY billing_carta_porte_delivery_api_boundary ON public.billing_carta_porte AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.billing_cfdis ENABLE ROW LEVEL SECURITY;
 CREATE POLICY billing_cfdis_delivery_api_boundary ON public.billing_cfdis AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.billing_credit_notes ENABLE ROW LEVEL SECURITY;
 CREATE POLICY billing_credit_notes_delivery_api_boundary ON public.billing_credit_notes AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.billing_documents ENABLE ROW LEVEL SECURITY;
 CREATE POLICY billing_documents_delivery_api_boundary ON public.billing_documents AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.billing_payment_complements ENABLE ROW LEVEL SECURITY;
 CREATE POLICY billing_payment_complements_delivery_api_boundary ON public.billing_payment_complements AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.business_contacts ENABLE ROW LEVEL SECURITY;
 CREATE POLICY business_contacts_delivery_api_boundary ON public.business_contacts AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.claim_service_policies ENABLE ROW LEVEL SECURITY;
 CREATE POLICY claim_service_policies_delivery_api_boundary ON public.claim_service_policies AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.commercial_lanes ENABLE ROW LEVEL SECURITY;
 CREATE POLICY commercial_lanes_delivery_api_boundary ON public.commercial_lanes AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.commercial_rate_cards ENABLE ROW LEVEL SECURITY;
 CREATE POLICY commercial_rate_cards_delivery_api_boundary ON public.commercial_rate_cards AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.commercial_rate_charges ENABLE ROW LEVEL SECURITY;
 CREATE POLICY commercial_rate_charges_delivery_api_boundary ON public.commercial_rate_charges AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.commercial_rate_versions ENABLE ROW LEVEL SECURITY;
 CREATE POLICY commercial_rate_versions_delivery_api_boundary ON public.commercial_rate_versions AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.crm_deal_activity ENABLE ROW LEVEL SECURITY;
 CREATE POLICY crm_deal_activity_delivery_api_boundary ON public.crm_deal_activity AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.crm_deal_checklist_items ENABLE ROW LEVEL SECURITY;
 CREATE POLICY crm_deal_checklist_items_delivery_api_boundary ON public.crm_deal_checklist_items AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.crm_deal_notes ENABLE ROW LEVEL SECURITY;
 CREATE POLICY crm_deal_notes_delivery_api_boundary ON public.crm_deal_notes AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.crm_deals ENABLE ROW LEVEL SECURITY;
 CREATE POLICY crm_deals_delivery_api_boundary ON public.crm_deals AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.crm_quote_rate_snapshots ENABLE ROW LEVEL SECURITY;
 CREATE POLICY crm_quote_rate_snapshots_delivery_api_boundary ON public.crm_quote_rate_snapshots AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
 CREATE POLICY customers_delivery_api_boundary ON public.customers AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.customs_descargo_lines ENABLE ROW LEVEL SECURITY;
 CREATE POLICY customs_descargo_lines_delivery_api_boundary ON public.customs_descargo_lines AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.customs_pedimentos ENABLE ROW LEVEL SECURITY;
 CREATE POLICY customs_pedimentos_delivery_api_boundary ON public.customs_pedimentos AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.data_import_batches ENABLE ROW LEVEL SECURITY;
 CREATE POLICY data_import_batches_delivery_api_boundary ON public.data_import_batches AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.data_import_chunks ENABLE ROW LEVEL SECURITY;
 CREATE POLICY data_import_chunks_delivery_api_boundary ON public.data_import_chunks AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.data_import_mappings ENABLE ROW LEVEL SECURITY;
 CREATE POLICY data_import_mappings_delivery_api_boundary ON public.data_import_mappings AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.document_files ENABLE ROW LEVEL SECURITY;
 CREATE POLICY document_files_delivery_api_boundary ON public.document_files AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.document_relations ENABLE ROW LEVEL SECURITY;
 CREATE POLICY document_relations_delivery_api_boundary ON public.document_relations AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.document_template_versions ENABLE ROW LEVEL SECURITY;
 CREATE POLICY document_template_versions_delivery_api_boundary ON public.document_template_versions AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.document_templates ENABLE ROW LEVEL SECURITY;
 CREATE POLICY document_templates_delivery_api_boundary ON public.document_templates AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;
 CREATE POLICY drivers_delivery_api_boundary ON public.drivers AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.finance_invoices ENABLE ROW LEVEL SECURITY;
 CREATE POLICY finance_invoices_delivery_api_boundary ON public.finance_invoices AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.finance_payments ENABLE ROW LEVEL SECURITY;
 CREATE POLICY finance_payments_delivery_api_boundary ON public.finance_payments AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.fiscal_provider_attempts ENABLE ROW LEVEL SECURITY;
 CREATE POLICY fiscal_provider_attempts_delivery_api_boundary ON public.fiscal_provider_attempts AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.fiscal_provider_configs ENABLE ROW LEVEL SECURITY;
 CREATE POLICY fiscal_provider_configs_delivery_api_boundary ON public.fiscal_provider_configs AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.fiscal_requests ENABLE ROW LEVEL SECURITY;
 CREATE POLICY fiscal_requests_delivery_api_boundary ON public.fiscal_requests AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.generated_documents ENABLE ROW LEVEL SECURITY;
 CREATE POLICY generated_documents_delivery_api_boundary ON public.generated_documents AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.internal_notification_rules ENABLE ROW LEVEL SECURITY;
 CREATE POLICY internal_notification_rules_delivery_api_boundary ON public.internal_notification_rules AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.internal_notifications ENABLE ROW LEVEL SECURITY;
 CREATE POLICY internal_notifications_delivery_api_boundary ON public.internal_notifications AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.inventory_lots ENABLE ROW LEVEL SECURITY;
 CREATE POLICY inventory_lots_delivery_api_boundary ON public.inventory_lots AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;
 CREATE POLICY invitations_delivery_api_boundary ON public.invitations AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.logistics_providers ENABLE ROW LEVEL SECURITY;
 CREATE POLICY logistics_providers_delivery_api_boundary ON public.logistics_providers AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.operation_assignment_history ENABLE ROW LEVEL SECURITY;
 CREATE POLICY operation_assignment_history_delivery_api_boundary ON public.operation_assignment_history AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.operation_billing ENABLE ROW LEVEL SECURITY;
 CREATE POLICY operation_billing_delivery_api_boundary ON public.operation_billing AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.operation_crossings ENABLE ROW LEVEL SECURITY;
 CREATE POLICY operation_crossings_delivery_api_boundary ON public.operation_crossings AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.operation_documents ENABLE ROW LEVEL SECURITY;
 CREATE POLICY operation_documents_delivery_api_boundary ON public.operation_documents AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.operation_evidence ENABLE ROW LEVEL SECURITY;
 CREATE POLICY operation_evidence_delivery_api_boundary ON public.operation_evidence AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.operation_incidents ENABLE ROW LEVEL SECURITY;
 CREATE POLICY operation_incidents_delivery_api_boundary ON public.operation_incidents AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.operations ENABLE ROW LEVEL SECURITY;
 CREATE POLICY operations_delivery_api_boundary ON public.operations AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.partner_compliance_records ENABLE ROW LEVEL SECURITY;
 CREATE POLICY partner_compliance_records_delivery_api_boundary ON public.partner_compliance_records AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.partner_compliance_requirements ENABLE ROW LEVEL SECURITY;
 CREATE POLICY partner_compliance_requirements_delivery_api_boundary ON public.partner_compliance_requirements AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.partner_contracts ENABLE ROW LEVEL SECURITY;
 CREATE POLICY partner_contracts_delivery_api_boundary ON public.partner_contracts AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.provider_compliance_overrides ENABLE ROW LEVEL SECURITY;
 CREATE POLICY provider_compliance_overrides_delivery_api_boundary ON public.provider_compliance_overrides AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.service_catalog_items ENABLE ROW LEVEL SECURITY;
 CREATE POLICY service_catalog_items_delivery_api_boundary ON public.service_catalog_items AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.service_claim_actions ENABLE ROW LEVEL SECURITY;
 CREATE POLICY service_claim_actions_delivery_api_boundary ON public.service_claim_actions AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.service_claim_contacts ENABLE ROW LEVEL SECURITY;
 CREATE POLICY service_claim_contacts_delivery_api_boundary ON public.service_claim_contacts AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.service_claim_events ENABLE ROW LEVEL SECURITY;
 CREATE POLICY service_claim_events_delivery_api_boundary ON public.service_claim_events AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.service_claim_financials ENABLE ROW LEVEL SECURITY;
 CREATE POLICY service_claim_financials_delivery_api_boundary ON public.service_claim_financials AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.service_claims ENABLE ROW LEVEL SECURITY;
 CREATE POLICY service_claims_delivery_api_boundary ON public.service_claims AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.tenant_settings ENABLE ROW LEVEL SECURITY;
 CREATE POLICY tenant_settings_delivery_api_boundary ON public.tenant_settings AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.tenant_setup_status ENABLE ROW LEVEL SECURITY;
 CREATE POLICY tenant_setup_status_delivery_api_boundary ON public.tenant_setup_status AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.tracking_events ENABLE ROW LEVEL SECURITY;
 CREATE POLICY tracking_events_delivery_api_boundary ON public.tracking_events AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.tracking_route_points ENABLE ROW LEVEL SECURITY;
 CREATE POLICY tracking_route_points_delivery_api_boundary ON public.tracking_route_points AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.tracking_tokens ENABLE ROW LEVEL SECURITY;
 CREATE POLICY tracking_tokens_delivery_api_boundary ON public.tracking_tokens AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.user_saved_views ENABLE ROW LEVEL SECURITY;
 CREATE POLICY user_saved_views_delivery_api_boundary ON public.user_saved_views AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
 CREATE POLICY vehicles_delivery_api_boundary ON public.vehicles AS RESTRICTIVE FOR ALL TO anon,authenticated
 USING(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL))
 WITH CHECK(NOT private.delivery_required(tenant_id) AND NOT private.delivery_required(NULL));

SET LOCAL ROLE rotero_delivery_scope_owner;
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

CREATE VIEW private.delivery_operations WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."reference_code",t."route_summary",t."client_display_name",t."destination_city",t."eta_display",t."status",t."origin_place",t."destination_place",t."eta",t."driver_id",t."vehicle_id",t."planned_departure",t."priority",t."required_documents",t."driver_name",t."vehicle_ref",t."assigned_at",t."closed_at",t."cancelled_at",t."service_type",t."operational_window_start",t."operational_window_end",t."notes",t."cargo_summary",t."source_deal_id",t."customer_id",t."operation_scope",t."execution_type",t."provider_id",t."provider_name",t."external_driver",t."external_vehicle",t."provider_cost_amount",t."customer_price_amount",t."pricing_currency",t."service_catalog_item_id",t."service_catalog_snapshot",t."boxes_placed_days",t."documentation_received_at",t."documentation_received_note",t."created_at",t."updated_at",t."external_key",t."company_id",t."company_classification_status",t."company_classification_event_id" FROM public.operations t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_scope_allowed(t.tenant_id) AND (private.delivery_entity_allowed(t.tenant_id,'operation',t.id) AND (private.delivery_cap(t.tenant_id,'operations.read') OR private.delivery_cap(t.tenant_id,'financial.full.read'))) ELSE true END;
 REVOKE ALL ON private.delivery_operations FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_crm_deals WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."customer_id",t."title",t."company",t."contact_name",t."contact_email",t."contact_phone",t."value",t."currency",t."stage",t."priority",t."owner_user_id",t."notes",t."last_touch_at",t."quote_status",t."quote_reference",t."quote_payload",t."approved_at",t."approved_by",t."approval_note",t."rejected_at",t."rejected_by",t."rejection_note",t."converted_operation_id",t."converted_at",t."converted_by",t."conversion_note",t."created_at",t."updated_at",t."company_id",t."company_classification_event_id",t."company_classification_status",t."company_entity_table" FROM public.crm_deals t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_scope_allowed(t.tenant_id) AND (t.company_classification_status='resolved' AND t.company_id=ANY(private.delivery_company_ids()) AND (private.delivery_cap(t.tenant_id,'financial.full.read') OR private.delivery_cap(t.tenant_id,'pipeline.read'))) ELSE true END;
 REVOKE ALL ON private.delivery_crm_deals FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_inventory_lots WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."sku",t."description",t."warehouse",t."lot_code",t."qty_on_hand",t."qty_reserved",t."unit_cost",t."currency",t."unit",t."status",t."received_at",t."pedimento_ref",t."created_at",t."updated_at",t."company_id",t."company_classification_event_id",t."company_classification_status",t."company_entity_table" FROM public.inventory_lots t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_scope_allowed(t.tenant_id) AND (t.company_classification_status='resolved' AND t.company_id=ANY(private.delivery_company_ids()) AND (private.delivery_cap(t.tenant_id,'financial.full.read') OR private.delivery_cap(t.tenant_id,'inventory.read'))) ELSE true END;
 REVOKE ALL ON private.delivery_inventory_lots FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_billing_cfdis WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."operation_id",t."uuid",t."serie",t."folio",t."status",t."currency",t."subtotal",t."total",t."rfc_emisor",t."rfc_receptor",t."receptor_name",t."has_carta_porte",t."has_complemento_pago",t."issued_at",t."cancelled_at",t."pac_provider",t."notes",t."exchange_rate",t."exchange_rate_date",t."subtotal_mxn",t."iva_mxn",t."total_mxn",t."created_at",t."updated_at",t."fiscal_status",t."fiscal_provider",t."provider_document_id",t."fiscal_requested_at",t."fiscal_stamped_at",t."fiscal_cancelled_at",t."fiscal_last_checked_at",t."fiscal_error_code",t."fiscal_error_message_safe",t."xml_document_file_id",t."pdf_document_file_id",t."request_fingerprint",t."provider_version",t."cfdi_version",t."fiscal_input",t."fiscal_snapshot",t."fiscal_snapshot_created_at",t."fiscal_environment",t."fiscal_credential_profile",t."company_id",t."company_classification_event_id",t."company_classification_status",t."company_entity_table" FROM public.billing_cfdis t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_scope_allowed(t.tenant_id) AND (t.company_classification_status='resolved' AND t.company_id=ANY(private.delivery_company_ids()) AND private.delivery_cap(t.tenant_id,'financial.full.read') AND NOT private.fiscal02_is_lab_entity('cfdi',t.id)) ELSE true END;
 REVOKE ALL ON private.delivery_billing_cfdis FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_finance_invoices WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."customer_id",t."provider_id",t."operation_id",t."linked_cfdi_id",t."billing_document_id",t."payroll_period_id",t."direction",t."counterparty_name",t."reference",t."amount",t."currency",t."status",t."due_date",t."paid_at",t."received_at",t."notes",t."exchange_rate",t."exchange_rate_date",t."amount_mxn",t."created_at",t."updated_at",t."exchange_rate_source",t."voided_at",t."voided_by",t."void_reason",t."over_registration_override",t."over_registration_reason",t."created_by",t."company_id",t."company_classification_status",t."company_classification_event_id" FROM public.finance_invoices t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_scope_allowed(t.tenant_id) AND (private.delivery_entity_allowed(t.tenant_id,'invoice',t.id) AND private.delivery_cap(t.tenant_id,'financial.full.read') AND t.payroll_period_id IS NULL AND NOT private.fiscal02_is_lab_entity('invoice',t.id)) ELSE true END;
 REVOKE ALL ON private.delivery_finance_invoices FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_finance_payments WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."invoice_id",t."amount",t."paid_at",t."method",t."note",t."bank_reference",t."currency",t."exchange_rate",t."exchange_rate_date",t."amount_mxn",t."created_by",t."created_at",t."exchange_rate_source" FROM public.finance_payments t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_scope_allowed(t.tenant_id) AND (private.delivery_entity_allowed(t.tenant_id,'payment',t.id) AND private.delivery_cap(t.tenant_id,'financial.full.read') AND NOT private.fiscal02_is_lab_entity('payment',t.id)) ELSE true END;
 REVOKE ALL ON private.delivery_finance_payments FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_billing_documents WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."operation_id",t."customer_id",t."provider_id",t."linked_cfdi_id",t."document_direction",t."document_type",t."status",t."serie",t."folio",t."fiscal_uuid",t."currency",t."exchange_rate",t."exchange_rate_date",t."subtotal",t."total",t."total_mxn",t."notes",t."created_by",t."created_at",t."updated_at",t."company_id",t."company_classification_status",t."company_classification_event_id" FROM public.billing_documents t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_scope_allowed(t.tenant_id) AND (private.delivery_entity_allowed(t.tenant_id,'document',t.id) AND private.delivery_cap(t.tenant_id,'financial.full.read') AND NOT private.fiscal02_is_lab_entity('document',t.id)) ELSE true END;
 REVOKE ALL ON private.delivery_billing_documents FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_billing_credit_notes WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."note_type",t."customer_id",t."provider_id",t."operation_id",t."finance_invoice_id",t."cfdi_id",t."source_billing_document_id",t."credit_billing_document_id",t."folio",t."provider_note_reference",t."issue_date",t."received_at",t."reason",t."subtotal",t."iva",t."total",t."currency",t."exchange_rate",t."exchange_rate_date",t."total_mxn",t."status",t."notes",t."created_by",t."created_at",t."updated_at",t."company_id",t."company_classification_status",t."company_classification_event_id" FROM public.billing_credit_notes t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_scope_allowed(t.tenant_id) AND (private.delivery_entity_allowed(t.tenant_id,'credit',t.id) AND private.delivery_cap(t.tenant_id,'financial.full.read') AND NOT private.fiscal02_is_lab_entity('credit',t.id)) ELSE true END;
 REVOKE ALL ON private.delivery_billing_credit_notes FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_billing_payment_complements WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."finance_invoice_id",t."finance_payment_id",t."cfdi_id",t."invoice_billing_document_id",t."complement_billing_document_id",t."payment_date",t."method",t."bank_reference",t."currency",t."amount",t."exchange_rate",t."exchange_rate_date",t."amount_mxn",t."status",t."notes",t."created_by",t."created_at",t."updated_at" FROM public.billing_payment_complements t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_scope_allowed(t.tenant_id) AND (private.delivery_entity_allowed(t.tenant_id,'complement',t.id) AND private.delivery_cap(t.tenant_id,'financial.full.read') AND NOT private.fiscal02_is_lab_entity('complement',t.id)) ELSE true END;
 REVOKE ALL ON private.delivery_billing_payment_complements FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_operation_assignment_history WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."operation_id",t."change_type",t."old_driver_id",t."old_driver_name_snapshot",t."old_vehicle_id",t."old_vehicle_ref_snapshot",t."new_driver_id",t."new_driver_name_snapshot",t."new_vehicle_id",t."new_vehicle_ref_snapshot",t."reason",t."changed_by",t."changed_at",t."old_execution_type",t."new_execution_type",t."old_provider_id",t."new_provider_id",t."old_provider_name_snapshot",t."new_provider_name_snapshot",t."old_external_driver_snapshot",t."new_external_driver_snapshot",t."old_external_vehicle_snapshot",t."new_external_vehicle_snapshot" FROM public.operation_assignment_history t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_entity_allowed(t.tenant_id,'operation',t.operation_id) AND private.delivery_cap(t.tenant_id,'operations.read') ELSE true END;
 REVOKE ALL ON private.delivery_operation_assignment_history FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_operation_incidents WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."operation_id",t."tracking_event_id",t."category",t."title",t."description",t."status",t."is_blocking",t."reported_by",t."reported_at",t."resolved_by",t."resolved_at",t."resolution_note",t."dismissed_by",t."dismissed_at",t."dismiss_note",t."created_at",t."updated_at" FROM public.operation_incidents t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_entity_allowed(t.tenant_id,'operation',t.operation_id) AND private.delivery_cap(t.tenant_id,'operations.read') ELSE true END;
 REVOKE ALL ON private.delivery_operation_incidents FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_operation_evidence WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."operation_id",t."incident_id",t."kind",t."note",t."file_ref",t."external_url",t."created_by",t."created_at" FROM public.operation_evidence t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_entity_allowed(t.tenant_id,'operation',t.operation_id) AND private.delivery_cap(t.tenant_id,'operations.read') ELSE true END;
 REVOKE ALL ON private.delivery_operation_evidence FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_operation_documents WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."operation_id",t."document_type",t."requirement_level",t."status",t."document_reference",t."file_ref",t."external_url",t."note",t."updated_by",t."created_at",t."updated_at" FROM public.operation_documents t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_entity_allowed(t.tenant_id,'operation',t.operation_id) AND private.delivery_cap(t.tenant_id,'operations.read') ELSE true END;
 REVOKE ALL ON private.delivery_operation_documents FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_operation_crossings WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."operation_id",t."crossed_at",t."crossing_point",t."crossing_type",t."note",t."created_by",t."created_at",t."updated_at" FROM public.operation_crossings t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_entity_allowed(t.tenant_id,'operation',t.operation_id) AND private.delivery_cap(t.tenant_id,'operations.read') ELSE true END;
 REVOKE ALL ON private.delivery_operation_crossings FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_operation_billing WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."operation_id",t."status",t."billing_reference",t."issued_at",t."issued_by",t."linked_cfdi_id",t."notes",t."admin_closed_at",t."admin_closed_by",t."admin_close_override",t."voided_at",t."voided_by",t."void_reason",t."created_at",t."updated_at",t."admin_close_note" FROM public.operation_billing t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_entity_allowed(t.tenant_id,'operation',t.operation_id) AND private.delivery_cap(t.tenant_id,'operations.read') ELSE true END;
 REVOKE ALL ON private.delivery_operation_billing FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_tracking_events WITH(security_barrier=true) AS SELECT t."id",t."token_id",t."tenant_id",t."operation_id",t."event_type",t."source",t."client_timestamp",t."server_timestamp",t."lat",t."lng",t."accuracy_m",t."municipality",t."state_name",t."country_code",t."incident_type",t."incident_note",t."is_suspicious",t."offline_queued" FROM public.tracking_events t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_entity_allowed(t.tenant_id,'operation',t.operation_id) AND private.delivery_cap(t.tenant_id,'operations.read') ELSE true END;
 REVOKE ALL ON private.delivery_tracking_events FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_tracking_route_points WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."operation_id",t."token_id",t."lat",t."lng",t."accuracy_m",t."recorded_at",t."source" FROM public.tracking_route_points t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN private.delivery_entity_allowed(t.tenant_id,'operation',t.operation_id) AND private.delivery_cap(t.tenant_id,'operations.read') ELSE true END;
 REVOKE ALL ON private.delivery_tracking_route_points FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW private.delivery_billing_carta_porte WITH(security_barrier=true) AS SELECT t."id",t."tenant_id",t."cfdi_id",t."trans_type",t."vehicle_plate",t."carrier_name",t."origin",t."destination",t."goods_desc",t."created_at",t."updated_at" FROM public.billing_carta_porte t
 WHERE CASE WHEN private.delivery_required(t.tenant_id) OR private.delivery_required(NULL) THEN
 EXISTS(SELECT FROM private.delivery_billing_cfdis c WHERE c.id=t.cfdi_id AND c.tenant_id=t.tenant_id) ELSE true END;
 REVOKE ALL ON private.delivery_billing_carta_porte FROM PUBLIC,anon,authenticated,service_role;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_tracking_token' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid, p_scope text, p_ttl_hours integer' AND md5(p.prosrc)=ANY(ARRAY['5cfcf30dc81c4fd35ecd381f9187f345','25c6084284e616bd971b81251ff65ed4']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_tracking_token'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_tracking_token(','FUNCTION private.delivery_core_c686f73d103e17ae6a10(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_tracking_token' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid, p_scope text, p_ttl_hours integer';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_c686f73d103e17ae6a10(uuid, uuid, text, integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_tracking_token(p_tenant_id uuid, p_operation_id uuid, p_scope text, p_ttl_hours integer) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_c686f73d103e17ae6a10(p_tenant_id,p_operation_id,p_scope,p_ttl_hours);
  RETURN result;
 END IF;
 RETURN private.delivery_core_c686f73d103e17ae6a10(p_tenant_id,p_operation_id,p_scope,p_ttl_hours);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_tracking_token' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid, p_scope text, p_force_rotate boolean' AND md5(p.prosrc)=ANY(ARRAY['09870d05073d2c11e6b219a6ef0ec2af','ea9865a0168ff284e752bbf3fafd4822']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_tracking_token'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_tracking_token(','FUNCTION private.delivery_core_eb244e2ffbe9fee122b0(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_tracking_token' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid, p_scope text, p_force_rotate boolean';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_eb244e2ffbe9fee122b0(uuid, uuid, text, boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_tracking_token(p_tenant_id uuid, p_operation_id uuid, p_scope text, p_force_rotate boolean) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_eb244e2ffbe9fee122b0(p_tenant_id,p_operation_id,p_scope,p_force_rotate);
  RETURN result;
 END IF;
 RETURN private.delivery_core_eb244e2ffbe9fee122b0(p_tenant_id,p_operation_id,p_scope,p_force_rotate);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_finance_invoice' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['b7c1cd09c07b51b912ca53dbc1ab24e8','32a193664b1c91398d00b00615aebace']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_finance_invoice'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_create_finance_invoice(uuid, jsonb)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_b185f90b91c4a51b95e5(','FUNCTION private.delivery_core_591ee1fa87134e99bff2(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_finance_invoice(','FUNCTION private.delivery_core_591ee1fa87134e99bff2(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_create_finance_invoice' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_591ee1fa87134e99bff2(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_finance_invoice(','FUNCTION private.delivery_scoped_591ee1fa87134e99bff2('),'private.multi08_legacy_write_target','private.delivery_finance_write_target') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_finance_invoice' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_591ee1fa87134e99bff2(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_finance_invoice(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT private.delivery_cap(v_tenant,'finance.write') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_591ee1fa87134e99bff2(p_tenant_id,p_payload);
  IF result->>'error' IS NULL AND result->>'id' IS NOT NULL THEN PERFORM private.delivery_classify_new_invoice(v_tenant,(result->>'id')::uuid); END IF; RETURN result;
 END IF;
 RETURN private.delivery_core_591ee1fa87134e99bff2(p_tenant_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_operation' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['99df64027e59c04364985277795dc842','7f70581207944309fd66cb7de966331c']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_operation'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_get_operation(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_b571e0e8bae75d2b9fb1(','FUNCTION private.delivery_core_bffcf9e45a07c7cb06dc(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation(','FUNCTION private.delivery_core_bffcf9e45a07c7cb06dc(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_get_operation' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_bffcf9e45a07c7cb06dc(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation(','FUNCTION private.delivery_scoped_bffcf9e45a07c7cb06dc('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis'),'SELECT o.* INTO v_operation
    FROM private.delivery_operations AS o','SELECT (pg_catalog.jsonb_populate_record(NULL::public.operations,pg_catalog.to_jsonb(o))).* INTO v_operation FROM private.delivery_operations AS o') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_operation' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_bffcf9e45a07c7cb06dc(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_operation(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN
  SELECT tenant_id INTO v_tenant FROM public.operations WHERE id=p_operation_id;
  IF NOT private.delivery_entity_allowed(v_tenant,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_bffcf9e45a07c7cb06dc(p_operation_id);
  RETURN private.delivery_operation_dto(result) || CASE WHEN private.delivery_cap(v_tenant,'financial.full.read') THEN private.delivery_pick_dto(result,ARRAY['provider_cost_amount','customer_price_amount','pricing_currency']) ELSE '{}'::jsonb END;
 END IF;
 RETURN private.delivery_core_bffcf9e45a07c7cb06dc(p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_import_mappings' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text' AND md5(p.prosrc)=ANY(ARRAY['21cd20a520da00cce7256b8d438c8300','336ac27ad854a828c85b222d344a4946']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_import_mappings'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_import_mappings(','FUNCTION private.delivery_core_21f90d75d3af636bdb90(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_import_mappings' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_21f90d75d3af636bdb90(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_import_mappings(p_tenant_id uuid, p_entity_type text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_21f90d75d3af636bdb90(p_tenant_id,p_entity_type);
  RETURN result;
 END IF;
 RETURN private.delivery_core_21f90d75d3af636bdb90(p_tenant_id,p_entity_type);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_save_import_mapping' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['1813df41b52fe99669615338c33c2a25','796fed257b1371585ff52f605dfa9b66']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_save_import_mapping'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_save_import_mapping(','FUNCTION private.delivery_core_388904c3404e8728d046(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_save_import_mapping' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_388904c3404e8728d046(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_save_import_mapping(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_388904c3404e8728d046(p_tenant_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_388904c3404e8728d046(p_tenant_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_delete_import_mapping' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_mapping_id uuid' AND md5(p.prosrc)=ANY(ARRAY['71d01f20b4b3fb1fb05b24f7834d978e','304f7883346aaa9ca05728fb6e7b5978']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_delete_import_mapping'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_delete_import_mapping(','FUNCTION private.delivery_core_a930ad8257b194334369(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_delete_import_mapping' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_mapping_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_a930ad8257b194334369(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_delete_import_mapping(p_tenant_id uuid, p_mapping_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_a930ad8257b194334369(p_tenant_id,p_mapping_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_a930ad8257b194334369(p_tenant_id,p_mapping_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_bulk_update_operations' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_ids uuid[], p_action text, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['664b054486dbbfdf336e25a68ef7a2c5','aa5e26694e3e50c511d5c34948576907']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_bulk_update_operations'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_bulk_update_operations(','FUNCTION private.delivery_core_bf2ed1807a3bc43e45bd(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_bulk_update_operations' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_ids uuid[], p_action text, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_bf2ed1807a3bc43e45bd(uuid, uuid[], text, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_bulk_update_operations(p_tenant_id uuid, p_operation_ids uuid[], p_action text, p_payload jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_bf2ed1807a3bc43e45bd(p_tenant_id,p_operation_ids,p_action,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_bf2ed1807a3bc43e45bd(p_tenant_id,p_operation_ids,p_action,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_record_data_action' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_action text, p_entity_type text, p_count integer, p_detail text' AND md5(p.prosrc)=ANY(ARRAY['8c3be5d297bbce3f918083e503accd65','e00f864581f1d7082bfaf562ba7760fd']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_record_data_action'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_record_data_action(','FUNCTION private.delivery_core_06393d99ac1c649c6eed(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_record_data_action' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_action text, p_entity_type text, p_count integer, p_detail text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_06393d99ac1c649c6eed(uuid, text, text, integer, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_record_data_action(p_tenant_id uuid, p_action text, p_entity_type text, p_count integer, p_detail text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_06393d99ac1c649c6eed(p_tenant_id,p_action,p_entity_type,p_count,p_detail);
  RETURN result;
 END IF;
 RETURN private.delivery_core_06393d99ac1c649c6eed(p_tenant_id,p_action,p_entity_type,p_count,p_detail);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_export_data_page' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text, p_filters jsonb, p_cursor jsonb, p_limit integer' AND md5(p.prosrc)=ANY(ARRAY['335081d2983946f29c447a6e030d75a5','f241441097c754512881102d6d679906']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_export_data_page'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_export_data_page(','FUNCTION private.delivery_core_2cafd17bc241847e84e9(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_export_data_page' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text, p_filters jsonb, p_cursor jsonb, p_limit integer';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_2cafd17bc241847e84e9(uuid, text, jsonb, jsonb, integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_export_data_page(p_tenant_id uuid, p_entity_type text, p_filters jsonb DEFAULT '{}'::jsonb, p_cursor jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 500) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_2cafd17bc241847e84e9(p_tenant_id,p_entity_type,p_filters,p_cursor,p_limit);
  RETURN result;
 END IF;
 RETURN private.delivery_core_2cafd17bc241847e84e9(p_tenant_id,p_entity_type,p_filters,p_cursor,p_limit);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_service_claim_from_incident' AND pg_get_function_identity_arguments(p.oid)='p_incident_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['17824d62b7a79d41bf1f0c3f0d0e7469','1b27fa98f96073a760ecd9323c3ee60d']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_service_claim_from_incident'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_service_claim_from_incident(','FUNCTION private.delivery_core_3b76a0c50eeaab9b7b2d(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_service_claim_from_incident' AND pg_get_function_identity_arguments(p.oid)='p_incident_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_3b76a0c50eeaab9b7b2d(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_service_claim_from_incident(p_incident_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_3b76a0c50eeaab9b7b2d(p_incident_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_3b76a0c50eeaab9b7b2d(p_incident_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_members' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['aac7007c03a7c5bfb9c33b9150414de9','d0eedc32df7886606ee5c3ddf0959540']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_members'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_members(','FUNCTION private.delivery_core_fea61683eb1a1f5878de(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_members' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_fea61683eb1a1f5878de(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_members(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_fea61683eb1a1f5878de(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_fea61683eb1a1f5878de(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_operations' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['f0c862896c3576a7322d23d23ffce069','a9f121de8d799a183bfc5e4a86fe2a56']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_operations'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_operations(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_06c91f3c6cd8070eb6d8(','FUNCTION private.delivery_core_5ba7208896f9c51a9904(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_operations(','FUNCTION private.delivery_core_5ba7208896f9c51a9904(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_operations' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_5ba7208896f9c51a9904(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_operations(','FUNCTION private.delivery_scoped_5ba7208896f9c51a9904('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_operations' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_5ba7208896f9c51a9904(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_operations(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_5ba7208896f9c51a9904(p_tenant_id);
  RETURN private.delivery_operation_dto(result);
 END IF;
 RETURN private.delivery_core_5ba7208896f9c51a9904(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_reports_operations_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['d5e3a144491c72431da6d6b2cc7661c4','86d27d74d4e2443ff0766d3043e246ce']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_reports_operations_summary'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_reports_operations_summary(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_45af1da82f1f6522fe60(','FUNCTION private.delivery_core_ce5ababc5dcb5a219fcc(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_reports_operations_summary(','FUNCTION private.delivery_core_ce5ababc5dcb5a219fcc(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_reports_operations_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_ce5ababc5dcb5a219fcc(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_reports_operations_summary(','FUNCTION private.delivery_scoped_ce5ababc5dcb5a219fcc('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_reports_operations_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_ce5ababc5dcb5a219fcc(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_reports_operations_summary(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_ce5ababc5dcb5a219fcc(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_ce5ababc5dcb5a219fcc(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_assign_operation' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid, p_driver_id uuid, p_vehicle_id uuid, p_planned_departure timestamp with time zone, p_priority text' AND md5(p.prosrc)=ANY(ARRAY['25d629dd0595b6edd706a64525b04153','4c347216dfc32fbbe668ebdaac92120d']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_assign_operation'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_assign_operation(','FUNCTION private.delivery_core_adfe8acda606eb5a3465(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_assign_operation' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid, p_driver_id uuid, p_vehicle_id uuid, p_planned_departure timestamp with time zone, p_priority text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_adfe8acda606eb5a3465(uuid, uuid, uuid, uuid, timestamp with time zone, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_assign_operation(p_tenant_id uuid, p_operation_id uuid, p_driver_id uuid, p_vehicle_id uuid, p_planned_departure timestamp with time zone, p_priority text DEFAULT 'normal'::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_adfe8acda606eb5a3465(p_tenant_id,p_operation_id,p_driver_id,p_vehicle_id,p_planned_departure,p_priority);
  RETURN result;
 END IF;
 RETURN private.delivery_core_adfe8acda606eb5a3465(p_tenant_id,p_operation_id,p_driver_id,p_vehicle_id,p_planned_departure,p_priority);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_assign_operation_v2' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid, p_driver_id uuid, p_driver_name text, p_vehicle_id uuid, p_vehicle_ref text, p_planned_departure timestamp with time zone, p_priority text' AND md5(p.prosrc)=ANY(ARRAY['feaed63fca22874f0c4cd86b6f078c98','32d9d1b62db767eaaa9ec4bd6dd83d19']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_assign_operation_v2'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_assign_operation_v2(','FUNCTION private.delivery_core_c687c926f92063b08af4(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_assign_operation_v2' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid, p_driver_id uuid, p_driver_name text, p_vehicle_id uuid, p_vehicle_ref text, p_planned_departure timestamp with time zone, p_priority text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_c687c926f92063b08af4(uuid, uuid, uuid, text, uuid, text, timestamp with time zone, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_assign_operation_v2(p_tenant_id uuid, p_operation_id uuid, p_driver_id uuid, p_driver_name text, p_vehicle_id uuid, p_vehicle_ref text, p_planned_departure timestamp with time zone, p_priority text DEFAULT 'normal'::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_c687c926f92063b08af4(p_tenant_id,p_operation_id,p_driver_id,p_driver_name,p_vehicle_id,p_vehicle_ref,p_planned_departure,p_priority);
  RETURN result;
 END IF;
 RETURN private.delivery_core_c687c926f92063b08af4(p_tenant_id,p_operation_id,p_driver_id,p_driver_name,p_vehicle_id,p_vehicle_ref,p_planned_departure,p_priority);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_dashboard_recent_activity' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone' AND md5(p.prosrc)=ANY(ARRAY['a111e9e28f9e3fb3a842d22ff5420c70','228347872ccea254ecdbd97022a9c750']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_dashboard_recent_activity'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_dashboard_recent_activity(uuid, timestamp with time zone, timestamp with time zone)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_67e0f2a8d03084ee90f2(','FUNCTION private.delivery_core_c00ce58bb2d674fc0a7a(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_dashboard_recent_activity(','FUNCTION private.delivery_core_c00ce58bb2d674fc0a7a(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_dashboard_recent_activity' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_c00ce58bb2d674fc0a7a(uuid, timestamp with time zone, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_dashboard_recent_activity(','FUNCTION private.delivery_scoped_c00ce58bb2d674fc0a7a('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_dashboard_recent_activity' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_c00ce58bb2d674fc0a7a(uuid, timestamp with time zone, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_dashboard_recent_activity(p_tenant_id uuid, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_c00ce58bb2d674fc0a7a(p_tenant_id,p_start_date,p_end_date);
  RETURN result;
 END IF;
 RETURN private.delivery_core_c00ce58bb2d674fc0a7a(p_tenant_id,p_start_date,p_end_date);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_reports_financial_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_period text' AND md5(p.prosrc)=ANY(ARRAY['bf99dfb445b1bea862f5b7767581353e','1d003139c41cf38d52edcb2349c6eb9e']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_reports_financial_summary'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_reports_financial_summary(uuid, text)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_d3b2ab28d0a1f450579b(','FUNCTION private.delivery_core_96d8d933072a56e35c9c(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_reports_financial_summary(','FUNCTION private.delivery_core_96d8d933072a56e35c9c(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_reports_financial_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_period text';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_96d8d933072a56e35c9c(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_reports_financial_summary(','FUNCTION private.delivery_scoped_96d8d933072a56e35c9c('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_reports_financial_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_period text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_96d8d933072a56e35c9c(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_reports_financial_summary(p_tenant_id uuid, p_period text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_96d8d933072a56e35c9c(p_tenant_id,p_period);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_96d8d933072a56e35c9c(p_tenant_id,p_period);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_deal' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['6d60fd17d5fd874e4932caaebc0b1648','22a23288050ec90e7cac491824d3f022']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_deal'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_deal(','FUNCTION private.delivery_core_e10e1bdd49f169636dc8(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_deal' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_e10e1bdd49f169636dc8(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_deal(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_e10e1bdd49f169636dc8(p_tenant_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_e10e1bdd49f169636dc8(p_tenant_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_deal' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_patch jsonb' AND md5(p.prosrc)=ANY(ARRAY['649736cc9857e2b9574c994c32c77c5f','e19abb2b022b70cf5d24be2db0f496e2']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_deal'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_deal(','FUNCTION private.delivery_core_21bcc1f83f65cc4afd7b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_deal' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_patch jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_21bcc1f83f65cc4afd7b(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_deal(p_deal_id uuid, p_patch jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_21bcc1f83f65cc4afd7b(p_deal_id,p_patch);
  RETURN result;
 END IF;
 RETURN private.delivery_core_21bcc1f83f65cc4afd7b(p_deal_id,p_patch);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_move_deal' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_new_stage text' AND md5(p.prosrc)=ANY(ARRAY['93adeef15ca719a1ee948c51faae073f','baae10f03bc948c57c57411344b909cb']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_move_deal'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_move_deal(','FUNCTION private.delivery_core_dc8c784fe43223bbf51f(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_move_deal' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_new_stage text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_dc8c784fe43223bbf51f(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_move_deal(p_deal_id uuid, p_new_stage text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_dc8c784fe43223bbf51f(p_deal_id,p_new_stage);
  RETURN result;
 END IF;
 RETURN private.delivery_core_dc8c784fe43223bbf51f(p_deal_id,p_new_stage);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_add_deal_activity' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['73220d8c48705826edb72e11b90fbfde','befd1a0211795cad8dc4fed0241961fb']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_add_deal_activity'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_add_deal_activity(','FUNCTION private.delivery_core_f9eb18f98a67982d13cd(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_add_deal_activity' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_f9eb18f98a67982d13cd(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_add_deal_activity(p_deal_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_f9eb18f98a67982d13cd(p_deal_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_f9eb18f98a67982d13cd(p_deal_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_cfdis' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['80a142215abbd8895ae420f3fd153524','ad4c145f10f58a3ee3a73a7072203c50']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_cfdis'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_cfdis(uuid, jsonb)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_eb597b550f2b0f3b5238(','FUNCTION private.delivery_core_52acf1803b0c062167b1(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_cfdis(','FUNCTION private.delivery_core_52acf1803b0c062167b1(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_cfdis' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_52acf1803b0c062167b1(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_cfdis(','FUNCTION private.delivery_scoped_52acf1803b0c062167b1('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_cfdis' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_52acf1803b0c062167b1(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_cfdis(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_52acf1803b0c062167b1(p_tenant_id,p_filters);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_52acf1803b0c062167b1(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_cfdi_detail' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid' AND md5(p.prosrc)=ANY(ARRAY['37f02199ababfa15597007f0aee6d941','c7fdf30a83ec9e3a7d78a0c538ddbdd0']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_cfdi_detail'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_get_cfdi_detail(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_e13d31ab0fb3c7597615(','FUNCTION private.delivery_core_ee40044b90380c23208f(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_cfdi_detail(','FUNCTION private.delivery_core_ee40044b90380c23208f(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_get_cfdi_detail' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_ee40044b90380c23208f(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_cfdi_detail(','FUNCTION private.delivery_scoped_ee40044b90380c23208f('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis'),'SELECT c.* INTO v_cfdi FROM private.delivery_billing_cfdis AS c','SELECT (pg_catalog.jsonb_populate_record(NULL::public.billing_cfdis,pg_catalog.to_jsonb(c))).* INTO v_cfdi FROM private.delivery_billing_cfdis AS c') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_cfdi_detail' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_ee40044b90380c23208f(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_cfdi_detail(p_cfdi_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN
  SELECT tenant_id INTO v_tenant FROM public.billing_cfdis WHERE id=p_cfdi_id;
  IF private.fiscal02_is_lab_entity('cfdi',p_cfdi_id) OR NOT COALESCE(private.delivery_root_company(v_tenant,'billing_cfdi',p_cfdi_id)=ANY(private.delivery_company_ids()),false) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_ee40044b90380c23208f(p_cfdi_id);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_ee40044b90380c23208f(p_cfdi_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_cfdi' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['38e66700021866087bcf4c40af1b5228','6a6457d7fd29e03eac129556279bb60d']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_cfdi'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_cfdi(','FUNCTION private.delivery_core_091cf08c315e35578c67(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_cfdi' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_091cf08c315e35578c67(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_cfdi(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_091cf08c315e35578c67(p_tenant_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_091cf08c315e35578c67(p_tenant_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_cfdi' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid, p_patch jsonb' AND md5(p.prosrc)=ANY(ARRAY['7218b0e37aa63bd828f5c81d71f01bf1','4ee535b575a11e21f9e44655692ab955']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_cfdi'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_cfdi(','FUNCTION private.delivery_core_d291d6ac13b8279dd294(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_cfdi' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid, p_patch jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_d291d6ac13b8279dd294(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_cfdi(p_cfdi_id uuid, p_patch jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_d291d6ac13b8279dd294(p_cfdi_id,p_patch);
  RETURN result;
 END IF;
 RETURN private.delivery_core_d291d6ac13b8279dd294(p_cfdi_id,p_patch);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_upsert_carta_porte' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['9c7095788fd268f81df6634537efd42b','b4c3160c22a0dcdb00eca82ccb61a886']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_upsert_carta_porte'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_upsert_carta_porte(','FUNCTION private.delivery_core_a27c7d134a85babeec6d(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_upsert_carta_porte' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_a27c7d134a85babeec6d(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_upsert_carta_porte(p_cfdi_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_a27c7d134a85babeec6d(p_cfdi_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_a27c7d134a85babeec6d(p_cfdi_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_inventory_lot' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_sku text, p_lot_code text, p_qty_on_hand numeric, p_warehouse text, p_received_at timestamp with time zone, p_currency text, p_pedimento_ref text, p_description text, p_unit text' AND md5(p.prosrc)=ANY(ARRAY['e306e10357cbd743c93fa4d4a0da4ed2','aeee4d519712c9b8a2abd4d6163bd233']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_inventory_lot'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_inventory_lot(','FUNCTION private.delivery_core_a0e1059dd3356e235a5c(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_inventory_lot' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_sku text, p_lot_code text, p_qty_on_hand numeric, p_warehouse text, p_received_at timestamp with time zone, p_currency text, p_pedimento_ref text, p_description text, p_unit text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_a0e1059dd3356e235a5c(uuid, text, text, numeric, text, timestamp with time zone, text, text, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_inventory_lot(p_tenant_id uuid, p_sku text, p_lot_code text, p_qty_on_hand numeric, p_warehouse text, p_received_at timestamp with time zone, p_currency text, p_pedimento_ref text, p_description text, p_unit text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_a0e1059dd3356e235a5c(p_tenant_id,p_sku,p_lot_code,p_qty_on_hand,p_warehouse,p_received_at,p_currency,p_pedimento_ref,p_description,p_unit);
  RETURN result;
 END IF;
 RETURN private.delivery_core_a0e1059dd3356e235a5c(p_tenant_id,p_sku,p_lot_code,p_qty_on_hand,p_warehouse,p_received_at,p_currency,p_pedimento_ref,p_description,p_unit);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_inventory_lot' AND pg_get_function_identity_arguments(p.oid)='p_id uuid, p_patch jsonb' AND md5(p.prosrc)=ANY(ARRAY['5c4bb6969a6f79718d3f25179d91934b','b55dd0ff4ac8561ecd622656d6c161ea']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_inventory_lot'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_inventory_lot(','FUNCTION private.delivery_core_57e6aecefcb98778afd9(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_inventory_lot' AND pg_get_function_identity_arguments(p.oid)='p_id uuid, p_patch jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_57e6aecefcb98778afd9(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_inventory_lot(p_id uuid, p_patch jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_57e6aecefcb98778afd9(p_id,p_patch);
  RETURN result;
 END IF;
 RETURN private.delivery_core_57e6aecefcb98778afd9(p_id,p_patch);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_pedimento' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['db82de22bd584f46607321ecaa05827c','d598f88ca45b13bf3bb22c18f8b2632b']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_pedimento'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_pedimento(','FUNCTION private.delivery_core_5ba59b7c98b5c2f1e382(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_pedimento' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_5ba59b7c98b5c2f1e382(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_pedimento(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_5ba59b7c98b5c2f1e382(p_tenant_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_5ba59b7c98b5c2f1e382(p_tenant_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_pedimento' AND pg_get_function_identity_arguments(p.oid)='p_id uuid, p_patch jsonb' AND md5(p.prosrc)=ANY(ARRAY['10abe1e9bb0f89b1d9954465125533b5','26352f0e10303bf1e4ccba1c42577c25']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_pedimento'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_pedimento(','FUNCTION private.delivery_core_56dd9dbbf0a8fc8b5bf1(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_pedimento' AND pg_get_function_identity_arguments(p.oid)='p_id uuid, p_patch jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_56dd9dbbf0a8fc8b5bf1(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_pedimento(p_id uuid, p_patch jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_56dd9dbbf0a8fc8b5bf1(p_id,p_patch);
  RETURN result;
 END IF;
 RETURN private.delivery_core_56dd9dbbf0a8fc8b5bf1(p_id,p_patch);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_tenant_settings' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['df05e5181d43cd5a5998a230f2f7dc5c','1e145d8778a93e29e1058e393a9427c0']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_tenant_settings'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_tenant_settings(','FUNCTION private.delivery_core_b44f65b9a98d499b3430(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_tenant_settings' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_b44f65b9a98d499b3430(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_tenant_settings(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_b44f65b9a98d499b3430(p_tenant_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_b44f65b9a98d499b3430(p_tenant_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_member_role' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_member_user_id uuid, p_new_role text' AND md5(p.prosrc)=ANY(ARRAY['cd8f2abb461d0ec51dab0d761189d6a6','2c64c3b7e3320033a1dbe2e7c63f4ad4']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_member_role'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_member_role(','FUNCTION private.delivery_core_f7c44b13d0828c12bd10(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_member_role' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_member_user_id uuid, p_new_role text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_f7c44b13d0828c12bd10(uuid, uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_member_role(p_tenant_id uuid, p_member_user_id uuid, p_new_role text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_f7c44b13d0828c12bd10(p_tenant_id,p_member_user_id,p_new_role);
  RETURN result;
 END IF;
 RETURN private.delivery_core_f7c44b13d0828c12bd10(p_tenant_id,p_member_user_id,p_new_role);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_deactivate_member' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_member_user_id uuid' AND md5(p.prosrc)=ANY(ARRAY['234102156712bfcba225aa01903c3ff6','2331b9a5074eee8b3e18006c811f4b81']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_deactivate_member'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_deactivate_member(','FUNCTION private.delivery_core_3a7ba6cf096e12357cb4(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_deactivate_member' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_member_user_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_3a7ba6cf096e12357cb4(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_deactivate_member(p_tenant_id uuid, p_member_user_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_3a7ba6cf096e12357cb4(p_tenant_id,p_member_user_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_3a7ba6cf096e12357cb4(p_tenant_id,p_member_user_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_validate_module_access' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_module_name text' AND md5(p.prosrc)=ANY(ARRAY['9604e7eda3e28bd08ce1aa93706de0cb','b9702363ce3a7f838ce7b114f6cdaacc']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_validate_module_access'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_validate_module_access(','FUNCTION private.delivery_core_533931e980540283a533(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_validate_module_access' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_module_name text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_533931e980540283a533(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_validate_module_access(p_tenant_id uuid, p_module_name text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_533931e980540283a533(p_tenant_id,p_module_name);
  RETURN result;
 END IF;
 RETURN private.delivery_core_533931e980540283a533(p_tenant_id,p_module_name);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_accept_invitation' AND pg_get_function_identity_arguments(p.oid)='p_token text' AND md5(p.prosrc)=ANY(ARRAY['8c17899b982f45a6ed7d1c73f66aab51','49166f1c81fd2effcfaf34c034cf7dbc']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public, extensions']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_accept_invitation'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_accept_invitation(','FUNCTION private.delivery_core_9d091da682d210d2f85e(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_accept_invitation' AND pg_get_function_identity_arguments(p.oid)='p_token text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_9d091da682d210d2f85e(text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_accept_invitation(p_token text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'extensions' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_9d091da682d210d2f85e(p_token);
  RETURN result;
 END IF;
 RETURN private.delivery_core_9d091da682d210d2f85e(p_token);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_invitations' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['be04a76c8ec1dd9aef4a12d12a15fbb9','2d28ac7145c128d1dd67c29ae6a4c6a4']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_invitations'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_invitations(','FUNCTION private.delivery_core_cb607c8a2d4a1bf76fce(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_invitations' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_cb607c8a2d4a1bf76fce(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_invitations(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_cb607c8a2d4a1bf76fce(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_cb607c8a2d4a1bf76fce(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_revoke_invitation' AND pg_get_function_identity_arguments(p.oid)='p_invitation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['702d15a6176bb0e781c19a20b3f56946','6543e64ca96f4885583fb6e9b87070b3']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_revoke_invitation'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_revoke_invitation(','FUNCTION private.delivery_core_331e5d9ccc68bf928fa7(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_revoke_invitation' AND pg_get_function_identity_arguments(p.oid)='p_invitation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_331e5d9ccc68bf928fa7(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_revoke_invitation(p_invitation_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_331e5d9ccc68bf928fa7(p_invitation_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_331e5d9ccc68bf928fa7(p_invitation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_demo_configure_module' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_module_name text' AND md5(p.prosrc)=ANY(ARRAY['2164abee722b6d25451d31f64046a4bf','133483d37ada0e0ecd1d795c53074d46']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_demo_configure_module'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_demo_configure_module(','FUNCTION private.delivery_core_198514f80511a9b40d7b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_demo_configure_module' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_module_name text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_198514f80511a9b40d7b(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_demo_configure_module(p_tenant_id uuid, p_module_name text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_198514f80511a9b40d7b(p_tenant_id,p_module_name);
  RETURN result;
 END IF;
 RETURN private.delivery_core_198514f80511a9b40d7b(p_tenant_id,p_module_name);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_tracking_token' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid, p_scope text' AND md5(p.prosrc)=ANY(ARRAY['54c1fbcc629cc45cc073525d4d7340c6','ed2cbab38740a96224f92dd4acfb3944']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_tracking_token'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_tracking_token(','FUNCTION private.delivery_core_14279c36814f527a1be8(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_tracking_token' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid, p_scope text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_14279c36814f527a1be8(uuid, uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_tracking_token(p_tenant_id uuid, p_operation_id uuid, p_scope text DEFAULT 'public:read'::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_14279c36814f527a1be8(p_tenant_id,p_operation_id,p_scope);
  RETURN result;
 END IF;
 RETURN private.delivery_core_14279c36814f527a1be8(p_tenant_id,p_operation_id,p_scope);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_tracking_token' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid, p_scope text, p_ttl_hours integer, p_force_rotate boolean' AND md5(p.prosrc)=ANY(ARRAY['1b691bc22f01cdc19f12d44b8930e083','2a2d7d2249a7b9965f87f5365065a13d']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_tracking_token'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_tracking_token(','FUNCTION private.delivery_core_1dbd60d83305b0ba2fe9(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_tracking_token' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid, p_scope text, p_ttl_hours integer, p_force_rotate boolean';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_1dbd60d83305b0ba2fe9(uuid, uuid, text, integer, boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_tracking_token(p_tenant_id uuid, p_operation_id uuid, p_scope text, p_ttl_hours integer, p_force_rotate boolean) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_1dbd60d83305b0ba2fe9(p_tenant_id,p_operation_id,p_scope,p_ttl_hours,p_force_rotate);
  RETURN result;
 END IF;
 RETURN private.delivery_core_1dbd60d83305b0ba2fe9(p_tenant_id,p_operation_id,p_scope,p_ttl_hours,p_force_rotate);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_revoke_tracking_token' AND pg_get_function_identity_arguments(p.oid)='p_token_id uuid' AND md5(p.prosrc)=ANY(ARRAY['10aa0a46dc69ede0264ba001ce8ebb7c','8f11d307a1b8ffc455663eda72c11ee4']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_revoke_tracking_token'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_revoke_tracking_token(','FUNCTION private.delivery_core_3c1b18bc31de404cfc59(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_revoke_tracking_token' AND pg_get_function_identity_arguments(p.oid)='p_token_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_3c1b18bc31de404cfc59(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_revoke_tracking_token(p_token_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_3c1b18bc31de404cfc59(p_token_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_3c1b18bc31de404cfc59(p_token_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_tracking_tokens' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['cf2934e667cc32052cdf171d30eacdb8','69ca0608a0fc42551c8ea6a2829c46b4']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_tracking_tokens'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_tracking_tokens(','FUNCTION private.delivery_core_26926d5b6b53f8904828(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_tracking_tokens' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_26926d5b6b53f8904828(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_tracking_tokens(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_26926d5b6b53f8904828(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_26926d5b6b53f8904828(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_dashboard_overview' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone' AND md5(p.prosrc)=ANY(ARRAY['4a32a8d4c7030d9ae772a14fe30ce902','f090891dab06dee212562b4ff090e471']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_dashboard_overview'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_dashboard_overview(uuid, timestamp with time zone, timestamp with time zone)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_ab5a80603c84a2be8f81(','FUNCTION private.delivery_core_d2e2481b501e30c2b81c(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_dashboard_overview(','FUNCTION private.delivery_core_d2e2481b501e30c2b81c(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_dashboard_overview' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_d2e2481b501e30c2b81c(uuid, timestamp with time zone, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_dashboard_overview(','FUNCTION private.delivery_scoped_d2e2481b501e30c2b81c('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_dashboard_overview' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_d2e2481b501e30c2b81c(uuid, timestamp with time zone, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_dashboard_overview(p_tenant_id uuid, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_d2e2481b501e30c2b81c(p_tenant_id,p_start_date,p_end_date);
  RETURN CASE WHEN private.delivery_cap(v_tenant,'financial.full.read') THEN result ELSE jsonb_build_object('kpis',private.delivery_pick_dto(result->'kpis',ARRAY['ops_total','ops_in_transit']),'financial_available',false) END;
 END IF;
 RETURN private.delivery_core_d2e2481b501e30c2b81c(p_tenant_id,p_start_date,p_end_date);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_reports_pipeline_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['5429b9305b839513ec126a2dd9b2777f','fd9125d22809ae982f99b86082f70953']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_reports_pipeline_summary'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_reports_pipeline_summary(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_25f68b586ff755566c0f(','FUNCTION private.delivery_core_f3c1f8dc7525f8ba873d(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_reports_pipeline_summary(','FUNCTION private.delivery_core_f3c1f8dc7525f8ba873d(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_reports_pipeline_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_f3c1f8dc7525f8ba873d(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_reports_pipeline_summary(','FUNCTION private.delivery_scoped_f3c1f8dc7525f8ba873d('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_reports_pipeline_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_f3c1f8dc7525f8ba873d(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_reports_pipeline_summary(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read') OR private.delivery_cap(v_tenant,'pipeline.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_f3c1f8dc7525f8ba873d(p_tenant_id);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_f3c1f8dc7525f8ba873d(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_dashboard_alerts' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone' AND md5(p.prosrc)=ANY(ARRAY['901d36e73b3a914716bee93ba1dc3e00','f38fda7f6fc06c7655d53252cda13936']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_dashboard_alerts'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_dashboard_alerts(uuid, timestamp with time zone, timestamp with time zone)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_5af377c7d682526a1448(','FUNCTION private.delivery_core_80213c82e1a7d95ba774(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_dashboard_alerts(','FUNCTION private.delivery_core_80213c82e1a7d95ba774(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_dashboard_alerts' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_80213c82e1a7d95ba774(uuid, timestamp with time zone, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_dashboard_alerts(','FUNCTION private.delivery_scoped_80213c82e1a7d95ba774('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_dashboard_alerts' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_80213c82e1a7d95ba774(uuid, timestamp with time zone, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_dashboard_alerts(p_tenant_id uuid, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_80213c82e1a7d95ba774(p_tenant_id,p_start_date,p_end_date);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_80213c82e1a7d95ba774(p_tenant_id,p_start_date,p_end_date);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_reports_inventory_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['29a8bb71b3a502a6c69f007f546bd337','6becc75f231faa364307074f9e063209']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_reports_inventory_summary'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_reports_inventory_summary(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_2cce1756abcd6db6c774(','FUNCTION private.delivery_core_97e4ef2a873b967e0388(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_reports_inventory_summary(','FUNCTION private.delivery_core_97e4ef2a873b967e0388(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_reports_inventory_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_97e4ef2a873b967e0388(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_reports_inventory_summary(','FUNCTION private.delivery_scoped_97e4ef2a873b967e0388('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_reports_inventory_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_97e4ef2a873b967e0388(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_reports_inventory_summary(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read') OR private.delivery_cap(v_tenant,'inventory.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_97e4ef2a873b967e0388(p_tenant_id);
  RETURN CASE WHEN private.delivery_cap(v_tenant,'financial.full.read') THEN result ELSE private.delivery_pick_dto(result,ARRAY['blocked_count','low_stock_count']) END;
 END IF;
 RETURN private.delivery_core_97e4ef2a873b967e0388(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_inventory_lots' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['eed9e691a489ec833b53774f446980dd','d67f95ab5d8555f2304e8f7db9c84e80']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_inventory_lots'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_inventory_lots(','FUNCTION private.delivery_core_f67e0ccfbeaae337968f(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_inventory_lots' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_f67e0ccfbeaae337968f(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_inventory_lots(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_f67e0ccfbeaae337968f(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_f67e0ccfbeaae337968f(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_pedimentos' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['b0f645bd72549e6ab46c81ac6484dc9f','70c56c7dc600224029dbe11dac542dde']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_pedimentos'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_pedimentos(','FUNCTION private.delivery_core_fe7cf62ab16b5d39ca2b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_pedimentos' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_fe7cf62ab16b5d39ca2b(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_pedimentos(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_fe7cf62ab16b5d39ca2b(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_fe7cf62ab16b5d39ca2b(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_deals' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['8de84f9efcd58ce0753690be19156598','0d11da8b84e86dc2310bb18e5e26830e']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_deals'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_deals(','FUNCTION private.delivery_core_0775de5c9be223e710ba(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_deals' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_0775de5c9be223e710ba(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_deals(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_0775de5c9be223e710ba(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_0775de5c9be223e710ba(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_deal' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid' AND md5(p.prosrc)=ANY(ARRAY['31e69d8e778b5d195284c2f4b0e8a121','6350c6fd73a50b525757d01b9bbddc18']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_deal'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_deal(','FUNCTION private.delivery_core_22436962c4034e05bcbd(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_deal' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_22436962c4034e05bcbd(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_deal(p_deal_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_22436962c4034e05bcbd(p_deal_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_22436962c4034e05bcbd(p_deal_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_delete_operation_crossing' AND pg_get_function_identity_arguments(p.oid)='p_crossing_id uuid' AND md5(p.prosrc)=ANY(ARRAY['c1bfe4376540b760bf93bcb285f07fda','96f36df9dcd60c7b8d917d6718943caf']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_delete_operation_crossing'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_delete_operation_crossing(','FUNCTION private.delivery_core_ba443d65dc2ef369c631(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_delete_operation_crossing' AND pg_get_function_identity_arguments(p.oid)='p_crossing_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_ba443d65dc2ef369c631(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_delete_operation_crossing(p_crossing_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_ba443d65dc2ef369c631(p_crossing_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_ba443d65dc2ef369c631(p_crossing_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_deal_activities' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid' AND md5(p.prosrc)=ANY(ARRAY['ef7b7bcf489c5ebb342bc5630aaeabbb','6f77fd5da16e526caf507c3e0916a216']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_deal_activities'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_deal_activities(','FUNCTION private.delivery_core_3ab3178be7d22ffd1852(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_deal_activities' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_3ab3178be7d22ffd1852(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_deal_activities(p_deal_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_3ab3178be7d22ffd1852(p_deal_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_3ab3178be7d22ffd1852(p_deal_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_tenant_settings' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['c1d468613591a4ad45a930b2b34e28a4','1eb1662543a774f75e21df672bea2b28']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_tenant_settings'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_tenant_settings(','FUNCTION private.delivery_core_2a472b39ed56929a6d12(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_tenant_settings' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_2a472b39ed56929a6d12(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_tenant_settings(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_2a472b39ed56929a6d12(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_2a472b39ed56929a6d12(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_audit_log' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_limit integer, p_offset integer, p_entity_type text, p_action text, p_start timestamp with time zone, p_end timestamp with time zone' AND md5(p.prosrc)=ANY(ARRAY['520f406dcbc8e0aa47a400421aa689bc','7b5b01bf1c771f43c606bb74966ed146']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_audit_log'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_audit_log(','FUNCTION private.delivery_core_d44855d81d5219b53ba6(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_audit_log' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_limit integer, p_offset integer, p_entity_type text, p_action text, p_start timestamp with time zone, p_end timestamp with time zone';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_d44855d81d5219b53ba6(uuid, integer, integer, text, text, timestamp with time zone, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_audit_log(p_tenant_id uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_entity_type text DEFAULT NULL::text, p_action text DEFAULT NULL::text, p_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_d44855d81d5219b53ba6(p_tenant_id,p_limit,p_offset,p_entity_type,p_action,p_start,p_end);
  RETURN result;
 END IF;
 RETURN private.delivery_core_d44855d81d5219b53ba6(p_tenant_id,p_limit,p_offset,p_entity_type,p_action,p_start,p_end);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_upsert_quote' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_deal_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['266cb4d3000f2c5ecb6338e1cd45200d','e11e3806628ad1f50516ac9b1fa5dc4b']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_upsert_quote'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_upsert_quote(','FUNCTION private.delivery_core_997f80d29b3001ca2b26(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_upsert_quote' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_deal_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_997f80d29b3001ca2b26(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_upsert_quote(p_tenant_id uuid, p_deal_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_997f80d29b3001ca2b26(p_tenant_id,p_deal_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_997f80d29b3001ca2b26(p_tenant_id,p_deal_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_claim_documents' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid' AND md5(p.prosrc)=ANY(ARRAY['9e80b12ced00f5563314d0a9572683a1','d83c6e69df0c8c6901be749c611054e2']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_claim_documents'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_claim_documents(','FUNCTION private.delivery_core_ef87b22332d0957097e3(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_claim_documents' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_ef87b22332d0957097e3(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_claim_documents(p_claim_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_ef87b22332d0957097e3(p_claim_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_ef87b22332d0957097e3(p_claim_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_customers' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['59254c8e20e655b2d555e86a9beeb245','8bfe536fb2f9c388ae7a5a786d1ffbcd']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_customers'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_customers(','FUNCTION private.delivery_core_f902bd04832167957d8b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_customers' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_f902bd04832167957d8b(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_customers(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_f902bd04832167957d8b(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_f902bd04832167957d8b(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_customer_360' AND pg_get_function_identity_arguments(p.oid)='p_customer_id uuid' AND md5(p.prosrc)=ANY(ARRAY['067a2312bfd39f2e995c0186a6c2e92a','cdbad2443632ec1c3705d4d1b299027e']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_customer_360'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_customer_360(','FUNCTION private.delivery_core_14c038fa4fc4ac71855b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_customer_360' AND pg_get_function_identity_arguments(p.oid)='p_customer_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_14c038fa4fc4ac71855b(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_customer_360(p_customer_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_14c038fa4fc4ac71855b(p_customer_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_14c038fa4fc4ac71855b(p_customer_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_upsert_customer' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_customer_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['0144ec6e041d03ec2f2c66dc49a2583c','e20f3e0dd8d129cd38fd94792622c838']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_upsert_customer'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_upsert_customer(','FUNCTION private.delivery_core_d461a6f579acb0a992e0(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_upsert_customer' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_customer_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_d461a6f579acb0a992e0(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_upsert_customer(p_tenant_id uuid, p_customer_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_d461a6f579acb0a992e0(p_tenant_id,p_customer_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_d461a6f579acb0a992e0(p_tenant_id,p_customer_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_providers' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['877135a219046c8ae1655baaa7987c31','18d393a821e6bfadc278b359d6f80f5d']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_providers'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_providers(','FUNCTION private.delivery_core_dd877a049532f822c154(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_providers' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_dd877a049532f822c154(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_providers(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_dd877a049532f822c154(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_dd877a049532f822c154(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_convert_quote_to_operation' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_conversion_note text' AND md5(p.prosrc)=ANY(ARRAY['76760af74b1bc1985d0f42eb586f910d','0aefabf7dbc7ca439e1ff62aca2ca20a']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_convert_quote_to_operation'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_convert_quote_to_operation(','FUNCTION private.delivery_core_5cdc4c99fa598ba99923(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_convert_quote_to_operation' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_conversion_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_5cdc4c99fa598ba99923(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_convert_quote_to_operation(p_deal_id uuid, p_conversion_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_5cdc4c99fa598ba99923(p_deal_id,p_conversion_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_5cdc4c99fa598ba99923(p_deal_id,p_conversion_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_upsert_provider' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_provider_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['c8b1619d337f64df771b8caa4ed801c5','4147e6c768d533288f86c77a25ea892a']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_upsert_provider'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_upsert_provider(','FUNCTION private.delivery_core_ae430ac6e25f6d2152af(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_upsert_provider' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_provider_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_ae430ac6e25f6d2152af(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_upsert_provider(p_tenant_id uuid, p_provider_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_ae430ac6e25f6d2152af(p_tenant_id,p_provider_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_ae430ac6e25f6d2152af(p_tenant_id,p_provider_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_quotes' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['d635565562b2d6a198ab17834f6ea261','c9b4aceab5cb8763e8c0556ffcc991b3']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_quotes'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_quotes(','FUNCTION private.delivery_core_93f23f53f63138becff1(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_quotes' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_93f23f53f63138becff1(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_quotes(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_93f23f53f63138becff1(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_93f23f53f63138becff1(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_duplicate_quote' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid' AND md5(p.prosrc)=ANY(ARRAY['de07efeabf1ff793dcc8a75e47af19d6','5ef3fc0d683f5dab9917fb42ac222030']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_duplicate_quote'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_duplicate_quote(','FUNCTION private.delivery_core_c12c91da2580fee9a3ee(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_duplicate_quote' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_c12c91da2580fee9a3ee(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_duplicate_quote(p_deal_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_c12c91da2580fee9a3ee(p_deal_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_c12c91da2580fee9a3ee(p_deal_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_return_quote_to_draft' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid' AND md5(p.prosrc)=ANY(ARRAY['459af3d0393ee35b64d5f038128db101','b2569a97f71750711bc18451e637e95d']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_return_quote_to_draft'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_return_quote_to_draft(','FUNCTION private.delivery_core_599f7368cb5444978828(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_return_quote_to_draft' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_599f7368cb5444978828(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_return_quote_to_draft(p_deal_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_599f7368cb5444978828(p_deal_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_599f7368cb5444978828(p_deal_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_submit_quote_for_review' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid' AND md5(p.prosrc)=ANY(ARRAY['65496b6cbe411bdcced631814e68bb62','d33000e28416eb9e32a095f6bb0f8af7']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_submit_quote_for_review'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_submit_quote_for_review(','FUNCTION private.delivery_core_5419addff5df84ddcc19(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_submit_quote_for_review' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_5419addff5df84ddcc19(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_submit_quote_for_review(p_deal_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_5419addff5df84ddcc19(p_deal_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_5419addff5df84ddcc19(p_deal_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_approve_quote' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_approval_note text' AND md5(p.prosrc)=ANY(ARRAY['3a6d99f67a6f0de362dcddd341e459e8','a4e6b58966110c1884ad8a797cf859fc']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_approve_quote'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_approve_quote(','FUNCTION private.delivery_core_5b3b70c72577d93537bf(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_approve_quote' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_approval_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_5b3b70c72577d93537bf(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_approve_quote(p_deal_id uuid, p_approval_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_5b3b70c72577d93537bf(p_deal_id,p_approval_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_5b3b70c72577d93537bf(p_deal_id,p_approval_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_reject_quote' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_rejection_note text' AND md5(p.prosrc)=ANY(ARRAY['416d4d420cb215f58179702f55c363fe','d4a3e06ab28645911220c4e15b8a0d40']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_reject_quote'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_reject_quote(','FUNCTION private.delivery_core_dbc2183c13f57ce4882e(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_reject_quote' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_rejection_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_dbc2183c13f57ce4882e(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_reject_quote(p_deal_id uuid, p_rejection_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_dbc2183c13f57ce4882e(p_deal_id,p_rejection_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_dbc2183c13f57ce4882e(p_deal_id,p_rejection_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_upsert_claim_service_policy' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_policy_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['da93ed16a72001c3f903f7638a0179f0','c764fdae479139a37d830cd1b371444c']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_upsert_claim_service_policy'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_upsert_claim_service_policy(','FUNCTION private.delivery_core_dc95f6d5943a277769ff(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_upsert_claim_service_policy' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_policy_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_dc95f6d5943a277769ff(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_upsert_claim_service_policy(p_tenant_id uuid, p_policy_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_dc95f6d5943a277769ff(p_tenant_id,p_policy_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_dc95f6d5943a277769ff(p_tenant_id,p_policy_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_service_claim' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['4a05724a60f147a1020b955cb62b61ee','7f616dfe3001356c11e427c552a59778']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_service_claim'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_service_claim(','FUNCTION private.delivery_core_c190d142fddf66c2806f(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_service_claim' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_c190d142fddf66c2806f(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_service_claim(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_c190d142fddf66c2806f(p_tenant_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_c190d142fddf66c2806f(p_tenant_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_upsert_claim_financial' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_financial_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['93f58a534aee12d774c256cbf332e96d','ef256ebcc1eef0bc4fecfad51ed5c872']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_upsert_claim_financial'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_upsert_claim_financial(','FUNCTION private.delivery_core_321c533c515d818cb52b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_upsert_claim_financial' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_financial_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_321c533c515d818cb52b(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_upsert_claim_financial(p_claim_id uuid, p_financial_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_321c533c515d818cb52b(p_claim_id,p_financial_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_321c533c515d818cb52b(p_claim_id,p_financial_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_assign_operation_v3' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid, p_execution_type text, p_provider_id uuid, p_provider_name text, p_external_driver jsonb, p_external_vehicle jsonb, p_driver_id uuid, p_driver_name text, p_vehicle_id uuid, p_vehicle_ref text, p_planned_departure timestamp with time zone, p_priority text, p_reason text, p_force_override boolean' AND md5(p.prosrc)=ANY(ARRAY['890ff3b76e336c8093cc8f681a6432e8','6ecee6e75f1a1a4d712cb0114a5fd904']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_assign_operation_v3'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_assign_operation_v3(','FUNCTION private.delivery_core_21432671d8399568207c(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_assign_operation_v3' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid, p_execution_type text, p_provider_id uuid, p_provider_name text, p_external_driver jsonb, p_external_vehicle jsonb, p_driver_id uuid, p_driver_name text, p_vehicle_id uuid, p_vehicle_ref text, p_planned_departure timestamp with time zone, p_priority text, p_reason text, p_force_override boolean';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_21432671d8399568207c(uuid, uuid, text, uuid, text, jsonb, jsonb, uuid, text, uuid, text, timestamp with time zone, text, text, boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_assign_operation_v3(p_tenant_id uuid, p_operation_id uuid, p_execution_type text DEFAULT 'third_party'::text, p_provider_id uuid DEFAULT NULL::uuid, p_provider_name text DEFAULT NULL::text, p_external_driver jsonb DEFAULT '{}'::jsonb, p_external_vehicle jsonb DEFAULT '{}'::jsonb, p_driver_id uuid DEFAULT NULL::uuid, p_driver_name text DEFAULT NULL::text, p_vehicle_id uuid DEFAULT NULL::uuid, p_vehicle_ref text DEFAULT NULL::text, p_planned_departure timestamp with time zone DEFAULT NULL::timestamp with time zone, p_priority text DEFAULT 'normal'::text, p_reason text DEFAULT NULL::text, p_force_override boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_21432671d8399568207c(p_tenant_id,p_operation_id,p_execution_type,p_provider_id,p_provider_name,p_external_driver,p_external_vehicle,p_driver_id,p_driver_name,p_vehicle_id,p_vehicle_ref,p_planned_departure,p_priority,p_reason,p_force_override);
  RETURN result;
 END IF;
 RETURN private.delivery_core_21432671d8399568207c(p_tenant_id,p_operation_id,p_execution_type,p_provider_id,p_provider_name,p_external_driver,p_external_vehicle,p_driver_id,p_driver_name,p_vehicle_id,p_vehicle_ref,p_planned_departure,p_priority,p_reason,p_force_override);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_operation_assignment_history' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['a65baddfcd00c773f1e8083539125232','8663420a8ab3b7a59f272d4f7cf243ac']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_operation_assignment_history'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_operation_assignment_history(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_47486583dc83fc23d336(','FUNCTION private.delivery_core_0d3fea367ae721916896(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_operation_assignment_history(','FUNCTION private.delivery_core_0d3fea367ae721916896(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_operation_assignment_history' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_0d3fea367ae721916896(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_operation_assignment_history(','FUNCTION private.delivery_scoped_0d3fea367ae721916896('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_operation_assignment_history' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_0d3fea367ae721916896(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_operation_assignment_history(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN
  SELECT tenant_id INTO v_tenant FROM public.operations WHERE id=p_operation_id;
  IF NOT private.delivery_entity_allowed(v_tenant,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_0d3fea367ae721916896(p_operation_id);
  RETURN private.delivery_pick_dto(result,ARRAY['id','operation_id','execution_type','provider_id','provider_name','driver_name','vehicle_ref','planned_departure','created_at']);
 END IF;
 RETURN private.delivery_core_0d3fea367ae721916896(p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_operation' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_reference_code text, p_route_summary text, p_client_display_name text, p_destination_city text, p_eta_display text, p_status text, p_origin_place jsonb, p_destination_place jsonb, p_eta timestamp with time zone' AND md5(p.prosrc)=ANY(ARRAY['63a623bc006972504060c64a864b97f5','300cc8bd6e440697c96d8287372297ea']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_operation'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_operation(','FUNCTION private.delivery_core_7e01ede54979f7834f67(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_operation' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_reference_code text, p_route_summary text, p_client_display_name text, p_destination_city text, p_eta_display text, p_status text, p_origin_place jsonb, p_destination_place jsonb, p_eta timestamp with time zone';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_7e01ede54979f7834f67(uuid, text, text, text, text, text, text, jsonb, jsonb, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_operation(p_tenant_id uuid, p_reference_code text, p_route_summary text DEFAULT NULL::text, p_client_display_name text DEFAULT NULL::text, p_destination_city text DEFAULT NULL::text, p_eta_display text DEFAULT NULL::text, p_status text DEFAULT 'planned'::text, p_origin_place jsonb DEFAULT NULL::jsonb, p_destination_place jsonb DEFAULT NULL::jsonb, p_eta timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_7e01ede54979f7834f67(p_tenant_id,p_reference_code,p_route_summary,p_client_display_name,p_destination_city,p_eta_display,p_status,p_origin_place,p_destination_place,p_eta);
  RETURN result;
 END IF;
 RETURN private.delivery_core_7e01ede54979f7834f67(p_tenant_id,p_reference_code,p_route_summary,p_client_display_name,p_destination_city,p_eta_display,p_status,p_origin_place,p_destination_place,p_eta);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_operation_details' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_patch jsonb' AND md5(p.prosrc)=ANY(ARRAY['77faba19eda0a480f0987497dc12307f','f962b4c3d5cb38acd7c1a299eab619cb']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_operation_details'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_operation_details(','FUNCTION private.delivery_core_39930cd5b2225b32b375(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_operation_details' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_patch jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_39930cd5b2225b32b375(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_operation_details(p_operation_id uuid, p_patch jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_39930cd5b2225b32b375(p_operation_id,p_patch);
  RETURN result;
 END IF;
 RETURN private.delivery_core_39930cd5b2225b32b375(p_operation_id,p_patch);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_complete_operation_planning_v2' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_service_type text, p_origin_place jsonb, p_destination_place jsonb, p_operational_window_start timestamp with time zone, p_operational_window_end timestamp with time zone, p_notes text, p_cargo_summary jsonb, p_route_summary text, p_destination_city text, p_eta timestamp with time zone, p_eta_display text, p_operation_scope text, p_execution_type text, p_provider_cost_amount numeric, p_customer_price_amount numeric, p_pricing_currency text, p_service_catalog_item_id uuid, p_service_catalog_snapshot jsonb, p_boxes_placed_days integer, p_documentation_received_at timestamp with time zone, p_documentation_received_note text' AND md5(p.prosrc)=ANY(ARRAY['b315b4ecc499f5a07e129a778fe1d9fa','41f4120f774dee6c309649a63871d1d8']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_complete_operation_planning_v2'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_complete_operation_planning_v2(','FUNCTION private.delivery_core_9e95f351b63d1aeda4cb(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_complete_operation_planning_v2' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_service_type text, p_origin_place jsonb, p_destination_place jsonb, p_operational_window_start timestamp with time zone, p_operational_window_end timestamp with time zone, p_notes text, p_cargo_summary jsonb, p_route_summary text, p_destination_city text, p_eta timestamp with time zone, p_eta_display text, p_operation_scope text, p_execution_type text, p_provider_cost_amount numeric, p_customer_price_amount numeric, p_pricing_currency text, p_service_catalog_item_id uuid, p_service_catalog_snapshot jsonb, p_boxes_placed_days integer, p_documentation_received_at timestamp with time zone, p_documentation_received_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_9e95f351b63d1aeda4cb(uuid, text, jsonb, jsonb, timestamp with time zone, timestamp with time zone, text, jsonb, text, text, timestamp with time zone, text, text, text, numeric, numeric, text, uuid, jsonb, integer, timestamp with time zone, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_complete_operation_planning_v2(p_operation_id uuid, p_service_type text, p_origin_place jsonb, p_destination_place jsonb, p_operational_window_start timestamp with time zone, p_operational_window_end timestamp with time zone, p_notes text DEFAULT NULL::text, p_cargo_summary jsonb DEFAULT NULL::jsonb, p_route_summary text DEFAULT NULL::text, p_destination_city text DEFAULT NULL::text, p_eta timestamp with time zone DEFAULT NULL::timestamp with time zone, p_eta_display text DEFAULT NULL::text, p_operation_scope text DEFAULT 'national'::text, p_execution_type text DEFAULT 'third_party'::text, p_provider_cost_amount numeric DEFAULT NULL::numeric, p_customer_price_amount numeric DEFAULT NULL::numeric, p_pricing_currency text DEFAULT 'MXN'::text, p_service_catalog_item_id uuid DEFAULT NULL::uuid, p_service_catalog_snapshot jsonb DEFAULT '{}'::jsonb, p_boxes_placed_days integer DEFAULT NULL::integer, p_documentation_received_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_documentation_received_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_9e95f351b63d1aeda4cb(p_operation_id,p_service_type,p_origin_place,p_destination_place,p_operational_window_start,p_operational_window_end,p_notes,p_cargo_summary,p_route_summary,p_destination_city,p_eta,p_eta_display,p_operation_scope,p_execution_type,p_provider_cost_amount,p_customer_price_amount,p_pricing_currency,p_service_catalog_item_id,p_service_catalog_snapshot,p_boxes_placed_days,p_documentation_received_at,p_documentation_received_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_9e95f351b63d1aeda4cb(p_operation_id,p_service_type,p_origin_place,p_destination_place,p_operational_window_start,p_operational_window_end,p_notes,p_cargo_summary,p_route_summary,p_destination_city,p_eta,p_eta_display,p_operation_scope,p_execution_type,p_provider_cost_amount,p_customer_price_amount,p_pricing_currency,p_service_catalog_item_id,p_service_catalog_snapshot,p_boxes_placed_days,p_documentation_received_at,p_documentation_received_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_operation_operational_control' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['e09eb7cf1622c25e02a693b4d7e9b568','41d7afe4688951a9788f84b6281b2244']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_operation_operational_control'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_operation_operational_control(','FUNCTION private.delivery_core_9b6a7143f718bd678d48(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_operation_operational_control' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_9b6a7143f718bd678d48(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_operation_operational_control(p_operation_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_9b6a7143f718bd678d48(p_operation_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_9b6a7143f718bd678d48(p_operation_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_cancel_operation' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['b6434314479a4f0ea9534852435c92bf','b6434314479a4f0ea9534852435c92bf']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_cancel_operation'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_cancel_operation(','FUNCTION private.delivery_core_143087e85aba6c46efbb(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_cancel_operation' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_143087e85aba6c46efbb(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_cancel_operation(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_143087e85aba6c46efbb(p_operation_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_143087e85aba6c46efbb(p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_claim_saved_views' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['5d2eb421ff24cbc441fcb60c37ec16b1','5d2eb421ff24cbc441fcb60c37ec16b1']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_claim_saved_views'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_claim_saved_views(','FUNCTION private.delivery_core_7f1b0de5e6fc15643cf5(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_claim_saved_views' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_7f1b0de5e6fc15643cf5(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_claim_saved_views(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_7f1b0de5e6fc15643cf5(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_7f1b0de5e6fc15643cf5(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_operation_requirements' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['80cc311111e6db46e0a043760030d974','f2c117f88ca243845dedf8ecefc6965d']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_operation_requirements'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation_requirements(','FUNCTION private.delivery_core_41ce699223aca2d59b54(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_operation_requirements' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_41ce699223aca2d59b54(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_requirements(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_41ce699223aca2d59b54(p_operation_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_41ce699223aca2d59b54(p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_operation_tracking_events' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['f9bf5748a89c1c87ff6e376d47d74c97','1cacb928cf4521e2e116267d2bed5596']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_operation_tracking_events'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_operation_tracking_events(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_31fe5306ae6e26639194(','FUNCTION private.delivery_core_af116a9671028f9b8c90(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_operation_tracking_events(','FUNCTION private.delivery_core_af116a9671028f9b8c90(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_operation_tracking_events' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_af116a9671028f9b8c90(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_operation_tracking_events(','FUNCTION private.delivery_scoped_af116a9671028f9b8c90('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_operation_tracking_events' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_af116a9671028f9b8c90(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_operation_tracking_events(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN
  SELECT tenant_id INTO v_tenant FROM public.operations WHERE id=p_operation_id;
  IF NOT private.delivery_entity_allowed(v_tenant,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_af116a9671028f9b8c90(p_operation_id);
  RETURN private.delivery_pick_dto(result,ARRAY['id','operation_id','event_type','source','occurred_at','created_at']);
 END IF;
 RETURN private.delivery_core_af116a9671028f9b8c90(p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_operation_incidents' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['a0772f7eeebcadd4624b044532b82cea','461d25141cecb77acc8f7a43fc8601c8']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_operation_incidents'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_operation_incidents(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_8167ec9c1f9255a7b5b0(','FUNCTION private.delivery_core_55dac9565478b2786f5d(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_operation_incidents(','FUNCTION private.delivery_core_55dac9565478b2786f5d(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_operation_incidents' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_55dac9565478b2786f5d(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_operation_incidents(','FUNCTION private.delivery_scoped_55dac9565478b2786f5d('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_operation_incidents' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_55dac9565478b2786f5d(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_operation_incidents(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN
  SELECT tenant_id INTO v_tenant FROM public.operations WHERE id=p_operation_id;
  IF NOT private.delivery_entity_allowed(v_tenant,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_55dac9565478b2786f5d(p_operation_id);
  RETURN private.delivery_pick_dto(result,ARRAY['id','operation_id','category','title','is_blocking','status','created_at','updated_at','resolved_at']);
 END IF;
 RETURN private.delivery_core_55dac9565478b2786f5d(p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_operation_incident_summary' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['4792e2c856471d627bff0e3490218ce1','3b4ad5a5901e4eaaba4bebed1a1affe7']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_operation_incident_summary'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_get_operation_incident_summary(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_0525fa3d2ace18fe5876(','FUNCTION private.delivery_core_d4f5995d3807f0cf0c4e(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation_incident_summary(','FUNCTION private.delivery_core_d4f5995d3807f0cf0c4e(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_get_operation_incident_summary' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_d4f5995d3807f0cf0c4e(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation_incident_summary(','FUNCTION private.delivery_scoped_d4f5995d3807f0cf0c4e('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_operation_incident_summary' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_d4f5995d3807f0cf0c4e(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_incident_summary(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN
  SELECT tenant_id INTO v_tenant FROM public.operations WHERE id=p_operation_id;
  IF NOT private.delivery_entity_allowed(v_tenant,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_d4f5995d3807f0cf0c4e(p_operation_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_d4f5995d3807f0cf0c4e(p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_operation_incident' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_category text, p_title text, p_description text, p_is_blocking boolean, p_tracking_event_id uuid' AND md5(p.prosrc)=ANY(ARRAY['04b018261c28212e4c0c9089c2defa5f','730ec8e0bb3c1060eba0a4143abf6965']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_operation_incident'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_operation_incident(','FUNCTION private.delivery_core_0915e18f07eac7aae77d(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_operation_incident' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_category text, p_title text, p_description text, p_is_blocking boolean, p_tracking_event_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_0915e18f07eac7aae77d(uuid, text, text, text, boolean, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_operation_incident(p_operation_id uuid, p_category text, p_title text, p_description text DEFAULT NULL::text, p_is_blocking boolean DEFAULT false, p_tracking_event_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_0915e18f07eac7aae77d(p_operation_id,p_category,p_title,p_description,p_is_blocking,p_tracking_event_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_0915e18f07eac7aae77d(p_operation_id,p_category,p_title,p_description,p_is_blocking,p_tracking_event_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_resolve_operation_incident' AND pg_get_function_identity_arguments(p.oid)='p_incident_id uuid, p_resolution_note text' AND md5(p.prosrc)=ANY(ARRAY['0d2fafea5235773ba655f5d16bfceb0b','3b73ecda783fba662918db5000a12fe0']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_resolve_operation_incident'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_resolve_operation_incident(','FUNCTION private.delivery_core_d429ef817187577364df(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_resolve_operation_incident' AND pg_get_function_identity_arguments(p.oid)='p_incident_id uuid, p_resolution_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_d429ef817187577364df(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_resolve_operation_incident(p_incident_id uuid, p_resolution_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_d429ef817187577364df(p_incident_id,p_resolution_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_d429ef817187577364df(p_incident_id,p_resolution_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_dismiss_operation_incident' AND pg_get_function_identity_arguments(p.oid)='p_incident_id uuid, p_dismiss_note text' AND md5(p.prosrc)=ANY(ARRAY['15c444d8be74e2407331c080f6130593','6d61051e18cf667f2875236cf3bd7bd3']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_dismiss_operation_incident'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_dismiss_operation_incident(','FUNCTION private.delivery_core_719110b179a9b6922e84(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_dismiss_operation_incident' AND pg_get_function_identity_arguments(p.oid)='p_incident_id uuid, p_dismiss_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_719110b179a9b6922e84(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_dismiss_operation_incident(p_incident_id uuid, p_dismiss_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_719110b179a9b6922e84(p_incident_id,p_dismiss_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_719110b179a9b6922e84(p_incident_id,p_dismiss_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_operation_evidence' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_incident_id uuid' AND md5(p.prosrc)=ANY(ARRAY['6ec52744314079a3a989a1de7a0754cb','c197a8ff22832e57e3fe6d12f335d45b']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_operation_evidence'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_operation_evidence(uuid, uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_ccb437a4b8a06441644c(','FUNCTION private.delivery_core_0ac0e900e9c84504364c(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_operation_evidence(','FUNCTION private.delivery_core_0ac0e900e9c84504364c(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_operation_evidence' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_incident_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_0ac0e900e9c84504364c(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_operation_evidence(','FUNCTION private.delivery_scoped_0ac0e900e9c84504364c('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_operation_evidence' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_incident_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_0ac0e900e9c84504364c(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_operation_evidence(p_operation_id uuid, p_incident_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN
  SELECT tenant_id INTO v_tenant FROM public.operations WHERE id=p_operation_id;
  IF NOT private.delivery_entity_allowed(v_tenant,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_0ac0e900e9c84504364c(p_operation_id,p_incident_id);
  RETURN private.delivery_pick_dto(result,ARRAY['id','operation_id','incident_id','kind','created_at']);
 END IF;
 RETURN private.delivery_core_0ac0e900e9c84504364c(p_operation_id,p_incident_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_add_operation_evidence' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_incident_id uuid, p_kind text, p_note text, p_file_ref text, p_external_url text' AND md5(p.prosrc)=ANY(ARRAY['60247773a4d42248d6b38da3c5c48047','648e4562eecb15b34d916f93350c66ca']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_add_operation_evidence'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_add_operation_evidence(','FUNCTION private.delivery_core_858e88dcd8810a3be8d7(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_add_operation_evidence' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_incident_id uuid, p_kind text, p_note text, p_file_ref text, p_external_url text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_858e88dcd8810a3be8d7(uuid, uuid, text, text, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_add_operation_evidence(p_operation_id uuid, p_incident_id uuid DEFAULT NULL::uuid, p_kind text DEFAULT 'operational_note'::text, p_note text DEFAULT NULL::text, p_file_ref text DEFAULT NULL::text, p_external_url text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_858e88dcd8810a3be8d7(p_operation_id,p_incident_id,p_kind,p_note,p_file_ref,p_external_url);
  RETURN result;
 END IF;
 RETURN private.delivery_core_858e88dcd8810a3be8d7(p_operation_id,p_incident_id,p_kind,p_note,p_file_ref,p_external_url);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_operation_documents' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['8c64a4645b702b76463121a5e3af47bd','c8208ab7844e83789b17839a0583ecb7']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_operation_documents'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_operation_documents(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_ba1942f522adb2fae549(','FUNCTION private.delivery_core_80aa5f0a2c70720bb802(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_operation_documents(','FUNCTION private.delivery_core_80aa5f0a2c70720bb802(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_operation_documents' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_80aa5f0a2c70720bb802(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_operation_documents(','FUNCTION private.delivery_scoped_80aa5f0a2c70720bb802('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_operation_documents' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_80aa5f0a2c70720bb802(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_operation_documents(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN
  SELECT tenant_id INTO v_tenant FROM public.operations WHERE id=p_operation_id;
  IF NOT private.delivery_entity_allowed(v_tenant,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_80aa5f0a2c70720bb802(p_operation_id);
  RETURN private.delivery_pick_dto(result,ARRAY['id','operation_id','document_type','display_label','requirement_level','status','created_at','updated_at']);
 END IF;
 RETURN private.delivery_core_80aa5f0a2c70720bb802(p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_operation_document_summary' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['582fe678ef602ce639f056f63a0e1233','f7212de4d103c84c61243c500a901a89']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_operation_document_summary'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_get_operation_document_summary(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_e2167c6dc9bfc700d81b(','FUNCTION private.delivery_core_c3064fbb9e31ba959486(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation_document_summary(','FUNCTION private.delivery_core_c3064fbb9e31ba959486(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_get_operation_document_summary' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_c3064fbb9e31ba959486(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation_document_summary(','FUNCTION private.delivery_scoped_c3064fbb9e31ba959486('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_operation_document_summary' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_c3064fbb9e31ba959486(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_document_summary(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN
  SELECT tenant_id INTO v_tenant FROM public.operations WHERE id=p_operation_id;
  IF NOT private.delivery_entity_allowed(v_tenant,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_c3064fbb9e31ba959486(p_operation_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_c3064fbb9e31ba959486(p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_upsert_operation_document' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_document_type text, p_requirement_level text, p_status text, p_document_reference text, p_file_ref text, p_external_url text, p_note text' AND md5(p.prosrc)=ANY(ARRAY['7ea7a9542da247ba0f78180f8660755d','129cefb7a3e2e428af169c7ee061a6cd']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_upsert_operation_document'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_upsert_operation_document(','FUNCTION private.delivery_core_b826e0bf3d2bc7e83d22(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_upsert_operation_document' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_document_type text, p_requirement_level text, p_status text, p_document_reference text, p_file_ref text, p_external_url text, p_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_b826e0bf3d2bc7e83d22(uuid, text, text, text, text, text, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_upsert_operation_document(p_operation_id uuid, p_document_type text, p_requirement_level text, p_status text, p_document_reference text DEFAULT NULL::text, p_file_ref text DEFAULT NULL::text, p_external_url text DEFAULT NULL::text, p_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_b826e0bf3d2bc7e83d22(p_operation_id,p_document_type,p_requirement_level,p_status,p_document_reference,p_file_ref,p_external_url,p_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_b826e0bf3d2bc7e83d22(p_operation_id,p_document_type,p_requirement_level,p_status,p_document_reference,p_file_ref,p_external_url,p_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_operation_crossings' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['a2e86956bcf683f52901edfe8375b66d','477bb73b8994883bce6a60a20122af4e']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_operation_crossings'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_operation_crossings(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_c9b9f4b8fe2df4333ad0(','FUNCTION private.delivery_core_25918969f26225542a1e(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_operation_crossings(','FUNCTION private.delivery_core_25918969f26225542a1e(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_operation_crossings' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_25918969f26225542a1e(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_operation_crossings(','FUNCTION private.delivery_scoped_25918969f26225542a1e('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis'),'SELECT * INTO v_operation FROM private.delivery_operations','SELECT (pg_catalog.jsonb_populate_record(NULL::public.operations,pg_catalog.to_jsonb(delivery_operations))).* INTO v_operation FROM private.delivery_operations') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_operation_crossings' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_25918969f26225542a1e(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_operation_crossings(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN
  SELECT tenant_id INTO v_tenant FROM public.operations WHERE id=p_operation_id;
  IF NOT private.delivery_entity_allowed(v_tenant,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_25918969f26225542a1e(p_operation_id);
  RETURN private.delivery_pick_dto(result,ARRAY['id','operation_id','crossing_type','status','planned_at','crossed_at','created_at','updated_at']);
 END IF;
 RETURN private.delivery_core_25918969f26225542a1e(p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_upsert_operation_crossing' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['0e7704f2c37dfca3a92e1965671e1bce','edcdfe162175c3e38b4ab902662b0e76']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_upsert_operation_crossing'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_upsert_operation_crossing(','FUNCTION private.delivery_core_7916b5a033e445227cc2(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_upsert_operation_crossing' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_7916b5a033e445227cc2(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_upsert_operation_crossing(p_operation_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_7916b5a033e445227cc2(p_operation_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_7916b5a033e445227cc2(p_operation_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_operation_billing' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['8f238832547b8567dcbf91c52b9cf158','c4b399760c5edfd9c0da602625e76997']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_operation_billing'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_get_operation_billing(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_88328fb254a09ff102fb(','FUNCTION private.delivery_core_0b1dd6bb347df6bb466e(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation_billing(','FUNCTION private.delivery_core_0b1dd6bb347df6bb466e(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_get_operation_billing' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_0b1dd6bb347df6bb466e(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation_billing(','FUNCTION private.delivery_scoped_0b1dd6bb347df6bb466e('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_operation_billing' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_0b1dd6bb347df6bb466e(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_billing(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN
  SELECT tenant_id INTO v_tenant FROM public.operations WHERE id=p_operation_id;
  IF NOT private.delivery_entity_allowed(v_tenant,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_0b1dd6bb347df6bb466e(p_operation_id);
  RETURN private.delivery_pick_dto(result,ARRAY['operation_id','billing_status','is_billed','has_billing_record','pod_present','is_documentation_complete','billing_readiness','can_admin_close']);
 END IF;
 RETURN private.delivery_core_0b1dd6bb347df6bb466e(p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_operation_billing_summary' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['7b1ecf00a610b9c10fffb6fc8cd399db','c14b9f73fb611e28c72e5ab4a95c08e6']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_operation_billing_summary'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_get_operation_billing_summary(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_83579d9fbd6985aab780(','FUNCTION private.delivery_core_2eb544e85b693f1cdd0f(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation_billing_summary(','FUNCTION private.delivery_core_2eb544e85b693f1cdd0f(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_get_operation_billing_summary' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_2eb544e85b693f1cdd0f(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation_billing_summary(','FUNCTION private.delivery_scoped_2eb544e85b693f1cdd0f('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis'),'SELECT * INTO v_operation FROM private.delivery_operations','SELECT (pg_catalog.jsonb_populate_record(NULL::public.operations,pg_catalog.to_jsonb(delivery_operations))).* INTO v_operation FROM private.delivery_operations'),'SELECT * INTO v_billing FROM private.delivery_operation_billing','SELECT (pg_catalog.jsonb_populate_record(NULL::public.operation_billing,pg_catalog.to_jsonb(delivery_operation_billing))).* INTO v_billing FROM private.delivery_operation_billing') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_operation_billing_summary' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_2eb544e85b693f1cdd0f(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_billing_summary(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN
  SELECT tenant_id INTO v_tenant FROM public.operations WHERE id=p_operation_id;
  IF NOT private.delivery_entity_allowed(v_tenant,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_2eb544e85b693f1cdd0f(p_operation_id);
  RETURN private.delivery_pick_dto(result,ARRAY['operation_id','billing_status','is_billed','has_billing_record','pod_present','is_documentation_complete','billing_readiness','can_admin_close']);
 END IF;
 RETURN private.delivery_core_2eb544e85b693f1cdd0f(p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_transition_operation_status' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_to_status text' AND md5(p.prosrc)=ANY(ARRAY['bc317002949eedc3bc262b0fa40db61a','bff9b6e6c0af30c3256f95d44d266793']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_transition_operation_status'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_transition_operation_status(','FUNCTION private.delivery_core_a073d61eea6a26b9f8da(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_transition_operation_status' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_to_status text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_a073d61eea6a26b9f8da(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_transition_operation_status(p_operation_id uuid, p_to_status text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_a073d61eea6a26b9f8da(p_operation_id,p_to_status);
  RETURN result;
 END IF;
 RETURN private.delivery_core_a073d61eea6a26b9f8da(p_operation_id,p_to_status);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_override_operation_status' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_to_status text, p_reason text' AND md5(p.prosrc)=ANY(ARRAY['07b4ac81b07aa0012a27b14d7d5ce3ae','6891260ff4b8de3eadb938f9ad9898d1']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_override_operation_status'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_override_operation_status(','FUNCTION private.delivery_core_b70787747cc4a116db8b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_override_operation_status' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_to_status text, p_reason text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_b70787747cc4a116db8b(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_override_operation_status(p_operation_id uuid, p_to_status text, p_reason text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_b70787747cc4a116db8b(p_operation_id,p_to_status,p_reason);
  RETURN result;
 END IF;
 RETURN private.delivery_core_b70787747cc4a116db8b(p_operation_id,p_to_status,p_reason);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_close_operation' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['21a95efb7cfe7b8fb9b72f1488535038','e10ce8e7c8356fe783c6dc903926bf66']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_close_operation'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_close_operation(','FUNCTION private.delivery_core_293f9c89bd250a569fc7(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_close_operation' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_293f9c89bd250a569fc7(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_close_operation(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_293f9c89bd250a569fc7(p_operation_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_293f9c89bd250a569fc7(p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_close_operation_override' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_override_reason text' AND md5(p.prosrc)=ANY(ARRAY['48c3718230a364857c2a0599dc997a4f','45519f5c91993cdf8ec1db27be9c18f0']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_close_operation_override'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_close_operation_override(','FUNCTION private.delivery_core_5d57b68ad1bf61dbc498(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_close_operation_override' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_override_reason text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_5d57b68ad1bf61dbc498(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_close_operation_override(p_operation_id uuid, p_override_reason text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_5d57b68ad1bf61dbc498(p_operation_id,p_override_reason);
  RETURN result;
 END IF;
 RETURN private.delivery_core_5d57b68ad1bf61dbc498(p_operation_id,p_override_reason);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_upsert_business_contact' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_contact_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['c63d3386b8de79bfcd53fd9abede0371','aa1388bd2463e390285cf483c2539667']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_upsert_business_contact'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_upsert_business_contact(','FUNCTION private.delivery_core_0a0ed234cecc28bdabb3(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_upsert_business_contact' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_contact_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_0a0ed234cecc28bdabb3(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_upsert_business_contact(p_tenant_id uuid, p_contact_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_0a0ed234cecc28bdabb3(p_tenant_id,p_contact_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_0a0ed234cecc28bdabb3(p_tenant_id,p_contact_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_mark_generated_document_printed' AND pg_get_function_identity_arguments(p.oid)='p_document_id uuid' AND md5(p.prosrc)=ANY(ARRAY['bc25d6f76403a9c1903e99a335093c44','5ba9d53f5520bea3e8a8060e0378ea3a']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_mark_generated_document_printed'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_mark_generated_document_printed(','FUNCTION private.delivery_core_b1f428cc1a8115f589dd(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_mark_generated_document_printed' AND pg_get_function_identity_arguments(p.oid)='p_document_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_b1f428cc1a8115f589dd(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_mark_generated_document_printed(p_document_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_b1f428cc1a8115f589dd(p_document_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_b1f428cc1a8115f589dd(p_document_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_partner_history_page' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_history_type text, p_cursor jsonb, p_limit integer' AND md5(p.prosrc)=ANY(ARRAY['b7cfa907ad4da0908137fd278a551d21','2befcb6931ed3580206cb4e06e822995']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_partner_history_page'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_partner_history_page(','FUNCTION private.delivery_core_35022513d6ecfc45c37c(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_partner_history_page' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_history_type text, p_cursor jsonb, p_limit integer';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_35022513d6ecfc45c37c(uuid, text, uuid, text, jsonb, integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_partner_history_page(p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_history_type text, p_cursor jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 25) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_35022513d6ecfc45c37c(p_tenant_id,p_entity_type,p_entity_id,p_history_type,p_cursor,p_limit);
  RETURN result;
 END IF;
 RETURN private.delivery_core_35022513d6ecfc45c37c(p_tenant_id,p_entity_type,p_entity_id,p_history_type,p_cursor,p_limit);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_fiscal_provider_config' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['164f5161bd49890ce9efed2c8bbe7a8e','7d46832d0dbb08bdb6d046ff5e30bc51']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_fiscal_provider_config'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_fiscal_provider_config(','FUNCTION private.delivery_core_65da52df97f30bf153e1(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_fiscal_provider_config' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_65da52df97f30bf153e1(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_fiscal_provider_config(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_65da52df97f30bf153e1(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_65da52df97f30bf153e1(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_document_upload_contract' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['3ad6920b464ae56cd3d73bfba4b1b75d','5bbe098206e17bc0513d213770fb1380']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_document_upload_contract'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_document_upload_contract(','FUNCTION private.delivery_core_2756931a22d281e289bc(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_document_upload_contract' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_2756931a22d281e289bc(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_document_upload_contract(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_2756931a22d281e289bc(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_2756931a22d281e289bc(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_register_document_file' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['39876322d5ce7fee5d8b327973c902ab','f27f6d55adf70ab94adb4302552b6885']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_register_document_file'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_register_document_file(','FUNCTION private.delivery_core_cdb505c515593abd8cfa(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_register_document_file' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_cdb505c515593abd8cfa(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_register_document_file(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_cdb505c515593abd8cfa(p_tenant_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_cdb505c515593abd8cfa(p_tenant_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_document_files' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['fcf6b83c700793b4583f576e8538401b','9b5a73a1733ca4832df346bb530f3c1d']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_document_files'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_document_files(','FUNCTION private.delivery_core_d105996e3ece8148abe9(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_document_files' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_d105996e3ece8148abe9(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_document_files(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_d105996e3ece8148abe9(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_d105996e3ece8148abe9(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_mark_document_file_status' AND pg_get_function_identity_arguments(p.oid)='p_file_id uuid, p_status text, p_notes text' AND md5(p.prosrc)=ANY(ARRAY['1548f6d02d0a7651de29b1c29925742a','bcff543c291c10a8d1d2bbc63ff64d86']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_mark_document_file_status'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_mark_document_file_status(','FUNCTION private.delivery_core_5a9dba7fdb619ce357a9(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_mark_document_file_status' AND pg_get_function_identity_arguments(p.oid)='p_file_id uuid, p_status text, p_notes text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_5a9dba7fdb619ce357a9(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_mark_document_file_status(p_file_id uuid, p_status text, p_notes text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_5a9dba7fdb619ce357a9(p_file_id,p_status,p_notes);
  RETURN result;
 END IF;
 RETURN private.delivery_core_5a9dba7fdb619ce357a9(p_file_id,p_status,p_notes);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_relate_document_file' AND pg_get_function_identity_arguments(p.oid)='p_file_id uuid, p_entity_type text, p_entity_id uuid, p_notes text' AND md5(p.prosrc)=ANY(ARRAY['23c38d54cff6ab9de8a10994a5fdcb40','91db1c4371a03a4d59bcc27ce7774fab']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_relate_document_file'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_relate_document_file(','FUNCTION private.delivery_core_544ba11da954356d1b49(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_relate_document_file' AND pg_get_function_identity_arguments(p.oid)='p_file_id uuid, p_entity_type text, p_entity_id uuid, p_notes text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_544ba11da954356d1b49(uuid, text, uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_relate_document_file(p_file_id uuid, p_entity_type text, p_entity_id uuid, p_notes text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_544ba11da954356d1b49(p_file_id,p_entity_type,p_entity_id,p_notes);
  RETURN result;
 END IF;
 RETURN private.delivery_core_544ba11da954356d1b49(p_file_id,p_entity_type,p_entity_id,p_notes);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_document_relations' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text, p_entity_id uuid' AND md5(p.prosrc)=ANY(ARRAY['78693bf28f76a9accadd5b1675558e28','51ffbfa6f222ee6df133a737531b7c6a']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_document_relations'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_document_relations(','FUNCTION private.delivery_core_17ed462316a5c07ef5c3(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_document_relations' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text, p_entity_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_17ed462316a5c07ef5c3(uuid, text, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_document_relations(p_tenant_id uuid, p_entity_type text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_17ed462316a5c07ef5c3(p_tenant_id,p_entity_type,p_entity_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_17ed462316a5c07ef5c3(p_tenant_id,p_entity_type,p_entity_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_attach_operation_document_file' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_document_type text, p_file_id uuid, p_note text' AND md5(p.prosrc)=ANY(ARRAY['4b7af11b8ee44f62028664d492bc2e0d','b53af101de7efccfc4192789dd0d3c7f']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_attach_operation_document_file'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_attach_operation_document_file(','FUNCTION private.delivery_core_0c9a577e21ac2e0bb95b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_attach_operation_document_file' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_document_type text, p_file_id uuid, p_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_0c9a577e21ac2e0bb95b(uuid, text, uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_attach_operation_document_file(p_operation_id uuid, p_document_type text, p_file_id uuid, p_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_0c9a577e21ac2e0bb95b(p_operation_id,p_document_type,p_file_id,p_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_0c9a577e21ac2e0bb95b(p_operation_id,p_document_type,p_file_id,p_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_add_operation_file_evidence' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_file_id uuid, p_incident_id uuid, p_note text' AND md5(p.prosrc)=ANY(ARRAY['f7134104b7262f606917735f8fa90e6d','617dd856ab8912d277b4ed5086897a58']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_add_operation_file_evidence'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_add_operation_file_evidence(','FUNCTION private.delivery_core_2c9d91e5d3f4f267b6e8(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_add_operation_file_evidence' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_file_id uuid, p_incident_id uuid, p_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_2c9d91e5d3f4f267b6e8(uuid, uuid, uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_add_operation_file_evidence(p_operation_id uuid, p_file_id uuid, p_incident_id uuid DEFAULT NULL::uuid, p_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_2c9d91e5d3f4f267b6e8(p_operation_id,p_file_id,p_incident_id,p_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_2c9d91e5d3f4f267b6e8(p_operation_id,p_file_id,p_incident_id,p_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_relate_quote_documents_to_operation' AND pg_get_function_identity_arguments(p.oid)='p_quote_id uuid, p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['dc093018e9585d0bb25abb9d81013e5a','10aefdbc84551cddf6c69f37f963b7a0']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_relate_quote_documents_to_operation'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_relate_quote_documents_to_operation(','FUNCTION private.delivery_core_5b55a9108cd2c62e49f0(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_relate_quote_documents_to_operation' AND pg_get_function_identity_arguments(p.oid)='p_quote_id uuid, p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_5b55a9108cd2c62e49f0(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_relate_quote_documents_to_operation(p_quote_id uuid, p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_5b55a9108cd2c62e49f0(p_quote_id,p_operation_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_5b55a9108cd2c62e49f0(p_quote_id,p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_generate_document_f3' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_template_type text, p_entity_type text, p_entity_id uuid, p_options jsonb' AND md5(p.prosrc)=ANY(ARRAY['136d824a3de7e9d0ea87f139d6309d0b','d789e39c6f2b7a3100933210a1788116']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_generate_document_f3'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_generate_document_f3(','FUNCTION private.delivery_core_e7f145b6a9e5126cfe05(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_generate_document_f3' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_template_type text, p_entity_type text, p_entity_id uuid, p_options jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_e7f145b6a9e5126cfe05(uuid, text, text, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_generate_document_f3(p_tenant_id uuid, p_template_type text, p_entity_type text, p_entity_id uuid, p_options jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_e7f145b6a9e5126cfe05(p_tenant_id,p_template_type,p_entity_type,p_entity_id,p_options);
  RETURN result;
 END IF;
 RETURN private.delivery_core_e7f145b6a9e5126cfe05(p_tenant_id,p_template_type,p_entity_type,p_entity_id,p_options);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_generate_document' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_template_type text, p_entity_type text, p_entity_id uuid, p_options jsonb' AND md5(p.prosrc)=ANY(ARRAY['7b2ba0d24c2778c9d7549c9c5ec82af5','7b2ba0d24c2778c9d7549c9c5ec82af5']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_generate_document'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_generate_document(','FUNCTION private.delivery_core_3a191b7c6853fb2b6782(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_generate_document' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_template_type text, p_entity_type text, p_entity_id uuid, p_options jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_3a191b7c6853fb2b6782(uuid, text, text, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_generate_document(p_tenant_id uuid, p_template_type text, p_entity_type text, p_entity_id uuid, p_options jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_3a191b7c6853fb2b6782(p_tenant_id,p_template_type,p_entity_type,p_entity_id,p_options);
  RETURN result;
 END IF;
 RETURN private.delivery_core_3a191b7c6853fb2b6782(p_tenant_id,p_template_type,p_entity_type,p_entity_id,p_options);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_generated_documents' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['8cc08e30461f217a97e0493e86bd7563','ee36891d8630e89a3477e4a7f6badead']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_generated_documents'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_generated_documents(','FUNCTION private.delivery_core_fb7b9392eaa32e992309(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_generated_documents' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_fb7b9392eaa32e992309(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_generated_documents(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_fb7b9392eaa32e992309(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_fb7b9392eaa32e992309(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_cancel_generated_document' AND pg_get_function_identity_arguments(p.oid)='p_document_id uuid, p_reason text' AND md5(p.prosrc)=ANY(ARRAY['89479cbd7acd966742e46d980397146c','a2cb9a9a50646214d4455acc92a57467']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_cancel_generated_document'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_cancel_generated_document(','FUNCTION private.delivery_core_6067062fbbbe54154a7d(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_cancel_generated_document' AND pg_get_function_identity_arguments(p.oid)='p_document_id uuid, p_reason text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_6067062fbbbe54154a7d(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_cancel_generated_document(p_document_id uuid, p_reason text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_6067062fbbbe54154a7d(p_document_id,p_reason);
  RETURN result;
 END IF;
 RETURN private.delivery_core_6067062fbbbe54154a7d(p_document_id,p_reason);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_document_templates_v2' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_template_type text' AND md5(p.prosrc)=ANY(ARRAY['f69f3861d0c016e76802ebb02ef66016','3e8fcc704d6e535565ba8461b68441e1']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_document_templates_v2'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_document_templates_v2(','FUNCTION private.delivery_core_708b1716280fe19d470d(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_document_templates_v2' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_template_type text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_708b1716280fe19d470d(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_document_templates_v2(p_tenant_id uuid, p_template_type text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_708b1716280fe19d470d(p_tenant_id,p_template_type);
  RETURN result;
 END IF;
 RETURN private.delivery_core_708b1716280fe19d470d(p_tenant_id,p_template_type);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_document_source_options' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_template_type text, p_search text' AND md5(p.prosrc)=ANY(ARRAY['69133b84ec357379317722d4b5269433','b9ccd8fed45a36e6a64751b18b5fd590']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_document_source_options'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_document_source_options(','FUNCTION private.delivery_core_4f8a4f61eec06da702d3(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_document_source_options' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_template_type text, p_search text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_4f8a4f61eec06da702d3(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_document_source_options(p_tenant_id uuid, p_template_type text, p_search text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_4f8a4f61eec06da702d3(p_tenant_id,p_template_type,p_search);
  RETURN result;
 END IF;
 RETURN private.delivery_core_4f8a4f61eec06da702d3(p_tenant_id,p_template_type,p_search);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_record_payment' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['c6748e2c192761c59490f64d1a8eaa65','376a4008f98a93779f2785592ac0e1bd']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_record_payment'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_record_payment(uuid, jsonb)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_fd5b2d3deee7fc5681fd(','FUNCTION private.delivery_core_f4e3bac2457a6124984a(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_record_payment(','FUNCTION private.delivery_core_f4e3bac2457a6124984a(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_record_payment' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_f4e3bac2457a6124984a(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_record_payment(','FUNCTION private.delivery_scoped_f4e3bac2457a6124984a('),'private.multi08_legacy_write_target','private.delivery_finance_write_target') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_record_payment' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_f4e3bac2457a6124984a(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_record_payment(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT private.delivery_cap(v_tenant,'finance.write') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_f4e3bac2457a6124984a(p_tenant_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_f4e3bac2457a6124984a(p_tenant_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_finance_invoice_status' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_id uuid, p_status text' AND md5(p.prosrc)=ANY(ARRAY['ef2ee571c92a3e57227c0a6897ce25db','0059c83dcba2ab4b8c5c79e1cff78bad']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_finance_invoice_status'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_update_finance_invoice_status(uuid, uuid, text)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_f83cf610dbfabf29ed18(','FUNCTION private.delivery_core_24e62ca8048cc60b67e7(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_finance_invoice_status(','FUNCTION private.delivery_core_24e62ca8048cc60b67e7(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_update_finance_invoice_status' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_id uuid, p_status text';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_24e62ca8048cc60b67e7(uuid, uuid, text) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_finance_invoice_status(','FUNCTION private.delivery_scoped_24e62ca8048cc60b67e7('),'private.multi08_legacy_write_target','private.delivery_finance_write_target') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_finance_invoice_status' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_id uuid, p_status text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_24e62ca8048cc60b67e7(uuid, uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_finance_invoice_status(p_tenant_id uuid, p_id uuid, p_status text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT private.delivery_cap(v_tenant,'finance.write') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_24e62ca8048cc60b67e7(p_tenant_id,p_id,p_status);
  RETURN result;
 END IF;
 RETURN private.delivery_core_24e62ca8048cc60b67e7(p_tenant_id,p_id,p_status);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_finance_overview' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['2d9f713aadc5163ccc789266ccdad1bc','2d9f713aadc5163ccc789266ccdad1bc']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_finance_overview'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_finance_overview(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_0f5cdbe7304769938a60(','FUNCTION private.delivery_core_ae564bd462f19eda9801(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_finance_overview(','FUNCTION private.delivery_core_ae564bd462f19eda9801(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_finance_overview' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_ae564bd462f19eda9801(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_finance_overview(','FUNCTION private.delivery_scoped_ae564bd462f19eda9801('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_finance_overview' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_ae564bd462f19eda9801(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_finance_overview(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_ae564bd462f19eda9801(p_tenant_id);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_ae564bd462f19eda9801(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_finance_overview' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_start_date text, p_end_date text' AND md5(p.prosrc)=ANY(ARRAY['4b914a4e9e4b2e91b35a36bc40ca619c','4b914a4e9e4b2e91b35a36bc40ca619c']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_finance_overview'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_finance_overview(uuid, text, text)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_acae10bdffc108a8021e(','FUNCTION private.delivery_core_978d3de51a7440111755(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_finance_overview(','FUNCTION private.delivery_core_978d3de51a7440111755(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_finance_overview' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_start_date text, p_end_date text';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_978d3de51a7440111755(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_finance_overview(','FUNCTION private.delivery_scoped_978d3de51a7440111755('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_finance_overview' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_start_date text, p_end_date text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_978d3de51a7440111755(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_finance_overview(p_tenant_id uuid, p_start_date text, p_end_date text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_978d3de51a7440111755(p_tenant_id,p_start_date,p_end_date);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_978d3de51a7440111755(p_tenant_id,p_start_date,p_end_date);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_finance_invoices' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_limit integer, p_status text, p_direction text' AND md5(p.prosrc)=ANY(ARRAY['08e7051322e4146365aa4f6a402058be','4e2965bd8c186d807033f2c525ce9a09']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_finance_invoices'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_finance_invoices(uuid, integer, text, text)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_6238abfee02018c7e71c(','FUNCTION private.delivery_core_d7adec03596a0c40b7d2(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_finance_invoices(','FUNCTION private.delivery_core_d7adec03596a0c40b7d2(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_finance_invoices' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_limit integer, p_status text, p_direction text';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_d7adec03596a0c40b7d2(uuid, integer, text, text) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_finance_invoices(','FUNCTION private.delivery_scoped_d7adec03596a0c40b7d2('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_finance_invoices' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_limit integer, p_status text, p_direction text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_d7adec03596a0c40b7d2(uuid, integer, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_finance_invoices(p_tenant_id uuid, p_limit integer DEFAULT 50, p_status text DEFAULT NULL::text, p_direction text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_d7adec03596a0c40b7d2(p_tenant_id,p_limit,p_status,p_direction);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_d7adec03596a0c40b7d2(p_tenant_id,p_limit,p_status,p_direction);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_finance_invoices' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_limit integer, p_status text, p_direction text, p_start_date text, p_end_date text' AND md5(p.prosrc)=ANY(ARRAY['e749209e2b7f1ea25b388a36df4d6da4','e749209e2b7f1ea25b388a36df4d6da4']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_finance_invoices'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_finance_invoices(uuid, integer, text, text, text, text)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_6c35233d409844bd2e5f(','FUNCTION private.delivery_core_7591cd3936a66f1ae6a1(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_finance_invoices(','FUNCTION private.delivery_core_7591cd3936a66f1ae6a1(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_finance_invoices' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_limit integer, p_status text, p_direction text, p_start_date text, p_end_date text';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_7591cd3936a66f1ae6a1(uuid, integer, text, text, text, text) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_finance_invoices(','FUNCTION private.delivery_scoped_7591cd3936a66f1ae6a1('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_finance_invoices' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_limit integer, p_status text, p_direction text, p_start_date text, p_end_date text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_7591cd3936a66f1ae6a1(uuid, integer, text, text, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_finance_invoices(p_tenant_id uuid, p_limit integer, p_status text, p_direction text, p_start_date text, p_end_date text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_7591cd3936a66f1ae6a1(p_tenant_id,p_limit,p_status,p_direction,p_start_date,p_end_date);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_7591cd3936a66f1ae6a1(p_tenant_id,p_limit,p_status,p_direction,p_start_date,p_end_date);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_finance_overview' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['65505458bb84307a2a395f80bc164079','a786751826cecd362546377fe842ee9f']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_finance_overview'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_finance_overview(uuid, jsonb)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_24ba61a1e61e9243be5d(','FUNCTION private.delivery_core_2142fee53e757639dfdc(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_finance_overview(','FUNCTION private.delivery_core_2142fee53e757639dfdc(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_finance_overview' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_2142fee53e757639dfdc(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_finance_overview(','FUNCTION private.delivery_scoped_2142fee53e757639dfdc('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_finance_overview' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_2142fee53e757639dfdc(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_finance_overview(p_tenant_id uuid, p_filters jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_2142fee53e757639dfdc(p_tenant_id,p_filters);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_2142fee53e757639dfdc(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_finance_due_alerts' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_days_ahead integer' AND md5(p.prosrc)=ANY(ARRAY['ab3101a05bb0e52120e937884385a110','ab3101a05bb0e52120e937884385a110']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_finance_due_alerts'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_finance_due_alerts(uuid, integer)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_a7ef8bdbe93b791e629b(','FUNCTION private.delivery_core_df5cb9025787e0330ea5(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_finance_due_alerts(','FUNCTION private.delivery_core_df5cb9025787e0330ea5(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_finance_due_alerts' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_days_ahead integer';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_df5cb9025787e0330ea5(uuid, integer) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_finance_due_alerts(','FUNCTION private.delivery_scoped_df5cb9025787e0330ea5('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_finance_due_alerts' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_days_ahead integer';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_df5cb9025787e0330ea5(uuid, integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_finance_due_alerts(p_tenant_id uuid, p_days_ahead integer DEFAULT 7) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_df5cb9025787e0330ea5(p_tenant_id,p_days_ahead);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_df5cb9025787e0330ea5(p_tenant_id,p_days_ahead);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_export_finance_ledger' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_date_from text, p_date_to text' AND md5(p.prosrc)=ANY(ARRAY['6abfe982012e9642a0fb94a946662df1','6abfe982012e9642a0fb94a946662df1']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_export_finance_ledger'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_export_finance_ledger(uuid, text, text)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_a5202792c4751dd479e8(','FUNCTION private.delivery_core_b74ef824003f046eadff(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_export_finance_ledger(','FUNCTION private.delivery_core_b74ef824003f046eadff(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_export_finance_ledger' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_date_from text, p_date_to text';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_b74ef824003f046eadff(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_export_finance_ledger(','FUNCTION private.delivery_scoped_b74ef824003f046eadff('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_export_finance_ledger' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_date_from text, p_date_to text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_b74ef824003f046eadff(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_export_finance_ledger(p_tenant_id uuid, p_date_from text, p_date_to text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT private.delivery_cap(v_tenant,'export.financial') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_b74ef824003f046eadff(p_tenant_id,p_date_from,p_date_to);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_b74ef824003f046eadff(p_tenant_id,p_date_from,p_date_to);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_export_finance_ledger' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['27b183b95c534c80f13b6bc8754e3553','c00b0c1e4111d3b909f209cacacff046']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_export_finance_ledger'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_export_finance_ledger(uuid, jsonb)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_375044b33c2d038a037e(','FUNCTION private.delivery_core_50de00ba1ada0feccd41(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_export_finance_ledger(','FUNCTION private.delivery_core_50de00ba1ada0feccd41(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_export_finance_ledger' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_50de00ba1ada0feccd41(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_export_finance_ledger(','FUNCTION private.delivery_scoped_50de00ba1ada0feccd41('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_export_finance_ledger' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_50de00ba1ada0feccd41(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_export_finance_ledger(p_tenant_id uuid, p_filters jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT private.delivery_cap(v_tenant,'export.financial') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_50de00ba1ada0feccd41(p_tenant_id,p_filters);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_50de00ba1ada0feccd41(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_attention_items' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['598640c67ef5e55ee98945cb4146b54b','a064a5e6d016d65bb9372d08e7ba4648']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_attention_items'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_attention_items(','FUNCTION private.delivery_core_99980daa3ea019d9cb13(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_attention_items' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_99980daa3ea019d9cb13(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_attention_items(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_99980daa3ea019d9cb13(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_99980daa3ea019d9cb13(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_refresh_internal_notifications' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['2da5f15fc69c82b9ba2e48eaf0deb182','9c84dd2b01f531fe531c1a55e0b687f1']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_refresh_internal_notifications'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_refresh_internal_notifications(','FUNCTION private.delivery_core_ed7b960ca3503ca9ee63(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_refresh_internal_notifications' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_ed7b960ca3503ca9ee63(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_refresh_internal_notifications(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_ed7b960ca3503ca9ee63(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_ed7b960ca3503ca9ee63(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_internal_notification_unread_count' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['e07b9cab3806011e90141156dc09bca4','70e0e6991882d2c79a84703b904a0919']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_internal_notification_unread_count'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_internal_notification_unread_count(','FUNCTION private.delivery_core_b7444f4cf857431b7470(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_internal_notification_unread_count' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_b7444f4cf857431b7470(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_internal_notification_unread_count(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_b7444f4cf857431b7470(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_b7444f4cf857431b7470(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_executive_dashboard' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone' AND md5(p.prosrc)=ANY(ARRAY['bd60a21518d3dc4a3ef5e10cdb85d019','1e79d21b3d06ae0194b1122025f2b2e0']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_executive_dashboard'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_executive_dashboard(','FUNCTION private.delivery_core_d7007371b8152ebb1640(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_executive_dashboard' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_d7007371b8152ebb1640(uuid, timestamp with time zone, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_executive_dashboard(p_tenant_id uuid, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_d7007371b8152ebb1640(p_tenant_id,p_start_date,p_end_date);
  RETURN result;
 END IF;
 RETURN private.delivery_core_d7007371b8152ebb1640(p_tenant_id,p_start_date,p_end_date);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_mark_internal_notifications_read' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_notification_ids uuid[]' AND md5(p.prosrc)=ANY(ARRAY['8981f1e0189df669c46cd00577e1432e','364bca98b4425b17b2474694b2acdd0b']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_mark_internal_notifications_read'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_mark_internal_notifications_read(','FUNCTION private.delivery_core_f5874c58b13d035ecf90(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_mark_internal_notifications_read' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_notification_ids uuid[]';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_f5874c58b13d035ecf90(uuid, uuid[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_mark_internal_notifications_read(p_tenant_id uuid, p_notification_ids uuid[] DEFAULT NULL::uuid[]) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_f5874c58b13d035ecf90(p_tenant_id,p_notification_ids);
  RETURN result;
 END IF;
 RETURN private.delivery_core_f5874c58b13d035ecf90(p_tenant_id,p_notification_ids);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_dismiss_internal_notification' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_notification_id uuid' AND md5(p.prosrc)=ANY(ARRAY['583e6d97e932abd556559fa9c77eadec','12cf4f078c5c7b2dc9907c624d04866b']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_dismiss_internal_notification'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_dismiss_internal_notification(','FUNCTION private.delivery_core_7926bd21b3d482071165(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_dismiss_internal_notification' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_notification_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_7926bd21b3d482071165(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_dismiss_internal_notification(p_tenant_id uuid, p_notification_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_7926bd21b3d482071165(p_tenant_id,p_notification_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_7926bd21b3d482071165(p_tenant_id,p_notification_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_dismiss_internal_notification' AND pg_get_function_identity_arguments(p.oid)='p_notification_id uuid' AND md5(p.prosrc)=ANY(ARRAY['ceb887fa22bf348a619f5f17985dc4c2','7f275b3eb5aaebc4101ba5446d0ec397']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_dismiss_internal_notification'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_dismiss_internal_notification(','FUNCTION private.delivery_core_4cc59667551672ee7d26(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_dismiss_internal_notification' AND pg_get_function_identity_arguments(p.oid)='p_notification_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_4cc59667551672ee7d26(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_dismiss_internal_notification(p_notification_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_4cc59667551672ee7d26(p_notification_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_4cc59667551672ee7d26(p_notification_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_saved_views' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_module text' AND md5(p.prosrc)=ANY(ARRAY['2ba91cc4fded6d1c87f9ec1b0ee3c426','92cf4735380bf39c5bd1f3a14b134913']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_saved_views'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_saved_views(','FUNCTION private.delivery_core_3a1ff1406ba6c4393d53(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_saved_views' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_module text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_3a1ff1406ba6c4393d53(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_saved_views(p_tenant_id uuid, p_module text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_3a1ff1406ba6c4393d53(p_tenant_id,p_module);
  RETURN result;
 END IF;
 RETURN private.delivery_core_3a1ff1406ba6c4393d53(p_tenant_id,p_module);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_save_view' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['25f558e01daf64ee434a13803b65a0ad','21895e3a418fc07e8dcdad0c02732ce1']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_save_view'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_save_view(','FUNCTION private.delivery_core_275338a2c2f3e3ef3263(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_save_view' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_275338a2c2f3e3ef3263(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_save_view(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_275338a2c2f3e3ef3263(p_tenant_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_275338a2c2f3e3ef3263(p_tenant_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_delete_saved_view' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_view_id uuid' AND md5(p.prosrc)=ANY(ARRAY['543471f9ecf20e0a75f9405ef725ceb4','91cdfbd3360cc77a7e0a4d7dd742a8b2']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_delete_saved_view'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_delete_saved_view(','FUNCTION private.delivery_core_37dddcc4812e991b0853(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_delete_saved_view' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_view_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_37dddcc4812e991b0853(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_delete_saved_view(p_tenant_id uuid, p_view_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_37dddcc4812e991b0853(p_tenant_id,p_view_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_37dddcc4812e991b0853(p_tenant_id,p_view_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_global_search' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_query text, p_limit integer' AND md5(p.prosrc)=ANY(ARRAY['5397fd4bbff25bf7244f2cf25a46c76c','368396e3d6c67caa53961017cf09afd5']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_global_search'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_global_search(','FUNCTION private.delivery_core_17b2673af825acb128cf(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_global_search' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_query text, p_limit integer';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_17b2673af825acb128cf(uuid, text, integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_global_search(p_tenant_id uuid, p_query text, p_limit integer DEFAULT 5) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_17b2673af825acb128cf(p_tenant_id,p_query,p_limit);
  RETURN result;
 END IF;
 RETURN private.delivery_core_17b2673af825acb128cf(p_tenant_id,p_query,p_limit);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_validate_bulk_import' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text, p_mode text, p_rows jsonb' AND md5(p.prosrc)=ANY(ARRAY['9472bda57cfd22309c8d9d011c3f2524','92943a12caab7438edc007ef2591559a']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_validate_bulk_import'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_validate_bulk_import(','FUNCTION private.delivery_core_9225764ece71261ba911(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_validate_bulk_import' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text, p_mode text, p_rows jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_9225764ece71261ba911(uuid, text, text, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_validate_bulk_import(p_tenant_id uuid, p_entity_type text, p_mode text, p_rows jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_9225764ece71261ba911(p_tenant_id,p_entity_type,p_mode,p_rows);
  RETURN result;
 END IF;
 RETURN private.delivery_core_9225764ece71261ba911(p_tenant_id,p_entity_type,p_mode,p_rows);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_start_bulk_import' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text, p_filename text, p_mode text, p_idempotency_key text, p_total_rows integer, p_validation_summary jsonb' AND md5(p.prosrc)=ANY(ARRAY['a89a2fe2b9ec8245e00fb5134d24a636','ab1ad5afba5db3aed516f19cc76c7803']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_start_bulk_import'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_start_bulk_import(','FUNCTION private.delivery_core_b64b8f298670b160da29(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_start_bulk_import' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text, p_filename text, p_mode text, p_idempotency_key text, p_total_rows integer, p_validation_summary jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_b64b8f298670b160da29(uuid, text, text, text, text, integer, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_start_bulk_import(p_tenant_id uuid, p_entity_type text, p_filename text, p_mode text, p_idempotency_key text, p_total_rows integer, p_validation_summary jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_b64b8f298670b160da29(p_tenant_id,p_entity_type,p_filename,p_mode,p_idempotency_key,p_total_rows,p_validation_summary);
  RETURN result;
 END IF;
 RETURN private.delivery_core_b64b8f298670b160da29(p_tenant_id,p_entity_type,p_filename,p_mode,p_idempotency_key,p_total_rows,p_validation_summary);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_import_batches' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_limit integer' AND md5(p.prosrc)=ANY(ARRAY['15ba53b26959764e0bddd6b948f29e82','d4e54cc170702dfb77dd801af2fa691a']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_import_batches'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_import_batches(','FUNCTION private.delivery_core_201191be240a0d5600df(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_import_batches' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_limit integer';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_201191be240a0d5600df(uuid, integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_import_batches(p_tenant_id uuid, p_limit integer DEFAULT 50) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_201191be240a0d5600df(p_tenant_id,p_limit);
  RETURN result;
 END IF;
 RETURN private.delivery_core_201191be240a0d5600df(p_tenant_id,p_limit);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_apply_bulk_import' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_batch_id uuid, p_chunk_key text, p_rows jsonb, p_is_last boolean' AND md5(p.prosrc)=ANY(ARRAY['3d08f1a151d706ea2ee8c2fb1a25121c','3217c91ea9ac82b0cd57428505c01693']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_apply_bulk_import'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_apply_bulk_import(','FUNCTION private.delivery_core_e05aa62a31ef6c503e09(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_apply_bulk_import' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_batch_id uuid, p_chunk_key text, p_rows jsonb, p_is_last boolean';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_e05aa62a31ef6c503e09(uuid, uuid, text, jsonb, boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_apply_bulk_import(p_tenant_id uuid, p_batch_id uuid, p_chunk_key text, p_rows jsonb, p_is_last boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_e05aa62a31ef6c503e09(p_tenant_id,p_batch_id,p_chunk_key,p_rows,p_is_last);
  RETURN result;
 END IF;
 RETURN private.delivery_core_e05aa62a31ef6c503e09(p_tenant_id,p_batch_id,p_chunk_key,p_rows,p_is_last);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_internal_notifications' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_limit integer, p_unread_only boolean' AND md5(p.prosrc)=ANY(ARRAY['e4379b91d61b7d54bac0e490a1b4ef73','993d0328fa9c0bf26469d758ac38af90']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_internal_notifications'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_internal_notifications(','FUNCTION private.delivery_core_82761934cd22219e8931(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_internal_notifications' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_limit integer, p_unread_only boolean';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_82761934cd22219e8931(uuid, integer, boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_internal_notifications(p_tenant_id uuid, p_limit integer DEFAULT 50, p_unread_only boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_82761934cd22219e8931(p_tenant_id,p_limit,p_unread_only);
  RETURN result;
 END IF;
 RETURN private.delivery_core_82761934cd22219e8931(p_tenant_id,p_limit,p_unread_only);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_automation_rules' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['c4ef7051519c0a08241daecb5a566729','2a2352809895227da4808e227076e3d3']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_automation_rules'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_automation_rules(','FUNCTION private.delivery_core_7d58ecc1bc78ef5231aa(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_automation_rules' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_7d58ecc1bc78ef5231aa(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_automation_rules(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_7d58ecc1bc78ef5231aa(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_7d58ecc1bc78ef5231aa(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_automation_rule' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_rule_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['f786217fef098ae972733a0eab6a5386','962f1e2fc376bb137a119470a5a4a665']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_automation_rule'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_automation_rule(','FUNCTION private.delivery_core_50b5933d9d2263fe491f(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_automation_rule' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_rule_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_50b5933d9d2263fe491f(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_automation_rule(p_tenant_id uuid, p_rule_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_50b5933d9d2263fe491f(p_tenant_id,p_rule_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_50b5933d9d2263fe491f(p_tenant_id,p_rule_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_evaluate_automations' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['2934cedabdacb11cf07588435ed784e9','6f002a76f185382394ad46442df0bfe8']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_evaluate_automations'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_evaluate_automations(','FUNCTION private.delivery_core_a3edde69415d90eb9f8d(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_evaluate_automations' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_a3edde69415d90eb9f8d(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_evaluate_automations(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_a3edde69415d90eb9f8d(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_a3edde69415d90eb9f8d(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_automation_health' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['77242be52dd6bf94de5230b58028af86','d522ca930963cd3e8c62bc8ea230a27f']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_automation_health'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_automation_health(','FUNCTION private.delivery_core_2c7f5d36082b45014063(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_automation_health' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_2c7f5d36082b45014063(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_automation_health(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_2c7f5d36082b45014063(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_2c7f5d36082b45014063(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_daily_digest' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['69fabec9c3205ab21a7b1065585ef5ab','c8ab6a42860c1e71096dd2487ad6244c']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_daily_digest'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_daily_digest(','FUNCTION private.delivery_core_eb0f4e8c0100219426a7(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_daily_digest' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_eb0f4e8c0100219426a7(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_daily_digest(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_eb0f4e8c0100219426a7(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_eb0f4e8c0100219426a7(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_rate' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['4c41b7f5980a7a4b0cad6e98dbcf93ee','55bb402674843fae73ee5ef0fde4d26f']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_rate'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_rate(','FUNCTION private.delivery_core_f55e24e4134c53794297(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_rate' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_f55e24e4134c53794297(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_rate(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_f55e24e4134c53794297(p_tenant_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_f55e24e4134c53794297(p_tenant_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_rate_reference_data' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['535dcc153d064bf9db1c73ba68f41edf','64a4ae0a908c37bda9a5a286d24b4d64']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_rate_reference_data'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_rate_reference_data(','FUNCTION private.delivery_core_236c20dd0c5e365e1161(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_rate_reference_data' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_236c20dd0c5e365e1161(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_rate_reference_data(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_236c20dd0c5e365e1161(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_236c20dd0c5e365e1161(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_upsert_lane' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_lane_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['241f816515979082e4c85d2565c09079','530b94ddfd231c6922e4b30362753423']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_upsert_lane'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_upsert_lane(','FUNCTION private.delivery_core_8c3fd1884c701b9183e4(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_upsert_lane' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_lane_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_8c3fd1884c701b9183e4(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_upsert_lane(p_tenant_id uuid, p_lane_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_8c3fd1884c701b9183e4(p_tenant_id,p_lane_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_8c3fd1884c701b9183e4(p_tenant_id,p_lane_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_rate_version' AND pg_get_function_identity_arguments(p.oid)='p_rate_card_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['0eae8b15355095e89b680db6e9ad1e9c','50985cb6adbc180a34852b3c40292bf2']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_rate_version'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_rate_version(','FUNCTION private.delivery_core_32d725cc9702f5ca3a3b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_rate_version' AND pg_get_function_identity_arguments(p.oid)='p_rate_card_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_32d725cc9702f5ca3a3b(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_rate_version(p_rate_card_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_32d725cc9702f5ca3a3b(p_rate_card_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_32d725cc9702f5ca3a3b(p_rate_card_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_rates' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['b52f1fd645cef40202d0c61b746edcf0','66ffc88f282a0a5b0bc08077595dabb2']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_rates'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_rates(','FUNCTION private.delivery_core_6fd601b2e169ac0df7d6(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_rates' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_6fd601b2e169ac0df7d6(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_rates(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_6fd601b2e169ac0df7d6(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_6fd601b2e169ac0df7d6(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_compare_provider_rates' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['7306d070f3385c586b102304612a9ffd','8e7745d20d70ff5a79546ff54ce9cc2f']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_compare_provider_rates'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_compare_provider_rates(','FUNCTION private.delivery_core_ab585d7421d3de0c2025(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_compare_provider_rates' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_ab585d7421d3de0c2025(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_compare_provider_rates(p_tenant_id uuid, p_filters jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_ab585d7421d3de0c2025(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_ab585d7421d3de0c2025(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_apply_rate_to_quote' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_rate_version_id uuid' AND md5(p.prosrc)=ANY(ARRAY['241f2205442aed289e617e7071c493e6','1b718cbdc45455c6aa7e798a5bd7d7ff']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_apply_rate_to_quote'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_apply_rate_to_quote(','FUNCTION private.delivery_core_5bbe3ad9eb3b49c18f8a(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_apply_rate_to_quote' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_rate_version_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_5bbe3ad9eb3b49c18f8a(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_apply_rate_to_quote(p_deal_id uuid, p_rate_version_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_5bbe3ad9eb3b49c18f8a(p_deal_id,p_rate_version_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_5bbe3ad9eb3b49c18f8a(p_deal_id,p_rate_version_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_archive_rate' AND pg_get_function_identity_arguments(p.oid)='p_rate_card_id uuid' AND md5(p.prosrc)=ANY(ARRAY['8f5fb9744b67160ee7cfbe70fdcd27d7','6f1aa6b15fe8f7d9c1322a3479889131']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_archive_rate'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_archive_rate(','FUNCTION private.delivery_core_d2acb9d02350059503fb(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_archive_rate' AND pg_get_function_identity_arguments(p.oid)='p_rate_card_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_d2acb9d02350059503fb(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_archive_rate(p_rate_card_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_d2acb9d02350059503fb(p_rate_card_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_d2acb9d02350059503fb(p_rate_card_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_duplicate_rate' AND pg_get_function_identity_arguments(p.oid)='p_rate_card_id uuid' AND md5(p.prosrc)=ANY(ARRAY['3cda0ea198616bb183fa59b5ef1c01c3','3349cc2eb55f586e8535aae9542f9686']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_duplicate_rate'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_duplicate_rate(','FUNCTION private.delivery_core_a9e51d337a515d5b890a(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_duplicate_rate' AND pg_get_function_identity_arguments(p.oid)='p_rate_card_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_a9e51d337a515d5b890a(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_duplicate_rate(p_rate_card_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_a9e51d337a515d5b890a(p_rate_card_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_a9e51d337a515d5b890a(p_rate_card_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_partner_contacts' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text, p_entity_id uuid' AND md5(p.prosrc)=ANY(ARRAY['22a87213e60420f3143f774e96702e2f','9d643af99cab144e34a039fb69f347d0']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_partner_contacts'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_partner_contacts(','FUNCTION private.delivery_core_fb0e61256f7bc8454262(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_partner_contacts' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text, p_entity_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_fb0e61256f7bc8454262(uuid, text, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_partner_contacts(p_tenant_id uuid, p_entity_type text, p_entity_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_fb0e61256f7bc8454262(p_tenant_id,p_entity_type,p_entity_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_fb0e61256f7bc8454262(p_tenant_id,p_entity_type,p_entity_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_partner_terms' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_payment_terms_days integer' AND md5(p.prosrc)=ANY(ARRAY['7103a5bcd699ee6d1a4faeb864276aa2','da049cef72077acb8ea6656a98272395']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_partner_terms'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_partner_terms(','FUNCTION private.delivery_core_afb6210914e417a9dfe0(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_partner_terms' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_payment_terms_days integer';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_afb6210914e417a9dfe0(uuid, text, uuid, integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_partner_terms(p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_payment_terms_days integer) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_afb6210914e417a9dfe0(p_tenant_id,p_entity_type,p_entity_id,p_payment_terms_days);
  RETURN result;
 END IF;
 RETURN private.delivery_core_afb6210914e417a9dfe0(p_tenant_id,p_entity_type,p_entity_id,p_payment_terms_days);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_export_rates' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['b51d26b7e16e2bddcc95377094c586d0','cebed0db2ed196d342871ed9b27fdbbc']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_export_rates'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_export_rates(','FUNCTION private.delivery_core_5335a16ed0071dd66a76(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_export_rates' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_5335a16ed0071dd66a76(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_export_rates(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_5335a16ed0071dd66a76(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_5335a16ed0071dd66a76(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_partner_compliance_status' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_partner_type text, p_partner_id uuid, p_as_of date' AND md5(p.prosrc)=ANY(ARRAY['4a6103150fd1c702df54e5496d5effed','4a6103150fd1c702df54e5496d5effed']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_partner_compliance_status'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_partner_compliance_status(','FUNCTION private.delivery_core_621cc45a41a6177f448c(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_partner_compliance_status' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_partner_type text, p_partner_id uuid, p_as_of date';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_621cc45a41a6177f448c(uuid, text, uuid, date) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_partner_compliance_status(p_tenant_id uuid, p_partner_type text, p_partner_id uuid, p_as_of date DEFAULT CURRENT_DATE) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_621cc45a41a6177f448c(p_tenant_id,p_partner_type,p_partner_id,p_as_of);
  RETURN result;
 END IF;
 RETURN private.delivery_core_621cc45a41a6177f448c(p_tenant_id,p_partner_type,p_partner_id,p_as_of);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_compliance_requirements' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['e8cb0c755fde40629728a75bb5985310','f3e74a9dd11c21889bc04bfdb3a67e06']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_compliance_requirements'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_compliance_requirements(','FUNCTION private.delivery_core_86ae0bf8895a88d48020(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_compliance_requirements' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_86ae0bf8895a88d48020(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_compliance_requirements(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_86ae0bf8895a88d48020(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_86ae0bf8895a88d48020(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_upsert_compliance_requirement' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_requirement_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['4138b696ed8b84c128eafc3d4e995221','6c47e27371b47e011301f941a5e645e4']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_upsert_compliance_requirement'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_upsert_compliance_requirement(','FUNCTION private.delivery_core_5021b291833bcb3d22ac(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_upsert_compliance_requirement' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_requirement_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_5021b291833bcb3d22ac(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_upsert_compliance_requirement(p_tenant_id uuid, p_requirement_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_5021b291833bcb3d22ac(p_tenant_id,p_requirement_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_5021b291833bcb3d22ac(p_tenant_id,p_requirement_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_archive_compliance_requirement' AND pg_get_function_identity_arguments(p.oid)='p_requirement_id uuid' AND md5(p.prosrc)=ANY(ARRAY['86f137a9e5596b46a52f8e611b206e9c','efca4ab82ebf9ba7656c53f2bf08fc60']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_archive_compliance_requirement'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_archive_compliance_requirement(','FUNCTION private.delivery_core_8065e0df39631792c4f0(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_archive_compliance_requirement' AND pg_get_function_identity_arguments(p.oid)='p_requirement_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_8065e0df39631792c4f0(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_archive_compliance_requirement(p_requirement_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_8065e0df39631792c4f0(p_requirement_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_8065e0df39631792c4f0(p_requirement_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_submit_partner_compliance_record' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['5c4879704e0945e08fa495f8bf875823','e4dee4f6ab0d46632d9cddc95b41a62c']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_submit_partner_compliance_record'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_submit_partner_compliance_record(','FUNCTION private.delivery_core_e5c9e220500b08424d2b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_submit_partner_compliance_record' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_e5c9e220500b08424d2b(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_submit_partner_compliance_record(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_e5c9e220500b08424d2b(p_tenant_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_e5c9e220500b08424d2b(p_tenant_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_refresh_compliance_notifications' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['e08e620dd31e215ceace3defedecc68b','e08e620dd31e215ceace3defedecc68b']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_refresh_compliance_notifications'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_refresh_compliance_notifications(','FUNCTION private.delivery_core_7a6c8f738696609384e8(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_refresh_compliance_notifications' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_7a6c8f738696609384e8(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_refresh_compliance_notifications(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_7a6c8f738696609384e8(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_7a6c8f738696609384e8(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_review_partner_compliance_record' AND pg_get_function_identity_arguments(p.oid)='p_record_id uuid, p_decision text, p_note text' AND md5(p.prosrc)=ANY(ARRAY['ee92d879fd7e63c54aeb91f10d9e9471','879191ce24d74bb8d6330cc0b9ee00bc']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_review_partner_compliance_record'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_review_partner_compliance_record(','FUNCTION private.delivery_core_a11c27c21a43f9153866(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_review_partner_compliance_record' AND pg_get_function_identity_arguments(p.oid)='p_record_id uuid, p_decision text, p_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_a11c27c21a43f9153866(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_review_partner_compliance_record(p_record_id uuid, p_decision text, p_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_a11c27c21a43f9153866(p_record_id,p_decision,p_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_a11c27c21a43f9153866(p_record_id,p_decision,p_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_waive_partner_requirement' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['703c13e44bafd909d599ce3da13952f3','4fb4d81f096206ce996d9cbc759f81f7']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_waive_partner_requirement'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_waive_partner_requirement(','FUNCTION private.delivery_core_8fa1c3fc4ee2bb175d58(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_waive_partner_requirement' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_8fa1c3fc4ee2bb175d58(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_waive_partner_requirement(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_8fa1c3fc4ee2bb175d58(p_tenant_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_8fa1c3fc4ee2bb175d58(p_tenant_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_provider_operational_eligibility' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_provider_id uuid' AND md5(p.prosrc)=ANY(ARRAY['314e99d84260b27b3b7fa4d1be088c6e','67672c408920ebdcfc4df829053a7090']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_provider_operational_eligibility'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_provider_operational_eligibility(','FUNCTION private.delivery_core_3b2db0f7dd6e49d23b03(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_provider_operational_eligibility' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_provider_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_3b2db0f7dd6e49d23b03(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_provider_operational_eligibility(p_tenant_id uuid, p_provider_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_3b2db0f7dd6e49d23b03(p_tenant_id,p_provider_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_3b2db0f7dd6e49d23b03(p_tenant_id,p_provider_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_upsert_partner_contract' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_contract_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['3ec3a20742848809392c3f31dacba0ce','0c18736ea4b8bc1a86e3b480658b66c2']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_upsert_partner_contract'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_upsert_partner_contract(','FUNCTION private.delivery_core_e8d0924741d52a76d510(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_upsert_partner_contract' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_contract_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_e8d0924741d52a76d510(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_upsert_partner_contract(p_tenant_id uuid, p_contract_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_e8d0924741d52a76d510(p_tenant_id,p_contract_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_e8d0924741d52a76d510(p_tenant_id,p_contract_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_activate_partner_contract' AND pg_get_function_identity_arguments(p.oid)='p_contract_id uuid' AND md5(p.prosrc)=ANY(ARRAY['15a494b4f396e50839dcc822b97f7ee3','295f4f4c73e027993be15f4b5d6d7a33']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_activate_partner_contract'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_activate_partner_contract(','FUNCTION private.delivery_core_06de895be9869be74399(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_activate_partner_contract' AND pg_get_function_identity_arguments(p.oid)='p_contract_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_06de895be9869be74399(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_activate_partner_contract(p_contract_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_06de895be9869be74399(p_contract_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_06de895be9869be74399(p_contract_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_renew_partner_contract' AND pg_get_function_identity_arguments(p.oid)='p_contract_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['aa9f954154190a325b2df32a5eb2d24b','75d888b33c08d6aa15a25dafb5d85a92']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_renew_partner_contract'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_renew_partner_contract(','FUNCTION private.delivery_core_9c7cd019f9593fa4fab4(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_renew_partner_contract' AND pg_get_function_identity_arguments(p.oid)='p_contract_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_9c7cd019f9593fa4fab4(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_renew_partner_contract(p_contract_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_9c7cd019f9593fa4fab4(p_contract_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_9c7cd019f9593fa4fab4(p_contract_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_terminate_partner_contract' AND pg_get_function_identity_arguments(p.oid)='p_contract_id uuid, p_reason text' AND md5(p.prosrc)=ANY(ARRAY['ac6d79673a564810f7d2dec72eafba93','8a13dc34293673a28cafd1c923eafc8c']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_terminate_partner_contract'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_terminate_partner_contract(','FUNCTION private.delivery_core_edc13dabd7019c27571b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_terminate_partner_contract' AND pg_get_function_identity_arguments(p.oid)='p_contract_id uuid, p_reason text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_edc13dabd7019c27571b(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_terminate_partner_contract(p_contract_id uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_edc13dabd7019c27571b(p_contract_id,p_reason);
  RETURN result;
 END IF;
 RETURN private.delivery_core_edc13dabd7019c27571b(p_contract_id,p_reason);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_compliance_matrix' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['a3e1f3d2524dabb9593a1ce6556d8eb3','b1f82e8e8ee338b642ac435279c11610']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_compliance_matrix'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_compliance_matrix(','FUNCTION private.delivery_core_3470e7e3fc95995331f1(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_compliance_matrix' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_3470e7e3fc95995331f1(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_compliance_matrix(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_3470e7e3fc95995331f1(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_3470e7e3fc95995331f1(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_compliance_expirations' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_days integer' AND md5(p.prosrc)=ANY(ARRAY['05583e4bcd4f0fbdd19007848b3b6473','cdef2a9f82a4941f98b531bbd04f3e28']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_compliance_expirations'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_compliance_expirations(','FUNCTION private.delivery_core_82cc4d83f389b2c110ca(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_compliance_expirations' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_days integer';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_82cc4d83f389b2c110ca(uuid, integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_compliance_expirations(p_tenant_id uuid, p_days integer DEFAULT 30) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_82cc4d83f389b2c110ca(p_tenant_id,p_days);
  RETURN result;
 END IF;
 RETURN private.delivery_core_82cc4d83f389b2c110ca(p_tenant_id,p_days);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_provider_compliance_badges' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_provider_ids uuid[]' AND md5(p.prosrc)=ANY(ARRAY['749f9dacd67122e914b7cef4759c6ba8','482dc0a078bd0663701413439b512c24']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_provider_compliance_badges'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_provider_compliance_badges(','FUNCTION private.delivery_core_546bcf3724256af617e3(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_provider_compliance_badges' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_provider_ids uuid[]';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_546bcf3724256af617e3(uuid, uuid[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_provider_compliance_badges(p_tenant_id uuid, p_provider_ids uuid[]) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_546bcf3724256af617e3(p_tenant_id,p_provider_ids);
  RETURN result;
 END IF;
 RETURN private.delivery_core_546bcf3724256af617e3(p_tenant_id,p_provider_ids);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_compliance_dashboard' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['03435760357e0ae4dd14ddf8b21cdec2','34eb1b6f9ef5dac2d9e0988248b95eec']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_compliance_dashboard'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_compliance_dashboard(','FUNCTION private.delivery_core_3b9e29eb0e4ad3e207ef(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_compliance_dashboard' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_3b9e29eb0e4ad3e207ef(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_compliance_dashboard(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_3b9e29eb0e4ad3e207ef(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_3b9e29eb0e4ad3e207ef(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_compliance_attention_items' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['461556bb28c6904ac9a31226f52c34d4','a647fa0831e76e66050eb3476063ead9']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_compliance_attention_items'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_compliance_attention_items(','FUNCTION private.delivery_core_262d88c87aa4fd5c419c(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_compliance_attention_items' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_262d88c87aa4fd5c419c(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_compliance_attention_items(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_262d88c87aa4fd5c419c(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_262d88c87aa4fd5c419c(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_search_compliance' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_query text, p_limit integer' AND md5(p.prosrc)=ANY(ARRAY['38825799aadfc4896cee82893bbb1a49','900b09b1d4b361929ea37a0566ef2583']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_search_compliance'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_search_compliance(','FUNCTION private.delivery_core_84c1fae6b942a2bb80e6(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_search_compliance' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_query text, p_limit integer';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_84c1fae6b942a2bb80e6(uuid, text, integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_search_compliance(p_tenant_id uuid, p_query text, p_limit integer DEFAULT 10) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_84c1fae6b942a2bb80e6(p_tenant_id,p_query,p_limit);
  RETURN result;
 END IF;
 RETURN private.delivery_core_84c1fae6b942a2bb80e6(p_tenant_id,p_query,p_limit);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_export_partner_compliance' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['9d8c527083e0dd35898c67542d06499e','a7e244e3bc05148b7fe10277bcb71d0c']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_export_partner_compliance'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_export_partner_compliance(','FUNCTION private.delivery_core_dcf1812b4d53f50109cc(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_export_partner_compliance' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_dcf1812b4d53f50109cc(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_export_partner_compliance(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_dcf1812b4d53f50109cc(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_dcf1812b4d53f50109cc(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_provider_compliance_override' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_provider_id uuid, p_reason text' AND md5(p.prosrc)=ANY(ARRAY['678477bd6ec75b2662e4bacc4cb7ac17','800366bf764e705e1a2d1c0d05fd9000']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_provider_compliance_override'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_provider_compliance_override(','FUNCTION private.delivery_core_ebde3aaa7dd9d7f01b99(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_provider_compliance_override' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid, p_provider_id uuid, p_reason text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_ebde3aaa7dd9d7f01b99(uuid, uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_provider_compliance_override(p_operation_id uuid, p_provider_id uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_ebde3aaa7dd9d7f01b99(p_operation_id,p_provider_id,p_reason);
  RETURN result;
 END IF;
 RETURN private.delivery_core_ebde3aaa7dd9d7f01b99(p_operation_id,p_provider_id,p_reason);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_operation_dispatch_readiness' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['be6787fc7e72d4685e9752c1bfa0f321','6fb80644e5b4dbf6966387e35d06dda3']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_operation_dispatch_readiness'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_get_operation_dispatch_readiness(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_02b05fbd48f6dc0fe196(','FUNCTION private.delivery_core_85581b1c8d7c2f9fb17b(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation_dispatch_readiness(','FUNCTION private.delivery_core_85581b1c8d7c2f9fb17b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_get_operation_dispatch_readiness' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_85581b1c8d7c2f9fb17b(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation_dispatch_readiness(','FUNCTION private.delivery_scoped_85581b1c8d7c2f9fb17b('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis'),'SELECT * INTO v_operation FROM private.delivery_operations','SELECT (pg_catalog.jsonb_populate_record(NULL::public.operations,pg_catalog.to_jsonb(delivery_operations))).* INTO v_operation FROM private.delivery_operations') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_operation_dispatch_readiness' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_85581b1c8d7c2f9fb17b(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_dispatch_readiness(p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN
  SELECT tenant_id INTO v_tenant FROM public.operations WHERE id=p_operation_id;
  IF NOT private.delivery_entity_allowed(v_tenant,'operation',p_operation_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_85581b1c8d7c2f9fb17b(p_operation_id);
  RETURN private.delivery_pick_dto(result,ARRAY['operation_id','execution_type','is_minimum_planned_complete','is_assignment_complete','is_tracking_ready','has_driver_token','has_public_token','can_transition_to_assigned','can_transition_to_in_transit','blocking_reasons','provider_compliance_ready','provider_compliance_blocker_reasons']);
 END IF;
 RETURN private.delivery_core_85581b1c8d7c2f9fb17b(p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_service_claim' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid' AND md5(p.prosrc)=ANY(ARRAY['e727e6d7a619268e322e7a028b7032a8','2e2ab42cc44c68934c4e539f383ec1ac']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_service_claim'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_service_claim(','FUNCTION private.delivery_core_26c659b9361b26437691(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_service_claim' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_26c659b9361b26437691(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_service_claim(p_claim_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_26c659b9361b26437691(p_claim_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_26c659b9361b26437691(p_claim_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_claim_reference_data' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['355b236ca53a37c6e4c460fd9304fa8f','90d0157cf076d5060fbf052f0dc9c9e4']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_claim_reference_data'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_claim_reference_data(','FUNCTION private.delivery_core_6b213951f6f91c4d2223(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_claim_reference_data' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_6b213951f6f91c4d2223(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_claim_reference_data(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_6b213951f6f91c4d2223(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_6b213951f6f91c4d2223(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_service_claims' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['d74e2f94f77b846a365ee0778ace8eae','466c99b603896888038f2695749a0143']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_service_claims'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_service_claims(','FUNCTION private.delivery_core_b0d4f0baa8aa2158d2ee(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_service_claims' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_b0d4f0baa8aa2158d2ee(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_service_claims(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_b0d4f0baa8aa2158d2ee(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_b0d4f0baa8aa2158d2ee(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_transition_service_claim' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_to_status text, p_note text' AND md5(p.prosrc)=ANY(ARRAY['8da3017b8b3af702b2fb519178a4603c','be3b4aeb41248cf3f264960def42a364']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_transition_service_claim'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_transition_service_claim(','FUNCTION private.delivery_core_6d6fa3bb0c64ff048a71(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_transition_service_claim' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_to_status text, p_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_6d6fa3bb0c64ff048a71(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_transition_service_claim(p_claim_id uuid, p_to_status text, p_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_6d6fa3bb0c64ff048a71(p_claim_id,p_to_status,p_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_6d6fa3bb0c64ff048a71(p_claim_id,p_to_status,p_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_reopen_service_claim' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_reason text' AND md5(p.prosrc)=ANY(ARRAY['035ef04cf557938201cd60855c2b0770','199fb033167d1cc1b6e1a41134855476']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_reopen_service_claim'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_reopen_service_claim(','FUNCTION private.delivery_core_9121d4f8f12641df7a97(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_reopen_service_claim' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_reason text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_9121d4f8f12641df7a97(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_reopen_service_claim(p_claim_id uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_9121d4f8f12641df7a97(p_claim_id,p_reason);
  RETURN result;
 END IF;
 RETURN private.delivery_core_9121d4f8f12641df7a97(p_claim_id,p_reason);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_assign_service_claim' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_user_id uuid' AND md5(p.prosrc)=ANY(ARRAY['7073d48e78de46d3b81d0507dabe7b23','f028eb331dd88e99e4f5bf32a194341f']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_assign_service_claim'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_assign_service_claim(','FUNCTION private.delivery_core_fdf283be6942d043a4ff(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_assign_service_claim' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_user_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_fdf283be6942d043a4ff(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_assign_service_claim(p_claim_id uuid, p_user_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_fdf283be6942d043a4ff(p_claim_id,p_user_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_fdf283be6942d043a4ff(p_claim_id,p_user_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_claim_classification' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_responsibility text, p_root_cause text, p_note text' AND md5(p.prosrc)=ANY(ARRAY['7c10217095d4caa48a50ba87ec1a36bd','0e2b99b243e37097efc70cf653f7e9cf']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_claim_classification'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_claim_classification(','FUNCTION private.delivery_core_f21faefd845124fc30ea(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_claim_classification' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_responsibility text, p_root_cause text, p_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_f21faefd845124fc30ea(uuid, text, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_claim_classification(p_claim_id uuid, p_responsibility text, p_root_cause text, p_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_f21faefd845124fc30ea(p_claim_id,p_responsibility,p_root_cause,p_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_f21faefd845124fc30ea(p_claim_id,p_responsibility,p_root_cause,p_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_add_claim_note' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_note text' AND md5(p.prosrc)=ANY(ARRAY['b0a4737bb15e1746ae2d68f782ae233a','5fd00e2b22ad9e1e9ef44e98e1251438']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_add_claim_note'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_add_claim_note(','FUNCTION private.delivery_core_9bd6fad9f1b6cc829e37(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_add_claim_note' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_9bd6fad9f1b6cc829e37(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_add_claim_note(p_claim_id uuid, p_note text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_9bd6fad9f1b6cc829e37(p_claim_id,p_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_9bd6fad9f1b6cc829e37(p_claim_id,p_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_log_claim_contact' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_party text, p_contact_id uuid, p_channel text, p_summary text, p_occurred_at timestamp with time zone' AND md5(p.prosrc)=ANY(ARRAY['7540d81f4f09bd8808139f9806cb4b20','0ce496dc93fa7caed17737077072e5b9']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_log_claim_contact'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_log_claim_contact(','FUNCTION private.delivery_core_ebff37acc12d2b15a779(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_log_claim_contact' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_party text, p_contact_id uuid, p_channel text, p_summary text, p_occurred_at timestamp with time zone';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_ebff37acc12d2b15a779(uuid, text, uuid, text, text, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_log_claim_contact(p_claim_id uuid, p_party text, p_contact_id uuid, p_channel text, p_summary text, p_occurred_at timestamp with time zone DEFAULT now()) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_ebff37acc12d2b15a779(p_claim_id,p_party,p_contact_id,p_channel,p_summary,p_occurred_at);
  RETURN result;
 END IF;
 RETURN private.delivery_core_ebff37acc12d2b15a779(p_claim_id,p_party,p_contact_id,p_channel,p_summary,p_occurred_at);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_upsert_claim_action' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_action_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['af118464baefded57227a3602d167b45','3d91eb8828ab5039044bb43f7b2e6817']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_upsert_claim_action'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_upsert_claim_action(','FUNCTION private.delivery_core_0345d85e82603de8eca8(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_upsert_claim_action' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_action_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_0345d85e82603de8eca8(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_upsert_claim_action(p_claim_id uuid, p_action_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_0345d85e82603de8eca8(p_claim_id,p_action_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_0345d85e82603de8eca8(p_claim_id,p_action_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_claim_action_status' AND pg_get_function_identity_arguments(p.oid)='p_action_id uuid, p_status text, p_completion_note text' AND md5(p.prosrc)=ANY(ARRAY['f010de608d8ed682e5d11ab583add059','a6e38989f22f464dd67d1c781b7ac76f']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_claim_action_status'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_claim_action_status(','FUNCTION private.delivery_core_5419ba480aca78e18360(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_claim_action_status' AND pg_get_function_identity_arguments(p.oid)='p_action_id uuid, p_status text, p_completion_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_5419ba480aca78e18360(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_claim_action_status(p_action_id uuid, p_status text, p_completion_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_5419ba480aca78e18360(p_action_id,p_status,p_completion_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_5419ba480aca78e18360(p_action_id,p_status,p_completion_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_record_claim_settlement' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['509522ce79cecca4ddd202800653d767','6cc28e8b9c28f7aa0db6b3308ced6058']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_record_claim_settlement'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_record_claim_settlement(','FUNCTION private.delivery_core_d7d5ae6ab3b4f457ec8c(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_record_claim_settlement' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_d7d5ae6ab3b4f457ec8c(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_record_claim_settlement(p_claim_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_d7d5ae6ab3b4f457ec8c(p_claim_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_d7d5ae6ab3b4f457ec8c(p_claim_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_claim_finance_handoff' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid' AND md5(p.prosrc)=ANY(ARRAY['30b3ea57d03e6c0cf4a841f39c8f9ab5','4c4d521a1fafbad219f444f9ad7a81c3']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_claim_finance_handoff'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_claim_finance_handoff(','FUNCTION private.delivery_core_fc15c8d8073357391a99(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_claim_finance_handoff' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_fc15c8d8073357391a99(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_claim_finance_handoff(p_claim_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_fc15c8d8073357391a99(p_claim_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_fc15c8d8073357391a99(p_claim_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_register_claim_document' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['54d4be9255b1d095166402405b044d4e','039f95507c8a5a644b136a315abbcec5']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_register_claim_document'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_register_claim_document(','FUNCTION private.delivery_core_1846fff6701462e255e3(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_register_claim_document' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_1846fff6701462e255e3(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_register_claim_document(p_claim_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_1846fff6701462e255e3(p_claim_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_1846fff6701462e255e3(p_claim_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_relate_claim_document' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_file_id uuid, p_note text' AND md5(p.prosrc)=ANY(ARRAY['510fc9590264ad1240b3050a3e1c067c','c1f666150f29d302c176fc86eedff22d']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_relate_claim_document'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_relate_claim_document(','FUNCTION private.delivery_core_0e1e4f1947862036fe6b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_relate_claim_document' AND pg_get_function_identity_arguments(p.oid)='p_claim_id uuid, p_file_id uuid, p_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_0e1e4f1947862036fe6b(uuid, uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_relate_claim_document(p_claim_id uuid, p_file_id uuid, p_note text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_0e1e4f1947862036fe6b(p_claim_id,p_file_id,p_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_0e1e4f1947862036fe6b(p_claim_id,p_file_id,p_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_partner_claims' AND pg_get_function_identity_arguments(p.oid)='p_partner_type text, p_partner_id uuid, p_limit integer' AND md5(p.prosrc)=ANY(ARRAY['a6fdeaf62654c456721e3bd10b52af73','38178834232508972c7c04ce6b20a48f']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_partner_claims'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_partner_claims(','FUNCTION private.delivery_core_efe55a0f977760253125(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_partner_claims' AND pg_get_function_identity_arguments(p.oid)='p_partner_type text, p_partner_id uuid, p_limit integer';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_efe55a0f977760253125(text, uuid, integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_partner_claims(p_partner_type text, p_partner_id uuid, p_limit integer DEFAULT 50) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_efe55a0f977760253125(p_partner_type,p_partner_id,p_limit);
  RETURN result;
 END IF;
 RETURN private.delivery_core_efe55a0f977760253125(p_partner_type,p_partner_id,p_limit);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_claims_dashboard' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_from timestamp with time zone, p_to timestamp with time zone' AND md5(p.prosrc)=ANY(ARRAY['a6d45cfe875cde40ddf4a084936fdf04','17771231d1d04bbc847d32ea7e9404b9']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_claims_dashboard'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_claims_dashboard(','FUNCTION private.delivery_core_c8fc22d45dbeb0b0fce6(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_claims_dashboard' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_from timestamp with time zone, p_to timestamp with time zone';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_c8fc22d45dbeb0b0fce6(uuid, timestamp with time zone, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_claims_dashboard(p_tenant_id uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_c8fc22d45dbeb0b0fce6(p_tenant_id,p_from,p_to);
  RETURN result;
 END IF;
 RETURN private.delivery_core_c8fc22d45dbeb0b0fce6(p_tenant_id,p_from,p_to);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_claim_attention_items' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['d688becea00e2fac0c5a0cf666f3420d','c6f1173e06c4a6dee840750dad8d171b']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_claim_attention_items'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_claim_attention_items(','FUNCTION private.delivery_core_19df0f75f6ca625b918f(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_claim_attention_items' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_19df0f75f6ca625b918f(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_claim_attention_items(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_19df0f75f6ca625b918f(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_19df0f75f6ca625b918f(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_search_claims' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_query text, p_limit integer' AND md5(p.prosrc)=ANY(ARRAY['ac34ccb41cdc140efd8fc56bef04203b','f274ba6df5a91322e8361a02f41fb450']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_search_claims'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_search_claims(','FUNCTION private.delivery_core_a8eb92e2b7e5fe8b4931(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_search_claims' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_query text, p_limit integer';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_a8eb92e2b7e5fe8b4931(uuid, text, integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_search_claims(p_tenant_id uuid, p_query text, p_limit integer DEFAULT 10) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_a8eb92e2b7e5fe8b4931(p_tenant_id,p_query,p_limit);
  RETURN result;
 END IF;
 RETURN private.delivery_core_a8eb92e2b7e5fe8b4931(p_tenant_id,p_query,p_limit);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_claim_reporting' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_from timestamp with time zone, p_to timestamp with time zone' AND md5(p.prosrc)=ANY(ARRAY['37d2cfa3e1b3185329adb19ee22711d5','4994c36ad9e312170d6db30375f23a37']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_claim_reporting'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_claim_reporting(','FUNCTION private.delivery_core_290d784ea29636bc5f5b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_claim_reporting' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_from timestamp with time zone, p_to timestamp with time zone';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_290d784ea29636bc5f5b(uuid, timestamp with time zone, timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_claim_reporting(p_tenant_id uuid, p_from timestamp with time zone, p_to timestamp with time zone) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_290d784ea29636bc5f5b(p_tenant_id,p_from,p_to);
  RETURN result;
 END IF;
 RETURN private.delivery_core_290d784ea29636bc5f5b(p_tenant_id,p_from,p_to);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_export_claims' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['9ad899c95ddb77343be7170331909d14','9ad899c95ddb77343be7170331909d14']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_export_claims'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_export_claims(','FUNCTION private.delivery_core_b3d8ac39b3443dc624c0(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_export_claims' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_b3d8ac39b3443dc624c0(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_export_claims(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_b3d8ac39b3443dc624c0(p_tenant_id,p_filters);
  RETURN result;
 END IF;
 RETURN private.delivery_core_b3d8ac39b3443dc624c0(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_save_claim_view' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_view_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['8d77aa4c18f1cf4ae1c28f4aca5c3385','078470ade04dfa52060b626c2c3109fb']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_save_claim_view'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_save_claim_view(','FUNCTION private.delivery_core_74267eedda71f801f821(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_save_claim_view' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_view_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_74267eedda71f801f821(uuid, uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_save_claim_view(p_tenant_id uuid, p_view_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_74267eedda71f801f821(p_tenant_id,p_view_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_74267eedda71f801f821(p_tenant_id,p_view_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_delete_claim_view' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_view_id uuid' AND md5(p.prosrc)=ANY(ARRAY['d45047eb65bcef0208b73f4a547120da','d45047eb65bcef0208b73f4a547120da']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_delete_claim_view'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_delete_claim_view(','FUNCTION private.delivery_core_444f70c9982d478dac6b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_delete_claim_view' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_view_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_444f70c9982d478dac6b(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_delete_claim_view(p_tenant_id uuid, p_view_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_444f70c9982d478dac6b(p_tenant_id,p_view_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_444f70c9982d478dac6b(p_tenant_id,p_view_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_refresh_claim_notifications' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['739401b9265f7a71956f077a190b2b34','739401b9265f7a71956f077a190b2b34']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_refresh_claim_notifications'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_refresh_claim_notifications(','FUNCTION private.delivery_core_b53ae684af13f478c552(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_refresh_claim_notifications' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_b53ae684af13f478c552(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_refresh_claim_notifications(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_b53ae684af13f478c552(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_b53ae684af13f478c552(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_descargo_lines' AND pg_get_function_identity_arguments(p.oid)='p_pedimento_id uuid' AND md5(p.prosrc)=ANY(ARRAY['b72aa5540884bfabb9dc08974d79aa15','c5d11892b647fa7f2235062dfb322681']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_descargo_lines'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_descargo_lines(','FUNCTION private.delivery_core_d85e4d06ae68d1da8ad0(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_descargo_lines' AND pg_get_function_identity_arguments(p.oid)='p_pedimento_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_d85e4d06ae68d1da8ad0(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_descargo_lines(p_pedimento_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_d85e4d06ae68d1da8ad0(p_pedimento_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_d85e4d06ae68d1da8ad0(p_pedimento_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_add_descargo_line' AND pg_get_function_identity_arguments(p.oid)='p_pedimento_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['523b1bfff6b0e05cf105326f6b63f679','dbb8116c3f67bb38514c1e578a6db2a9']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_add_descargo_line'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_add_descargo_line(','FUNCTION private.delivery_core_ed0c9eeababb3998aec9(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_add_descargo_line' AND pg_get_function_identity_arguments(p.oid)='p_pedimento_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_ed0c9eeababb3998aec9(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_add_descargo_line(p_pedimento_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_ed0c9eeababb3998aec9(p_pedimento_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_ed0c9eeababb3998aec9(p_pedimento_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_deal_notes' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid' AND md5(p.prosrc)=ANY(ARRAY['44f589048deccc31619d9b0fe3450e1e','9e056ef38e435319017cf1f33498d3ad']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_deal_notes'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_deal_notes(','FUNCTION private.delivery_core_5f2d4d23fcb06e1fc08e(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_deal_notes' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_5f2d4d23fcb06e1fc08e(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_deal_notes(p_deal_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_5f2d4d23fcb06e1fc08e(p_deal_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_5f2d4d23fcb06e1fc08e(p_deal_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_deal_checklist' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid' AND md5(p.prosrc)=ANY(ARRAY['f8abe0b3fd331b2629c113381e0c0b98','1b84c723ff34aa63e05303e2e97f68b8']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_deal_checklist'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_deal_checklist(','FUNCTION private.delivery_core_6cc803f776d5d875cb95(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_deal_checklist' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_6cc803f776d5d875cb95(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_deal_checklist(p_deal_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_6cc803f776d5d875cb95(p_deal_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_6cc803f776d5d875cb95(p_deal_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_add_deal_note' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_note text' AND md5(p.prosrc)=ANY(ARRAY['f726987111398bb70cbeae832ac151b1','340b6ed02c99c419aac555991c0b814f']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_add_deal_note'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_add_deal_note(','FUNCTION private.delivery_core_8f6b774e22b06ab4af4b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_add_deal_note' AND pg_get_function_identity_arguments(p.oid)='p_deal_id uuid, p_note text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_8f6b774e22b06ab4af4b(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_add_deal_note(p_deal_id uuid, p_note text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_8f6b774e22b06ab4af4b(p_deal_id,p_note);
  RETURN result;
 END IF;
 RETURN private.delivery_core_8f6b774e22b06ab4af4b(p_deal_id,p_note);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_toggle_deal_checklist_item' AND pg_get_function_identity_arguments(p.oid)='p_item_id uuid, p_is_done boolean' AND md5(p.prosrc)=ANY(ARRAY['9ae5f7abc9ae5a50d53d03a0a38f152f','1aed20a8f44f0204cf9da27c1a487756']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_toggle_deal_checklist_item'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_toggle_deal_checklist_item(','FUNCTION private.delivery_core_6a27ff4142e094286066(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_toggle_deal_checklist_item' AND pg_get_function_identity_arguments(p.oid)='p_item_id uuid, p_is_done boolean';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_6a27ff4142e094286066(uuid, boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_toggle_deal_checklist_item(p_item_id uuid, p_is_done boolean) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_6a27ff4142e094286066(p_item_id,p_is_done);
  RETURN result;
 END IF;
 RETURN private.delivery_core_6a27ff4142e094286066(p_item_id,p_is_done);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_invitation' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_email text, p_role text' AND md5(p.prosrc)=ANY(ARRAY['5954cf308d51c5d8bf9a7471d8eef495','c88f6be3971b4454b985b2a8e8e5fa1b']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public, extensions']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_invitation'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_invitation(','FUNCTION private.delivery_core_ec5ff6efe82f329f8487(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_invitation' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_email text, p_role text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_ec5ff6efe82f329f8487(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_invitation(p_tenant_id uuid, p_email text, p_role text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'extensions' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_ec5ff6efe82f329f8487(p_tenant_id,p_email,p_role);
  RETURN result;
 END IF;
 RETURN private.delivery_core_ec5ff6efe82f329f8487(p_tenant_id,p_email,p_role);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_partner_compliance_bundle' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_partner_type text, p_partner_id uuid' AND md5(p.prosrc)=ANY(ARRAY['960ecd944aa1e2321ddc25c2dbe80c4b','74067873366e53b8cf0253dccae31238']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_partner_compliance_bundle'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_partner_compliance_bundle(','FUNCTION private.delivery_core_b6ed163fe7f81eee3e13(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_partner_compliance_bundle' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_partner_type text, p_partner_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_b6ed163fe7f81eee3e13(uuid, text, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_partner_compliance_bundle(p_tenant_id uuid, p_partner_type text, p_partner_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_b6ed163fe7f81eee3e13(p_tenant_id,p_partner_type,p_partner_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_b6ed163fe7f81eee3e13(p_tenant_id,p_partner_type,p_partner_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_rate_360' AND pg_get_function_identity_arguments(p.oid)='p_rate_card_id uuid' AND md5(p.prosrc)=ANY(ARRAY['5a155038f177e68ee11b92e00aba55e2','3fd3f595c670b8d60bdde301845e4bc3']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_rate_360'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_rate_360(','FUNCTION private.delivery_core_5a1c038ebc25e0da07a2(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_rate_360' AND pg_get_function_identity_arguments(p.oid)='p_rate_card_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_5a1c038ebc25e0da07a2(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_rate_360(p_rate_card_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_5a1c038ebc25e0da07a2(p_rate_card_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_5a1c038ebc25e0da07a2(p_rate_card_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_customer_partner_360' AND pg_get_function_identity_arguments(p.oid)='p_customer_id uuid' AND md5(p.prosrc)=ANY(ARRAY['3fb7a8ac3bc36bbc5706ece16d643899','6496dd1e6aa2eec4dda654a7d6a364aa']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_customer_partner_360'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_customer_partner_360(','FUNCTION private.delivery_core_b2ffa7c2d8d9e9477ffc(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_customer_partner_360' AND pg_get_function_identity_arguments(p.oid)='p_customer_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_b2ffa7c2d8d9e9477ffc(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_customer_partner_360(p_customer_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_b2ffa7c2d8d9e9477ffc(p_customer_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_b2ffa7c2d8d9e9477ffc(p_customer_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_internal_notifications_page' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_unread_only boolean, p_cursor jsonb, p_limit integer' AND md5(p.prosrc)=ANY(ARRAY['7f4ca0abf060baa865507ed5060ac8c3','6a4804f32b4f39f0c4c3551ccd345c9f']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_internal_notifications_page'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_internal_notifications_page(','FUNCTION private.delivery_core_59df620a81c989a5ec60(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_internal_notifications_page' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_unread_only boolean, p_cursor jsonb, p_limit integer';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_59df620a81c989a5ec60(uuid, boolean, jsonb, integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_internal_notifications_page(p_tenant_id uuid, p_unread_only boolean DEFAULT false, p_cursor jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 25) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_59df620a81c989a5ec60(p_tenant_id,p_unread_only,p_cursor,p_limit);
  RETURN result;
 END IF;
 RETURN private.delivery_core_59df620a81c989a5ec60(p_tenant_id,p_unread_only,p_cursor,p_limit);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_fiscal_operational_status' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid' AND md5(p.prosrc)=ANY(ARRAY['a20a8915a09d0567197892c4a785f34f','2f6d8d458b628dd5739a48fa045fb37d']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_fiscal_operational_status'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_fiscal_operational_status(','FUNCTION private.delivery_core_c66b1c7a64fea67280fb(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_fiscal_operational_status' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_c66b1c7a64fea67280fb(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_fiscal_operational_status(p_tenant_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_c66b1c7a64fea67280fb(p_tenant_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_c66b1c7a64fea67280fb(p_tenant_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_cfdi_fiscal_input' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid, p_fiscal_input jsonb, p_cfdi_version text' AND md5(p.prosrc)=ANY(ARRAY['cf83ede0ceb9e82831e2840d900c5c13','7f4ed35ae4afef4e577527a33915aafb']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_cfdi_fiscal_input'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_cfdi_fiscal_input(','FUNCTION private.delivery_core_5ab3e7fcf07911d91233(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_cfdi_fiscal_input' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid, p_fiscal_input jsonb, p_cfdi_version text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_5ab3e7fcf07911d91233(uuid, jsonb, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_cfdi_fiscal_input(p_cfdi_id uuid, p_fiscal_input jsonb, p_cfdi_version text DEFAULT '4.0'::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_5ab3e7fcf07911d91233(p_cfdi_id,p_fiscal_input,p_cfdi_version);
  RETURN result;
 END IF;
 RETURN private.delivery_core_5ab3e7fcf07911d91233(p_cfdi_id,p_fiscal_input,p_cfdi_version);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_update_fiscal_provider_config' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_provider_code text, p_enabled boolean, p_environment text, p_capabilities jsonb' AND md5(p.prosrc)=ANY(ARRAY['7f9e04f5d927818b1f1ff3374fca3c64','ea65689f7547ee4283dfe903d2a9c2a8']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=""']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_update_fiscal_provider_config'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_update_fiscal_provider_config(','FUNCTION private.delivery_core_1f081e72bf129c92912e(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_update_fiscal_provider_config' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_provider_code text, p_enabled boolean, p_environment text, p_capabilities jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_1f081e72bf129c92912e(uuid, text, boolean, text, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_update_fiscal_provider_config(p_tenant_id uuid, p_provider_code text, p_enabled boolean, p_environment text, p_capabilities jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO '' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_1f081e72bf129c92912e(p_tenant_id,p_provider_code,p_enabled,p_environment,p_capabilities);
  RETURN result;
 END IF;
 RETURN private.delivery_core_1f081e72bf129c92912e(p_tenant_id,p_provider_code,p_enabled,p_environment,p_capabilities);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_reports_tanda1' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_date_from text, p_date_to text' AND md5(p.prosrc)=ANY(ARRAY['67075e444de80fa24c784e43c483d14e','8e6caf5659f1cf6a6b5ae7025a29c30c']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=""']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_reports_tanda1'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_reports_tanda1(uuid, text, text)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_c09b97a267d1981466fb(','FUNCTION private.delivery_core_d47fbc4e94870e79244c(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_reports_tanda1(','FUNCTION private.delivery_core_d47fbc4e94870e79244c(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_reports_tanda1' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_date_from text, p_date_to text';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_d47fbc4e94870e79244c(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_reports_tanda1(','FUNCTION private.delivery_scoped_d47fbc4e94870e79244c('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_reports_tanda1' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_date_from text, p_date_to text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_d47fbc4e94870e79244c(uuid, text, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_reports_tanda1(p_tenant_id uuid, p_date_from text DEFAULT NULL::text, p_date_to text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO '' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'operations.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_d47fbc4e94870e79244c(p_tenant_id,p_date_from,p_date_to);
  RETURN result;
 END IF;
 RETURN private.delivery_core_d47fbc4e94870e79244c(p_tenant_id,p_date_from,p_date_to);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_create_payment_complement' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb' AND md5(p.prosrc)=ANY(ARRAY['455ccd948d72703ee97710bb2abc75d2','9722a1b56ec27420b51dd98678cc8b89']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_create_payment_complement'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_create_payment_complement(uuid, jsonb)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_accc9a2b6dff03673ba2(','FUNCTION private.delivery_core_96c4b1a8460a3509942e(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_payment_complement(','FUNCTION private.delivery_core_96c4b1a8460a3509942e(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_create_payment_complement' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_96c4b1a8460a3509942e(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_create_payment_complement(','FUNCTION private.delivery_scoped_96c4b1a8460a3509942e('),'private.multi08_legacy_write_target','private.delivery_finance_write_target') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_create_payment_complement' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_payload jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_96c4b1a8460a3509942e(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_create_payment_complement(p_tenant_id uuid, p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT private.delivery_cap(v_tenant,'finance.write') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT private.delivery_cap(v_tenant,'billing.draft') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_96c4b1a8460a3509942e(p_tenant_id,p_payload);
  RETURN result;
 END IF;
 RETURN private.delivery_core_96c4b1a8460a3509942e(p_tenant_id,p_payload);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_provider_360' AND pg_get_function_identity_arguments(p.oid)='p_provider_id uuid' AND md5(p.prosrc)=ANY(ARRAY['2d8521d42cc088fd9ff580dd48fd7b61','0354e6ed1d0bf22808a7a7424caf3b75']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_provider_360'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_provider_360(','FUNCTION private.delivery_core_a44c59fbcacf2c25cab6(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_provider_360' AND pg_get_function_identity_arguments(p.oid)='p_provider_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_a44c59fbcacf2c25cab6(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_provider_360(p_provider_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_a44c59fbcacf2c25cab6(p_provider_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_a44c59fbcacf2c25cab6(p_provider_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_reset_cfdi_fiscal_draft' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid, p_reason text' AND md5(p.prosrc)=ANY(ARRAY['c25c982984674f9103c8cf50a61d1a47','fe9ecef4fa5259d4ffd29218ada71a7b']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_reset_cfdi_fiscal_draft'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_reset_cfdi_fiscal_draft(','FUNCTION private.delivery_core_bf3a0d6fa0e6802ed6de(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_reset_cfdi_fiscal_draft' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid, p_reason text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_bf3a0d6fa0e6802ed6de(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_reset_cfdi_fiscal_draft(p_cfdi_id uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_bf3a0d6fa0e6802ed6de(p_cfdi_id,p_reason);
  RETURN result;
 END IF;
 RETURN private.delivery_core_bf3a0d6fa0e6802ed6de(p_cfdi_id,p_reason);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_prepare_cfdi_for_api' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid' AND md5(p.prosrc)=ANY(ARRAY['406a1e8e7026f1eefe48579e72e457ec','380b667d7d0eb5d585820cbfb12136f6']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_prepare_cfdi_for_api'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_prepare_cfdi_for_api(','FUNCTION private.delivery_core_a967fb42f122e6b2b827(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_prepare_cfdi_for_api' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_a967fb42f122e6b2b827(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_prepare_cfdi_for_api(p_cfdi_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_a967fb42f122e6b2b827(p_cfdi_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_a967fb42f122e6b2b827(p_cfdi_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_retry_fiscal_request' AND pg_get_function_identity_arguments(p.oid)='p_request_id uuid' AND md5(p.prosrc)=ANY(ARRAY['7a5aa9c10b0057768820c3914980f572','284aef569e24aec4e631ad885a4858ce']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_retry_fiscal_request'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_retry_fiscal_request(','FUNCTION private.delivery_core_053135c2282f1d4c85ca(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_retry_fiscal_request' AND pg_get_function_identity_arguments(p.oid)='p_request_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_053135c2282f1d4c85ca(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_retry_fiscal_request(p_request_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_053135c2282f1d4c85ca(p_request_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_053135c2282f1d4c85ca(p_request_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_request_fiscal_cancellation' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid, p_reason text' AND md5(p.prosrc)=ANY(ARRAY['35a5bef004b7a273c1f577fe7c186fc0','7b173e4aa5fb30cb25f6bd0d4139d620']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_request_fiscal_cancellation'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_request_fiscal_cancellation(','FUNCTION private.delivery_core_6c44b73845f656800aa0(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_request_fiscal_cancellation' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid, p_reason text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_6c44b73845f656800aa0(uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_request_fiscal_cancellation(p_cfdi_id uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_6c44b73845f656800aa0(p_cfdi_id,p_reason);
  RETURN result;
 END IF;
 RETURN private.delivery_core_6c44b73845f656800aa0(p_cfdi_id,p_reason);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_queue_fiscal_status_check' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid' AND md5(p.prosrc)=ANY(ARRAY['fd50f0acc8d12c54a037e6bfa39826e4','a6385f56630b4f140d4352431e2779a8']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_queue_fiscal_status_check'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_queue_fiscal_status_check(','FUNCTION private.delivery_core_8f741a740367d56f16bd(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_queue_fiscal_status_check' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_8f741a740367d56f16bd(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_queue_fiscal_status_check(p_cfdi_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_8f741a740367d56f16bd(p_cfdi_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_8f741a740367d56f16bd(p_cfdi_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_finance_invoice_detail' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_invoice_id uuid' AND md5(p.prosrc)=ANY(ARRAY['7a451f10b5ea2e0049932991ce943b40','3c5e7c31e5b1b80753c7c09d9608f15a']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_finance_invoice_detail'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_get_finance_invoice_detail(uuid, uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_595e47f86c9f552b4d5f(','FUNCTION private.delivery_core_3216cf3b8634685a48ce(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_finance_invoice_detail(','FUNCTION private.delivery_core_3216cf3b8634685a48ce(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_get_finance_invoice_detail' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_invoice_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_3216cf3b8634685a48ce(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_finance_invoice_detail(','FUNCTION private.delivery_scoped_3216cf3b8634685a48ce('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_finance_invoice_detail' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_invoice_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_3216cf3b8634685a48ce(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_finance_invoice_detail(p_tenant_id uuid, p_invoice_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_3216cf3b8634685a48ce(p_tenant_id,p_invoice_id);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_3216cf3b8634685a48ce(p_tenant_id,p_invoice_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_finance_invoices' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['e56cc2d5962dcef13cf18e7cb028d126','01623f0644aec1c23d2cd8a139e752bb']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_finance_invoices'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_finance_invoices(uuid, jsonb)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_6807d4aa81dd75798486(','FUNCTION private.delivery_core_908fd958c5cc1a223706(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_finance_invoices(','FUNCTION private.delivery_core_908fd958c5cc1a223706(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_finance_invoices' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_908fd958c5cc1a223706(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_finance_invoices(','FUNCTION private.delivery_scoped_908fd958c5cc1a223706('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_finance_invoices' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_908fd958c5cc1a223706(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_finance_invoices(p_tenant_id uuid, p_filters jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_908fd958c5cc1a223706(p_tenant_id,p_filters);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_908fd958c5cc1a223706(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_finance_payments' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['ad496e0cf84d65b6a6f068235dc883f6','a6f685fc08167a2d366fabe1a05e26e4']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_finance_payments'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_finance_payments(uuid, jsonb)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_9f84f712b7efebc9ffaa(','FUNCTION private.delivery_core_f6e86d149c7b692ca83a(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_finance_payments(','FUNCTION private.delivery_core_f6e86d149c7b692ca83a(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_finance_payments' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_f6e86d149c7b692ca83a(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_finance_payments(','FUNCTION private.delivery_scoped_f6e86d149c7b692ca83a('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_finance_payments' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_f6e86d149c7b692ca83a(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_finance_payments(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_f6e86d149c7b692ca83a(p_tenant_id,p_filters);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_f6e86d149c7b692ca83a(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_finance_due_alerts' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['930e1e506f365d6579577e5411561f54','e1615f67070dc1ee85ff64c1827c485e']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_finance_due_alerts'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_finance_due_alerts(uuid, jsonb)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_66aa392cc751a150eafb(','FUNCTION private.delivery_core_36627b7d04acc5541632(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_finance_due_alerts(','FUNCTION private.delivery_core_36627b7d04acc5541632(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_finance_due_alerts' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_36627b7d04acc5541632(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_finance_due_alerts(','FUNCTION private.delivery_scoped_36627b7d04acc5541632('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_finance_due_alerts' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_36627b7d04acc5541632(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_finance_due_alerts(p_tenant_id uuid, p_filters jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_36627b7d04acc5541632(p_tenant_id,p_filters);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_36627b7d04acc5541632(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_operation_finance_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid' AND md5(p.prosrc)=ANY(ARRAY['3c0f3e0c0fce41a8226afe80acaede25','a0c600db0e716b6976d2cc9048efffe1']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_operation_finance_summary'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_get_operation_finance_summary(uuid, uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_88f44bef42c53e2d1fa1(','FUNCTION private.delivery_core_8487efa5defb37e515af(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation_finance_summary(','FUNCTION private.delivery_core_8487efa5defb37e515af(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_get_operation_finance_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_8487efa5defb37e515af(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_operation_finance_summary(','FUNCTION private.delivery_scoped_8487efa5defb37e515af('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_operation_finance_summary' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_operation_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_8487efa5defb37e515af(uuid, uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_operation_finance_summary(p_tenant_id uuid, p_operation_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_8487efa5defb37e515af(p_tenant_id,p_operation_id);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_8487efa5defb37e515af(p_tenant_id,p_operation_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_finance_profitability' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['370d1281916a82b10baf9859b924a483','9c867301f3150f80ecd20d2aa9b29d43']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_finance_profitability'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_finance_profitability(uuid, jsonb)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_7cca07eebc63b14cce34(','FUNCTION private.delivery_core_d4d626255ea21d7f59cf(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_finance_profitability(','FUNCTION private.delivery_core_d4d626255ea21d7f59cf(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_finance_profitability' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_d4d626255ea21d7f59cf(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_finance_profitability(','FUNCTION private.delivery_scoped_d4d626255ea21d7f59cf('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_finance_profitability' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_d4d626255ea21d7f59cf(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_finance_profitability(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_d4d626255ea21d7f59cf(p_tenant_id,p_filters);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_d4d626255ea21d7f59cf(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_list_payment_complements' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb' AND md5(p.prosrc)=ANY(ARRAY['50a154d8c8353a6567bcd50836652fa3','6aac2abf86921dbd77653804571bc85c']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_list_payment_complements'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_list_payment_complements(uuid, jsonb)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_92386de67f2a3bf65072(','FUNCTION private.delivery_core_6b115a142aaa4311595b(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_payment_complements(','FUNCTION private.delivery_core_6b115a142aaa4311595b(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_list_payment_complements' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_6b115a142aaa4311595b(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_list_payment_complements(','FUNCTION private.delivery_scoped_6b115a142aaa4311595b('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_list_payment_complements' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_filters jsonb';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_6b115a142aaa4311595b(uuid, jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_list_payment_complements(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_6b115a142aaa4311595b(p_tenant_id,p_filters);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_6b115a142aaa4311595b(p_tenant_id,p_filters);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_void_finance_invoice' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_id uuid, p_reason text' AND md5(p.prosrc)=ANY(ARRAY['06d7ebaff20ab5122161ca1f04828679','f52b1fbb9597c1657dc180769bfa3f90']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_void_finance_invoice'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_void_finance_invoice(uuid, uuid, text)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_60d9097800841c341546(','FUNCTION private.delivery_core_ac2126482fb18fd7c111(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_void_finance_invoice(','FUNCTION private.delivery_core_ac2126482fb18fd7c111(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_void_finance_invoice' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_id uuid, p_reason text';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_ac2126482fb18fd7c111(uuid, uuid, text) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_void_finance_invoice(','FUNCTION private.delivery_scoped_ac2126482fb18fd7c111('),'private.multi08_legacy_write_target','private.delivery_finance_write_target') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_void_finance_invoice' AND pg_get_function_identity_arguments(p.oid)='p_tenant_id uuid, p_id uuid, p_reason text';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_ac2126482fb18fd7c111(uuid, uuid, text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_void_finance_invoice(p_tenant_id uuid, p_id uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=p_tenant_id;result jsonb;
 BEGIN
 IF (private.delivery_required(p_tenant_id) OR private.delivery_required(NULL)) THEN

  IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT private.delivery_cap(v_tenant,'finance.write') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_ac2126482fb18fd7c111(p_tenant_id,p_id,p_reason);
  RETURN result;
 END IF;
 RETURN private.delivery_core_ac2126482fb18fd7c111(p_tenant_id,p_id,p_reason);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_get_fiscal_readiness' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid' AND md5(p.prosrc)=ANY(ARRAY['f4dc20c311e3a22460ff6c7fc1419e16','58fff55b531f0e77371189a48a186855']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_get_fiscal_readiness'; END IF; END $guard$;

DO $legacy$ DECLARE d text;observed text;BEGIN
  observed:=private.c02_legacy_definition('public.rpc_get_fiscal_readiness(uuid)');
  IF observed IS NOT NULL THEN
   d:=replace(observed,'FUNCTION private.c02_observed_964b27d3e1237659c5ad(','FUNCTION private.delivery_core_9a5de6decc55850d17cb(');
  ELSE SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_fiscal_readiness(','FUNCTION private.delivery_core_9a5de6decc55850d17cb(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='rpc_get_fiscal_readiness' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid';END IF;
  EXECUTE d;END $legacy$;

REVOKE ALL ON FUNCTION private.delivery_core_9a5de6decc55850d17cb(uuid) FROM PUBLIC,anon,authenticated,service_role;

DO $clone$ DECLARE d text; BEGIN SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_get_fiscal_readiness(','FUNCTION private.delivery_scoped_9a5de6decc55850d17cb('),'(?i)\m(from|join)\s+public\.operations\M','\1 private.delivery_operations','g'),'(?i)\m(from|join)\s+public\.crm_deals\M','\1 private.delivery_crm_deals','g'),'(?i)\m(from|join)\s+public\.inventory_lots\M','\1 private.delivery_inventory_lots','g'),'(?i)\m(from|join)\s+public\.billing_cfdis\M','\1 private.delivery_billing_cfdis','g'),'(?i)\m(from|join)\s+public\.finance_invoices\M','\1 private.delivery_finance_invoices','g'),'(?i)\m(from|join)\s+public\.finance_payments\M','\1 private.delivery_finance_payments','g'),'(?i)\m(from|join)\s+public\.billing_documents\M','\1 private.delivery_billing_documents','g'),'(?i)\m(from|join)\s+public\.billing_credit_notes\M','\1 private.delivery_billing_credit_notes','g'),'(?i)\m(from|join)\s+public\.billing_payment_complements\M','\1 private.delivery_billing_payment_complements','g'),'(?i)\m(from|join)\s+public\.operation_assignment_history\M','\1 private.delivery_operation_assignment_history','g'),'(?i)\m(from|join)\s+public\.operation_incidents\M','\1 private.delivery_operation_incidents','g'),'(?i)\m(from|join)\s+public\.operation_evidence\M','\1 private.delivery_operation_evidence','g'),'(?i)\m(from|join)\s+public\.operation_documents\M','\1 private.delivery_operation_documents','g'),'(?i)\m(from|join)\s+public\.operation_crossings\M','\1 private.delivery_operation_crossings','g'),'(?i)\m(from|join)\s+public\.operation_billing\M','\1 private.delivery_operation_billing','g'),'(?i)\m(from|join)\s+public\.tracking_events\M','\1 private.delivery_tracking_events','g'),'(?i)\m(from|join)\s+public\.tracking_route_points\M','\1 private.delivery_tracking_route_points','g'),'(?i)\m(from|join)\s+public\.billing_carta_porte\M','\1 private.delivery_billing_carta_porte','g'),'private.m07_set_operations','private.delivery_operations'),'private.m07_row_operations','private.delivery_operations'),'private.m07_export_operations','private.delivery_operations'),'private.m07_single_operations','private.delivery_operations'),'private.m07_set_crm_deals','private.delivery_crm_deals'),'private.m07_row_crm_deals','private.delivery_crm_deals'),'private.m07_export_crm_deals','private.delivery_crm_deals'),'private.m07_single_crm_deals','private.delivery_crm_deals'),'private.m07_set_inventory_lots','private.delivery_inventory_lots'),'private.m07_row_inventory_lots','private.delivery_inventory_lots'),'private.m07_export_inventory_lots','private.delivery_inventory_lots'),'private.m07_single_inventory_lots','private.delivery_inventory_lots'),'private.m07_set_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_row_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_export_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_single_billing_cfdis','private.delivery_billing_cfdis'),'private.m07_set_finance_invoices','private.delivery_finance_invoices'),'private.m07_row_finance_invoices','private.delivery_finance_invoices'),'private.m07_export_finance_invoices','private.delivery_finance_invoices'),'private.m07_single_finance_invoices','private.delivery_finance_invoices'),'private.m07_set_finance_payments','private.delivery_finance_payments'),'private.m07_row_finance_payments','private.delivery_finance_payments'),'private.m07_export_finance_payments','private.delivery_finance_payments'),'private.m07_single_finance_payments','private.delivery_finance_payments'),'private.m07_set_billing_documents','private.delivery_billing_documents'),'private.m07_row_billing_documents','private.delivery_billing_documents'),'private.m07_export_billing_documents','private.delivery_billing_documents'),'private.m07_single_billing_documents','private.delivery_billing_documents'),'private.m07_set_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_row_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_export_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_single_billing_credit_notes','private.delivery_billing_credit_notes'),'private.m07_set_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_row_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_export_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_single_billing_payment_complements','private.delivery_billing_payment_complements'),'private.m07_set_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_row_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_export_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_single_operation_assignment_history','private.delivery_operation_assignment_history'),'private.m07_set_operation_incidents','private.delivery_operation_incidents'),'private.m07_row_operation_incidents','private.delivery_operation_incidents'),'private.m07_export_operation_incidents','private.delivery_operation_incidents'),'private.m07_single_operation_incidents','private.delivery_operation_incidents'),'private.m07_set_operation_evidence','private.delivery_operation_evidence'),'private.m07_row_operation_evidence','private.delivery_operation_evidence'),'private.m07_export_operation_evidence','private.delivery_operation_evidence'),'private.m07_single_operation_evidence','private.delivery_operation_evidence'),'private.m07_set_operation_documents','private.delivery_operation_documents'),'private.m07_row_operation_documents','private.delivery_operation_documents'),'private.m07_export_operation_documents','private.delivery_operation_documents'),'private.m07_single_operation_documents','private.delivery_operation_documents'),'private.m07_set_operation_crossings','private.delivery_operation_crossings'),'private.m07_row_operation_crossings','private.delivery_operation_crossings'),'private.m07_export_operation_crossings','private.delivery_operation_crossings'),'private.m07_single_operation_crossings','private.delivery_operation_crossings'),'private.m07_set_operation_billing','private.delivery_operation_billing'),'private.m07_row_operation_billing','private.delivery_operation_billing'),'private.m07_export_operation_billing','private.delivery_operation_billing'),'private.m07_single_operation_billing','private.delivery_operation_billing'),'private.m07_set_tracking_events','private.delivery_tracking_events'),'private.m07_row_tracking_events','private.delivery_tracking_events'),'private.m07_export_tracking_events','private.delivery_tracking_events'),'private.m07_single_tracking_events','private.delivery_tracking_events'),'private.m07_set_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_row_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_export_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_single_tracking_route_points','private.delivery_tracking_route_points'),'private.m07_set_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_row_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_export_billing_carta_porte','private.delivery_billing_carta_porte'),'private.m07_single_billing_carta_porte','private.delivery_billing_carta_porte'),'private.fiscal02_legacy_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_readable_finance_invoices','private.delivery_finance_invoices'),'private.fiscal02_legacy_finance_payments','private.delivery_finance_payments'),'private.fiscal02_readable_finance_payments','private.delivery_finance_payments'),'private.fiscal02_legacy_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_readable_billing_credit_notes','private.delivery_billing_credit_notes'),'private.fiscal02_legacy_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_readable_billing_payment_complements','private.delivery_billing_payment_complements'),'private.fiscal02_legacy_billing_documents','private.delivery_billing_documents'),'private.fiscal02_readable_billing_documents','private.delivery_billing_documents'),'private.fiscal02_legacy_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_billing_cfdis','private.delivery_billing_cfdis'),'private.fiscal02_readable_cfdis','private.delivery_billing_cfdis'),'SELECT * INTO v_cfdi FROM private.delivery_billing_cfdis','SELECT (pg_catalog.jsonb_populate_record(NULL::public.billing_cfdis,pg_catalog.to_jsonb(delivery_billing_cfdis))).* INTO v_cfdi FROM private.delivery_billing_cfdis') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_get_fiscal_readiness' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_scoped_9a5de6decc55850d17cb(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_get_fiscal_readiness(p_cfdi_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN
  SELECT tenant_id INTO v_tenant FROM public.billing_cfdis WHERE id=p_cfdi_id;
  IF private.fiscal02_is_lab_entity('cfdi',p_cfdi_id) OR NOT COALESCE(private.delivery_root_company(v_tenant,'billing_cfdi',p_cfdi_id)=ANY(private.delivery_company_ids()),false) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;IF NOT (private.delivery_cap(v_tenant,'financial.full.read')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  result:=private.delivery_scoped_9a5de6decc55850d17cb(p_cfdi_id);
  RETURN CASE WHEN jsonb_typeof(result)='object' AND NOT(result ? 'error') THEN result||jsonb_build_object('classification_notice','resolved_only; excludes unclassified history and fiscal laboratory','company_ids',private.delivery_company_ids()) ELSE result END;
 END IF;
 RETURN private.delivery_core_9a5de6decc55850d17cb(p_cfdi_id);
 END $wrapper$;

DO $guard$ BEGIN IF NOT EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='rpc_queue_fiscal_stamp' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid' AND md5(p.prosrc)=ANY(ARRAY['84667286ffdb243c08a55270ae448334','4caf11292020f9c84bc69ca43471236e']) AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=""']::text[] AND p.prorettype='jsonb'::regtype) THEN RAISE EXCEPTION 'delivery_source_drift: rpc_queue_fiscal_stamp'; END IF; END $guard$;

DO $clone$ DECLARE d text; BEGIN SELECT replace(pg_get_functiondef(p.oid),'FUNCTION public.rpc_queue_fiscal_stamp(','FUNCTION private.delivery_core_8ba24222de0b00735dfe(') INTO STRICT d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='rpc_queue_fiscal_stamp' AND pg_get_function_identity_arguments(p.oid)='p_cfdi_id uuid';EXECUTE d; END $clone$;

REVOKE ALL ON FUNCTION private.delivery_core_8ba24222de0b00735dfe(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.rpc_queue_fiscal_stamp(p_cfdi_id uuid) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO '' AS $wrapper$
 DECLARE v_tenant uuid:=NULL::uuid;result jsonb;
 BEGIN
 IF (private.delivery_required(NULL::uuid) OR private.delivery_required(NULL)) THEN

  RETURN jsonb_build_object('error','company_adoption_pending');
  result:=private.delivery_core_8ba24222de0b00735dfe(p_cfdi_id);
  RETURN result;
 END IF;
 RETURN private.delivery_core_8ba24222de0b00735dfe(p_cfdi_id);
 END $wrapper$;

-- Explicit DTO; unknown fields never enter a browser/CSV, even after a schema addition.
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
DO $surface$ DECLARE f record;BEGIN
 FOR f IN SELECT p.oid,p.proname,pg_get_function_identity_arguments(p.oid) args FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND (p.proname LIKE 'rpc_%' OR p.proname LIKE 'tanda1_%') AND has_function_privilege('authenticated',p.oid,'EXECUTE') LOOP
 IF NOT (f.proname||'('||f.args||')'=ANY(ARRAY['rpc_create_tracking_token(p_tenant_id uuid, p_operation_id uuid, p_scope text, p_ttl_hours integer)','rpc_create_tracking_token(p_tenant_id uuid, p_operation_id uuid, p_scope text, p_force_rotate boolean)','rpc_create_finance_invoice(p_tenant_id uuid, p_payload jsonb)','rpc_get_operation(p_operation_id uuid)','rpc_list_import_mappings(p_tenant_id uuid, p_entity_type text)','rpc_save_import_mapping(p_tenant_id uuid, p_payload jsonb)','rpc_delete_import_mapping(p_tenant_id uuid, p_mapping_id uuid)','rpc_bulk_update_operations(p_tenant_id uuid, p_operation_ids uuid[], p_action text, p_payload jsonb)','rpc_record_data_action(p_tenant_id uuid, p_action text, p_entity_type text, p_count integer, p_detail text)','rpc_export_data_page(p_tenant_id uuid, p_entity_type text, p_filters jsonb, p_cursor jsonb, p_limit integer)','rpc_create_service_claim_from_incident(p_incident_id uuid, p_payload jsonb)','rpc_get_my_context()','rpc_list_members(p_tenant_id uuid)','rpc_list_operations(p_tenant_id uuid)','rpc_reports_operations_summary(p_tenant_id uuid)','rpc_assign_operation(p_tenant_id uuid, p_operation_id uuid, p_driver_id uuid, p_vehicle_id uuid, p_planned_departure timestamp with time zone, p_priority text)','rpc_assign_operation_v2(p_tenant_id uuid, p_operation_id uuid, p_driver_id uuid, p_driver_name text, p_vehicle_id uuid, p_vehicle_ref text, p_planned_departure timestamp with time zone, p_priority text)','rpc_dashboard_recent_activity(p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone)','rpc_reports_financial_summary(p_tenant_id uuid, p_period text)','rpc_create_deal(p_tenant_id uuid, p_payload jsonb)','rpc_update_deal(p_deal_id uuid, p_patch jsonb)','rpc_move_deal(p_deal_id uuid, p_new_stage text)','rpc_add_deal_activity(p_deal_id uuid, p_payload jsonb)','rpc_list_cfdis(p_tenant_id uuid, p_filters jsonb)','rpc_get_cfdi_detail(p_cfdi_id uuid)','rpc_create_cfdi(p_tenant_id uuid, p_payload jsonb)','rpc_update_cfdi(p_cfdi_id uuid, p_patch jsonb)','rpc_upsert_carta_porte(p_cfdi_id uuid, p_payload jsonb)','rpc_create_inventory_lot(p_tenant_id uuid, p_sku text, p_lot_code text, p_qty_on_hand numeric, p_warehouse text, p_received_at timestamp with time zone, p_currency text, p_pedimento_ref text, p_description text, p_unit text)','rpc_update_inventory_lot(p_id uuid, p_patch jsonb)','rpc_create_pedimento(p_tenant_id uuid, p_payload jsonb)','rpc_update_pedimento(p_id uuid, p_patch jsonb)','rpc_update_tenant_settings(p_tenant_id uuid, p_payload jsonb)','rpc_update_member_role(p_tenant_id uuid, p_member_user_id uuid, p_new_role text)','rpc_deactivate_member(p_tenant_id uuid, p_member_user_id uuid)','rpc_validate_module_access(p_tenant_id uuid, p_module_name text)','rpc_accept_invitation(p_token text)','rpc_list_invitations(p_tenant_id uuid)','rpc_revoke_invitation(p_invitation_id uuid)','rpc_demo_configure_module(p_tenant_id uuid, p_module_name text)','rpc_create_tracking_token(p_tenant_id uuid, p_operation_id uuid, p_scope text)','rpc_create_tracking_token(p_tenant_id uuid, p_operation_id uuid, p_scope text, p_ttl_hours integer, p_force_rotate boolean)','rpc_revoke_tracking_token(p_token_id uuid)','rpc_list_tracking_tokens(p_tenant_id uuid)','tanda1_user_is_member(p_tenant_id uuid)','tanda1_user_has_role(p_tenant_id uuid, p_roles text[])','rpc_dashboard_overview(p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone)','rpc_get_company_fiscal_provider(p_tenant_id uuid, p_company_id uuid)','rpc_reports_pipeline_summary(p_tenant_id uuid)','rpc_dashboard_alerts(p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone)','rpc_reports_inventory_summary(p_tenant_id uuid)','rpc_list_inventory_lots(p_tenant_id uuid, p_filters jsonb)','rpc_list_pedimentos(p_tenant_id uuid, p_filters jsonb)','rpc_list_deals(p_tenant_id uuid, p_filters jsonb)','rpc_get_deal(p_deal_id uuid)','rpc_delete_operation_crossing(p_crossing_id uuid)','rpc_list_deal_activities(p_deal_id uuid)','rpc_get_tenant_settings(p_tenant_id uuid)','rpc_list_audit_log(p_tenant_id uuid, p_limit integer, p_offset integer, p_entity_type text, p_action text, p_start timestamp with time zone, p_end timestamp with time zone)','rpc_list_route_points(p_operation_id uuid, p_start timestamp with time zone, p_end timestamp with time zone, p_limit integer)','rpc_upsert_quote(p_tenant_id uuid, p_deal_id uuid, p_payload jsonb)','rpc_list_claim_documents(p_claim_id uuid)','rpc_list_customers(p_tenant_id uuid, p_filters jsonb)','rpc_get_customer_360(p_customer_id uuid)','rpc_upsert_customer(p_tenant_id uuid, p_customer_id uuid, p_payload jsonb)','rpc_list_providers(p_tenant_id uuid, p_filters jsonb)','rpc_convert_quote_to_operation(p_deal_id uuid, p_conversion_note text)','rpc_upsert_provider(p_tenant_id uuid, p_provider_id uuid, p_payload jsonb)','rpc_list_quotes(p_tenant_id uuid, p_filters jsonb)','rpc_duplicate_quote(p_deal_id uuid)','rpc_return_quote_to_draft(p_deal_id uuid)','rpc_submit_quote_for_review(p_deal_id uuid)','rpc_approve_quote(p_deal_id uuid, p_approval_note text)','rpc_reject_quote(p_deal_id uuid, p_rejection_note text)','rpc_upsert_claim_service_policy(p_tenant_id uuid, p_policy_id uuid, p_payload jsonb)','rpc_create_service_claim(p_tenant_id uuid, p_payload jsonb)','rpc_upsert_claim_financial(p_claim_id uuid, p_financial_id uuid, p_payload jsonb)','rpc_assign_operation_v3(p_tenant_id uuid, p_operation_id uuid, p_execution_type text, p_provider_id uuid, p_provider_name text, p_external_driver jsonb, p_external_vehicle jsonb, p_driver_id uuid, p_driver_name text, p_vehicle_id uuid, p_vehicle_ref text, p_planned_departure timestamp with time zone, p_priority text, p_reason text, p_force_override boolean)','rpc_list_operation_assignment_history(p_operation_id uuid)','rpc_create_operation(p_tenant_id uuid, p_reference_code text, p_route_summary text, p_client_display_name text, p_destination_city text, p_eta_display text, p_status text, p_origin_place jsonb, p_destination_place jsonb, p_eta timestamp with time zone)','rpc_update_operation_details(p_operation_id uuid, p_patch jsonb)','rpc_complete_operation_planning_v2(p_operation_id uuid, p_service_type text, p_origin_place jsonb, p_destination_place jsonb, p_operational_window_start timestamp with time zone, p_operational_window_end timestamp with time zone, p_notes text, p_cargo_summary jsonb, p_route_summary text, p_destination_city text, p_eta timestamp with time zone, p_eta_display text, p_operation_scope text, p_execution_type text, p_provider_cost_amount numeric, p_customer_price_amount numeric, p_pricing_currency text, p_service_catalog_item_id uuid, p_service_catalog_snapshot jsonb, p_boxes_placed_days integer, p_documentation_received_at timestamp with time zone, p_documentation_received_note text)','rpc_update_operation_operational_control(p_operation_id uuid, p_payload jsonb)','rpc_cancel_operation(p_operation_id uuid)','rpc_list_claim_saved_views(p_tenant_id uuid)','rpc_get_operation_requirements(p_operation_id uuid)','rpc_list_operation_tracking_events(p_operation_id uuid)','rpc_list_operation_incidents(p_operation_id uuid)','rpc_get_operation_incident_summary(p_operation_id uuid)','rpc_create_operation_incident(p_operation_id uuid, p_category text, p_title text, p_description text, p_is_blocking boolean, p_tracking_event_id uuid)','rpc_resolve_operation_incident(p_incident_id uuid, p_resolution_note text)','rpc_dismiss_operation_incident(p_incident_id uuid, p_dismiss_note text)','rpc_list_operation_evidence(p_operation_id uuid, p_incident_id uuid)','rpc_add_operation_evidence(p_operation_id uuid, p_incident_id uuid, p_kind text, p_note text, p_file_ref text, p_external_url text)','rpc_list_operation_documents(p_operation_id uuid)','rpc_get_operation_document_summary(p_operation_id uuid)','rpc_upsert_operation_document(p_operation_id uuid, p_document_type text, p_requirement_level text, p_status text, p_document_reference text, p_file_ref text, p_external_url text, p_note text)','rpc_list_operation_crossings(p_operation_id uuid)','rpc_upsert_operation_crossing(p_operation_id uuid, p_payload jsonb)','rpc_get_operation_billing(p_operation_id uuid)','rpc_get_operation_billing_summary(p_operation_id uuid)','rpc_transition_operation_status(p_operation_id uuid, p_to_status text)','rpc_override_operation_status(p_operation_id uuid, p_to_status text, p_reason text)','rpc_close_operation(p_operation_id uuid)','rpc_close_operation_override(p_operation_id uuid, p_override_reason text)','rpc_upsert_business_contact(p_tenant_id uuid, p_contact_id uuid, p_payload jsonb)','rpc_mark_generated_document_printed(p_document_id uuid)','rpc_list_partner_history_page(p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_history_type text, p_cursor jsonb, p_limit integer)','rpc_get_fiscal_provider_config(p_tenant_id uuid)','rpc_get_document_upload_contract(p_tenant_id uuid)','rpc_register_document_file(p_tenant_id uuid, p_payload jsonb)','rpc_list_document_files(p_tenant_id uuid, p_filters jsonb)','rpc_mark_document_file_status(p_file_id uuid, p_status text, p_notes text)','rpc_relate_document_file(p_file_id uuid, p_entity_type text, p_entity_id uuid, p_notes text)','rpc_list_document_relations(p_tenant_id uuid, p_entity_type text, p_entity_id uuid)','rpc_attach_operation_document_file(p_operation_id uuid, p_document_type text, p_file_id uuid, p_note text)','rpc_add_operation_file_evidence(p_operation_id uuid, p_file_id uuid, p_incident_id uuid, p_note text)','rpc_relate_quote_documents_to_operation(p_quote_id uuid, p_operation_id uuid)','rpc_generate_document_f3(p_tenant_id uuid, p_template_type text, p_entity_type text, p_entity_id uuid, p_options jsonb)','rpc_generate_document(p_tenant_id uuid, p_template_type text, p_entity_type text, p_entity_id uuid, p_options jsonb)','rpc_list_generated_documents(p_tenant_id uuid, p_filters jsonb)','rpc_cancel_generated_document(p_document_id uuid, p_reason text)','rpc_list_document_templates_v2(p_tenant_id uuid, p_template_type text)','rpc_list_document_source_options(p_tenant_id uuid, p_template_type text, p_search text)','rpc_record_payment(p_tenant_id uuid, p_payload jsonb)','rpc_update_finance_invoice_status(p_tenant_id uuid, p_id uuid, p_status text)','rpc_finance_overview(p_tenant_id uuid)','rpc_finance_overview(p_tenant_id uuid, p_start_date text, p_end_date text)','rpc_list_finance_invoices(p_tenant_id uuid, p_limit integer, p_status text, p_direction text)','rpc_list_finance_invoices(p_tenant_id uuid, p_limit integer, p_status text, p_direction text, p_start_date text, p_end_date text)','rpc_finance_overview(p_tenant_id uuid, p_filters jsonb)','rpc_list_finance_due_alerts(p_tenant_id uuid, p_days_ahead integer)','rpc_export_finance_ledger(p_tenant_id uuid, p_date_from text, p_date_to text)','rpc_export_finance_ledger(p_tenant_id uuid, p_filters jsonb)','rpc_list_attention_items(p_tenant_id uuid)','rpc_refresh_internal_notifications(p_tenant_id uuid)','rpc_get_internal_notification_unread_count(p_tenant_id uuid)','rpc_get_executive_dashboard(p_tenant_id uuid, p_start_date timestamp with time zone, p_end_date timestamp with time zone)','rpc_mark_internal_notifications_read(p_tenant_id uuid, p_notification_ids uuid[])','rpc_dismiss_internal_notification(p_tenant_id uuid, p_notification_id uuid)','rpc_dismiss_internal_notification(p_notification_id uuid)','rpc_list_saved_views(p_tenant_id uuid, p_module text)','rpc_save_view(p_tenant_id uuid, p_payload jsonb)','rpc_delete_saved_view(p_tenant_id uuid, p_view_id uuid)','rpc_global_search(p_tenant_id uuid, p_query text, p_limit integer)','rpc_validate_bulk_import(p_tenant_id uuid, p_entity_type text, p_mode text, p_rows jsonb)','rpc_start_bulk_import(p_tenant_id uuid, p_entity_type text, p_filename text, p_mode text, p_idempotency_key text, p_total_rows integer, p_validation_summary jsonb)','rpc_list_import_batches(p_tenant_id uuid, p_limit integer)','rpc_apply_bulk_import(p_tenant_id uuid, p_batch_id uuid, p_chunk_key text, p_rows jsonb, p_is_last boolean)','rpc_list_internal_notifications(p_tenant_id uuid, p_limit integer, p_unread_only boolean)','rpc_list_automation_rules(p_tenant_id uuid)','rpc_update_automation_rule(p_tenant_id uuid, p_rule_id uuid, p_payload jsonb)','rpc_evaluate_automations(p_tenant_id uuid)','rpc_get_automation_health(p_tenant_id uuid)','rpc_get_daily_digest(p_tenant_id uuid)','rpc_create_rate(p_tenant_id uuid, p_payload jsonb)','rpc_list_rate_reference_data(p_tenant_id uuid)','rpc_upsert_lane(p_tenant_id uuid, p_lane_id uuid, p_payload jsonb)','rpc_create_rate_version(p_rate_card_id uuid, p_payload jsonb)','rpc_list_rates(p_tenant_id uuid, p_filters jsonb)','rpc_compare_provider_rates(p_tenant_id uuid, p_filters jsonb)','rpc_apply_rate_to_quote(p_deal_id uuid, p_rate_version_id uuid)','rpc_archive_rate(p_rate_card_id uuid)','rpc_duplicate_rate(p_rate_card_id uuid)','rpc_list_partner_contacts(p_tenant_id uuid, p_entity_type text, p_entity_id uuid)','rpc_update_partner_terms(p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_payment_terms_days integer)','rpc_export_rates(p_tenant_id uuid, p_filters jsonb)','rpc_get_partner_compliance_status(p_tenant_id uuid, p_partner_type text, p_partner_id uuid, p_as_of date)','rpc_list_compliance_requirements(p_tenant_id uuid, p_filters jsonb)','rpc_upsert_compliance_requirement(p_tenant_id uuid, p_requirement_id uuid, p_payload jsonb)','rpc_archive_compliance_requirement(p_requirement_id uuid)','rpc_submit_partner_compliance_record(p_tenant_id uuid, p_payload jsonb)','rpc_refresh_compliance_notifications(p_tenant_id uuid)','rpc_review_partner_compliance_record(p_record_id uuid, p_decision text, p_note text)','rpc_waive_partner_requirement(p_tenant_id uuid, p_payload jsonb)','rpc_get_provider_operational_eligibility(p_tenant_id uuid, p_provider_id uuid)','rpc_upsert_partner_contract(p_tenant_id uuid, p_contract_id uuid, p_payload jsonb)','rpc_activate_partner_contract(p_contract_id uuid)','rpc_renew_partner_contract(p_contract_id uuid, p_payload jsonb)','rpc_terminate_partner_contract(p_contract_id uuid, p_reason text)','rpc_list_compliance_matrix(p_tenant_id uuid, p_filters jsonb)','rpc_list_compliance_expirations(p_tenant_id uuid, p_days integer)','rpc_get_provider_compliance_badges(p_tenant_id uuid, p_provider_ids uuid[])','rpc_get_compliance_dashboard(p_tenant_id uuid)','rpc_list_compliance_attention_items(p_tenant_id uuid)','rpc_search_compliance(p_tenant_id uuid, p_query text, p_limit integer)','rpc_export_partner_compliance(p_tenant_id uuid, p_filters jsonb)','rpc_create_provider_compliance_override(p_operation_id uuid, p_provider_id uuid, p_reason text)','rpc_get_operation_dispatch_readiness(p_operation_id uuid)','rpc_get_service_claim(p_claim_id uuid)','rpc_get_claim_reference_data(p_tenant_id uuid)','rpc_list_service_claims(p_tenant_id uuid, p_filters jsonb)','rpc_transition_service_claim(p_claim_id uuid, p_to_status text, p_note text)','rpc_reopen_service_claim(p_claim_id uuid, p_reason text)','rpc_assign_service_claim(p_claim_id uuid, p_user_id uuid)','rpc_update_claim_classification(p_claim_id uuid, p_responsibility text, p_root_cause text, p_note text)','rpc_add_claim_note(p_claim_id uuid, p_note text)','rpc_log_claim_contact(p_claim_id uuid, p_party text, p_contact_id uuid, p_channel text, p_summary text, p_occurred_at timestamp with time zone)','rpc_upsert_claim_action(p_claim_id uuid, p_action_id uuid, p_payload jsonb)','rpc_update_claim_action_status(p_action_id uuid, p_status text, p_completion_note text)','rpc_record_claim_settlement(p_claim_id uuid, p_payload jsonb)','rpc_get_claim_finance_handoff(p_claim_id uuid)','rpc_register_claim_document(p_claim_id uuid, p_payload jsonb)','rpc_relate_claim_document(p_claim_id uuid, p_file_id uuid, p_note text)','rpc_list_partner_claims(p_partner_type text, p_partner_id uuid, p_limit integer)','rpc_get_claims_dashboard(p_tenant_id uuid, p_from timestamp with time zone, p_to timestamp with time zone)','rpc_list_claim_attention_items(p_tenant_id uuid)','rpc_search_claims(p_tenant_id uuid, p_query text, p_limit integer)','rpc_get_claim_reporting(p_tenant_id uuid, p_from timestamp with time zone, p_to timestamp with time zone)','rpc_export_claims(p_tenant_id uuid, p_filters jsonb)','rpc_save_claim_view(p_tenant_id uuid, p_view_id uuid, p_payload jsonb)','rpc_delete_claim_view(p_tenant_id uuid, p_view_id uuid)','rpc_refresh_claim_notifications(p_tenant_id uuid)','rpc_list_descargo_lines(p_pedimento_id uuid)','rpc_add_descargo_line(p_pedimento_id uuid, p_payload jsonb)','rpc_list_deal_notes(p_deal_id uuid)','rpc_list_deal_checklist(p_deal_id uuid)','rpc_add_deal_note(p_deal_id uuid, p_note text)','rpc_toggle_deal_checklist_item(p_item_id uuid, p_is_done boolean)','rpc_create_invitation(p_tenant_id uuid, p_email text, p_role text)','rpc_get_partner_compliance_bundle(p_tenant_id uuid, p_partner_type text, p_partner_id uuid)','rpc_get_rate_360(p_rate_card_id uuid)','rpc_get_customer_partner_360(p_customer_id uuid)','rpc_list_internal_notifications_page(p_tenant_id uuid, p_unread_only boolean, p_cursor jsonb, p_limit integer)','rpc_get_fiscal_operational_status(p_tenant_id uuid)','rpc_update_cfdi_fiscal_input(p_cfdi_id uuid, p_fiscal_input jsonb, p_cfdi_version text)','rpc_update_fiscal_provider_config(p_tenant_id uuid, p_provider_code text, p_enabled boolean, p_environment text, p_capabilities jsonb)','rpc_reports_tanda1(p_tenant_id uuid, p_date_from text, p_date_to text)','rpc_fiscal01_context(p_cfdi_id uuid)','rpc_create_payment_complement(p_tenant_id uuid, p_payload jsonb)','rpc_get_provider_360(p_provider_id uuid)','rpc_reset_cfdi_fiscal_draft(p_cfdi_id uuid, p_reason text)','rpc_prepare_cfdi_for_api(p_cfdi_id uuid)','rpc_retry_fiscal_request(p_request_id uuid)','rpc_request_fiscal_cancellation(p_cfdi_id uuid, p_reason text)','rpc_queue_fiscal_status_check(p_cfdi_id uuid)','rpc_get_finance_invoice_detail(p_tenant_id uuid, p_invoice_id uuid)','rpc_list_finance_invoices(p_tenant_id uuid, p_filters jsonb)','rpc_list_finance_payments(p_tenant_id uuid, p_filters jsonb)','rpc_list_finance_due_alerts(p_tenant_id uuid, p_filters jsonb)','rpc_get_operation_finance_summary(p_tenant_id uuid, p_operation_id uuid)','rpc_finance_profitability(p_tenant_id uuid, p_filters jsonb)','rpc_list_payment_complements(p_tenant_id uuid, p_filters jsonb)','rpc_void_finance_invoice(p_tenant_id uuid, p_id uuid, p_reason text)','rpc_get_fiscal_readiness(p_cfdi_id uuid)','rpc_queue_fiscal_stamp(p_cfdi_id uuid)','rpc_configure_company_fiscal_provider(p_tenant_id uuid, p_company_id uuid, p_provider_code text, p_environment text, p_approval_reference text)','rpc_delivery_context(p_tenant_id uuid)'])) AND NOT private.c02_is_reviewed_api(f.oid) THEN RAISE EXCEPTION 'unreviewed_authenticated_RPC: %',f.proname;END IF;
 END LOOP;
 IF EXISTS(SELECT FROM pg_class WHERE relnamespace='public'::regnamespace AND relkind IN('v','m')
  AND (has_table_privilege('authenticated',oid,'SELECT') OR has_table_privilege('anon',oid,'SELECT')))
 THEN RAISE EXCEPTION 'unreviewed_public_view'; END IF;
END $surface$;
COMMIT;
