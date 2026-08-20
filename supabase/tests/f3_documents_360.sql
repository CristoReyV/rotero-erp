\set ON_ERROR_STOP on

BEGIN;

DO $catalog$
DECLARE v_signature text; v_oid oid; v_table text;
BEGIN
    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_get_document_upload_contract(uuid)',
        'public.rpc_register_document_file(uuid,jsonb)',
        'public.rpc_list_document_files(uuid,jsonb)',
        'public.rpc_mark_document_file_status(uuid,text,text)',
        'public.rpc_relate_document_file(uuid,text,uuid,text)',
        'public.rpc_list_document_relations(uuid,text,uuid)',
        'public.rpc_attach_operation_document_file(uuid,text,uuid,text)',
        'public.rpc_add_operation_file_evidence(uuid,uuid,uuid,text)',
        'public.rpc_relate_quote_documents_to_operation(uuid,uuid)',
        'public.rpc_generate_document(uuid,text,text,uuid,jsonb)',
        'public.rpc_list_generated_documents(uuid,jsonb)',
        'public.rpc_mark_generated_document_printed(uuid)',
        'public.rpc_cancel_generated_document(uuid,text)',
        'public.rpc_list_document_templates_v2(uuid,text)',
        'public.rpc_list_document_source_options(uuid,text,text)'
    ] LOOP
        v_oid := to_regprocedure(v_signature);
        IF v_oid IS NULL THEN RAISE EXCEPTION 'F3 CONTRACT FAILED: missing %', v_signature; END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = v_oid AND prosecdef AND proconfig @> ARRAY['search_path=pg_catalog, public']::text[]) THEN
            RAISE EXCEPTION 'F3 CONTRACT FAILED: unsafe attributes %', v_signature;
        END IF;
        IF NOT has_function_privilege('authenticated', v_oid, 'EXECUTE')
           OR has_function_privilege('anon', v_oid, 'EXECUTE')
           OR has_function_privilege('service_role', v_oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'F3 CONTRACT FAILED: unexpected ACL %', v_signature;
        END IF;
    END LOOP;

    FOREACH v_table IN ARRAY ARRAY['document_files','document_relations','document_templates','document_template_versions','generated_documents'] LOOP
        IF to_regclass('public.' || v_table) IS NULL THEN RAISE EXCEPTION 'F3 CONTRACT FAILED: missing table %', v_table; END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = to_regclass('public.' || v_table) AND relrowsecurity) THEN
            RAISE EXCEPTION 'F3 CONTRACT FAILED: RLS disabled %', v_table;
        END IF;
        IF has_table_privilege('authenticated', 'public.' || v_table, 'SELECT,INSERT,UPDATE,DELETE')
           OR has_table_privilege('anon', 'public.' || v_table, 'SELECT,INSERT,UPDATE,DELETE') THEN
            RAISE EXCEPTION 'F3 CONTRACT FAILED: direct table privilege %', v_table;
        END IF;
    END LOOP;

    IF NOT EXISTS (
        SELECT 1 FROM storage.buckets WHERE id = 'tenant-documents' AND NOT public
          AND file_size_limit = 52428800
          AND allowed_mime_types @> ARRAY['application/pdf','image/jpeg','image/png']::text[]
    ) THEN RAISE EXCEPTION 'F3 STORAGE FAILED: canonical private bucket contract missing'; END IF;
    IF EXISTS (
        SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects'
          AND policyname LIKE 'tenant_documents_%_f3' AND roles @> ARRAY['public']::name[]
    ) THEN RAISE EXCEPTION 'F3 STORAGE FAILED: policy still targets PUBLIC'; END IF;
    IF (SELECT count(*) FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname LIKE 'tenant_documents_%_f3') <> 4 THEN
        RAISE EXCEPTION 'F3 STORAGE FAILED: expected select/insert/update/orphan-delete policies';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM pg_constraint AS con
        WHERE con.contype = 'f'
          AND con.conrelid IN ('public.document_files'::regclass, 'public.document_relations'::regclass,
              'public.generated_documents'::regclass, 'public.document_templates'::regclass,
              'public.document_template_versions'::regclass)
          AND NOT EXISTS (
              SELECT 1 FROM pg_index AS idx
              WHERE idx.indrelid = con.conrelid AND idx.indisvalid AND idx.indpred IS NULL
                AND (idx.indkey::smallint[])[0:cardinality(con.conkey)-1] = con.conkey
          )
    ) THEN RAISE EXCEPTION 'F3 PERFORMANCE FAILED: foreign key without covering index'; END IF;
