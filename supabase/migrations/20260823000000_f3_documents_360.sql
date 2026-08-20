-- F3 — ROTERO Documents 360 + real file storage
-- Forward-only and additive. Reconstructs the reviewed contracts locally and
-- hardens the same contracts when they already exist.

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.f3_user_can_access_module(
    p_tenant_id uuid, p_module text, p_write boolean DEFAULT false
)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM public.memberships AS m
        WHERE m.tenant_id = p_tenant_id
          AND m.user_id = (SELECT auth.uid())
          AND CASE m.role
              WHEN 'admin' THEN true
              WHEN 'operator' THEN p_module IN ('commercial', 'operations', 'documents')
              WHEN 'finance' THEN p_module IN ('operations', 'billing', 'finance')
              WHEN 'viewer' THEN NOT p_write AND p_module IN ('commercial', 'operations', 'documents')
              ELSE false
          END
    );
$function$;

CREATE OR REPLACE FUNCTION private.f3_storage_tenant_from_path(p_name text)
RETURNS uuid
LANGUAGE sql IMMUTABLE
SET search_path TO pg_catalog
AS $function$
    SELECT CASE
        WHEN split_part(COALESCE(p_name, ''), '/', 1)
             ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN split_part(p_name, '/', 1)::uuid
        ELSE NULL
    END;
$function$;

CREATE OR REPLACE FUNCTION private.f3_storage_path_is_valid(
    p_name text, p_tenant_id uuid, p_module text, p_entity_type text, p_entity_id uuid
)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path TO pg_catalog
AS $function$
    SELECT private.f3_storage_tenant_from_path(p_name) = p_tenant_id
       AND split_part(p_name, '/', 2) = p_module
       AND split_part(p_name, '/', 3) = p_entity_type
       AND split_part(p_name, '/', 4) = p_entity_id::text
       AND split_part(p_name, '/', 5) ~* '^[0-9a-f-]{36}\.[a-z0-9]{1,10}$'
       AND split_part(p_name, '/', 6) = '';
$function$;

CREATE OR REPLACE FUNCTION private.f3_entity_belongs_to_tenant(
    p_tenant_id uuid, p_entity_type text, p_entity_id uuid
)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_exists boolean := false;
BEGIN
    IF (SELECT auth.uid()) IS NULL THEN RETURN false; END IF;
    CASE p_entity_type
        WHEN 'operation' THEN
            SELECT EXISTS (SELECT 1 FROM public.operations WHERE id = p_entity_id AND tenant_id = p_tenant_id) INTO v_exists;
        WHEN 'quote' THEN
            SELECT EXISTS (SELECT 1 FROM public.crm_deals WHERE id = p_entity_id AND tenant_id = p_tenant_id AND quote_reference IS NOT NULL) INTO v_exists;
        WHEN 'customer' THEN
            SELECT EXISTS (SELECT 1 FROM public.customers WHERE id = p_entity_id AND tenant_id = p_tenant_id) INTO v_exists;
        WHEN 'provider' THEN
            SELECT EXISTS (SELECT 1 FROM public.logistics_providers WHERE id = p_entity_id AND tenant_id = p_tenant_id) INTO v_exists;
        WHEN 'generated_document' THEN
            IF to_regclass('public.generated_documents') IS NOT NULL THEN
                EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.generated_documents WHERE id = $1 AND tenant_id = $2)'
                INTO v_exists USING p_entity_id, p_tenant_id;
            END IF;
        WHEN 'billing_document' THEN
            IF to_regclass('public.billing_documents') IS NOT NULL THEN
                EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.billing_documents WHERE id = $1 AND tenant_id = $2)'
                INTO v_exists USING p_entity_id, p_tenant_id;
            END IF;
        ELSE v_exists := false;
    END CASE;
    RETURN v_exists;
END;
$function$;

CREATE TABLE IF NOT EXISTS public.document_templates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    template_type text NOT NULL,
    name text NOT NULL,
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    title text NOT NULL DEFAULT '', body_text text NOT NULL DEFAULT '',
    footer_text text NOT NULL DEFAULT '', legal_notes text NOT NULL DEFAULT '',
    tokens text[] NOT NULL DEFAULT ARRAY[]::text[],
    brand_settings jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_active boolean NOT NULL DEFAULT true, created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    module text, layout_key text NOT NULL DEFAULT 'standard',
    visible_fields jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(visible_fields) = 'array'),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'archived')),
    active_version_id uuid,
    CONSTRAINT document_templates_type_check CHECK (template_type IN (
        'commercial_quote', 'payroll_receipt', 'operation_summary', 'operation_document',
        'payment_complement', 'credit_note', 'provider_document', 'finance_internal_receipt', 'finance_note'
    ))
);

CREATE TABLE IF NOT EXISTS public.document_template_versions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    template_id uuid NOT NULL REFERENCES public.document_templates(id) ON DELETE CASCADE,
    version_number integer NOT NULL CHECK (version_number > 0), template_type text NOT NULL,
    name text NOT NULL, layout_key text NOT NULL DEFAULT 'standard',
    title text NOT NULL DEFAULT '', body_text text NOT NULL DEFAULT '',
    footer_text text NOT NULL DEFAULT '', legal_notes text NOT NULL DEFAULT '',
    tokens text[] NOT NULL DEFAULT ARRAY[]::text[],
    visible_fields jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(visible_fields) = 'array'),
    brand_settings jsonb NOT NULL DEFAULT '{}'::jsonb,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'archived')),
    created_by uuid, created_at timestamptz NOT NULL DEFAULT now(), activated_at timestamptz,
    CONSTRAINT document_template_versions_type_check CHECK (template_type IN (
        'commercial_quote', 'payroll_receipt', 'operation_summary', 'operation_document',
        'payment_complement', 'credit_note', 'provider_document', 'finance_internal_receipt', 'finance_note'
    )),
    CONSTRAINT document_template_versions_template_number_key UNIQUE (template_id, version_number)
);

CREATE TABLE IF NOT EXISTS public.generated_documents (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    template_id uuid REFERENCES public.document_templates(id) ON DELETE SET NULL,
    entity_type text NOT NULL, entity_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'final' CHECK (status IN ('draft', 'final', 'cancelled')),
    html_snapshot text NOT NULL DEFAULT '', data_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    generated_by uuid, generated_at timestamptz NOT NULL DEFAULT now(), created_at timestamptz NOT NULL DEFAULT now(),
    template_version_id uuid REFERENCES public.document_template_versions(id) ON DELETE SET NULL,
    document_number text, source_module text, related_entity_type text, related_entity_id uuid,
    finalized_at timestamptz, cancelled_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb, print_count integer NOT NULL DEFAULT 0 CHECK (print_count >= 0),
    CONSTRAINT generated_documents_entity_type_check CHECK (entity_type IN (
        'commercial_quote', 'payroll_receipt', 'operation_summary', 'operation_document',
        'payment_complement', 'credit_note', 'provider_document', 'finance_internal_receipt', 'finance_note'
    ))
);

