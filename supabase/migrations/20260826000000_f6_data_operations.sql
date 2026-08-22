-- F6 — ROTERO Data Operations 360
-- CSV-first, bounded, admin-only imports and role-aware paginated exports.
-- No Auth, Edge, Tracking capability, fiscal-payment or raw-file contract changes.

ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS external_key text;
ALTER TABLE public.logistics_providers ADD COLUMN IF NOT EXISTS external_key text;
ALTER TABLE public.operations ADD COLUMN IF NOT EXISTS external_key text;

DO $block$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.customers'::regclass AND conname='customers_external_key_check') THEN
        ALTER TABLE public.customers ADD CONSTRAINT customers_external_key_check
        CHECK (external_key IS NULL OR (external_key=btrim(external_key) AND char_length(external_key) BETWEEN 1 AND 100));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.logistics_providers'::regclass AND conname='logistics_providers_external_key_check') THEN
        ALTER TABLE public.logistics_providers ADD CONSTRAINT logistics_providers_external_key_check
        CHECK (external_key IS NULL OR (external_key=btrim(external_key) AND char_length(external_key) BETWEEN 1 AND 100));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.operations'::regclass AND conname='operations_external_key_check') THEN
        ALTER TABLE public.operations ADD CONSTRAINT operations_external_key_check
        CHECK (external_key IS NULL OR (external_key=btrim(external_key) AND char_length(external_key) BETWEEN 1 AND 100));
    END IF;
END;
$block$;

CREATE UNIQUE INDEX IF NOT EXISTS customers_tenant_external_key_uidx
    ON public.customers (tenant_id, lower(external_key)) WHERE external_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS logistics_providers_tenant_external_key_uidx
    ON public.logistics_providers (tenant_id, lower(external_key)) WHERE external_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS operations_tenant_external_key_uidx
    ON public.operations (tenant_id, lower(external_key)) WHERE external_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS logistics_providers_tenant_tax_id_idx
    ON public.logistics_providers (tenant_id, tax_id) WHERE tax_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.data_import_batches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    entity_type text NOT NULL CHECK (entity_type IN ('customers','providers','operations')),
    filename text NOT NULL CHECK (char_length(btrim(filename)) BETWEEN 1 AND 255),
    mode text NOT NULL CHECK (mode IN ('create_only','upsert')),
    idempotency_key text NOT NULL CHECK (char_length(idempotency_key) BETWEEN 16 AND 200),
    total_rows integer NOT NULL CHECK (total_rows BETWEEN 1 AND 1000),
    valid_rows integer NOT NULL DEFAULT 0 CHECK (valid_rows >= 0),
    applied_rows integer NOT NULL DEFAULT 0 CHECK (applied_rows >= 0),
    updated_rows integer NOT NULL DEFAULT 0 CHECK (updated_rows >= 0),
    skipped_rows integer NOT NULL DEFAULT 0 CHECK (skipped_rows >= 0),
    error_rows integer NOT NULL DEFAULT 0 CHECK (error_rows >= 0),
    status text NOT NULL DEFAULT 'processing' CHECK (status IN ('processing','completed','completed_with_errors','failed')),
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    summary jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(summary)='object'),
    CONSTRAINT data_import_batches_idempotency_unique UNIQUE (tenant_id,user_id,idempotency_key)
);

CREATE TABLE IF NOT EXISTS public.data_import_chunks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    batch_id uuid NOT NULL REFERENCES public.data_import_batches(id) ON DELETE CASCADE,
    chunk_key text NOT NULL CHECK (char_length(btrim(chunk_key)) BETWEEN 1 AND 120),
    row_count integer NOT NULL CHECK (row_count BETWEEN 1 AND 200),
    result jsonb NOT NULL CHECK (jsonb_typeof(result)='object'),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT data_import_chunks_batch_key_unique UNIQUE (batch_id,chunk_key)
);

CREATE TABLE IF NOT EXISTS public.data_import_mappings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    entity_type text NOT NULL CHECK (entity_type IN ('customers','providers','operations')),
    name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 80),
    mapping jsonb NOT NULL CHECK (jsonb_typeof(mapping)='object'),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS data_import_batches_tenant_started_idx
    ON public.data_import_batches (tenant_id,started_at DESC,id DESC);
CREATE INDEX IF NOT EXISTS data_import_chunks_tenant_batch_idx
    ON public.data_import_chunks (tenant_id,batch_id,created_at);
CREATE UNIQUE INDEX IF NOT EXISTS data_import_mappings_owner_name_uidx
    ON public.data_import_mappings (tenant_id,user_id,entity_type,lower(name));
CREATE INDEX IF NOT EXISTS data_import_mappings_owner_idx
    ON public.data_import_mappings (tenant_id,user_id,entity_type,updated_at DESC);

DROP TRIGGER IF EXISTS trg_data_import_mappings_touch_updated_at ON public.data_import_mappings;
CREATE TRIGGER trg_data_import_mappings_touch_updated_at
BEFORE UPDATE ON public.data_import_mappings
FOR EACH ROW EXECUTE FUNCTION public.tanda1_touch_updated_at();

