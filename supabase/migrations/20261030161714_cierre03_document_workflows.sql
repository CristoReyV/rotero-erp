-- Managed uploads are write-once objects. Existing classified history is retained.
BEGIN;
SET LOCAL ROLE rotero_company_access_owner;
GRANT REFERENCES(tenant_id,id) ON public.companies TO postgres;
SET LOCAL ROLE postgres;
CREATE TABLE private.c03_document_uploads(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tenant_id uuid NOT NULL REFERENCES public.tenants(id),
 company_id uuid NOT NULL,actor_id uuid NOT NULL,request_id uuid NOT NULL,
 source_entity_type text NOT NULL CHECK(source_entity_type IN('operation','finance_invoice','billing_document')),
 source_entity_id uuid NOT NULL,access_class text NOT NULL CHECK(access_class IN('operational','financial')),
 storage_path text NOT NULL UNIQUE,file_name text NOT NULL,mime_type text NOT NULL,size_bytes bigint NOT NULL CHECK(size_bytes>0),
 checksum_sha256 text NOT NULL CHECK(checksum_sha256 ~ '^[a-f0-9]{64}$'),
 replaces_file_id uuid REFERENCES public.document_files(id),reason text,
 created_at timestamptz NOT NULL DEFAULT now(),expires_at timestamptz NOT NULL DEFAULT now()+interval '15 minutes',
 file_id uuid REFERENCES public.document_files(id),UNIQUE(tenant_id,actor_id,request_id),
 FOREIGN KEY(tenant_id,company_id) REFERENCES public.companies(tenant_id,id));