CREATE TABLE IF NOT EXISTS public.document_files (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    storage_bucket text NOT NULL DEFAULT 'tenant-documents' CHECK (storage_bucket = 'tenant-documents'),
    storage_path text NOT NULL, file_name text NOT NULL, mime_type text NOT NULL,
    size_bytes bigint NOT NULL DEFAULT 0 CHECK (size_bytes >= 0), checksum_sha256 text,
    file_kind text NOT NULL DEFAULT 'supporting_file' CHECK (file_kind IN (
        'generated_pdf', 'fiscal_xml', 'fiscal_pdf', 'provider_upload',
        'operation_evidence', 'supporting_file', 'html_snapshot'
    )),
    source_module text NOT NULL DEFAULT 'documents', source_entity_type text NOT NULL, source_entity_id uuid NOT NULL,
    generated_document_id uuid REFERENCES public.generated_documents(id) ON DELETE SET NULL,
    billing_document_id uuid, status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'superseded', 'cancelled')),
    notes text, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, uploaded_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT document_files_storage_path_tenant_check CHECK (private.f3_storage_tenant_from_path(storage_path) = tenant_id),
    CONSTRAINT document_files_source_type_check CHECK (source_entity_type IN ('operation', 'quote', 'customer', 'provider', 'billing_document', 'generated_document')),
    CONSTRAINT document_files_source_module_check CHECK (source_module IN ('operations', 'commercial', 'billing', 'finance', 'documents')),
    CONSTRAINT document_files_checksum_check CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-f]{64}$')
);

CREATE TABLE IF NOT EXISTS public.document_relations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    relation_type text NOT NULL CHECK (relation_type IN (
        'generated_from', 'payment_to_invoice', 'credit_note_to_invoice', 'provider_doc_to_ap',
        'operation_doc_to_operation', 'payroll_receipt_to_period', 'ccp_ccc', 'supporting_document'
    )),
    source_entity_type text NOT NULL, source_entity_id uuid NOT NULL,
    target_entity_type text NOT NULL, target_entity_id uuid NOT NULL,
    source_generated_document_id uuid REFERENCES public.generated_documents(id) ON DELETE SET NULL,
    target_generated_document_id uuid REFERENCES public.generated_documents(id) ON DELETE SET NULL,
    notes text, created_by uuid, created_at timestamptz NOT NULL DEFAULT now(),
    document_file_id uuid REFERENCES public.document_files(id) ON DELETE CASCADE
);

