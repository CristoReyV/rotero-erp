-- Company-scoped operational and receivables contracts. No backfill or grants.
BEGIN;

ALTER TABLE public.document_files ADD COLUMN access_class text NOT NULL DEFAULT 'unclassified'
    CHECK(access_class IN('unclassified','operational','receivable','financial'));
ALTER TABLE public.generated_documents ADD COLUMN access_class text NOT NULL DEFAULT 'unclassified'
    CHECK(access_class IN('unclassified','operational','receivable','financial'));
ALTER TABLE public.document_files ADD CONSTRAINT file_delivery_access_class_evidence_fk
 FOREIGN KEY(company_entity_table,tenant_id,id,company_id,access_class,company_classification_event_id)
 REFERENCES private.delivery_classification_events(entity_table,tenant_id,entity_id,company_id,access_class,id);
ALTER TABLE public.generated_documents ADD CONSTRAINT generated_delivery_access_class_evidence_fk
 FOREIGN KEY(company_entity_table,tenant_id,id,company_id,access_class,company_classification_event_id)
 REFERENCES private.delivery_classification_events(entity_table,tenant_id,entity_id,company_id,access_class,id);

CREATE FUNCTION private.delivery_file_allowed(p_id uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE f public.document_files%ROWTYPE;c uuid;
BEGIN
 SELECT * INTO f FROM public.document_files WHERE id=p_id AND status='active';
 IF NOT FOUND OR f.storage_bucket<>'tenant-documents' OR f.company_classification_status<>'resolved' OR f.access_class='unclassified'
    OR NOT private.delivery_scope_allowed(f.tenant_id) OR NOT(f.company_id=ANY(private.delivery_company_ids()))
    OR NOT private.delivery_cap(f.tenant_id,'billing.document.read') THEN RETURN false; END IF;
 c:=private.delivery_root_company(f.tenant_id,f.source_entity_type,f.source_entity_id);
 IF c IS DISTINCT FROM f.company_id THEN RETURN false; END IF;
 IF f.source_entity_type IN('finance_invoice','billing_document','billing_cfdi') AND private.fiscal02_is_lab_entity(
  CASE f.source_entity_type WHEN 'finance_invoice' THEN 'invoice' WHEN 'billing_document' THEN 'document' ELSE 'cfdi' END,f.source_entity_id)
 THEN RETURN false; END IF;
 IF f.source_entity_type IN('finance_invoice','billing_document') AND NOT private.delivery_entity_allowed(f.tenant_id,
  CASE f.source_entity_type WHEN 'finance_invoice' THEN 'invoice' ELSE 'document' END,f.source_entity_id) THEN RETURN false; END IF;
 IF f.access_class='operational' THEN
  RETURN f.source_entity_type='operation' AND private.delivery_cap(f.tenant_id,'operations.read');
 ELSIF f.access_class='receivable' THEN
  RETURN public.tanda1_user_has_role(f.tenant_id,ARRAY['admin','finance']) AND private.delivery_cap(f.tenant_id,'receivables.read') AND f.source_entity_type='finance_invoice'
   AND EXISTS(SELECT FROM public.finance_invoices i WHERE i.id=f.source_entity_id AND i.tenant_id=f.tenant_id
      AND i.direction='ar' AND i.payroll_period_id IS NULL
      AND NOT private.fiscal02_is_lab_entity('invoice',i.id));
 END IF;
 RETURN f.access_class='financial' AND private.delivery_cap(f.tenant_id,'financial.full.read');
END $$;
REVOKE ALL ON FUNCTION private.delivery_file_allowed(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.delivery_storage_allowed(p_bucket text,p_name text) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 RETURN p_bucket='tenant-documents' AND EXISTS(SELECT FROM public.document_files f
  WHERE f.storage_bucket=p_bucket AND f.storage_path=p_name AND private.delivery_file_allowed(f.id));
END $$;
REVOKE ALL ON FUNCTION private.delivery_storage_allowed(text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION private.delivery_storage_allowed(text,text) TO authenticated;
CREATE POLICY delivery_storage_read ON storage.objects AS RESTRICTIVE FOR SELECT TO authenticated
USING(bucket_id<>'tenant-documents' OR
 CASE WHEN private.delivery_required(private.f3_storage_tenant_from_path(name)) OR private.delivery_required(NULL)
 THEN private.delivery_storage_allowed(bucket_id,name) ELSE true END);
CREATE POLICY delivery_storage_insert ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK(bucket_id<>'tenant-documents' OR
 (NOT private.delivery_required(private.f3_storage_tenant_from_path(name)) AND NOT private.delivery_required(NULL)));
CREATE POLICY delivery_storage_update ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated
USING(bucket_id<>'tenant-documents' OR
 (NOT private.delivery_required(private.f3_storage_tenant_from_path(name)) AND NOT private.delivery_required(NULL)))
WITH CHECK(bucket_id<>'tenant-documents' OR
 (NOT private.delivery_required(private.f3_storage_tenant_from_path(name)) AND NOT private.delivery_required(NULL)));
CREATE POLICY delivery_storage_delete ON storage.objects AS RESTRICTIVE FOR DELETE TO authenticated
USING(bucket_id<>'tenant-documents' OR
 (NOT private.delivery_required(private.f3_storage_tenant_from_path(name)) AND NOT private.delivery_required(NULL)));

CREATE FUNCTION public.rpc_delivery_operation_files(p_tenant_id uuid,p_operation_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private.delivery_entity_allowed(p_tenant_id,'operation',p_operation_id)
 OR NOT private.delivery_cap(p_tenant_id,'operations.read') OR NOT private.delivery_cap(p_tenant_id,'billing.document.read')
 THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 RETURN jsonb_build_object('items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
  'id',f.id,'file_name',f.file_name,'mime_type',f.mime_type,'size_bytes',f.size_bytes,'created_at',f.created_at)
  ORDER BY f.created_at,f.id) FROM public.document_files f
  WHERE f.tenant_id=p_tenant_id AND f.source_entity_type='operation' AND f.source_entity_id=p_operation_id
    AND private.delivery_file_allowed(f.id)),'[]'::jsonb));