SET LOCAL ROLE rotero_company_access_owner;
REVOKE REFERENCES(tenant_id,id) ON public.companies FROM postgres;
SET LOCAL ROLE postgres;
CREATE TABLE private.c03_document_events(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tenant_id uuid NOT NULL REFERENCES public.tenants(id),
 file_id uuid NOT NULL REFERENCES public.document_files(id),previous_file_id uuid REFERENCES public.document_files(id),
 actor_id uuid NOT NULL,action text NOT NULL CHECK(action IN('registered','replaced','cancelled')),
 reason text,created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE private.c03_document_uploads ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.c03_document_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.c03_document_uploads,private.c03_document_events FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.c03_document_event_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'document_evidence_immutable';END $$;
REVOKE ALL ON FUNCTION private.c03_document_event_immutable() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER c03_document_events_immutable BEFORE UPDATE OR DELETE ON private.c03_document_events
 FOR EACH ROW EXECUTE FUNCTION private.c03_document_event_immutable();
CREATE INDEX c03_document_events_file ON private.c03_document_events(file_id,created_at,id);
CREATE UNIQUE INDEX c03_document_single_replacement ON private.c03_document_events(previous_file_id)
 WHERE previous_file_id IS NOT NULL AND action='replaced';
CREATE INDEX c03_document_uploads_pending ON private.c03_document_uploads(tenant_id,actor_id,expires_at) WHERE file_id IS NULL;

CREATE FUNCTION private.c03_document_access(t uuid,k text,parent uuid,classification text,writing boolean DEFAULT false)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE c uuid;
BEGIN
 IF k NOT IN('operation','finance_invoice','billing_document') OR classification NOT IN('operational','financial')
  OR NOT private.delivery_required(t) OR NOT private.delivery_cap(t,'billing.document.read') THEN RETURN false;END IF;
 c:=private.delivery_root_company(t,k,parent);
 IF c IS NULL OR NOT(c=ANY(private.delivery_company_ids())) OR NOT private.delivery_entity_allowed(t,
  CASE k WHEN 'finance_invoice' THEN 'invoice' WHEN 'billing_document' THEN 'document' ELSE k END,parent) THEN RETURN false;END IF;
 IF k='finance_invoice' AND NOT EXISTS(SELECT FROM private.delivery_finance_invoices WHERE tenant_id=t AND id=parent) THEN RETURN false;END IF;
 IF k='billing_document' AND NOT EXISTS(SELECT FROM private.delivery_billing_documents WHERE tenant_id=t AND id=parent) THEN RETURN false;END IF;
 IF k IN('finance_invoice','billing_document') AND private.fiscal02_is_lab_entity(
  CASE k WHEN 'finance_invoice' THEN 'invoice' ELSE 'document' END,parent) THEN RETURN false;END IF;
 IF classification='operational' THEN
  IF k<>'operation' OR NOT private.delivery_cap(t,'operations.read') THEN RETURN false;END IF;
 ELSE
  IF NOT private.delivery_cap(t,'financial.full.read') THEN RETURN false;END IF;
 END IF;
 IF NOT writing THEN RETURN true;END IF;
 RETURN cardinality(private.delivery_company_ids())=1 AND private.delivery_cap(t,'documents.upload')
  AND CASE classification WHEN 'operational' THEN private.delivery_cap(t,'operations.evidence.write')
    AND public.tanda1_user_has_role(t,ARRAY['admin','operator'])
   ELSE private.delivery_cap(t,'finance.write') AND public.tanda1_user_has_role(t,ARRAY['admin','finance']) END;
END $$;
REVOKE ALL ON FUNCTION private.c03_document_access(uuid,text,uuid,text,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.rpc_delivery_prepare_upload(p_tenant_id uuid,p_request_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE u uuid;k text;parent uuid;classification text;c uuid;b storage.buckets%ROWTYPE;i private.c03_document_uploads%ROWTYPE;
 old public.document_files%ROWTYPE;name text;mime text;n bigint;checksum text;previous uuid;reason text;module text;path text;
BEGIN
 u:=(SELECT auth.uid());
 IF u IS NULL OR p_request_id IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object'
  OR p_payload-ARRAY['entity_type','entity_id','access_class','file_name','mime_type','size_bytes','checksum_sha256','replaces_file_id','reason']<>'{}'::jsonb
 THEN RETURN jsonb_build_object('error','invalid_payload');END IF;
 BEGIN
  k:=p_payload->>'entity_type';parent:=(p_payload->>'entity_id')::uuid;classification:=p_payload->>'access_class';
  name:=p_payload->>'file_name';mime:=lower(p_payload->>'mime_type');n:=(p_payload->>'size_bytes')::bigint;
  checksum:=p_payload->>'checksum_sha256';previous:=(p_payload->>'replaces_file_id')::uuid;reason:=nullif(btrim(p_payload->>'reason'),'');
 EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN jsonb_build_object('error','invalid_payload');END;
 IF NOT COALESCE(private.c03_document_access(p_tenant_id,k,parent,classification,true),false) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 IF name IS NULL OR length(name) NOT BETWEEN 1 AND 180 OR (name ~ '[[:cntrl:]/]' OR position(chr(92) IN name)>0) OR n IS NULL OR n<=0
  OR checksum IS NULL OR checksum !~ '^[a-f0-9]{64}$' OR length(COALESCE(reason,''))>1000 THEN RETURN jsonb_build_object('error','invalid_payload');END IF;
 SELECT * INTO b FROM storage.buckets WHERE id='tenant-documents' AND NOT public;
 IF NOT FOUND OR b.file_size_limit IS NULL OR n>b.file_size_limit OR NOT COALESCE(mime=ANY(b.allowed_mime_types),false)
  OR NOT private.f3_extension_matches_mime(name,mime) THEN RETURN jsonb_build_object('error','file_type_or_size_not_allowed');END IF;
 c:=private.delivery_root_company(p_tenant_id,k,parent);
 IF previous IS NOT NULL THEN
  SELECT * INTO old FROM public.document_files WHERE id=previous AND tenant_id=p_tenant_id;
  IF NOT FOUND OR old.company_id<>c OR old.source_entity_type<>k OR old.source_entity_id<>parent OR old.access_class<>classification
   OR old.status<>'active' OR reason IS NULL OR NOT private.delivery_cap(p_tenant_id,'documents.manage')
  THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||u::text||p_request_id::text,1));
 SELECT * INTO i FROM private.c03_document_uploads WHERE tenant_id=p_tenant_id AND actor_id=u AND request_id=p_request_id;
 IF FOUND THEN
  IF ROW(i.company_id,i.source_entity_type,i.source_entity_id,i.access_class,i.file_name,i.mime_type,i.size_bytes,i.checksum_sha256,i.replaces_file_id,i.reason)
   IS DISTINCT FROM ROW(c,k,parent,classification,name,mime,n,checksum,previous,reason) THEN RETURN jsonb_build_object('error','request_conflict');END IF;
  IF i.expires_at<=now() AND i.file_id IS NULL THEN RETURN jsonb_build_object('error','upload_expired');END IF;
 ELSE
  module:=CASE k WHEN 'operation' THEN 'operations' WHEN 'billing_document' THEN 'billing' ELSE 'finance' END;
  path:=p_tenant_id::text||'/'||module||'/'||k||'/'||parent::text||'/c03-'||gen_random_uuid()::text||'.'||lower(reverse(split_part(reverse(name),'.',1)));
  INSERT INTO private.c03_document_uploads(tenant_id,company_id,actor_id,request_id,source_entity_type,source_entity_id,access_class,
   storage_path,file_name,mime_type,size_bytes,checksum_sha256,replaces_file_id,reason)
  VALUES(p_tenant_id,c,u,p_request_id,k,parent,classification,path,name,mime,n,checksum,previous,reason) RETURNING * INTO i;
 END IF;
 RETURN jsonb_build_object('id',i.id,'bucket','tenant-documents','path',i.storage_path,'expires_at',i.expires_at,'file_id',i.file_id);
END $$;

CREATE FUNCTION private.c03_upload_allowed(bucket text,path text,owner_id text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT bucket='tenant-documents' AND EXISTS(SELECT FROM private.c03_document_uploads i
 WHERE i.storage_path=path AND i.actor_id=(SELECT auth.uid()) AND owner_id=i.actor_id::text
 AND i.file_id IS NULL AND i.expires_at>now() AND private.c03_document_access(i.tenant_id,i.source_entity_type,i.source_entity_id,i.access_class,true));
$$;
REVOKE ALL ON FUNCTION private.c03_upload_allowed(text,text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION private.c03_upload_allowed(text,text,text) TO authenticated;
-- Preserve every legacy fence. Only a fresh owned, scoped upload intent can
-- satisfy INSERT for a cutover tenant; UPDATE/upsert and DELETE stay closed.
ALTER POLICY delivery_storage_insert ON storage.objects WITH CHECK(bucket_id<>'tenant-documents' OR
 CASE WHEN private.delivery_required(private.f3_storage_tenant_from_path(name)) OR private.delivery_required(NULL)
 THEN private.c03_upload_allowed(bucket_id,name,owner_id)
 ELSE true END);
CREATE POLICY c03_storage_insert ON storage.objects FOR INSERT TO authenticated
 WITH CHECK(private.c03_upload_allowed(bucket_id,name,owner_id));
CREATE POLICY c03_storage_read ON storage.objects FOR SELECT TO authenticated
 USING(private.delivery_storage_allowed(bucket_id,name));

CREATE FUNCTION public.rpc_delivery_finalize_upload(p_tenant_id uuid,p_upload_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i private.c03_document_uploads%ROWTYPE;old public.document_files%ROWTYPE;object storage.objects%ROWTYPE;
 u uuid;f uuid;e uuid;module text;kind text;
BEGIN
 u:=(SELECT auth.uid());
 SELECT * INTO i FROM private.c03_document_uploads WHERE id=p_upload_id AND tenant_id=p_tenant_id AND actor_id=u FOR UPDATE;
 IF NOT FOUND OR NOT private.c03_document_access(i.tenant_id,i.source_entity_type,i.source_entity_id,i.access_class,true)
 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 IF i.source_entity_type='operation' THEN PERFORM 1 FROM public.operations WHERE tenant_id=i.tenant_id AND id=i.source_entity_id FOR UPDATE;END IF;
 IF NOT private.c03_document_access(i.tenant_id,i.source_entity_type,i.source_entity_id,i.access_class,true) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 IF i.file_id IS NOT NULL THEN RETURN jsonb_build_object('id',i.file_id,'success',true);END IF;
 IF i.expires_at<=now() THEN RETURN jsonb_build_object('error','upload_expired');END IF;
 SELECT * INTO object FROM storage.objects WHERE bucket_id='tenant-documents' AND name=i.storage_path;
 IF NOT FOUND OR object.owner_id IS DISTINCT FROM u::text
  OR object.metadata->>'size' IS DISTINCT FROM i.size_bytes::text OR lower(object.metadata->>'mimetype') IS DISTINCT FROM i.mime_type
 THEN RETURN jsonb_build_object('error','storage_object_not_verified');END IF;
 IF i.replaces_file_id IS NOT NULL THEN
  SELECT * INTO old FROM public.document_files WHERE id=i.replaces_file_id FOR UPDATE;
  IF old.status<>'active' OR old.tenant_id<>i.tenant_id OR old.company_id<>i.company_id OR old.source_entity_type<>i.source_entity_type
   OR old.source_entity_id<>i.source_entity_id OR old.access_class<>i.access_class OR NOT private.delivery_cap(i.tenant_id,'documents.manage')
  THEN RETURN jsonb_build_object('error','replacement_conflict');END IF;
 END IF;
 module:=CASE i.source_entity_type WHEN 'operation' THEN 'operations' WHEN 'billing_document' THEN 'billing' ELSE 'finance' END;
 kind:=CASE i.access_class WHEN 'operational' THEN 'operation_evidence' ELSE 'supporting_file' END;
 INSERT INTO public.document_files(tenant_id,storage_path,file_name,mime_type,size_bytes,checksum_sha256,file_kind,
  source_module,source_entity_type,source_entity_id,uploaded_by,access_class)
 VALUES(i.tenant_id,i.storage_path,i.file_name,i.mime_type,i.size_bytes,i.checksum_sha256,kind,module,i.source_entity_type,i.source_entity_id,u,i.access_class)
 RETURNING id INTO f;
 INSERT INTO private.delivery_classification_events(tenant_id,entity_table,entity_id,company_id,access_class,evidence_reference,recorded_by)
 VALUES(i.tenant_id,'document_files',f,i.company_id,i.access_class,'c03-upload:'||i.id::text,u) RETURNING id INTO e;
 UPDATE public.document_files SET company_id=i.company_id,company_classification_event_id=e,company_classification_status='resolved' WHERE id=f;
 IF i.replaces_file_id IS NOT NULL THEN
  UPDATE public.document_files SET status='superseded',updated_at=now() WHERE id=i.replaces_file_id;
  IF i.source_entity_type='operation' AND i.access_class='operational' THEN
   UPDATE public.operation_documents SET file_ref=f::text,updated_by=u,updated_at=now()
   WHERE tenant_id=i.tenant_id AND operation_id=i.source_entity_id AND file_ref=i.replaces_file_id::text;
  END IF;
 END IF;
 IF i.source_entity_type='operation' THEN UPDATE public.operations SET workflow_revision=workflow_revision+1 WHERE tenant_id=i.tenant_id AND id=i.source_entity_id;END IF;
 INSERT INTO private.c03_document_events(tenant_id,file_id,previous_file_id,actor_id,action,reason)
 VALUES(i.tenant_id,f,i.replaces_file_id,u,CASE WHEN i.replaces_file_id IS NULL THEN 'registered' ELSE 'replaced' END,i.reason);
 UPDATE private.c03_document_uploads SET file_id=f WHERE id=i.id;
 PERFORM public.rpc_write_audit(i.tenant_id,'c03_document_registered','document_file',f,jsonb_build_object('previous_file_id',i.replaces_file_id,'access_class',i.access_class));
 RETURN jsonb_build_object('id',f,'success',true);
END $$;

CREATE FUNCTION public.rpc_delivery_cancel_file(p_tenant_id uuid,p_file_id uuid,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE f public.document_files%ROWTYPE;u uuid;
BEGIN
 u:=(SELECT auth.uid());
 SELECT * INTO f FROM public.document_files WHERE id=p_file_id AND tenant_id=p_tenant_id;
 IF FOUND AND f.source_entity_type='operation' THEN PERFORM 1 FROM public.operations WHERE tenant_id=p_tenant_id AND id=f.source_entity_id FOR UPDATE;END IF;
 SELECT * INTO f FROM public.document_files WHERE id=p_file_id AND tenant_id=p_tenant_id FOR UPDATE;
 IF NOT FOUND OR u IS NULL OR NOT private.c03_document_access(p_tenant_id,f.source_entity_type,f.source_entity_id,f.access_class,true)
  OR NOT private.delivery_cap(p_tenant_id,'documents.manage') THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 1000 THEN RETURN jsonb_build_object('error','reason_required');END IF;
 IF f.status<>'active' THEN RETURN jsonb_build_object('error','invalid_status');END IF;
 UPDATE public.document_files SET status='cancelled',updated_at=now() WHERE id=p_file_id;
 IF f.source_entity_type='operation' THEN
  IF f.access_class='operational' THEN
   UPDATE public.operation_documents SET file_ref=NULL,
    status=CASE WHEN nullif(btrim(document_reference),'') IS NULL AND nullif(btrim(external_url),'') IS NULL THEN 'missing' ELSE status END,
    updated_by=u,updated_at=now() WHERE tenant_id=p_tenant_id AND operation_id=f.source_entity_id AND file_ref=p_file_id::text;
  END IF;
  UPDATE public.operations SET workflow_revision=workflow_revision+1 WHERE tenant_id=p_tenant_id AND id=f.source_entity_id;
 END IF;
 INSERT INTO private.c03_document_events(tenant_id,file_id,actor_id,action,reason) VALUES(p_tenant_id,p_file_id,u,'cancelled',btrim(p_reason));
 PERFORM public.rpc_write_audit(p_tenant_id,'c03_document_cancelled','document_file',p_file_id,'{}');
 RETURN jsonb_build_object('id',p_file_id,'success',true);
END $$;

CREATE FUNCTION public.rpc_delivery_document_history(p_tenant_id uuid,p_entity_type text,p_entity_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT(private.c03_document_access(p_tenant_id,p_entity_type,p_entity_id,'operational')
  OR private.c03_document_access(p_tenant_id,p_entity_type,p_entity_id,'financial')) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN jsonb_build_object('items',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',f.id,'file_name',f.file_name,'mime_type',f.mime_type,
  'size_bytes',f.size_bytes,'created_at',f.created_at,'status',f.status,'access_class',f.access_class,
  'events',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',e.id,'action',e.action,'previous_file_id',e.previous_file_id,'created_at',e.created_at)
   ORDER BY e.created_at,e.id) FROM private.c03_document_events e WHERE e.file_id=f.id OR e.previous_file_id=f.id),'[]')) ORDER BY f.created_at,f.id)
  FROM public.document_files f WHERE f.tenant_id=p_tenant_id AND f.source_entity_type=p_entity_type AND f.source_entity_id=p_entity_id
  AND f.company_classification_status='resolved' AND private.c03_document_access(p_tenant_id,p_entity_type,p_entity_id,f.access_class)),'[]'));