END;
$catalog$;

DO $fixtures$
DECLARE
    v_tenant_a uuid; v_tenant_b uuid;
    v_admin uuid := gen_random_uuid(); v_finance uuid := gen_random_uuid();
    v_operator uuid := gen_random_uuid(); v_nonmember uuid := gen_random_uuid();
    v_customer uuid; v_provider uuid; v_quote uuid; v_operation uuid; v_foreign_operation uuid; v_foreign_path text;
BEGIN
    INSERT INTO auth.users (instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
      ('00000000-0000-0000-0000-000000000000',v_admin,'authenticated','authenticated','f3-admin@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_finance,'authenticated','authenticated','f3-finance@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_operator,'authenticated','authenticated','f3-operator@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_nonmember,'authenticated','authenticated','f3-none@example.invalid',now(),'{}','{}',now(),now());
    INSERT INTO public.tenants(name,slug) VALUES ('F3 A','f3-a'),('F3 B','f3-b');
    SELECT id INTO v_tenant_a FROM public.tenants WHERE slug='f3-a';
    SELECT id INTO v_tenant_b FROM public.tenants WHERE slug='f3-b';
    INSERT INTO public.memberships(tenant_id,user_id,role) VALUES
      (v_tenant_a,v_admin,'admin'),(v_tenant_a,v_finance,'finance'),(v_tenant_a,v_operator,'operator');
    INSERT INTO public.customers(tenant_id,display_name) VALUES(v_tenant_a,'Cliente F3') RETURNING id INTO v_customer;
    INSERT INTO public.logistics_providers(tenant_id,display_name) VALUES(v_tenant_a,'Proveedor F3') RETURNING id INTO v_provider;
    INSERT INTO public.crm_deals(
        tenant_id,title,company,currency,stage,customer_id,quote_status,quote_reference,quote_payload
    ) VALUES (
        v_tenant_a,'Cotización F3','Cliente F3','MXN','proposal',v_customer,'approved','COT-F3-001',
        jsonb_build_object('provider_id',v_provider,'provider_cost_amount',8000,'customer_price_amount',10000,
            'currency','MXN','service_type','FTL','route_summary','Monterrey → Saltillo','notes','NOTA INTERNA SECRETA')
    ) RETURNING id INTO v_quote;
    INSERT INTO public.operations(tenant_id,reference_code,customer_id,client_display_name,status,source_deal_id)
      VALUES(v_tenant_a,'OP-F3-001',v_customer,'Cliente F3','planned',v_quote) RETURNING id INTO v_operation;
    INSERT INTO public.operations(tenant_id,reference_code,client_display_name,status)
      VALUES(v_tenant_b,'OP-F3-FOREIGN','Otro tenant','planned') RETURNING id INTO v_foreign_operation;
    v_foreign_path := v_tenant_b || '/operations/operation/' || v_foreign_operation || '/' || gen_random_uuid() || '.pdf';
    INSERT INTO storage.objects(bucket_id,name,owner_id,metadata)
      VALUES ('tenant-documents',v_foreign_path,v_nonmember::text,'{"mimetype":"application/pdf","size":20}'::jsonb);

    PERFORM set_config('f3.tenant_a',v_tenant_a::text,true); PERFORM set_config('f3.tenant_b',v_tenant_b::text,true);
    PERFORM set_config('f3.admin',v_admin::text,true); PERFORM set_config('f3.finance',v_finance::text,true);
    PERFORM set_config('f3.operator',v_operator::text,true); PERFORM set_config('f3.nonmember',v_nonmember::text,true);
    PERFORM set_config('f3.quote',v_quote::text,true); PERFORM set_config('f3.operation',v_operation::text,true);
    PERFORM set_config('f3.foreign_operation',v_foreign_operation::text,true);
    PERFORM set_config('f3.foreign_path',v_foreign_path,true);
END;
$fixtures$;

SET LOCAL ROLE authenticated;

DO $admin$
DECLARE v_tenant uuid := current_setting('f3.tenant_a')::uuid; v_admin uuid := current_setting('f3.admin')::uuid;
    v_quote uuid := current_setting('f3.quote')::uuid; v_operation uuid := current_setting('f3.operation')::uuid;
    v_path text; v_orphan text; v_operation_path text; v_file uuid; v_operation_file uuid; v_result jsonb; v_generated uuid; v_snapshot jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
    v_path := v_tenant || '/commercial/quote/' || v_quote || '/' || gen_random_uuid() || '.pdf';
    v_orphan := v_tenant || '/commercial/quote/' || v_quote || '/' || gen_random_uuid() || '.pdf';
    INSERT INTO storage.objects(bucket_id,name,owner_id,metadata) VALUES
      ('tenant-documents',v_path,v_admin::text,'{"mimetype":"application/pdf","size":1234}'::jsonb),
      ('tenant-documents',v_orphan,v_admin::text,'{"mimetype":"application/pdf","size":10}'::jsonb);

    v_result := public.rpc_register_document_file(v_tenant,jsonb_build_object(
        'storage_path',v_path,'file_name','solicitud-cliente.pdf','mime_type','application/pdf','size_bytes',1234,
        'checksum_sha256',repeat('a',64),'file_kind','supporting_file','source_module','commercial',
        'source_entity_type','quote','source_entity_id',v_quote,'notes','Soporte comercial',
        'metadata',jsonb_build_object('operationally_relevant',true)
    ));
    IF v_result ? 'error' OR v_result->>'checksum_sha256' <> repeat('a',64) THEN RAISE EXCEPTION 'F3 ADMIN FAILED: register %',v_result; END IF;
    v_file := (v_result->>'id')::uuid; PERFORM set_config('f3.file',v_file::text,true);
    PERFORM set_config('f3.path',v_path,true);

    v_operation_path := v_tenant || '/operations/operation/' || v_operation || '/' || gen_random_uuid() || '.pdf';
    INSERT INTO storage.objects(bucket_id,name,owner_id,metadata)
      VALUES ('tenant-documents',v_operation_path,v_admin::text,'{"mimetype":"application/pdf","size":250}'::jsonb);
    v_result := public.rpc_register_document_file(v_tenant,jsonb_build_object(
        'storage_path',v_operation_path,'file_name','pod-operativo.pdf','mime_type','application/pdf','size_bytes',250,
        'checksum_sha256',repeat('c',64),'file_kind','supporting_file','source_module','operations',
        'source_entity_type','operation','source_entity_id',v_operation
    ));
    IF v_result ? 'error' THEN RAISE EXCEPTION 'F3 ADMIN FAILED: operation register %',v_result; END IF;
    v_operation_file := (v_result->>'id')::uuid;
    PERFORM set_config('f3.operation_path',v_operation_path,true);

    v_result := public.rpc_list_document_files(v_tenant,jsonb_build_object('search','COT-F3-001','limit',20));
    IF jsonb_array_length(v_result->'items') <> 1 OR v_result#>>'{items,0,entity_reference}' <> 'COT-F3-001' THEN
        RAISE EXCEPTION 'F3 ADMIN FAILED: human search/list %',v_result;
    END IF;
    v_result := public.rpc_relate_document_file(v_file,'operation',v_operation,'Soporte útil en operación');
    IF v_result ? 'error' THEN RAISE EXCEPTION 'F3 ADMIN FAILED: relation %',v_result; END IF;
    v_result := public.rpc_attach_operation_document_file(v_operation,'proof_of_delivery',v_operation_file,'POD recibido');
    IF v_result ? 'error' OR NOT (public.rpc_get_operation_document_summary(v_operation)->>'pod_present')::boolean THEN
        RAISE EXCEPTION 'F3 ADMIN FAILED: POD attach %',v_result;
    END IF;
    v_result := public.rpc_add_operation_file_evidence(v_operation,v_operation_file,NULL,'Evidencia real');
    IF v_result ? 'error' THEN RAISE EXCEPTION 'F3 ADMIN FAILED: evidence attach %',v_result; END IF;

    v_result := public.rpc_generate_document(v_tenant,'commercial_quote','quote',v_quote,'{}'::jsonb);
    IF v_result ? 'error' THEN RAISE EXCEPTION 'F3 ADMIN FAILED: generation %',v_result; END IF;
    v_generated := (v_result->>'id')::uuid; v_snapshot := v_result->'data_snapshot';
    PERFORM set_config('f3.generated',v_generated::text,true);
    IF lower(v_snapshot::text) ~ 'provider_cost|gross_margin|internal|secreta|8000'
       OR lower(v_result->>'html_snapshot') ~ 'costo proveedor|margen|secreta|8000' THEN
        RAISE EXCEPTION 'F3 SECURITY FAILED: internal economics leaked';
    END IF;
    v_result := public.rpc_mark_generated_document_printed(v_generated);
    IF v_result ? 'error' THEN RAISE EXCEPTION 'F3 ADMIN FAILED: print %',v_result; END IF;
    IF NOT (public.rpc_cancel_generated_document(v_generated,'Versión sustituida')->>'status' = 'cancelled') THEN
        RAISE EXCEPTION 'F3 ADMIN FAILED: cancel';
    END IF;

    v_result := public.rpc_register_document_file(v_tenant,jsonb_build_object(
        'storage_path',v_tenant||'/commercial/quote/'||v_quote||'/'||gen_random_uuid()||'.pdf',
        'file_name','missing.pdf','mime_type','application/pdf','size_bytes',1,'checksum_sha256',repeat('b',64),
        'source_module','commercial','source_entity_type','quote','source_entity_id',v_quote
    ));
    IF v_result->>'error' <> 'storage_object_not_found' THEN RAISE EXCEPTION 'F3 ORPHAN FAILED: metadata accepted without object %',v_result; END IF;
END;
$admin$;

RESET ROLE;
DO $immutable$
BEGIN
    BEGIN
        UPDATE public.generated_documents SET data_snapshot='{"tampered":true}'
        WHERE id=current_setting('f3.generated')::uuid;
        RAISE EXCEPTION 'F3 INTEGRITY FAILED: generated snapshot mutated';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'generated_snapshot_immutable' THEN RAISE; END IF;
    END;
END;
$immutable$;
SET LOCAL ROLE authenticated;

DO $rbac$
DECLARE v_tenant uuid := current_setting('f3.tenant_a')::uuid; v_finance uuid := current_setting('f3.finance')::uuid;
    v_file uuid := current_setting('f3.file')::uuid; v_result jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',v_finance::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_finance,'role','authenticated')::text,true);
    v_result := public.rpc_list_document_files(v_tenant,jsonb_build_object('source_module','commercial'));
    IF jsonb_array_length(v_result->'items') <> 0 THEN RAISE EXCEPTION 'F3 RBAC FAILED: finance read commercial support'; END IF;
    v_result := public.rpc_list_document_files(v_tenant,jsonb_build_object('source_module','operations'));
    IF jsonb_array_length(v_result->'items') <> 1 THEN RAISE EXCEPTION 'F3 RBAC FAILED: finance cannot read operation document %',v_result; END IF;
    IF NOT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='tenant-documents' AND name=current_setting('f3.operation_path')) THEN
        RAISE EXCEPTION 'F3 STORAGE FAILED: finance cannot read allowed operation object';
    END IF;
    IF EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='tenant-documents' AND name=current_setting('f3.path')) THEN
        RAISE EXCEPTION 'F3 STORAGE FAILED: finance read commercial object';
    END IF;
    IF public.rpc_mark_document_file_status(v_file,'cancelled',NULL)->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'F3 RBAC FAILED: finance mutated commercial support';
    END IF;
    IF public.rpc_relate_document_file(v_file,'operation',current_setting('f3.foreign_operation')::uuid,NULL)->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'F3 SECURITY FAILED: cross-tenant relation not denied';
    END IF;

    PERFORM set_config('request.jwt.claim.sub',current_setting('f3.admin'),true);
    IF EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='tenant-documents' AND name=current_setting('f3.foreign_path')) THEN
        RAISE EXCEPTION 'F3 STORAGE FAILED: cross-tenant object visible';
    END IF;

    PERFORM set_config('request.jwt.claim.sub',current_setting('f3.nonmember'),true);
    IF EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='tenant-documents') THEN
        RAISE EXCEPTION 'F3 STORAGE FAILED: nonmember object visible';
    END IF;
    IF public.rpc_list_document_files(v_tenant,'{}'::jsonb)->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'F3 SECURITY FAILED: nonmember list not denied';
    END IF;
    PERFORM set_config('request.jwt.claim.sub','',true);
    PERFORM set_config('request.jwt.claims','{}',true);
    IF public.rpc_list_document_files(v_tenant,'{}'::jsonb)->>'error' <> 'unauthorized' THEN
        RAISE EXCEPTION 'F3 SECURITY FAILED: anonymous context not denied';
    END IF;
    IF EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='tenant-documents') THEN
        RAISE EXCEPTION 'F3 STORAGE FAILED: anonymous context can read objects';
    END IF;
END;
$rbac$;

RESET ROLE;
ROLLBACK;