END $$;

CREATE FUNCTION public.rpc_delivery_file_download(p_tenant_id uuid,p_file_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private.delivery_file_allowed(p_file_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 RETURN COALESCE((SELECT jsonb_build_object('id',f.id,'bucket',f.storage_bucket,'path',f.storage_path,
 'file_name',f.file_name,'mime_type',f.mime_type) FROM public.document_files f
 WHERE f.id=p_file_id AND f.tenant_id=p_tenant_id),jsonb_build_object('error','unauthorized'));
END $$;

CREATE FUNCTION public.rpc_delivery_entity_files(p_tenant_id uuid,p_entity_type text,p_entity_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE c uuid;allowed boolean;
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'billing.document.read') OR p_entity_type NOT IN('operation','finance_invoice','billing_document','billing_cfdi','quote')
 THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 c:=private.delivery_root_company(p_tenant_id,p_entity_type,p_entity_id);
 IF c IS NULL OR NOT(c=ANY(private.delivery_company_ids())) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 allowed:=private.delivery_cap(p_tenant_id,'financial.full.read') OR (p_entity_type='operation' AND private.delivery_cap(p_tenant_id,'operations.read'))
 OR (p_entity_type='finance_invoice' AND public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','finance']) AND private.delivery_cap(p_tenant_id,'receivables.read') AND EXISTS(SELECT FROM public.finance_invoices WHERE id=p_entity_id AND tenant_id=p_tenant_id AND direction='ar' AND payroll_period_id IS NULL));
 IF NOT COALESCE(allowed,false) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 RETURN jsonb_build_object('items',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',f.id,'file_name',f.file_name,'mime_type',f.mime_type,'size_bytes',f.size_bytes,'created_at',f.created_at) ORDER BY f.created_at,f.id)
 FROM public.document_files f WHERE f.tenant_id=p_tenant_id AND f.source_entity_type=p_entity_type AND f.source_entity_id=p_entity_id AND private.delivery_file_allowed(f.id)),'[]'::jsonb));
END $$;

CREATE FUNCTION public.rpc_delivery_files_page(p_tenant_id uuid,p_search text DEFAULT '',p_after_id uuid DEFAULT NULL,p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE items jsonb;total bigint;next_id uuid;
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'billing.document.read') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 IF p_search IS NULL OR length(p_search)>160 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RETURN jsonb_build_object('error','invalid_filters'); END IF;
 IF p_after_id IS NOT NULL AND NOT EXISTS(SELECT FROM public.document_files WHERE id=p_after_id AND tenant_id=p_tenant_id AND private.delivery_file_allowed(id)) THEN RETURN jsonb_build_object('error','invalid_cursor'); END IF;
 WITH scoped AS MATERIALIZED(SELECT id,file_name,mime_type,size_bytes,created_at FROM public.document_files
 WHERE tenant_id=p_tenant_id AND private.delivery_file_allowed(id) AND (p_search='' OR position(lower(p_search) IN lower(file_name))>0)),
 page AS(SELECT * FROM scoped WHERE p_after_id IS NULL OR id>p_after_id ORDER BY id LIMIT p_limit)
 SELECT (SELECT count(*) FROM scoped),(SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.id),'[]') FROM page p),
 CASE WHEN EXISTS(SELECT FROM scoped WHERE id>(SELECT id FROM page ORDER BY id DESC LIMIT 1)) THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END INTO total,items,next_id;
 RETURN jsonb_build_object('items',items,'total',total,'next_cursor',next_id,'classification_notice','classified and authorized files only');