END $$;

CREATE FUNCTION public.rpc_delivery_document_sources(p_tenant_id uuid,p_query text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'billing.document.read') OR p_query IS NULL OR length(p_query)>160
 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 RETURN jsonb_build_object('items',COALESCE((SELECT jsonb_agg(to_jsonb(q)) FROM(
  SELECT 'operation'::text kind,o.id,o.reference_code label FROM private.delivery_operations o WHERE o.tenant_id=p_tenant_id
   AND private.c03_document_access(p_tenant_id,'operation',o.id,'operational',true)
   AND position(lower(p_query) IN lower(COALESCE(o.reference_code,'')))>0
  UNION ALL SELECT 'finance_invoice',i.id,i.reference FROM private.delivery_finance_invoices i WHERE i.tenant_id=p_tenant_id
   AND private.c03_document_access(p_tenant_id,'finance_invoice',i.id,'financial',true)
   AND position(lower(p_query) IN lower(COALESCE(i.reference,'')))>0
  UNION ALL SELECT 'billing_document',d.id,d.id::text FROM private.delivery_billing_documents d WHERE d.tenant_id=p_tenant_id
   AND private.c03_document_access(p_tenant_id,'billing_document',d.id,'financial',true)
   AND position(lower(p_query) IN lower(d.id::text))>0 ORDER BY kind,id LIMIT 50)q),'[]'));