ALTER TABLE public.data_import_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_import_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_import_mappings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS data_import_batches_owner_f6 ON public.data_import_batches;
CREATE POLICY data_import_batches_owner_f6 ON public.data_import_batches FOR ALL TO authenticated
USING (user_id=(SELECT auth.uid()) AND (SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])))
WITH CHECK (user_id=(SELECT auth.uid()) AND (SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])));
DROP POLICY IF EXISTS data_import_chunks_owner_f6 ON public.data_import_chunks;
CREATE POLICY data_import_chunks_owner_f6 ON public.data_import_chunks FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.data_import_batches b WHERE b.id=data_import_chunks.batch_id AND b.user_id=(SELECT auth.uid()) AND b.tenant_id=data_import_chunks.tenant_id))
WITH CHECK (EXISTS (SELECT 1 FROM public.data_import_batches b WHERE b.id=data_import_chunks.batch_id AND b.user_id=(SELECT auth.uid()) AND b.tenant_id=data_import_chunks.tenant_id));
DROP POLICY IF EXISTS data_import_mappings_owner_f6 ON public.data_import_mappings;
CREATE POLICY data_import_mappings_owner_f6 ON public.data_import_mappings FOR ALL TO authenticated
USING (user_id=(SELECT auth.uid()) AND (SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])))
WITH CHECK (user_id=(SELECT auth.uid()) AND (SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin'])));

REVOKE ALL ON TABLE public.data_import_batches,public.data_import_chunks,public.data_import_mappings
FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION private.f6_current_role(p_tenant_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,public
AS $function$
    SELECT m.role FROM public.memberships m
    WHERE m.tenant_id=p_tenant_id AND m.user_id=(SELECT auth.uid()) LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION private.f6_issue(p_code text,p_message text)
RETURNS jsonb LANGUAGE sql IMMUTABLE
SET search_path TO pg_catalog
AS $function$
    SELECT jsonb_build_object('code',p_code,'message',p_message);
$function$;

CREATE OR REPLACE FUNCTION private.f6_resolve_relation(
    p_tenant_id uuid,p_entity_type text,p_external_key text,p_tax_id text,p_display_name text
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,public
AS $function$
DECLARE v_count integer; v_id uuid; v_name text; v_existing_key text;
BEGIN
    IF p_entity_type NOT IN ('customer','provider') THEN RETURN jsonb_build_object('error','invalid_relation_type'); END IF;
    IF NULLIF(btrim(COALESCE(p_external_key,'')),'') IS NOT NULL THEN
        IF p_entity_type='customer' THEN
            SELECT count(*) INTO v_count FROM public.customers WHERE tenant_id=p_tenant_id AND lower(external_key)=lower(btrim(p_external_key));
            IF v_count=1 THEN SELECT id,display_name,external_key INTO v_id,v_name,v_existing_key FROM public.customers WHERE tenant_id=p_tenant_id AND lower(external_key)=lower(btrim(p_external_key)); END IF;
        ELSE
            SELECT count(*) INTO v_count FROM public.logistics_providers WHERE tenant_id=p_tenant_id AND lower(external_key)=lower(btrim(p_external_key));
            IF v_count=1 THEN SELECT id,display_name,external_key INTO v_id,v_name,v_existing_key FROM public.logistics_providers WHERE tenant_id=p_tenant_id AND lower(external_key)=lower(btrim(p_external_key)); END IF;
        END IF;
        IF v_count>1 THEN RETURN jsonb_build_object('error','ambiguous_'||p_entity_type); END IF;
        IF v_count=1 THEN RETURN jsonb_build_object('id',v_id,'display_name',v_name,'external_key',v_existing_key,'matched_by','external_key'); END IF;
    END IF;

    IF NULLIF(btrim(COALESCE(p_tax_id,'')),'') IS NOT NULL THEN
        IF p_entity_type='customer' THEN
            SELECT count(*) INTO v_count FROM public.customers WHERE tenant_id=p_tenant_id AND tax_id=upper(btrim(p_tax_id));
            IF v_count=1 THEN SELECT id,display_name,external_key INTO v_id,v_name,v_existing_key FROM public.customers WHERE tenant_id=p_tenant_id AND tax_id=upper(btrim(p_tax_id)); END IF;
        ELSE
            SELECT count(*) INTO v_count FROM public.logistics_providers WHERE tenant_id=p_tenant_id AND tax_id=upper(btrim(p_tax_id));
            IF v_count=1 THEN SELECT id,display_name,external_key INTO v_id,v_name,v_existing_key FROM public.logistics_providers WHERE tenant_id=p_tenant_id AND tax_id=upper(btrim(p_tax_id)); END IF;
        END IF;
        IF v_count>1 THEN RETURN jsonb_build_object('error','ambiguous_'||p_entity_type); END IF;
        IF v_count=1 THEN RETURN jsonb_build_object('id',v_id,'display_name',v_name,'external_key',v_existing_key,'matched_by','tax_id'); END IF;
    END IF;

    IF NULLIF(btrim(COALESCE(p_display_name,'')),'') IS NOT NULL THEN
        IF p_entity_type='customer' THEN
            SELECT count(*) INTO v_count FROM public.customers WHERE tenant_id=p_tenant_id AND lower(display_name)=lower(btrim(p_display_name));
            IF v_count=1 THEN SELECT id,display_name,external_key INTO v_id,v_name,v_existing_key FROM public.customers WHERE tenant_id=p_tenant_id AND lower(display_name)=lower(btrim(p_display_name)); END IF;
        ELSE
            SELECT count(*) INTO v_count FROM public.logistics_providers WHERE tenant_id=p_tenant_id AND lower(display_name)=lower(btrim(p_display_name));
            IF v_count=1 THEN SELECT id,display_name,external_key INTO v_id,v_name,v_existing_key FROM public.logistics_providers WHERE tenant_id=p_tenant_id AND lower(display_name)=lower(btrim(p_display_name)); END IF;
        END IF;
        IF v_count>1 THEN RETURN jsonb_build_object('error','ambiguous_'||p_entity_type); END IF;
        IF v_count=1 THEN RETURN jsonb_build_object('id',v_id,'display_name',v_name,'external_key',v_existing_key,'matched_by','display_name'); END IF;
    END IF;
    RETURN jsonb_build_object('error',p_entity_type||'_not_found');
END;
$function$;

CREATE OR REPLACE FUNCTION private.f6_validate_row(
    p_tenant_id uuid,p_entity_type text,p_mode text,p_row jsonb
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,public
AS $function$
DECLARE
    v_errors jsonb:='[]'::jsonb; v_warnings jsonb:='[]'::jsonb; v_normalized jsonb:='{}'::jsonb;
    v_external text:=NULLIF(btrim(COALESCE(p_row->>'external_key','')),'');
    v_display text:=NULLIF(btrim(COALESCE(p_row->>'display_name','')),'');
    v_tax text:=NULLIF(upper(btrim(COALESCE(p_row->>'tax_id',''))),'');
    v_email text; v_billing_email text; v_active_text text; v_active boolean;
    v_relation jsonb; v_existing_id uuid; v_existing_key text; v_existing_status text; v_existing_reference text;
    v_action text:='create'; v_scope text; v_execution text; v_currency text; v_reference text;
    v_customer jsonb; v_provider jsonb; v_start timestamptz; v_end timestamptz;
    v_origin_country text; v_destination_country text; v_origin_municipality text; v_origin_state text;
    v_destination_municipality text; v_destination_state text; v_service text; v_cargo text;
    v_provider_cost numeric; v_customer_sell numeric; v_pieces numeric; v_weight numeric;
BEGIN
    IF p_row IS NULL OR jsonb_typeof(p_row)<>'object' THEN
        RETURN jsonb_build_object('action','error','normalized','{}'::jsonb,'warnings','[]'::jsonb,
            'errors',jsonb_build_array(private.f6_issue('invalid_row','La fila no tiene una estructura válida.')));
    END IF;

    IF p_entity_type IN ('customers','providers') THEN
        IF v_display IS NULL THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('missing_display_name','El nombre es obligatorio.')); END IF;
        IF v_external IS NULL THEN
            v_warnings:=v_warnings||jsonb_build_array(private.f6_issue('missing_external_key','Se recomienda external_key para reimportaciones deterministas.'));
        ELSIF char_length(v_external)>100 THEN
            v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_external_key','external_key excede 100 caracteres.'));
        END IF;
        IF v_tax IS NOT NULL AND v_tax !~ '^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$' THEN
            v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_tax_id','El RFC no tiene un formato válido.'));
        END IF;
        v_email:=NULLIF(lower(btrim(COALESCE(p_row->>'contact_email',''))),'');
        v_billing_email:=NULLIF(lower(btrim(COALESCE(p_row->>'billing_email',''))),'');
        IF v_email IS NOT NULL AND v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
            v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_email','El correo de contacto no es válido.'));
        END IF;
        IF v_billing_email IS NOT NULL AND v_billing_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
            v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_billing_email','El correo de facturación no es válido.'));
        END IF;

        IF p_row?'is_active' THEN
            v_active_text:=lower(btrim(COALESCE(p_row->>'is_active','')));
            IF v_active_text IN ('true','1','yes','si','sí','activo','active') THEN v_active:=true;
            ELSIF v_active_text IN ('false','0','no','inactivo','inactive') THEN v_active:=false;
            ELSE v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_status','El estado debe ser activo o inactivo.')); END IF;
        END IF;

        v_relation:=private.f6_resolve_relation(p_tenant_id,CASE WHEN p_entity_type='customers' THEN 'customer' ELSE 'provider' END,v_external,v_tax,v_display);
        IF NOT (v_relation?'error') THEN
            v_existing_id:=(v_relation->>'id')::uuid; v_existing_key:=NULLIF(v_relation->>'external_key','');
            IF v_external IS NOT NULL AND v_existing_key IS NOT NULL AND lower(v_external)<>lower(v_existing_key) THEN
                v_errors:=v_errors||jsonb_build_array(private.f6_issue('external_key_conflict','El registro coincidente ya tiene otro external_key.'));
            END IF;
            IF p_mode='create_only' THEN
                v_action:='skip';
                v_warnings:=v_warnings||jsonb_build_array(private.f6_issue('already_exists','El registro ya existe; create_only no lo modifica.'));
            ELSE v_action:='update'; END IF;
        ELSIF v_relation->>'error' IN ('ambiguous_customer','ambiguous_provider') THEN
            v_errors:=v_errors||jsonb_build_array(private.f6_issue(v_relation->>'error','Hay más de una coincidencia posible; usa external_key.'));
        END IF;

        v_normalized:=jsonb_build_object('external_key',v_external,'display_name',v_display);
        IF p_row?'legal_name' THEN v_normalized:=v_normalized||jsonb_build_object('legal_name',NULLIF(btrim(COALESCE(p_row->>'legal_name','')),'')); END IF;
        IF p_row?'tax_id' THEN v_normalized:=v_normalized||jsonb_build_object('tax_id',v_tax); END IF;
        IF p_row?'contact_name' THEN v_normalized:=v_normalized||jsonb_build_object('contact_name',NULLIF(btrim(COALESCE(p_row->>'contact_name','')),'')); END IF;
        IF p_row?'contact_email' THEN v_normalized:=v_normalized||jsonb_build_object('contact_email',v_email); END IF;
        IF p_row?'contact_phone' THEN v_normalized:=v_normalized||jsonb_build_object('contact_phone',NULLIF(btrim(COALESCE(p_row->>'contact_phone','')),'')); END IF;
        IF p_row?'billing_email' THEN v_normalized:=v_normalized||jsonb_build_object('billing_email',v_billing_email); END IF;
        IF p_row?'notes' THEN v_normalized:=v_normalized||jsonb_build_object('notes',NULLIF(btrim(COALESCE(p_row->>'notes','')),'')); END IF;
        IF p_row?'is_active' AND v_active IS NOT NULL THEN v_normalized:=v_normalized||jsonb_build_object('is_active',v_active); END IF;
        IF p_entity_type='customers' THEN
            v_currency:=upper(btrim(COALESCE(p_row->>'preferred_currency','MXN')));
            IF v_currency NOT IN ('MXN','USD') THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_currency','La moneda debe ser MXN o USD.'));
            ELSIF p_row?'preferred_currency' OR v_existing_id IS NULL THEN v_normalized:=v_normalized||jsonb_build_object('preferred_currency',v_currency); END IF;
        END IF;

    ELSIF p_entity_type='operations' THEN
        IF v_external IS NULL THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('missing_external_key','external_key es obligatorio para operaciones.'));
        ELSIF char_length(v_external)>100 THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_external_key','external_key excede 100 caracteres.')); END IF;

        IF v_external IS NOT NULL THEN
            SELECT id,status,reference_code INTO v_existing_id,v_existing_status,v_existing_reference
            FROM public.operations WHERE tenant_id=p_tenant_id AND lower(external_key)=lower(v_external);
        END IF;

        v_customer:=private.f6_resolve_relation(p_tenant_id,'customer',p_row->>'customer_external_key',p_row->>'customer_tax_id',p_row->>'customer_name');
        IF v_customer?'error' THEN
            v_errors:=v_errors||jsonb_build_array(private.f6_issue(v_customer->>'error',CASE WHEN v_customer->>'error'='ambiguous_customer' THEN 'El cliente es ambiguo; usa customer_external_key.' ELSE 'No fue posible resolver el cliente dentro del tenant.' END));
        END IF;
        IF NULLIF(btrim(concat_ws('',p_row->>'provider_external_key',p_row->>'provider_tax_id',p_row->>'provider_name')),'') IS NOT NULL THEN
            v_provider:=private.f6_resolve_relation(p_tenant_id,'provider',p_row->>'provider_external_key',p_row->>'provider_tax_id',p_row->>'provider_name');
            IF v_provider?'error' THEN
                v_errors:=v_errors||jsonb_build_array(private.f6_issue(v_provider->>'error',CASE WHEN v_provider->>'error'='ambiguous_provider' THEN 'El proveedor es ambiguo; usa provider_external_key.' ELSE 'No fue posible resolver el proveedor dentro del tenant.' END));
            END IF;
        END IF;

        v_service:=NULLIF(btrim(COALESCE(p_row->>'service_type','')),'');
        v_scope:=lower(btrim(COALESCE(p_row->>'operation_scope','national')));
        v_execution:=lower(btrim(COALESCE(p_row->>'execution_type','third_party')));
        v_currency:=upper(btrim(COALESCE(p_row->>'pricing_currency','MXN')));
        v_origin_municipality:=NULLIF(btrim(COALESCE(p_row->>'origin_municipality','')),'');
        v_origin_state:=NULLIF(btrim(COALESCE(p_row->>'origin_state','')),'');
        v_origin_country:=upper(btrim(COALESCE(p_row->>'origin_country_code','MX')));
        v_destination_municipality:=NULLIF(btrim(COALESCE(p_row->>'destination_municipality','')),'');
        v_destination_state:=NULLIF(btrim(COALESCE(p_row->>'destination_state','')),'');
        v_destination_country:=upper(btrim(COALESCE(p_row->>'destination_country_code','MX')));
        v_cargo:=NULLIF(btrim(COALESCE(p_row->>'cargo_description','')),'');

        IF v_service IS NULL THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('missing_service_type','El servicio es obligatorio.')); END IF;
        IF v_scope NOT IN ('national','international') THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_operation_scope','El alcance debe ser national o international.')); END IF;
        IF v_execution<>'third_party' THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_execution_type','La importación sólo admite ejecución third_party.')); END IF;
        IF v_currency NOT IN ('MXN','USD') THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_currency','La moneda debe ser MXN o USD.')); END IF;
        IF v_origin_municipality IS NULL OR v_origin_state IS NULL OR v_destination_municipality IS NULL OR v_destination_state IS NULL
           OR v_origin_country NOT IN ('MX','US') OR v_destination_country NOT IN ('MX','US') THEN
            v_errors:=v_errors||jsonb_build_array(private.f6_issue('incomplete_places','Origen y destino requieren municipio, estado y país MX/US.'));
        END IF;
        IF v_scope='national' AND (v_origin_country<>'MX' OR v_destination_country<>'MX') THEN
            v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_national_country','Una operación nacional debe iniciar y terminar en México.'));
        END IF;
        IF v_cargo IS NULL THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('missing_cargo_summary','La descripción de carga es obligatoria.')); END IF;
        IF p_row?'status' AND lower(btrim(COALESCE(p_row->>'status',''))) NOT IN ('','draft','planned') THEN
            v_errors:=v_errors||jsonb_build_array(private.f6_issue('unsafe_status','No se permiten estados avanzados en importación.'));
        END IF;

        BEGIN v_start:=NULLIF(btrim(COALESCE(p_row->>'operational_window_start','')),'')::timestamptz;
        EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_start_date','La fecha inicial no es válida.')); END;
        BEGIN v_end:=NULLIF(btrim(COALESCE(p_row->>'operational_window_end','')),'')::timestamptz;
        EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_end_date','La fecha final no es válida.')); END;
        IF v_start IS NULL OR v_end IS NULL THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('missing_operational_window','La ventana operativa es obligatoria.'));
        ELSIF v_end<=v_start THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_operational_window','La fecha final debe ser posterior a la inicial.')); END IF;

        BEGIN
            v_provider_cost:=NULLIF(btrim(COALESCE(p_row->>'provider_cost_amount','')),'')::numeric;
            v_customer_sell:=NULLIF(btrim(COALESCE(p_row->>'customer_price_amount','')),'')::numeric;
            v_pieces:=NULLIF(btrim(COALESCE(p_row->>'cargo_pieces','')),'')::numeric;
            v_weight:=NULLIF(btrim(COALESCE(p_row->>'cargo_weight_kg','')),'')::numeric;
        EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
            v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_numeric','Los importes, piezas y peso deben ser numéricos.'));
        END;
        IF COALESCE(v_provider_cost,0)<0 OR COALESCE(v_customer_sell,0)<0 THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('negative_economics','Los importes no pueden ser negativos.')); END IF;
        IF COALESCE(v_pieces,0)<0 OR COALESCE(v_weight,0)<0 THEN v_errors:=v_errors||jsonb_build_array(private.f6_issue('invalid_cargo_amount','Piezas y peso no pueden ser negativos.')); END IF;

        v_reference:=NULLIF(btrim(COALESCE(p_row->>'reference_code','')),'');
        IF v_reference IS NULL AND v_external IS NOT NULL THEN
            v_reference:='IMP-'||left(upper(regexp_replace(v_external,'[^A-Za-z0-9]+','','g')),18)||'-'||upper(substr(md5(v_external),1,6));
        END IF;
        IF v_existing_id IS NULL AND v_reference IS NOT NULL AND EXISTS (SELECT 1 FROM public.operations WHERE tenant_id=p_tenant_id AND reference_code=v_reference) THEN
            v_errors:=v_errors||jsonb_build_array(private.f6_issue('reference_conflict','La referencia operativa ya existe.'));
        END IF;
        IF v_existing_id IS NOT NULL THEN
            IF p_mode='create_only' THEN v_action:='skip'; v_warnings:=v_warnings||jsonb_build_array(private.f6_issue('already_exists','La operación ya existe; create_only no la modifica.'));
            ELSIF v_existing_status NOT IN ('draft','planned') THEN v_action:='skip'; v_warnings:=v_warnings||jsonb_build_array(private.f6_issue('existing_operation_locked','La operación ya avanzó y no puede sobrescribirse por importación.'));
            ELSE v_action:='update'; END IF;
            v_reference:=v_existing_reference;
        END IF;

        v_normalized:=jsonb_build_object(
            'external_key',v_external,'reference_code',v_reference,'status','planned','service_type',v_service,
            'operation_scope',v_scope,'execution_type','third_party','pricing_currency',v_currency,
            'customer_id',v_customer->>'id','client_display_name',v_customer->>'display_name',
            'provider_id',CASE WHEN v_provider?'id' THEN v_provider->>'id' ELSE NULL END,
            'provider_name',CASE WHEN v_provider?'display_name' THEN v_provider->>'display_name' ELSE NULL END,
            'origin_place',jsonb_build_object('municipality',v_origin_municipality,'state',v_origin_state,'countryCode',v_origin_country,'label',concat_ws(', ',v_origin_municipality,v_origin_state)),
            'destination_place',jsonb_build_object('municipality',v_destination_municipality,'state',v_destination_state,'countryCode',v_destination_country,'label',concat_ws(', ',v_destination_municipality,v_destination_state)),
            'operational_window_start',v_start,'operational_window_end',v_end,
            'route_summary',concat_ws(' -> ',concat_ws(', ',v_origin_municipality,v_origin_state),concat_ws(', ',v_destination_municipality,v_destination_state)),
            'destination_city',v_destination_municipality,
            'cargo_summary',jsonb_strip_nulls(jsonb_build_object('description',v_cargo,'pieces',v_pieces,'unit',NULLIF(btrim(COALESCE(p_row->>'cargo_unit','')),''),'weightKg',v_weight,'measurements',NULLIF(btrim(COALESCE(p_row->>'cargo_measurements','')),'')))
        );
        IF p_row?'provider_cost_amount' THEN v_normalized:=v_normalized||jsonb_build_object('provider_cost_amount',v_provider_cost); END IF;
        IF p_row?'customer_price_amount' THEN v_normalized:=v_normalized||jsonb_build_object('customer_price_amount',v_customer_sell); END IF;
        IF p_row?'notes' THEN v_normalized:=v_normalized||jsonb_build_object('notes',NULLIF(btrim(COALESCE(p_row->>'notes','')),'')); END IF;
    ELSE
        RETURN jsonb_build_object('action','error','normalized','{}'::jsonb,'warnings','[]'::jsonb,
            'errors',jsonb_build_array(private.f6_issue('invalid_entity_type','El tipo de importación no está soportado.')));
    END IF;

    IF jsonb_array_length(v_errors)>0 THEN v_action:='error'; END IF;
    RETURN jsonb_build_object('external_key',v_external,'action',v_action,'normalized',jsonb_strip_nulls(v_normalized),
        'warnings',v_warnings,'errors',v_errors,'existing_entity_id',v_existing_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_validate_bulk_import(
    p_tenant_id uuid,p_entity_type text,p_mode text,p_rows jsonb
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,public
AS $function$
DECLARE v_results jsonb:='[]'::jsonb; v_row jsonb; v_result jsonb; v_ordinal bigint; v_row_number integer; v_duplicates integer;
    v_create integer; v_update integer; v_skip integer; v_error integer; v_warning integer;
BEGIN
    IF private.f6_current_role(p_tenant_id)<>'admin' THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF p_entity_type NOT IN ('customers','providers','operations') OR p_mode NOT IN ('create_only','upsert') THEN RETURN jsonb_build_object('error','invalid_contract'); END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows)<>'array' OR jsonb_array_length(p_rows)<1 OR jsonb_array_length(p_rows)>200 THEN
        RETURN jsonb_build_object('error','row_limit_exceeded','message','Cada solicitud debe contener entre 1 y 200 filas.');
    END IF;
    FOR v_row,v_ordinal IN SELECT value,ordinality FROM jsonb_array_elements(p_rows) WITH ORDINALITY LOOP
        v_row_number:=COALESCE(NULLIF(v_row->>'row_number','')::integer,v_ordinal::integer);
        v_result:=private.f6_validate_row(p_tenant_id,p_entity_type,p_mode,v_row);
        IF NULLIF(btrim(COALESCE(v_row->>'external_key','')),'') IS NOT NULL THEN
            SELECT count(*) INTO v_duplicates FROM jsonb_array_elements(p_rows) x
            WHERE lower(btrim(COALESCE(x->>'external_key','')))=lower(btrim(v_row->>'external_key'));
            IF v_duplicates>1 THEN
                v_result:=jsonb_set(v_result,'{errors}',COALESCE(v_result->'errors','[]'::jsonb)||jsonb_build_array(private.f6_issue('duplicate_external_key_in_file','external_key está repetido dentro del archivo.')));
                v_result:=jsonb_set(v_result,'{action}','"error"'::jsonb);
            END IF;
        END IF;
        v_results:=v_results||jsonb_build_array(v_result||jsonb_build_object('row_number',v_row_number));
    END LOOP;
    SELECT count(*) FILTER(WHERE x->>'action'='create'),count(*) FILTER(WHERE x->>'action'='update'),
           count(*) FILTER(WHERE x->>'action'='skip'),count(*) FILTER(WHERE x->>'action'='error'),
           count(*) FILTER(WHERE jsonb_array_length(COALESCE(x->'warnings','[]'::jsonb))>0)
    INTO v_create,v_update,v_skip,v_error,v_warning FROM jsonb_array_elements(v_results) x;
    RETURN jsonb_build_object('results',v_results,'summary',jsonb_build_object(
        'total',jsonb_array_length(v_results),'create',v_create,'update',v_update,'skip',v_skip,'errors',v_error,'warnings',v_warning));
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_start_bulk_import(
    p_tenant_id uuid,p_entity_type text,p_filename text,p_mode text,p_idempotency_key text,
    p_total_rows integer,p_validation_summary jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,public
AS $function$
DECLARE v_id uuid; v_existing boolean:=false; v_summary jsonb;
BEGIN
    IF private.f6_current_role(p_tenant_id)<>'admin' OR (SELECT auth.uid()) IS NULL THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF p_entity_type NOT IN ('customers','providers','operations') OR p_mode NOT IN ('create_only','upsert')
       OR NULLIF(btrim(COALESCE(p_filename,'')),'') IS NULL OR char_length(btrim(p_filename))>255
       OR NULLIF(btrim(COALESCE(p_idempotency_key,'')),'') IS NULL OR char_length(p_idempotency_key) NOT BETWEEN 16 AND 200
       OR p_total_rows NOT BETWEEN 1 AND 1000 OR jsonb_typeof(COALESCE(p_validation_summary,'{}'::jsonb))<>'object' THEN
        RETURN jsonb_build_object('error','invalid_payload');
    END IF;
    v_summary:=jsonb_build_object(
        'total',p_total_rows,'create',COALESCE((p_validation_summary->>'create')::integer,0),
        'update',COALESCE((p_validation_summary->>'update')::integer,0),'skip',COALESCE((p_validation_summary->>'skip')::integer,0),
        'warnings',COALESCE((p_validation_summary->>'warnings')::integer,0),'errors',COALESCE((p_validation_summary->>'errors')::integer,0));
    INSERT INTO public.data_import_batches(tenant_id,user_id,entity_type,filename,mode,idempotency_key,total_rows,valid_rows,error_rows,summary)
    VALUES(p_tenant_id,(SELECT auth.uid()),p_entity_type,btrim(p_filename),p_mode,btrim(p_idempotency_key),p_total_rows,
        p_total_rows-COALESCE((p_validation_summary->>'errors')::integer,0),COALESCE((p_validation_summary->>'errors')::integer,0),v_summary)
    ON CONFLICT(tenant_id,user_id,idempotency_key) DO NOTHING RETURNING id INTO v_id;
    IF v_id IS NULL THEN
        SELECT id INTO v_id FROM public.data_import_batches
        WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid()) AND idempotency_key=btrim(p_idempotency_key);
        v_existing:=true;
    ELSE
        PERFORM public.rpc_write_audit(p_tenant_id,'data_import_validated','data_import_batch',v_id,
            jsonb_build_object('entity_type',p_entity_type,'mode',p_mode,'total_rows',p_total_rows,
                'valid_rows',p_total_rows-COALESCE((p_validation_summary->>'errors')::integer,0),'error_rows',COALESCE((p_validation_summary->>'errors')::integer,0)));
    END IF;
    RETURN (SELECT jsonb_build_object('id',b.id,'status',b.status,'entity_type',b.entity_type,'mode',b.mode,
        'total_rows',b.total_rows,'summary',b.summary,'duplicate_batch',v_existing) FROM public.data_import_batches b WHERE b.id=v_id);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR check_violation THEN
    RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_import_batches(p_tenant_id uuid,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,public
AS $function$
DECLARE v_limit integer:=LEAST(GREATEST(COALESCE(p_limit,50),1),100);
BEGIN
    IF private.f6_current_role(p_tenant_id)<>'admin' THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN jsonb_build_object('items',COALESCE((SELECT jsonb_agg(to_jsonb(b) ORDER BY b.started_at DESC)
        FROM (SELECT id,entity_type,filename,mode,total_rows,valid_rows,applied_rows,updated_rows,skipped_rows,error_rows,status,started_at,completed_at,summary
              FROM public.data_import_batches WHERE tenant_id=p_tenant_id ORDER BY started_at DESC LIMIT v_limit) b),'[]'::jsonb));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_apply_bulk_import(
    p_tenant_id uuid,p_batch_id uuid,p_chunk_key text,p_rows jsonb,p_is_last boolean DEFAULT false
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,public
AS $function$
DECLARE
    v_batch public.data_import_batches%ROWTYPE; v_existing jsonb; v_validation jsonb; v_item jsonb; v_norm jsonb;
    v_result_items jsonb:='[]'::jsonb; v_outcome jsonb; v_entity_id uuid;
    v_created integer:=0; v_updated integer:=0; v_skipped integer:=0; v_errors integer:=0;
    v_total_created integer; v_total_updated integer; v_total_skipped integer; v_total_errors integer;
    v_result jsonb; v_status text;
BEGIN
    IF private.f6_current_role(p_tenant_id)<>'admin' OR (SELECT auth.uid()) IS NULL THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF NULLIF(btrim(COALESCE(p_chunk_key,'')),'') IS NULL OR char_length(btrim(p_chunk_key))>120
       OR p_rows IS NULL OR jsonb_typeof(p_rows)<>'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 200 THEN
        RETURN jsonb_build_object('error','invalid_payload');
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(p_batch_id::text||':'||btrim(p_chunk_key),0));
    SELECT result INTO v_existing FROM public.data_import_chunks
    WHERE batch_id=p_batch_id AND chunk_key=btrim(p_chunk_key) AND tenant_id=p_tenant_id;
    IF v_existing IS NOT NULL THEN RETURN v_existing||jsonb_build_object('duplicate_response',true); END IF;

    SELECT * INTO v_batch FROM public.data_import_batches
    WHERE id=p_batch_id AND tenant_id=p_tenant_id AND user_id=(SELECT auth.uid()) FOR UPDATE;
    IF v_batch.id IS NULL THEN RETURN jsonb_build_object('error','batch_not_found'); END IF;
    IF v_batch.status<>'processing' THEN RETURN jsonb_build_object('error','batch_closed'); END IF;

    v_validation:=public.rpc_validate_bulk_import(p_tenant_id,v_batch.entity_type,v_batch.mode,p_rows);
    IF v_validation?'error' THEN RETURN v_validation; END IF;
    FOR v_item IN SELECT value FROM jsonb_array_elements(v_validation->'results') LOOP
        v_outcome:=v_item; v_entity_id:=NULL; v_norm:=v_item->'normalized';
        IF v_item->>'action'='create' THEN
            BEGIN
                IF v_batch.entity_type='customers' THEN
                    INSERT INTO public.customers(tenant_id,external_key,display_name,legal_name,contact_name,contact_email,contact_phone,tax_id,billing_email,notes,is_active,preferred_currency)
                    VALUES(p_tenant_id,v_norm->>'external_key',v_norm->>'display_name',v_norm->>'legal_name',v_norm->>'contact_name',v_norm->>'contact_email',v_norm->>'contact_phone',v_norm->>'tax_id',v_norm->>'billing_email',v_norm->>'notes',COALESCE((v_norm->>'is_active')::boolean,true),COALESCE(v_norm->>'preferred_currency','MXN')) RETURNING id INTO v_entity_id;
                ELSIF v_batch.entity_type='providers' THEN
                    INSERT INTO public.logistics_providers(tenant_id,external_key,display_name,legal_name,tax_id,contact_name,contact_email,contact_phone,billing_email,notes,is_active)
                    VALUES(p_tenant_id,v_norm->>'external_key',v_norm->>'display_name',v_norm->>'legal_name',v_norm->>'tax_id',v_norm->>'contact_name',v_norm->>'contact_email',v_norm->>'contact_phone',v_norm->>'billing_email',v_norm->>'notes',COALESCE((v_norm->>'is_active')::boolean,true)) RETURNING id INTO v_entity_id;
                ELSE
                    INSERT INTO public.operations(tenant_id,external_key,reference_code,status,customer_id,client_display_name,provider_id,provider_name,
                        service_type,operation_scope,execution_type,origin_place,destination_place,operational_window_start,operational_window_end,
                        route_summary,destination_city,cargo_summary,pricing_currency,provider_cost_amount,customer_price_amount,notes)
                    VALUES(p_tenant_id,v_norm->>'external_key',v_norm->>'reference_code','planned',(v_norm->>'customer_id')::uuid,v_norm->>'client_display_name',
                        NULLIF(v_norm->>'provider_id','')::uuid,v_norm->>'provider_name',v_norm->>'service_type',v_norm->>'operation_scope','third_party',
                        v_norm->'origin_place',v_norm->'destination_place',(v_norm->>'operational_window_start')::timestamptz,(v_norm->>'operational_window_end')::timestamptz,
                        v_norm->>'route_summary',v_norm->>'destination_city',v_norm->'cargo_summary',v_norm->>'pricing_currency',
                        NULLIF(v_norm->>'provider_cost_amount','')::numeric,NULLIF(v_norm->>'customer_price_amount','')::numeric,v_norm->>'notes') RETURNING id INTO v_entity_id;
                END IF;
                v_created:=v_created+1; v_outcome:=v_outcome||jsonb_build_object('status','applied','applied_entity_id',v_entity_id);
            EXCEPTION WHEN unique_violation OR check_violation OR not_null_violation OR invalid_text_representation OR numeric_value_out_of_range THEN
                v_errors:=v_errors+1; v_outcome:=jsonb_set(v_outcome,'{action}','"error"'::jsonb);
                v_outcome:=jsonb_set(v_outcome,'{errors}',COALESCE(v_outcome->'errors','[]'::jsonb)||jsonb_build_array(private.f6_issue('apply_conflict','La fila cambió o entra en conflicto con datos existentes.')))||jsonb_build_object('status','error');
            END;
        ELSIF v_item->>'action'='update' THEN
            BEGIN
                v_entity_id:=(v_item->>'existing_entity_id')::uuid;
                IF v_batch.entity_type='customers' THEN
                    UPDATE public.customers SET
                        external_key=CASE WHEN v_norm?'external_key' THEN v_norm->>'external_key' ELSE external_key END,
                        display_name=v_norm->>'display_name',legal_name=CASE WHEN v_norm?'legal_name' THEN v_norm->>'legal_name' ELSE legal_name END,
                        contact_name=CASE WHEN v_norm?'contact_name' THEN v_norm->>'contact_name' ELSE contact_name END,
                        contact_email=CASE WHEN v_norm?'contact_email' THEN v_norm->>'contact_email' ELSE contact_email END,
                        contact_phone=CASE WHEN v_norm?'contact_phone' THEN v_norm->>'contact_phone' ELSE contact_phone END,
                        tax_id=CASE WHEN v_norm?'tax_id' THEN v_norm->>'tax_id' ELSE tax_id END,
                        billing_email=CASE WHEN v_norm?'billing_email' THEN v_norm->>'billing_email' ELSE billing_email END,
                        notes=CASE WHEN v_norm?'notes' THEN v_norm->>'notes' ELSE notes END,
                        is_active=CASE WHEN v_norm?'is_active' THEN (v_norm->>'is_active')::boolean ELSE is_active END,
                        preferred_currency=CASE WHEN v_norm?'preferred_currency' THEN v_norm->>'preferred_currency' ELSE preferred_currency END,
                        updated_at=now() WHERE id=v_entity_id AND tenant_id=p_tenant_id;
                ELSIF v_batch.entity_type='providers' THEN
                    UPDATE public.logistics_providers SET
                        external_key=CASE WHEN v_norm?'external_key' THEN v_norm->>'external_key' ELSE external_key END,
                        display_name=v_norm->>'display_name',legal_name=CASE WHEN v_norm?'legal_name' THEN v_norm->>'legal_name' ELSE legal_name END,
                        tax_id=CASE WHEN v_norm?'tax_id' THEN v_norm->>'tax_id' ELSE tax_id END,
                        contact_name=CASE WHEN v_norm?'contact_name' THEN v_norm->>'contact_name' ELSE contact_name END,
                        contact_email=CASE WHEN v_norm?'contact_email' THEN v_norm->>'contact_email' ELSE contact_email END,
                        contact_phone=CASE WHEN v_norm?'contact_phone' THEN v_norm->>'contact_phone' ELSE contact_phone END,
                        billing_email=CASE WHEN v_norm?'billing_email' THEN v_norm->>'billing_email' ELSE billing_email END,
                        notes=CASE WHEN v_norm?'notes' THEN v_norm->>'notes' ELSE notes END,
                        is_active=CASE WHEN v_norm?'is_active' THEN (v_norm->>'is_active')::boolean ELSE is_active END,
                        updated_at=now() WHERE id=v_entity_id AND tenant_id=p_tenant_id;
                ELSE
                    UPDATE public.operations SET customer_id=(v_norm->>'customer_id')::uuid,client_display_name=v_norm->>'client_display_name',
                        provider_id=NULLIF(v_norm->>'provider_id','')::uuid,provider_name=v_norm->>'provider_name',service_type=v_norm->>'service_type',
                        operation_scope=v_norm->>'operation_scope',execution_type='third_party',origin_place=v_norm->'origin_place',destination_place=v_norm->'destination_place',
                        operational_window_start=(v_norm->>'operational_window_start')::timestamptz,operational_window_end=(v_norm->>'operational_window_end')::timestamptz,
                        route_summary=v_norm->>'route_summary',destination_city=v_norm->>'destination_city',cargo_summary=v_norm->'cargo_summary',pricing_currency=v_norm->>'pricing_currency',
                        provider_cost_amount=CASE WHEN v_norm?'provider_cost_amount' THEN NULLIF(v_norm->>'provider_cost_amount','')::numeric ELSE provider_cost_amount END,
                        customer_price_amount=CASE WHEN v_norm?'customer_price_amount' THEN NULLIF(v_norm->>'customer_price_amount','')::numeric ELSE customer_price_amount END,
                        notes=CASE WHEN v_norm?'notes' THEN v_norm->>'notes' ELSE notes END,updated_at=now()
                    WHERE id=v_entity_id AND tenant_id=p_tenant_id AND status IN ('draft','planned');
                    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514'; END IF;
                END IF;
                IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514'; END IF;
                v_updated:=v_updated+1; v_outcome:=v_outcome||jsonb_build_object('status','updated','applied_entity_id',v_entity_id);
            EXCEPTION WHEN unique_violation OR check_violation OR not_null_violation OR invalid_text_representation OR numeric_value_out_of_range THEN
                v_errors:=v_errors+1; v_outcome:=jsonb_set(v_outcome,'{action}','"error"'::jsonb);
                v_outcome:=jsonb_set(v_outcome,'{errors}',COALESCE(v_outcome->'errors','[]'::jsonb)||jsonb_build_array(private.f6_issue('apply_conflict','La fila cambió o entra en conflicto con datos existentes.')))||jsonb_build_object('status','error');
            END;
        ELSIF v_item->>'action'='skip' THEN v_skipped:=v_skipped+1; v_outcome:=v_outcome||jsonb_build_object('status','skipped');
        ELSE v_errors:=v_errors+1; v_outcome:=v_outcome||jsonb_build_object('status','error'); END IF;
        -- Keep the durable idempotency response useful without retaining imported
        -- contact, route, cargo, price, or note payloads after the transaction.
        v_result_items:=v_result_items||jsonb_build_array(v_outcome-'normalized');
    END LOOP;

    v_result:=jsonb_build_object('batch_id',p_batch_id,'chunk_key',btrim(p_chunk_key),'duplicate_response',false,'items',v_result_items,
        'summary',jsonb_build_object('total',jsonb_array_length(p_rows),'created',v_created,'updated',v_updated,'skipped',v_skipped,'errors',v_errors));
    INSERT INTO public.data_import_chunks(tenant_id,batch_id,chunk_key,row_count,result)
    VALUES(p_tenant_id,p_batch_id,btrim(p_chunk_key),jsonb_array_length(p_rows),v_result);

    SELECT COALESCE(sum((c.result#>>'{summary,created}')::integer),0),COALESCE(sum((c.result#>>'{summary,updated}')::integer),0),
           COALESCE(sum((c.result#>>'{summary,skipped}')::integer),0),COALESCE(sum((c.result#>>'{summary,errors}')::integer),0)
    INTO v_total_created,v_total_updated,v_total_skipped,v_total_errors FROM public.data_import_chunks c WHERE c.batch_id=p_batch_id;
    v_status:=CASE WHEN COALESCE(p_is_last,false) THEN CASE WHEN v_total_errors>0 THEN 'completed_with_errors' ELSE 'completed' END ELSE 'processing' END;
    UPDATE public.data_import_batches SET applied_rows=v_total_created,updated_rows=v_total_updated,skipped_rows=v_total_skipped,error_rows=v_total_errors,
        valid_rows=GREATEST(total_rows-v_total_errors,0),status=v_status,completed_at=CASE WHEN COALESCE(p_is_last,false) THEN now() ELSE NULL END,
        summary=jsonb_build_object('total',total_rows,'created',v_total_created,'updated',v_total_updated,'skipped',v_total_skipped,'errors',v_total_errors)
    WHERE id=p_batch_id;
    IF COALESCE(p_is_last,false) THEN
        PERFORM public.rpc_write_audit(p_tenant_id,'data_import_applied','data_import_batch',p_batch_id,
            jsonb_build_object('entity_type',v_batch.entity_type,'mode',v_batch.mode,'created',v_total_created,'updated',v_total_updated,'skipped',v_total_skipped,'errors',v_total_errors));
    END IF;
    RETURN v_result||jsonb_build_object('batch_status',v_status);
END;
$function$;

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
            FROM public.finance_invoices i LEFT JOIN public.operations o ON o.id=i.operation_id
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

CREATE OR REPLACE FUNCTION public.rpc_list_import_mappings(p_tenant_id uuid,p_entity_type text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
BEGIN
    IF private.f6_current_role(p_tenant_id)<>'admin' THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF p_entity_type NOT IN ('customers','providers','operations') THEN RETURN jsonb_build_object('error','invalid_entity_type'); END IF;
    RETURN jsonb_build_object('items',COALESCE((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.updated_at DESC)
        FROM (SELECT id,entity_type,name,mapping,created_at,updated_at FROM public.data_import_mappings
              WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid()) AND entity_type=p_entity_type) m),'[]'::jsonb));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_save_import_mapping(p_tenant_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE v_id uuid; v_entity text:=lower(btrim(COALESCE(p_payload->>'entity_type',''))); v_name text:=btrim(COALESCE(p_payload->>'name','')); v_mapping jsonb:=p_payload->'mapping';
BEGIN
    IF private.f6_current_role(p_tenant_id)<>'admin' THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    BEGIN v_id:=NULLIF(p_payload->>'id','')::uuid; EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_id'); END;
    IF v_entity NOT IN ('customers','providers','operations') OR char_length(v_name) NOT BETWEEN 1 AND 80 OR jsonb_typeof(v_mapping)<>'object' THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
    IF v_id IS NULL THEN
        INSERT INTO public.data_import_mappings(tenant_id,user_id,entity_type,name,mapping)
        VALUES(p_tenant_id,(SELECT auth.uid()),v_entity,v_name,v_mapping) RETURNING id INTO v_id;
    ELSE
        UPDATE public.data_import_mappings SET name=v_name,mapping=v_mapping,updated_at=now()
        WHERE id=v_id AND tenant_id=p_tenant_id AND user_id=(SELECT auth.uid()) AND entity_type=v_entity;
        IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
    END IF;
    RETURN (SELECT to_jsonb(m) FROM (SELECT id,entity_type,name,mapping,created_at,updated_at FROM public.data_import_mappings WHERE id=v_id) m);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('error','mapping_name_conflict');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_delete_import_mapping(p_tenant_id uuid,p_mapping_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
BEGIN
    IF private.f6_current_role(p_tenant_id)<>'admin' THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    DELETE FROM public.data_import_mappings WHERE id=p_mapping_id AND tenant_id=p_tenant_id AND user_id=(SELECT auth.uid());
    IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
    RETURN jsonb_build_object('success',true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_bulk_update_operations(p_tenant_id uuid,p_operation_ids uuid[],p_action text,p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE v_count integer; v_priority text; v_note text; v_distinct integer;
BEGIN
    IF private.f6_current_role(p_tenant_id)<>'admin' THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    v_distinct:=(SELECT count(DISTINCT x) FROM unnest(p_operation_ids) x);
    IF p_operation_ids IS NULL OR v_distinct NOT BETWEEN 1 AND 100 OR v_distinct<>cardinality(p_operation_ids)
       OR p_action NOT IN ('set_priority','add_note') OR jsonb_typeof(COALESCE(p_payload,'{}'::jsonb))<>'object' THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
    SELECT count(*) INTO v_count FROM public.operations WHERE tenant_id=p_tenant_id AND id=ANY(p_operation_ids);
    IF v_count<>v_distinct THEN RETURN jsonb_build_object('error','cross_tenant_or_missing'); END IF;
    IF p_action='set_priority' THEN
        v_priority:=lower(btrim(COALESCE(p_payload->>'priority','')));
        IF v_priority NOT IN ('low','normal','high') THEN RETURN jsonb_build_object('error','invalid_priority'); END IF;
        UPDATE public.operations SET priority=v_priority,updated_at=now() WHERE tenant_id=p_tenant_id AND id=ANY(p_operation_ids);
    ELSE
        v_note:=btrim(COALESCE(p_payload->>'note',''));
        IF char_length(v_note) NOT BETWEEN 1 AND 240 THEN RETURN jsonb_build_object('error','invalid_note'); END IF;
        UPDATE public.operations SET notes=concat_ws(E'\n',NULLIF(notes,''),'[Acción masiva] '||v_note),updated_at=now()
        WHERE tenant_id=p_tenant_id AND id=ANY(p_operation_ids);
    END IF;
    GET DIAGNOSTICS v_count=ROW_COUNT;
    PERFORM public.rpc_write_audit(p_tenant_id,'data_bulk_action','operations',NULL,jsonb_build_object('action',p_action,'count',v_count));
    RETURN jsonb_build_object('success',true,'updated',v_count,'action',p_action);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_record_data_action(p_tenant_id uuid,p_action text,p_entity_type text,p_count integer,p_detail text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE v_role text:=private.f6_current_role(p_tenant_id);
BEGIN
    IF v_role NOT IN ('admin','finance') OR p_action NOT IN ('export_requested','bulk_action') OR p_count NOT BETWEEN 1 AND 5000
       OR p_entity_type NOT IN ('customers','providers','quotes','operations','documents','finance_ar','finance_ap')
       OR char_length(COALESCE(p_detail,''))>80 THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF v_role='finance' AND p_entity_type NOT IN ('operations','documents','finance_ar','finance_ap') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    PERFORM public.rpc_write_audit(p_tenant_id,'data_'||p_action,'data_operation',NULL,
        jsonb_build_object('entity_type',p_entity_type,'count',p_count,'detail',NULLIF(btrim(COALESCE(p_detail,'')),'')));
    RETURN jsonb_build_object('success',true);
END;
$function$;

REVOKE EXECUTE ON FUNCTION private.f6_current_role(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION private.f6_issue(text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION private.f6_resolve_relation(uuid,text,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION private.f6_validate_row(uuid,text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;

REVOKE EXECUTE ON FUNCTION public.rpc_validate_bulk_import(uuid,text,text,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_start_bulk_import(uuid,text,text,text,text,integer,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_import_batches(uuid,integer) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_apply_bulk_import(uuid,uuid,text,jsonb,boolean) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_export_data_page(uuid,text,jsonb,jsonb,integer) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_import_mappings(uuid,text) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_save_import_mapping(uuid,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_delete_import_mapping(uuid,uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_bulk_update_operations(uuid,uuid[],text,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_record_data_action(uuid,text,text,integer,text) FROM PUBLIC,anon,service_role;

GRANT EXECUTE ON FUNCTION public.rpc_validate_bulk_import(uuid,text,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_start_bulk_import(uuid,text,text,text,text,integer,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_import_batches(uuid,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_apply_bulk_import(uuid,uuid,text,jsonb,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_export_data_page(uuid,text,jsonb,jsonb,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_import_mappings(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_save_import_mapping(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_delete_import_mapping(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_bulk_update_operations(uuid,uuid[],text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_data_action(uuid,text,text,integer,text) TO authenticated;