END $$;

CREATE FUNCTION public.rpc_delivery_operations_page(p_tenant_id uuid,p_search text DEFAULT '',
 p_after_id uuid DEFAULT NULL,p_limit integer DEFAULT 50,p_export boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE items jsonb;total bigint;next_id uuid;
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'operations.read') OR p_export IS NULL
 OR (p_export AND NOT private.delivery_cap(p_tenant_id,'export.operational')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 IF p_search IS NULL OR length(p_search)>160 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RETURN jsonb_build_object('error','invalid_filters'); END IF;
 IF p_after_id IS NOT NULL AND NOT EXISTS(SELECT FROM private.delivery_operations WHERE tenant_id=p_tenant_id AND id=p_after_id)
 THEN RETURN jsonb_build_object('error','invalid_cursor'); END IF;
 WITH scoped AS MATERIALIZED(SELECT o.* FROM private.delivery_operations o WHERE o.tenant_id=p_tenant_id
 AND (p_search='' OR position(lower(p_search) IN lower(concat_ws(' ',o.reference_code,o.route_summary,o.client_display_name,o.provider_name)))>0)),
 page AS(SELECT * FROM scoped WHERE p_after_id IS NULL OR id>p_after_id ORDER BY id LIMIT p_limit)
 SELECT (SELECT count(*) FROM scoped),(SELECT COALESCE(jsonb_agg(private.delivery_operation_dto(to_jsonb(p)) ORDER BY p.id),'[]') FROM page p),
 CASE WHEN EXISTS(SELECT FROM scoped WHERE id>(SELECT id FROM page ORDER BY id DESC LIMIT 1))
 THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END INTO total,items,next_id;
 RETURN jsonb_build_object('items',items,'total',total,'next_cursor',next_id,'company_ids',private.delivery_company_ids(),
 'classification_notice','resolved_only; unclassified history requires reviewed reconciliation');
END $$;

-- Existing F4 balance arithmetic is preserved. This projection authorizes AR face
-- amounts and balances as receivables work, without exposing AP, costs or margins.
CREATE FUNCTION public.rpc_delivery_receivables_page(p_tenant_id uuid,p_search text DEFAULT '',
 p_after_id uuid DEFAULT NULL,p_limit integer DEFAULT 50,p_export boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE items jsonb;total bigint;next_id uuid;
BEGIN
 IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','finance']) OR NOT private.delivery_cap(p_tenant_id,'receivables.read') OR p_export IS NULL
 OR (p_export AND NOT private.delivery_cap(p_tenant_id,'export.receivables')) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 IF p_search IS NULL OR length(p_search)>160 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RETURN jsonb_build_object('error','invalid_filters'); END IF;
 IF p_after_id IS NOT NULL AND NOT EXISTS(SELECT FROM public.finance_invoices i WHERE i.id=p_after_id
  AND i.tenant_id=p_tenant_id AND i.direction='ar' AND i.payroll_period_id IS NULL
  AND private.delivery_entity_allowed(i.tenant_id,'invoice',i.id)
  AND NOT private.fiscal02_is_lab_entity('invoice',i.id)) THEN RETURN jsonb_build_object('error','invalid_cursor'); END IF;
 WITH scoped AS MATERIALIZED(SELECT i.id,i.company_id,i.operation_id,i.reference,i.counterparty_name,i.currency,i.status,
 i.due_date,i.amount,t.paid_amount,t.credit_amount,t.balance_amount,i.created_at
 FROM public.finance_invoices i CROSS JOIN LATERAL private.f4_invoice_totals(i.id) t
 WHERE i.tenant_id=p_tenant_id AND i.direction='ar' AND i.payroll_period_id IS NULL
 AND private.delivery_entity_allowed(i.tenant_id,'invoice',i.id)
 AND NOT private.fiscal02_is_lab_entity('invoice',i.id)
 AND (p_search='' OR position(lower(p_search) IN lower(concat_ws(' ',i.reference,i.counterparty_name)))>0)),
 page AS(SELECT * FROM scoped WHERE p_after_id IS NULL OR id>p_after_id ORDER BY id LIMIT p_limit)
 SELECT (SELECT count(*) FROM scoped),(SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.id),'[]') FROM page p),
 CASE WHEN EXISTS(SELECT FROM scoped WHERE id>(SELECT id FROM page ORDER BY id DESC LIMIT 1))
 THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END INTO total,items,next_id;
 RETURN jsonb_build_object('items',items,'total',total,'next_cursor',next_id,'company_ids',private.delivery_company_ids(),
 'classification_notice','resolved_only; excludes unclassified history, payroll and fiscal laboratory');