ALTER TABLE public.document_relations ADD COLUMN IF NOT EXISTS document_file_id uuid;
DO $block$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.document_relations'::regclass AND conname = 'document_relations_document_file_id_fkey') THEN
        ALTER TABLE public.document_relations ADD CONSTRAINT document_relations_document_file_id_fkey
            FOREIGN KEY (document_file_id) REFERENCES public.document_files(id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.document_templates'::regclass AND conname = 'document_templates_active_version_id_fkey') THEN
        ALTER TABLE public.document_templates ADD CONSTRAINT document_templates_active_version_id_fkey
            FOREIGN KEY (active_version_id) REFERENCES public.document_template_versions(id) ON DELETE SET NULL;
    END IF;
END;
$block$;

CREATE UNIQUE INDEX IF NOT EXISTS document_files_bucket_path_uidx ON public.document_files (storage_bucket, storage_path);
CREATE INDEX IF NOT EXISTS document_files_tenant_module_created_idx ON public.document_files (tenant_id, source_module, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS document_files_tenant_source_idx ON public.document_files (tenant_id, source_entity_type, source_entity_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS document_files_checksum_idx ON public.document_files (tenant_id, checksum_sha256) WHERE checksum_sha256 IS NOT NULL;
CREATE INDEX IF NOT EXISTS document_files_generated_document_idx ON public.document_files (generated_document_id);
CREATE INDEX IF NOT EXISTS document_relations_file_target_idx ON public.document_relations (document_file_id, target_entity_type, target_entity_id);
CREATE UNIQUE INDEX IF NOT EXISTS document_relations_file_target_uidx ON public.document_relations (document_file_id, target_entity_type, target_entity_id, relation_type) WHERE document_file_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS document_relations_source_idx ON public.document_relations (tenant_id, source_entity_type, source_entity_id, relation_type);
CREATE INDEX IF NOT EXISTS document_relations_target_idx ON public.document_relations (tenant_id, target_entity_type, target_entity_id, relation_type);
CREATE INDEX IF NOT EXISTS document_relations_source_generated_idx ON public.document_relations (source_generated_document_id);
CREATE INDEX IF NOT EXISTS document_relations_target_generated_idx ON public.document_relations (target_generated_document_id);
CREATE INDEX IF NOT EXISTS document_templates_tenant_type_idx ON public.document_templates (tenant_id, template_type, is_active, updated_at DESC);
CREATE INDEX IF NOT EXISTS document_templates_active_version_idx ON public.document_templates (active_version_id);
CREATE INDEX IF NOT EXISTS document_template_versions_tenant_type_idx ON public.document_template_versions (tenant_id, template_type, status, version_number DESC);
CREATE UNIQUE INDEX IF NOT EXISTS generated_documents_tenant_number_uidx ON public.generated_documents (tenant_id, lower(document_number)) WHERE document_number IS NOT NULL AND trim(document_number) <> '';
CREATE INDEX IF NOT EXISTS generated_documents_tenant_type_status_idx ON public.generated_documents (tenant_id, entity_type, status, generated_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS generated_documents_tenant_entity_idx ON public.generated_documents (tenant_id, entity_type, entity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS generated_documents_template_idx ON public.generated_documents (template_id);
CREATE INDEX IF NOT EXISTS generated_documents_template_version_idx ON public.generated_documents (template_version_id);


DO $block$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.document_files'::regclass AND conname = 'document_files_source_type_check') THEN
        ALTER TABLE public.document_files ADD CONSTRAINT document_files_source_type_check
            CHECK (source_entity_type IN ('operation', 'quote', 'customer', 'provider', 'billing_document', 'generated_document')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.document_files'::regclass AND conname = 'document_files_source_module_check') THEN
        ALTER TABLE public.document_files ADD CONSTRAINT document_files_source_module_check
            CHECK (source_module IN ('operations', 'commercial', 'billing', 'finance', 'documents')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.document_files'::regclass AND conname = 'document_files_checksum_check') THEN
        ALTER TABLE public.document_files ADD CONSTRAINT document_files_checksum_check
            CHECK (checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9a-f]{64}$') NOT VALID;
    END IF;
END;
$block$;
ALTER TABLE public.document_files VALIDATE CONSTRAINT document_files_source_type_check;
ALTER TABLE public.document_files VALIDATE CONSTRAINT document_files_source_module_check;
ALTER TABLE public.document_files VALIDATE CONSTRAINT document_files_checksum_check;

ALTER TABLE public.document_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_relations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_template_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.generated_documents ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.document_files FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.document_relations FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.document_templates FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.document_template_versions FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.generated_documents FROM PUBLIC, anon, authenticated, service_role;

DROP POLICY IF EXISTS document_files_manage_tanda5 ON public.document_files;
DROP POLICY IF EXISTS document_files_select_tanda5 ON public.document_files;
DROP POLICY IF EXISTS document_files_select_f3 ON public.document_files;
DROP POLICY IF EXISTS document_files_insert_f3 ON public.document_files;
DROP POLICY IF EXISTS document_files_update_f3 ON public.document_files;
CREATE POLICY document_files_select_f3 ON public.document_files FOR SELECT TO authenticated
    USING ((SELECT private.f3_user_can_access_module(tenant_id, source_module, false)));
CREATE POLICY document_files_insert_f3 ON public.document_files FOR INSERT TO authenticated
    WITH CHECK ((SELECT private.f3_user_can_access_module(tenant_id, source_module, true)));
CREATE POLICY document_files_update_f3 ON public.document_files FOR UPDATE TO authenticated
    USING ((SELECT private.f3_user_can_access_module(tenant_id, source_module, true)))
    WITH CHECK ((SELECT private.f3_user_can_access_module(tenant_id, source_module, true)));

DROP POLICY IF EXISTS document_relations_manage_tanda4 ON public.document_relations;
DROP POLICY IF EXISTS document_relations_select_tanda4 ON public.document_relations;
DROP POLICY IF EXISTS document_relations_select_f3 ON public.document_relations;
CREATE POLICY document_relations_select_f3 ON public.document_relations FOR SELECT TO authenticated
    USING ((SELECT private.f3_user_can_access_module(
        tenant_id,
        CASE target_entity_type WHEN 'operation' THEN 'operations' WHEN 'billing_document' THEN 'billing' ELSE 'commercial' END,
        false
    )));

DROP POLICY IF EXISTS document_templates_manage_tanda4 ON public.document_templates;
DROP POLICY IF EXISTS document_templates_select_tanda4 ON public.document_templates;
DROP POLICY IF EXISTS document_templates_select_f3 ON public.document_templates;
CREATE POLICY document_templates_select_f3 ON public.document_templates FOR SELECT TO authenticated
    USING ((SELECT private.f3_user_can_access_module(tenant_id, COALESCE(module, 'documents'), false)));

DROP POLICY IF EXISTS document_template_versions_manage_tanda4 ON public.document_template_versions;
DROP POLICY IF EXISTS document_template_versions_select_tanda4 ON public.document_template_versions;
DROP POLICY IF EXISTS document_template_versions_select_f3 ON public.document_template_versions;
CREATE POLICY document_template_versions_select_f3 ON public.document_template_versions FOR SELECT TO authenticated
    USING ((SELECT private.f3_user_can_access_module(
        tenant_id,
        CASE WHEN template_type IN ('operation_summary', 'operation_document') THEN 'operations'
             WHEN template_type = 'commercial_quote' THEN 'commercial' ELSE 'finance' END,
        false
    )));

DROP POLICY IF EXISTS generated_documents_manage_tanda4 ON public.generated_documents;
DROP POLICY IF EXISTS generated_documents_select_tanda4 ON public.generated_documents;
DROP POLICY IF EXISTS generated_documents_select_f3 ON public.generated_documents;
CREATE POLICY generated_documents_select_f3 ON public.generated_documents FOR SELECT TO authenticated
    USING ((SELECT private.f3_user_can_access_module(
        tenant_id,
        CASE WHEN entity_type IN ('operation_summary', 'operation_document') THEN 'operations'
             WHEN entity_type = 'commercial_quote' THEN 'commercial' ELSE 'finance' END,
        false
    )));

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'tenant-documents', 'tenant-documents', false, 52428800,
    ARRAY['application/pdf', 'application/xml', 'text/xml', 'text/plain', 'text/html',
          'image/png', 'image/jpeg', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE OR REPLACE FUNCTION private.f3_can_delete_orphan_storage_object(p_name text, p_owner_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT (SELECT auth.uid()) IS NOT NULL
       AND p_owner_id = (SELECT auth.uid())::text
       AND private.f3_user_can_access_module(
            private.f3_storage_tenant_from_path(p_name), split_part(p_name, '/', 2), true
       )
       AND NOT EXISTS (
            SELECT 1 FROM public.document_files AS df
            WHERE df.storage_bucket = 'tenant-documents' AND df.storage_path = p_name
       );
$function$;

DROP POLICY IF EXISTS tenant_documents_insert_tanda5 ON storage.objects;
DROP POLICY IF EXISTS tenant_documents_select_tanda5 ON storage.objects;
DROP POLICY IF EXISTS tenant_documents_update_tanda5 ON storage.objects;
DROP POLICY IF EXISTS tenant_documents_select_f3 ON storage.objects;
DROP POLICY IF EXISTS tenant_documents_insert_f3 ON storage.objects;
DROP POLICY IF EXISTS tenant_documents_update_f3 ON storage.objects;
DROP POLICY IF EXISTS tenant_documents_delete_orphan_f3 ON storage.objects;

CREATE POLICY tenant_documents_select_f3 ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'tenant-documents'
    AND (SELECT private.f3_user_can_access_module(
        private.f3_storage_tenant_from_path(name), split_part(name, '/', 2), false
    ))
);
CREATE POLICY tenant_documents_insert_f3 ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'tenant-documents' AND owner_id = (SELECT auth.uid())::text
    AND (SELECT private.f3_user_can_access_module(
        private.f3_storage_tenant_from_path(name), split_part(name, '/', 2), true
    ))
);
CREATE POLICY tenant_documents_update_f3 ON storage.objects FOR UPDATE TO authenticated
USING (
    bucket_id = 'tenant-documents' AND owner_id = (SELECT auth.uid())::text
    AND (SELECT private.f3_user_can_access_module(
        private.f3_storage_tenant_from_path(name), split_part(name, '/', 2), true
    ))
)
WITH CHECK (
    bucket_id = 'tenant-documents' AND owner_id = (SELECT auth.uid())::text
    AND (SELECT private.f3_user_can_access_module(
        private.f3_storage_tenant_from_path(name), split_part(name, '/', 2), true
    ))
);
CREATE POLICY tenant_documents_delete_orphan_f3 ON storage.objects FOR DELETE TO authenticated
USING (
    bucket_id = 'tenant-documents'
    AND (SELECT private.f3_can_delete_orphan_storage_object(name, owner_id))
);

REVOKE ALL ON FUNCTION private.f3_user_can_access_module(uuid, text, boolean) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION private.f3_entity_belongs_to_tenant(uuid, text, uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION private.f3_can_delete_orphan_storage_object(text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION private.f3_user_can_access_module(uuid, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION private.f3_entity_belongs_to_tenant(uuid, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.f3_can_delete_orphan_storage_object(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION private.f3_extension_matches_mime(p_file_name text, p_mime_type text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path TO pg_catalog
AS $function$
    SELECT CASE lower(COALESCE(p_mime_type, ''))
        WHEN 'application/pdf' THEN lower(p_file_name) ~ '\.pdf$'
        WHEN 'application/xml' THEN lower(p_file_name) ~ '\.xml$'
        WHEN 'text/xml' THEN lower(p_file_name) ~ '\.xml$'
        WHEN 'text/plain' THEN lower(p_file_name) ~ '\.(txt|csv)$'
        WHEN 'text/html' THEN lower(p_file_name) ~ '\.html?$'
        WHEN 'image/png' THEN lower(p_file_name) ~ '\.png$'
        WHEN 'image/jpeg' THEN lower(p_file_name) ~ '\.jpe?g$'
        WHEN 'image/webp' THEN lower(p_file_name) ~ '\.webp$'
        ELSE false
    END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_document_upload_contract(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_bucket storage.buckets%ROWTYPE;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.memberships
        WHERE tenant_id = p_tenant_id AND user_id = (SELECT auth.uid())
    ) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;

    SELECT * INTO v_bucket FROM storage.buckets WHERE id = 'tenant-documents' AND public = false;
    IF v_bucket.id IS NULL THEN RETURN jsonb_build_object('error', 'storage_not_configured'); END IF;
    RETURN jsonb_build_object(
        'bucket', v_bucket.id,
        'private', NOT v_bucket.public,
        'max_file_size', v_bucket.file_size_limit,
        'allowed_mime_types', to_jsonb(v_bucket.allowed_mime_types),
        'signed_url_ttl_seconds', 300
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_register_document_file(p_tenant_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_file_kind text := COALESCE(NULLIF(trim(p_payload->>'file_kind'), ''), 'supporting_file');
    v_module text := NULLIF(trim(p_payload->>'source_module'), '');
    v_entity_type text := NULLIF(trim(p_payload->>'source_entity_type'), '');
    v_entity_id uuid;
    v_path text := NULLIF(trim(p_payload->>'storage_path'), '');
    v_file_name text := NULLIF(trim(p_payload->>'file_name'), '');
    v_mime text := lower(NULLIF(trim(p_payload->>'mime_type'), ''));
    v_size bigint;
    v_checksum text := lower(NULLIF(trim(p_payload->>'checksum_sha256'), ''));
    v_bucket storage.buckets%ROWTYPE;
    v_id uuid;
BEGIN
    BEGIN
        v_entity_id := NULLIF(p_payload->>'source_entity_id', '')::uuid;
        v_size := NULLIF(p_payload->>'size_bytes', '')::bigint;
    EXCEPTION WHEN invalid_text_representation THEN
        RETURN jsonb_build_object('error', 'invalid_payload');
    END;

    IF v_file_name IS NULL OR v_path IS NULL OR v_module IS NULL OR v_entity_type IS NULL
       OR v_entity_id IS NULL OR v_mime IS NULL OR v_size IS NULL OR v_size <= 0 THEN
        RETURN jsonb_build_object('error', 'invalid_payload');
    END IF;
    IF v_file_kind NOT IN ('generated_pdf', 'fiscal_xml', 'fiscal_pdf', 'provider_upload', 'operation_evidence', 'supporting_file', 'html_snapshot') THEN
        RETURN jsonb_build_object('error', 'invalid_file_kind');
    END IF;
    IF NOT private.f3_user_can_access_module(p_tenant_id, v_module, true) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF NOT private.f3_entity_belongs_to_tenant(p_tenant_id, v_entity_type, v_entity_id) THEN
        RETURN jsonb_build_object('error', 'invalid_source_entity');
    END IF;
    IF (v_entity_type = 'operation' AND v_module <> 'operations')
       OR (v_entity_type IN ('quote', 'customer', 'provider') AND v_module <> 'commercial')
       OR (v_entity_type = 'billing_document' AND v_module NOT IN ('billing', 'finance')) THEN
        RETURN jsonb_build_object('error', 'invalid_source_module');
    END IF;
    IF NOT private.f3_storage_path_is_valid(v_path, p_tenant_id, v_module, v_entity_type, v_entity_id) THEN
        RETURN jsonb_build_object('error', 'invalid_storage_path');
    END IF;

    SELECT * INTO v_bucket FROM storage.buckets WHERE id = 'tenant-documents' AND public = false;
    IF v_bucket.id IS NULL THEN RETURN jsonb_build_object('error', 'storage_not_configured'); END IF;
    IF v_size > v_bucket.file_size_limit THEN RETURN jsonb_build_object('error', 'file_too_large'); END IF;
    IF NOT (v_mime = ANY(v_bucket.allowed_mime_types)) OR NOT private.f3_extension_matches_mime(v_file_name, v_mime) THEN
        RETURN jsonb_build_object('error', 'file_type_not_allowed');
    END IF;
    IF v_checksum IS NULL OR v_checksum !~ '^[0-9a-f]{64}$' THEN
        RETURN jsonb_build_object('error', 'invalid_checksum');
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM storage.objects AS so
        WHERE so.bucket_id = 'tenant-documents' AND so.name = v_path
          AND so.owner_id = (SELECT auth.uid())::text
    ) THEN
        RETURN jsonb_build_object('error', 'storage_object_not_found');
    END IF;

    INSERT INTO public.document_files (
        tenant_id, storage_bucket, storage_path, file_name, mime_type, size_bytes,
        checksum_sha256, file_kind, source_module, source_entity_type, source_entity_id,
        status, notes, metadata, uploaded_by
    ) VALUES (
        p_tenant_id, 'tenant-documents', v_path, v_file_name, v_mime, v_size,
        v_checksum, v_file_kind, v_module, v_entity_type, v_entity_id,
        'active', NULLIF(trim(p_payload->>'notes'), ''), COALESCE(p_payload->'metadata', '{}'::jsonb), (SELECT auth.uid())
    ) RETURNING id INTO v_id;

    PERFORM public.rpc_write_audit(p_tenant_id, 'document_file_registered', 'document_file', v_id,
        jsonb_build_object('source_module', v_module, 'source_entity_type', v_entity_type, 'file_kind', v_file_kind));
    RETURN (SELECT to_jsonb(df) FROM public.document_files AS df WHERE df.id = v_id);
EXCEPTION
    WHEN unique_violation THEN RETURN jsonb_build_object('error', 'storage_path_already_registered');
END;
$function$;

CREATE OR REPLACE FUNCTION private.f3_entity_reference(p_tenant_id uuid, p_entity_type text, p_entity_id uuid)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_reference text;
BEGIN
    CASE p_entity_type
        WHEN 'operation' THEN SELECT reference_code INTO v_reference FROM public.operations WHERE id = p_entity_id AND tenant_id = p_tenant_id;
        WHEN 'quote' THEN SELECT COALESCE(quote_reference, title) INTO v_reference FROM public.crm_deals WHERE id = p_entity_id AND tenant_id = p_tenant_id;
        WHEN 'customer' THEN SELECT display_name INTO v_reference FROM public.customers WHERE id = p_entity_id AND tenant_id = p_tenant_id;
        WHEN 'provider' THEN SELECT display_name INTO v_reference FROM public.logistics_providers WHERE id = p_entity_id AND tenant_id = p_tenant_id;
        WHEN 'generated_document' THEN SELECT document_number INTO v_reference FROM public.generated_documents WHERE id = p_entity_id AND tenant_id = p_tenant_id;
        WHEN 'billing_document' THEN
            IF to_regclass('public.billing_documents') IS NOT NULL THEN
                EXECUTE 'SELECT COALESCE(NULLIF(concat_ws(''-'', serie, folio), ''''), fiscal_uuid, id::text) FROM public.billing_documents WHERE id = $1 AND tenant_id = $2'
                INTO v_reference USING p_entity_id, p_tenant_id;
            END IF;
    END CASE;
    RETURN COALESCE(v_reference, 'Referencia no disponible');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_document_files(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_limit integer := LEAST(GREATEST(COALESCE(NULLIF(p_filters->>'limit', '')::integer, 50), 1), 100);
    v_cursor_at timestamptz := NULLIF(p_filters->>'cursor_created_at', '')::timestamptz;
    v_cursor_id uuid := NULLIF(p_filters->>'cursor_id', '')::uuid;
    v_entity_id uuid := NULLIF(p_filters->>'source_entity_id', '')::uuid;
    v_search text := NULLIF(lower(trim(p_filters->>'search')), '');
    v_items jsonb;
    v_last record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.memberships WHERE tenant_id = p_tenant_id AND user_id = (SELECT auth.uid())) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    WITH visible AS (
        SELECT df.*,
               private.f3_entity_reference(df.tenant_id, df.source_entity_type, df.source_entity_id) AS entity_reference,
               private.f3_user_can_access_module(df.tenant_id, df.source_module, true) AS can_manage
        FROM public.document_files AS df
        WHERE df.tenant_id = p_tenant_id
          AND private.f3_user_can_access_module(df.tenant_id, df.source_module, false)
          AND (p_filters->>'source_module' IS NULL OR df.source_module = p_filters->>'source_module')
          AND (p_filters->>'file_kind' IS NULL OR df.file_kind = p_filters->>'file_kind')
          AND (p_filters->>'status' IS NULL OR df.status = p_filters->>'status')
          AND (p_filters->>'source_entity_type' IS NULL OR df.source_entity_type = p_filters->>'source_entity_type'
               OR EXISTS (SELECT 1 FROM public.document_relations r WHERE r.document_file_id = df.id AND r.target_entity_type = p_filters->>'source_entity_type'))
          AND (v_entity_id IS NULL OR df.source_entity_id = v_entity_id
               OR EXISTS (SELECT 1 FROM public.document_relations r WHERE r.document_file_id = df.id AND r.target_entity_id = v_entity_id))
          AND (p_filters->>'date_from' IS NULL OR df.created_at >= (p_filters->>'date_from')::date)
          AND (p_filters->>'date_to' IS NULL OR df.created_at < ((p_filters->>'date_to')::date + 1))
          AND (v_search IS NULL OR lower(df.file_name || ' ' || COALESCE(df.notes, '') || ' ' || private.f3_entity_reference(df.tenant_id, df.source_entity_type, df.source_entity_id)) LIKE '%' || v_search || '%')
          AND (v_cursor_at IS NULL OR (df.created_at, df.id) < (v_cursor_at, v_cursor_id))
        ORDER BY df.created_at DESC, df.id DESC
        LIMIT v_limit
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(visible) ORDER BY created_at DESC, id DESC), '[]'::jsonb)
    INTO v_items FROM visible;

    SELECT item->>'created_at' AS created_at, item->>'id' AS id INTO v_last
    FROM jsonb_array_elements(v_items) WITH ORDINALITY AS entries(item, ordinality)
    ORDER BY ordinality DESC LIMIT 1;
    RETURN jsonb_build_object(
        'items', v_items,
        'next_cursor', CASE WHEN jsonb_array_length(v_items) = v_limit THEN
            jsonb_build_object('created_at', v_last.created_at, 'id', v_last.id) ELSE NULL END
    );
EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN
    RETURN jsonb_build_object('error', 'invalid_filters');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_mark_document_file_status(p_file_id uuid, p_status text, p_notes text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_file public.document_files%ROWTYPE;
BEGIN
    IF p_status NOT IN ('active', 'superseded', 'cancelled') THEN RETURN jsonb_build_object('error', 'invalid_status'); END IF;
    SELECT * INTO v_file FROM public.document_files WHERE id = p_file_id;
    IF v_file.id IS NULL THEN RETURN jsonb_build_object('error', 'file_not_found'); END IF;
    IF NOT private.f3_user_can_access_module(v_file.tenant_id, v_file.source_module, true) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    UPDATE public.document_files SET status = p_status,
        notes = COALESCE(NULLIF(trim(p_notes), ''), notes), updated_at = now()
    WHERE id = p_file_id;
    PERFORM public.rpc_write_audit(v_file.tenant_id, 'document_file_status_changed', 'document_file', p_file_id,
        jsonb_build_object('from', v_file.status, 'to', p_status));
    RETURN (SELECT to_jsonb(df) FROM public.document_files AS df WHERE id = p_file_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_relate_document_file(
    p_file_id uuid, p_entity_type text, p_entity_id uuid, p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_file public.document_files%ROWTYPE; v_target_module text; v_id uuid;
BEGIN
    SELECT * INTO v_file FROM public.document_files WHERE id = p_file_id;
    IF v_file.id IS NULL THEN RETURN jsonb_build_object('error', 'file_not_found'); END IF;
    v_target_module := CASE p_entity_type WHEN 'operation' THEN 'operations' WHEN 'billing_document' THEN 'billing' ELSE 'commercial' END;
    IF NOT private.f3_user_can_access_module(v_file.tenant_id, v_file.source_module, true)
       OR NOT private.f3_user_can_access_module(v_file.tenant_id, v_target_module, true) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF NOT private.f3_entity_belongs_to_tenant(v_file.tenant_id, p_entity_type, p_entity_id) THEN
        RETURN jsonb_build_object('error', 'invalid_target_entity');
    END IF;
    INSERT INTO public.document_relations (
        tenant_id, relation_type, source_entity_type, source_entity_id,
        target_entity_type, target_entity_id, notes, created_by, document_file_id
    ) VALUES (
        v_file.tenant_id, 'supporting_document', 'document_file', v_file.id,
        p_entity_type, p_entity_id, NULLIF(trim(p_notes), ''), (SELECT auth.uid()), v_file.id
    )
    ON CONFLICT (document_file_id, target_entity_type, target_entity_id, relation_type)
        WHERE document_file_id IS NOT NULL
    DO UPDATE SET notes = COALESCE(EXCLUDED.notes, public.document_relations.notes)
    RETURNING id INTO v_id;
    PERFORM public.rpc_write_audit(v_file.tenant_id, 'document_file_related', 'document_file', v_file.id,
        jsonb_build_object('target_entity_type', p_entity_type, 'target_entity_id', p_entity_id));
    RETURN jsonb_build_object('id', v_id, 'success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_document_relations(
    p_tenant_id uuid, p_entity_type text DEFAULT NULL, p_entity_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.memberships WHERE tenant_id = p_tenant_id AND user_id = (SELECT auth.uid())) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    RETURN (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', r.id, 'relation_type', r.relation_type, 'document_file_id', r.document_file_id,
            'file_name', df.file_name, 'target_entity_type', r.target_entity_type,
            'target_entity_id', r.target_entity_id,
            'target_reference', private.f3_entity_reference(r.tenant_id, r.target_entity_type, r.target_entity_id),
            'notes', r.notes, 'created_at', r.created_at
        ) ORDER BY r.created_at DESC), '[]'::jsonb)
        FROM public.document_relations AS r
        LEFT JOIN public.document_files AS df ON df.id = r.document_file_id
        WHERE r.tenant_id = p_tenant_id
          AND (p_entity_type IS NULL OR r.target_entity_type = p_entity_type OR r.source_entity_type = p_entity_type)
          AND (p_entity_id IS NULL OR r.target_entity_id = p_entity_id OR r.source_entity_id = p_entity_id)
          AND (df.id IS NULL OR private.f3_user_can_access_module(df.tenant_id, df.source_module, false))
    );
END;
$function$;
CREATE OR REPLACE FUNCTION public.rpc_attach_operation_document_file(
    p_operation_id uuid, p_document_type text, p_file_id uuid, p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_operation public.operations%ROWTYPE; v_file public.document_files%ROWTYPE; v_result jsonb;
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id;
    SELECT * INTO v_file FROM public.document_files WHERE id = p_file_id;
    IF v_operation.id IS NULL OR v_file.id IS NULL OR v_file.tenant_id <> v_operation.tenant_id THEN
        RETURN jsonb_build_object('error', 'invalid_document_file');
    END IF;
    IF NOT private.f3_user_can_access_module(v_operation.tenant_id, 'operations', true)
       OR NOT private.f3_user_can_access_module(v_file.tenant_id, v_file.source_module, false) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    SELECT public.rpc_upsert_operation_document(
        p_operation_id, p_document_type, 'required', 'present', v_file.file_name,
        v_file.id::text, NULL, p_note
    ) INTO v_result;
    IF v_result ? 'error' THEN RETURN v_result; END IF;
    SELECT public.rpc_relate_document_file(v_file.id, 'operation', p_operation_id, p_note) INTO v_result;
    IF v_result ? 'error' THEN RETURN v_result; END IF;
    RETURN jsonb_build_object('success', true, 'file_id', v_file.id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_add_operation_file_evidence(
    p_operation_id uuid, p_file_id uuid, p_incident_id uuid DEFAULT NULL, p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_operation public.operations%ROWTYPE; v_file public.document_files%ROWTYPE; v_result jsonb;
BEGIN
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id;
    SELECT * INTO v_file FROM public.document_files WHERE id = p_file_id;
    IF v_operation.id IS NULL OR v_file.id IS NULL OR v_file.tenant_id <> v_operation.tenant_id THEN
        RETURN jsonb_build_object('error', 'invalid_document_file');
    END IF;
    IF NOT private.f3_user_can_access_module(v_operation.tenant_id, 'operations', true) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    SELECT public.rpc_add_operation_evidence(
        p_operation_id, p_incident_id, 'file_reference', p_note, v_file.id::text, NULL
    ) INTO v_result;
    IF v_result ? 'error' THEN RETURN v_result; END IF;
    SELECT public.rpc_relate_document_file(v_file.id, 'operation', p_operation_id, p_note) INTO v_result;
    IF v_result ? 'error' THEN RETURN v_result; END IF;
    RETURN jsonb_build_object('success', true, 'file_id', v_file.id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_relate_quote_documents_to_operation(p_quote_id uuid, p_operation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_quote public.crm_deals%ROWTYPE; v_operation public.operations%ROWTYPE; v_file record; v_count integer := 0; v_result jsonb;
BEGIN
    SELECT * INTO v_quote FROM public.crm_deals WHERE id = p_quote_id;
    SELECT * INTO v_operation FROM public.operations WHERE id = p_operation_id;
    IF v_quote.id IS NULL OR v_operation.id IS NULL OR v_quote.tenant_id <> v_operation.tenant_id
       OR v_quote.converted_operation_id IS DISTINCT FROM v_operation.id THEN
        RETURN jsonb_build_object('error', 'invalid_quote_operation_relation');
    END IF;
    IF NOT private.f3_user_can_access_module(v_quote.tenant_id, 'commercial', true)
       OR NOT private.f3_user_can_access_module(v_quote.tenant_id, 'operations', true) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    FOR v_file IN
        SELECT id FROM public.document_files
        WHERE tenant_id = v_quote.tenant_id AND source_entity_type = 'quote'
          AND source_entity_id = v_quote.id AND status = 'active'
          AND COALESCE((metadata->>'operationally_relevant')::boolean, false)
    LOOP
        SELECT public.rpc_relate_document_file(v_file.id, 'operation', v_operation.id, 'Transferencia explícita desde cotización') INTO v_result;
        IF NOT (v_result ? 'error') THEN v_count := v_count + 1; END IF;
    END LOOP;
    RETURN jsonb_build_object('success', true, 'related_count', v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION private.f3_escape_html(p_value text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path TO pg_catalog
AS $function$
    SELECT replace(replace(replace(replace(replace(COALESCE(p_value, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;');
$function$;

CREATE OR REPLACE FUNCTION private.f3_render_snapshot_html(p_data jsonb, p_document_number text)
RETURNS text
LANGUAGE plpgsql IMMUTABLE
SET search_path TO pg_catalog
AS $function$
DECLARE v_rows text := ''; v_item jsonb;
BEGIN
    IF jsonb_typeof(p_data->'fields') = 'array' THEN
        FOR v_item IN SELECT value FROM jsonb_array_elements(p_data->'fields') LOOP
            IF lower(COALESCE(v_item->>'label', '')) !~ 'costo|margen|utilidad|nota interna' THEN
                v_rows := v_rows || '<tr><th>' || private.f3_escape_html(v_item->>'label') || '</th><td>' || private.f3_escape_html(v_item->>'value') || '</td></tr>';
            END IF;
        END LOOP;
    ELSE
        FOR v_item IN SELECT jsonb_build_object('label', key, 'value', value #>> '{}') FROM jsonb_each(p_data) WHERE key NOT IN ('notes', 'internal_notes') LOOP
            v_rows := v_rows || '<tr><th>' || private.f3_escape_html(v_item->>'label') || '</th><td>' || private.f3_escape_html(v_item->>'value') || '</td></tr>';
        END LOOP;
    END IF;
    IF jsonb_typeof(p_data->'amounts') = 'array' THEN
        FOR v_item IN SELECT value FROM jsonb_array_elements(p_data->'amounts') LOOP
            IF lower(COALESCE(v_item->>'label', '')) !~ 'costo|margen|utilidad|proveedor' THEN
                v_rows := v_rows || '<tr><th>' || private.f3_escape_html(v_item->>'label') || '</th><td>' || private.f3_escape_html(v_item->>'value') || '</td></tr>';
            END IF;
        END LOOP;
    END IF;
    RETURN '<!doctype html><html><head><meta charset="utf-8"><title>' || private.f3_escape_html(p_document_number) ||
           '</title><style>body{font-family:Arial,sans-serif;color:#172033;padding:32px}h1{font-size:22px}table{width:100%;border-collapse:collapse}th,td{padding:9px;border-bottom:1px solid #ddd;text-align:left}th{width:36%;color:#64748b}</style></head><body><h1>' ||
           private.f3_escape_html(COALESCE(p_data->>'title', 'Documento ROTERO')) || '</h1><p>' ||
           private.f3_escape_html(p_document_number) || '</p><table>' || v_rows || '</table></body></html>';
END;
$function$;

CREATE OR REPLACE FUNCTION private.f3_guard_generated_snapshot()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_filtered jsonb;
BEGIN
    IF TG_OP = 'UPDATE' AND (
        NEW.tenant_id IS DISTINCT FROM OLD.tenant_id OR NEW.template_id IS DISTINCT FROM OLD.template_id
        OR NEW.template_version_id IS DISTINCT FROM OLD.template_version_id OR NEW.entity_type IS DISTINCT FROM OLD.entity_type
        OR NEW.entity_id IS DISTINCT FROM OLD.entity_id OR NEW.html_snapshot IS DISTINCT FROM OLD.html_snapshot
        OR NEW.data_snapshot IS DISTINCT FROM OLD.data_snapshot OR NEW.document_number IS DISTINCT FROM OLD.document_number
        OR NEW.generated_at IS DISTINCT FROM OLD.generated_at
    ) THEN RAISE EXCEPTION 'generated_snapshot_immutable'; END IF;

    IF TG_OP = 'INSERT' AND NEW.entity_type = 'commercial_quote' THEN
        v_filtered := NEW.data_snapshot - ARRAY['notes', 'internal_notes', 'provider_cost', 'provider_cost_amount', 'gross_margin', 'margin', 'utility'];
        IF jsonb_typeof(v_filtered->'fields') = 'array' THEN
            v_filtered := jsonb_set(v_filtered, '{fields}', COALESCE((
                SELECT jsonb_agg(value) FROM jsonb_array_elements(v_filtered->'fields')
                WHERE lower(COALESCE(value->>'label', '')) !~ 'costo|margen|utilidad|nota interna'
            ), '[]'::jsonb));
        END IF;
        IF jsonb_typeof(v_filtered->'amounts') = 'array' THEN
            v_filtered := jsonb_set(v_filtered, '{amounts}', COALESCE((
                SELECT jsonb_agg(value) FROM jsonb_array_elements(v_filtered->'amounts')
                WHERE lower(COALESCE(value->>'label', '')) !~ 'costo|margen|utilidad|proveedor'
            ), '[]'::jsonb));
        END IF;
        NEW.data_snapshot := v_filtered;
        NEW.html_snapshot := private.f3_render_snapshot_html(v_filtered, NEW.document_number);
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_generate_document_f3(
    p_tenant_id uuid, p_template_type text, p_entity_type text, p_entity_id uuid, p_options jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_module text; v_data jsonb; v_template_id uuid; v_version_id uuid; v_id uuid;
    v_number text; v_html text; v_title text;
BEGIN
    v_module := CASE WHEN p_template_type = 'commercial_quote' THEN 'commercial'
                     WHEN p_template_type IN ('operation_summary', 'operation_document') THEN 'operations'
                     ELSE NULL END;
    IF v_module IS NULL THEN RETURN jsonb_build_object('error', 'unsupported_template_type'); END IF;
    IF NOT private.f3_user_can_access_module(p_tenant_id, v_module, true) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    IF NOT private.f3_entity_belongs_to_tenant(p_tenant_id, p_entity_type, p_entity_id) THEN RETURN jsonb_build_object('error', 'invalid_source_entity'); END IF;
    IF (p_template_type = 'commercial_quote' AND p_entity_type <> 'quote')
       OR (p_template_type IN ('operation_summary', 'operation_document') AND p_entity_type <> 'operation') THEN
        RETURN jsonb_build_object('error', 'invalid_source_entity');
    END IF;

    IF p_template_type = 'commercial_quote' THEN
        SELECT jsonb_build_object(
            'title', 'Cotización', 'reference', COALESCE(d.quote_reference, d.title),
            'customer', COALESCE(c.display_name, d.company, 'Datos por confirmar'),
            'route', COALESCE(d.quote_payload->>'route_summary',
                concat_ws(' → ', d.quote_payload#>>'{origin_place,municipality}', d.quote_payload#>>'{destination_place,municipality}')),
            'service', COALESCE(d.quote_payload->>'service_type', 'Datos por confirmar'),
            'customer_price', concat_ws(' ', d.quote_payload->>'customer_price_amount', COALESCE(d.quote_payload->>'currency', d.currency, 'MXN'))
        ) INTO v_data
        FROM public.crm_deals AS d LEFT JOIN public.customers AS c ON c.id = d.customer_id
        WHERE d.id = p_entity_id AND d.tenant_id = p_tenant_id;
        v_title := 'Cotización';
    ELSE
        SELECT jsonb_build_object(
            'title', 'Resumen operativo', 'reference', o.reference_code,
            'customer', COALESCE(c.display_name, o.client_display_name, 'Datos por confirmar'),
            'route', COALESCE(o.route_summary, 'Datos por confirmar'),
            'service', COALESCE(o.service_type, 'Datos por confirmar'), 'status', o.status
        ) INTO v_data
        FROM public.operations AS o LEFT JOIN public.customers AS c ON c.id = o.customer_id
        WHERE o.id = p_entity_id AND o.tenant_id = p_tenant_id;
        v_title := 'Resumen operativo';
    END IF;
    IF v_data IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;

    SELECT id, active_version_id INTO v_template_id, v_version_id
    FROM public.document_templates
    WHERE tenant_id = p_tenant_id AND template_type = p_template_type AND status = 'active'
    ORDER BY updated_at DESC LIMIT 1;
    IF v_template_id IS NULL THEN
        INSERT INTO public.document_templates (tenant_id, template_type, name, title, module, created_by)
        VALUES (p_tenant_id, p_template_type, v_title || ' ROTERO', v_title, v_module, (SELECT auth.uid()))
        RETURNING id INTO v_template_id;
        INSERT INTO public.document_template_versions (
            tenant_id, template_id, version_number, template_type, name, title, status, created_by, activated_at
        ) VALUES (p_tenant_id, v_template_id, 1, p_template_type, v_title || ' ROTERO', v_title, 'active', (SELECT auth.uid()), now())
        RETURNING id INTO v_version_id;
        UPDATE public.document_templates SET active_version_id = v_version_id WHERE id = v_template_id;
    END IF;

    v_number := COALESCE(NULLIF(trim(p_options->>'document_number'), ''),
        CASE WHEN p_template_type = 'commercial_quote' THEN 'COT-' ELSE 'OPD-' END ||
        to_char(clock_timestamp(), 'YYMMDDHH24MISS') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)));
    v_html := private.f3_render_snapshot_html(v_data, v_number);
    INSERT INTO public.generated_documents (
        tenant_id, template_id, template_version_id, entity_type, entity_id, status,
        html_snapshot, data_snapshot, generated_by, document_number, source_module,
        related_entity_type, related_entity_id, finalized_at, metadata
    ) VALUES (
        p_tenant_id, v_template_id, v_version_id, p_template_type, p_entity_id, 'final',
        v_html, v_data, (SELECT auth.uid()), v_number, v_module,
        p_entity_type, p_entity_id, now(), jsonb_build_object('f3_snapshot', true)
    ) RETURNING id INTO v_id;
    PERFORM public.rpc_write_audit(p_tenant_id, 'generated_document_created', 'generated_document', v_id,
        jsonb_build_object('template_type', p_template_type, 'entity_type', p_entity_type));
    RETURN (SELECT to_jsonb(gd) FROM public.generated_documents AS gd WHERE id = v_id);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('error', 'document_number_conflict');
END;
$function$;

DO $block$
BEGIN
    IF to_regprocedure('public.rpc_generate_document(uuid,text,text,uuid,jsonb)') IS NULL THEN
        EXECUTE $sql$
            CREATE FUNCTION public.rpc_generate_document(
                p_tenant_id uuid, p_template_type text, p_entity_type text, p_entity_id uuid, p_options jsonb DEFAULT '{}'::jsonb
            ) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO pg_catalog, public
            AS $body$ SELECT public.rpc_generate_document_f3($1, $2, $3, $4, $5); $body$
        $sql$;
    END IF;
END;
$block$;
ALTER FUNCTION public.rpc_generate_document(uuid, text, text, uuid, jsonb) SET search_path TO pg_catalog, public;

DROP TRIGGER IF EXISTS trg_f3_guard_generated_snapshot ON public.generated_documents;
CREATE TRIGGER trg_f3_guard_generated_snapshot
BEFORE INSERT OR UPDATE ON public.generated_documents
FOR EACH ROW EXECUTE FUNCTION private.f3_guard_generated_snapshot();
CREATE OR REPLACE FUNCTION public.rpc_list_generated_documents(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_limit integer := LEAST(GREATEST(COALESCE(NULLIF(p_filters->>'limit', '')::integer, 50), 1), 100);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.memberships WHERE tenant_id = p_tenant_id AND user_id = (SELECT auth.uid())) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    RETURN jsonb_build_object('items', COALESCE((
        SELECT jsonb_agg(row_data ORDER BY generated_at DESC, id DESC)
        FROM (
            SELECT gd.id, gd.tenant_id, gd.template_id, gd.template_version_id,
                   t.name AS template_name, gd.entity_type AS template_type, gd.entity_type,
                   gd.entity_id, gd.document_number, gd.source_module, gd.related_entity_type,
                   gd.related_entity_id, gd.status, gd.html_snapshot, gd.data_snapshot,
                   gd.metadata, gd.print_count, gd.generated_by, gd.generated_at,
                   gd.finalized_at, gd.cancelled_at, gd.created_at,
                   private.f3_entity_reference(gd.tenant_id, gd.related_entity_type, gd.related_entity_id) AS entity_reference,
                   private.f3_user_can_access_module(
                       gd.tenant_id,
                       CASE WHEN gd.entity_type IN ('operation_summary', 'operation_document') THEN 'operations'
                            WHEN gd.entity_type = 'commercial_quote' THEN 'commercial' ELSE 'finance' END,
                       true
                   ) AS can_manage
            FROM public.generated_documents AS gd
            LEFT JOIN public.document_templates AS t ON t.id = gd.template_id
            WHERE gd.tenant_id = p_tenant_id
              AND private.f3_user_can_access_module(
                  gd.tenant_id,
                  CASE WHEN gd.entity_type IN ('operation_summary', 'operation_document') THEN 'operations'
                       WHEN gd.entity_type = 'commercial_quote' THEN 'commercial' ELSE 'finance' END,
                  false
              )
              AND (p_filters->>'template_type' IS NULL OR gd.entity_type = p_filters->>'template_type')
              AND (p_filters->>'status' IS NULL OR gd.status = p_filters->>'status')
              AND (p_filters->>'search' IS NULL OR lower(COALESCE(gd.document_number, '') || ' ' ||
                  private.f3_entity_reference(gd.tenant_id, gd.related_entity_type, gd.related_entity_id))
                  LIKE '%' || lower(trim(p_filters->>'search')) || '%')
            ORDER BY gd.generated_at DESC, gd.id DESC
            LIMIT v_limit
        ) AS row_data
    ), '[]'::jsonb));
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error', 'invalid_filters');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_mark_generated_document_printed(p_document_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_document public.generated_documents%ROWTYPE; v_module text;
BEGIN
    SELECT * INTO v_document FROM public.generated_documents WHERE id = p_document_id;
    IF v_document.id IS NULL THEN RETURN jsonb_build_object('error', 'document_not_found'); END IF;
    v_module := CASE WHEN v_document.entity_type IN ('operation_summary', 'operation_document') THEN 'operations'
                     WHEN v_document.entity_type = 'commercial_quote' THEN 'commercial' ELSE 'finance' END;
    IF NOT private.f3_user_can_access_module(v_document.tenant_id, v_module, true) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    UPDATE public.generated_documents SET print_count = print_count + 1 WHERE id = p_document_id;
    PERFORM public.rpc_write_audit(v_document.tenant_id, 'generated_document_printed', 'generated_document', p_document_id, '{}'::jsonb);
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_cancel_generated_document(p_document_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_document public.generated_documents%ROWTYPE; v_module text;
BEGIN
    IF NULLIF(trim(p_reason), '') IS NULL THEN RETURN jsonb_build_object('error', 'cancel_reason_required'); END IF;
    SELECT * INTO v_document FROM public.generated_documents WHERE id = p_document_id;
    IF v_document.id IS NULL THEN RETURN jsonb_build_object('error', 'document_not_found'); END IF;
    v_module := CASE WHEN v_document.entity_type IN ('operation_summary', 'operation_document') THEN 'operations'
                     WHEN v_document.entity_type = 'commercial_quote' THEN 'commercial' ELSE 'finance' END;
    IF NOT private.f3_user_can_access_module(v_document.tenant_id, v_module, true) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    IF v_document.status = 'cancelled' THEN RETURN to_jsonb(v_document); END IF;
    UPDATE public.generated_documents SET status = 'cancelled', cancelled_at = now(),
        metadata = metadata || jsonb_build_object('cancel_reason', trim(p_reason), 'cancelled_by', (SELECT auth.uid()), 'cancelled_at', now())
    WHERE id = p_document_id;
    PERFORM public.rpc_write_audit(v_document.tenant_id, 'generated_document_cancelled', 'generated_document', p_document_id,
        jsonb_build_object('reason', trim(p_reason)));
    RETURN (SELECT to_jsonb(gd) FROM public.generated_documents AS gd WHERE id = p_document_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_document_templates_v2(p_tenant_id uuid, p_template_type text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.memberships WHERE tenant_id = p_tenant_id AND user_id = (SELECT auth.uid())) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    RETURN (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', t.id, 'tenant_id', t.tenant_id, 'template_type', t.template_type,
            'module', t.module, 'name', t.name, 'version', t.version,
            'active_version_id', t.active_version_id, 'layout_key', t.layout_key,
            'title', t.title, 'status', t.status, 'is_active', t.is_active,
            'updated_at', t.updated_at,
            'active_version', CASE WHEN v.id IS NULL THEN NULL ELSE jsonb_build_object(
                'id', v.id, 'version_number', v.version_number, 'status', v.status,
                'created_at', v.created_at, 'activated_at', v.activated_at
            ) END
        ) ORDER BY t.template_type, t.name), '[]'::jsonb)
        FROM public.document_templates AS t
        LEFT JOIN public.document_template_versions AS v ON v.id = t.active_version_id
        WHERE t.tenant_id = p_tenant_id
          AND (p_template_type IS NULL OR t.template_type = p_template_type)
          AND private.f3_user_can_access_module(
              t.tenant_id,
              CASE WHEN t.template_type IN ('operation_summary', 'operation_document') THEN 'operations'
                   WHEN t.template_type = 'commercial_quote' THEN 'commercial' ELSE 'finance' END,
              false
          )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_document_source_options(
    p_tenant_id uuid, p_template_type text, p_search text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_search text := NULLIF(lower(trim(p_search)), ''); v_module text;
BEGIN
    v_module := CASE WHEN p_template_type = 'commercial_quote' THEN 'commercial'
                     WHEN p_template_type IN ('operation_summary', 'operation_document') THEN 'operations'
                     ELSE 'finance' END;
    IF NOT private.f3_user_can_access_module(p_tenant_id, v_module, false) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    IF p_template_type = 'commercial_quote' THEN
        RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', d.id, 'label', COALESCE(d.quote_reference, d.title),
            'description', COALESCE(c.display_name, d.company, 'Sin cliente'),
            'module', 'commercial', 'status', d.quote_status, 'created_at', d.created_at
        ) ORDER BY d.updated_at DESC), '[]'::jsonb)
        FROM public.crm_deals AS d LEFT JOIN public.customers AS c ON c.id = d.customer_id
        WHERE d.tenant_id = p_tenant_id AND d.quote_reference IS NOT NULL
          AND (v_search IS NULL OR lower(COALESCE(d.quote_reference, '') || ' ' || d.title || ' ' || COALESCE(c.display_name, '')) LIKE '%' || v_search || '%')
        LIMIT 50);
    ELSIF p_template_type IN ('operation_summary', 'operation_document') THEN
        RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', o.id, 'label', o.reference_code,
            'description', COALESCE(c.display_name, o.client_display_name, 'Sin cliente') || ' · ' || COALESCE(o.route_summary, 'Sin ruta'),
            'module', 'operations', 'status', o.status, 'created_at', o.created_at
        ) ORDER BY o.created_at DESC), '[]'::jsonb)
        FROM public.operations AS o LEFT JOIN public.customers AS c ON c.id = o.customer_id
        WHERE o.tenant_id = p_tenant_id
          AND (v_search IS NULL OR lower(o.reference_code || ' ' || COALESCE(c.display_name, o.client_display_name, '') || ' ' || COALESCE(o.route_summary, '')) LIKE '%' || v_search || '%')
        LIMIT 50);
    END IF;
    RETURN '[]'::jsonb;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.rpc_get_document_upload_contract(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_register_document_file(uuid, jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_document_files(uuid, jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_mark_document_file_status(uuid, text, text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_relate_document_file(uuid, text, uuid, text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_document_relations(uuid, text, uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_attach_operation_document_file(uuid, text, uuid, text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_add_operation_file_evidence(uuid, uuid, uuid, text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_relate_quote_documents_to_operation(uuid, uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_generate_document_f3(uuid, text, text, uuid, jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_generate_document(uuid, text, text, uuid, jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_generated_documents(uuid, jsonb) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_mark_generated_document_printed(uuid) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_cancel_generated_document(uuid, text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_document_templates_v2(uuid, text) FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_document_source_options(uuid, text, text) FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.rpc_get_document_upload_contract(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_register_document_file(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_document_files(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_mark_document_file_status(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_relate_document_file(uuid, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_document_relations(uuid, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_attach_operation_document_file(uuid, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_add_operation_file_evidence(uuid, uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_relate_quote_documents_to_operation(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_generate_document_f3(uuid, text, text, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_generate_document(uuid, text, text, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_generated_documents(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_mark_generated_document_printed(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_cancel_generated_document(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_document_templates_v2(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_document_source_options(uuid, text, text) TO authenticated;

REVOKE ALL ON FUNCTION private.f3_extension_matches_mime(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.f3_entity_reference(uuid, text, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.f3_render_snapshot_html(jsonb, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.f3_guard_generated_snapshot() FROM PUBLIC, anon, authenticated, service_role;