END $$;
CREATE FUNCTION public.rpc_delivery_upload_contract(p_tenant_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE b storage.buckets%ROWTYPE;
BEGIN
 IF NOT private.delivery_cap(p_tenant_id,'documents.upload') OR NOT private.delivery_cap(p_tenant_id,'billing.document.read')
  OR cardinality(private.delivery_company_ids()) IS DISTINCT FROM 1 THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 SELECT * INTO b FROM storage.buckets WHERE id='tenant-documents' AND NOT public;
 IF NOT FOUND THEN RETURN jsonb_build_object('error','storage_not_configured');END IF;
 RETURN jsonb_build_object('bucket',b.id,'private',true,'max_file_size',b.file_size_limit,
  'allowed_mime_types',b.allowed_mime_types,'signed_url_ttl_seconds',300);
END $$;
DO $$DECLARE s text;BEGIN FOREACH s IN ARRAY ARRAY[
 'rpc_delivery_prepare_upload(uuid,uuid,jsonb)','rpc_delivery_finalize_upload(uuid,uuid)',
 'rpc_delivery_cancel_file(uuid,uuid,text)','rpc_delivery_document_history(uuid,text,uuid)','rpc_delivery_document_sources(uuid,text)','rpc_delivery_upload_contract(uuid)'] LOOP
 EXECUTE 'REVOKE ALL ON FUNCTION public.'||s||' FROM PUBLIC,anon,service_role';
 EXECUTE 'GRANT EXECUTE ON FUNCTION public.'||s||' TO authenticated';END LOOP;END $$;
COMMIT;