END $$;

-- Company search reads only the same operational projection. Other entity kinds
-- remain explicitly pending; no tenant-wide partner/claim/quote fallback.
CREATE FUNCTION public.rpc_delivery_search(p_tenant_id uuid,p_query text,p_limit integer DEFAULT 20) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'operations.read') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 IF p_query IS NULL OR length(p_query)>160 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN RETURN jsonb_build_object('error','invalid_filters'); END IF;
 RETURN jsonb_build_object('items',COALESCE((SELECT jsonb_agg(jsonb_build_object('type','operation','id',o.id,
 'primary_label',o.reference_code,'secondary_label',o.route_summary,'status',o.status,'module','operations',
 'route','/operations?operation_id='||o.id::text)) FROM(SELECT id,reference_code,route_summary,status FROM private.delivery_operations
 WHERE tenant_id=p_tenant_id AND position(lower(p_query) IN lower(concat_ws(' ',reference_code,route_summary,client_display_name)))>0
 ORDER BY id LIMIT p_limit)o),'[]'::jsonb));
END $$;

-- Read-only listing; legacy free-text materialized notifications have no approved
-- sensitivity classification. They are not exposed as operational DTOs by default.
CREATE FUNCTION public.rpc_delivery_notifications(p_tenant_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE items jsonb;
BEGIN
 IF NOT private.delivery_scope_allowed(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',n.id,'module',n.area,'kind',n.trigger_type,'priority',n.priority,
 'title',n.title,'body',n.body,'route',n.route,'entity_type',n.related_entity_type,'entity_id',n.related_entity_id,
 'occurred_at',n.first_seen_at,'read_at',n.read_at,'created_at',n.first_seen_at) ORDER BY n.first_seen_at DESC),'[]') INTO items
 FROM public.internal_notifications n WHERE n.tenant_id=p_tenant_id AND n.user_id=auth.uid()
 AND n.company_classification_status='resolved' AND n.company_id=ANY(private.delivery_company_ids())
 AND n.status<>'dismissed' AND n.resolved_at IS NULL AND private.delivery_cap(n.tenant_id,'financial.full.read');
 RETURN jsonb_build_object('items',items,'unread_count',(SELECT count(*) FROM jsonb_array_elements(items) e WHERE e->>'read_at' IS NULL),
 'has_more',false,'next_cursor',NULL,'classification_notice','Only classified notifications; no automatic materialization');
END $$;

DO $acl$ DECLARE f record;BEGIN
 FOR f IN SELECT p.oid::regprocedure signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN('rpc_delivery_operation_files','rpc_delivery_file_download',
 'rpc_delivery_operations_page','rpc_delivery_receivables_page','rpc_delivery_search','rpc_delivery_notifications','rpc_delivery_entity_files','rpc_delivery_files_page') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,service_role',f.signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.signature);
 END LOOP;
END $acl$;
CREATE INDEX file_delivery_access_evidence_fk_idx ON public.document_files
 (company_entity_table,tenant_id,id,company_id,access_class,company_classification_event_id);
CREATE INDEX generated_delivery_access_evidence_fk_idx ON public.generated_documents
 (company_entity_table,tenant_id,id,company_id,access_class,company_classification_event_id);
COMMIT;
