-- FISCAL.0 — provider-neutral fiscal readiness
-- Forward-only. No PAC endpoint, credential, certificate, webhook or provider payload
-- is defined here. billing_cfdis remains the canonical fiscal aggregate while
-- Finance remains the accounting truth.

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;

ALTER TABLE public.billing_cfdis
    ADD COLUMN IF NOT EXISTS fiscal_status text NOT NULL DEFAULT 'draft',
    ADD COLUMN IF NOT EXISTS fiscal_provider text,
    ADD COLUMN IF NOT EXISTS provider_document_id text,
    ADD COLUMN IF NOT EXISTS fiscal_requested_at timestamptz,
    ADD COLUMN IF NOT EXISTS fiscal_stamped_at timestamptz,
    ADD COLUMN IF NOT EXISTS fiscal_cancelled_at timestamptz,
    ADD COLUMN IF NOT EXISTS fiscal_last_checked_at timestamptz,
    ADD COLUMN IF NOT EXISTS fiscal_error_code text,
    ADD COLUMN IF NOT EXISTS fiscal_error_message_safe text,
    ADD COLUMN IF NOT EXISTS xml_document_file_id uuid REFERENCES public.document_files(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS pdf_document_file_id uuid REFERENCES public.document_files(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS request_fingerprint text,
    ADD COLUMN IF NOT EXISTS provider_version text,
    ADD COLUMN IF NOT EXISTS cfdi_version text NOT NULL DEFAULT '4.0',
    ADD COLUMN IF NOT EXISTS fiscal_input jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS fiscal_snapshot jsonb,
    ADD COLUMN IF NOT EXISTS fiscal_snapshot_created_at timestamptz;

ALTER TABLE public.billing_cfdis DROP CONSTRAINT IF EXISTS billing_cfdis_fiscal_status_check;
ALTER TABLE public.billing_cfdis ADD CONSTRAINT billing_cfdis_fiscal_status_check CHECK (fiscal_status IN (
    'draft','ready_for_api','queued','submitting','processing','stamped','rejected','api_error',
    'cancellation_requested','cancelled','cancellation_rejected'
));
ALTER TABLE public.billing_cfdis DROP CONSTRAINT IF EXISTS billing_cfdis_cfdi_version_check;
ALTER TABLE public.billing_cfdis ADD CONSTRAINT billing_cfdis_cfdi_version_check
    CHECK (cfdi_version ~ '^[0-9]+\.[0-9]+$');
ALTER TABLE public.billing_cfdis DROP CONSTRAINT IF EXISTS billing_cfdis_fiscal_input_object_check;
ALTER TABLE public.billing_cfdis ADD CONSTRAINT billing_cfdis_fiscal_input_object_check
    CHECK (jsonb_typeof(fiscal_input) = 'object');
ALTER TABLE public.billing_cfdis DROP CONSTRAINT IF EXISTS billing_cfdis_fiscal_snapshot_object_check;
ALTER TABLE public.billing_cfdis ADD CONSTRAINT billing_cfdis_fiscal_snapshot_object_check
    CHECK (fiscal_snapshot IS NULL OR jsonb_typeof(fiscal_snapshot) = 'object');
ALTER TABLE public.billing_cfdis DROP CONSTRAINT IF EXISTS billing_cfdis_request_fingerprint_check;
ALTER TABLE public.billing_cfdis ADD CONSTRAINT billing_cfdis_request_fingerprint_check
    CHECK (request_fingerprint IS NULL OR request_fingerprint ~ '^[0-9a-f]{64}$');

CREATE UNIQUE INDEX IF NOT EXISTS billing_cfdis_tenant_provider_document_uidx
    ON public.billing_cfdis (tenant_id, fiscal_provider, provider_document_id)
    WHERE fiscal_provider IS NOT NULL AND provider_document_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_cfdis_tenant_fiscal_status_idx
    ON public.billing_cfdis (tenant_id, fiscal_status, updated_at DESC);

CREATE TABLE public.fiscal_provider_configs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL UNIQUE REFERENCES public.tenants(id) ON DELETE CASCADE,
    provider_code text,
    enabled boolean NOT NULL DEFAULT false,
    environment text NOT NULL DEFAULT 'sandbox',
    capabilities jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid,
    updated_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fiscal_provider_configs_environment_check CHECK (environment IN ('sandbox','production')),
    CONSTRAINT fiscal_provider_configs_provider_check CHECK (
        provider_code IS NULL OR (provider_code ~ '^[a-z][a-z0-9_]{1,62}$' AND provider_code <> 'mock')
    ),
    CONSTRAINT fiscal_provider_configs_capabilities_object_check CHECK (jsonb_typeof(capabilities) = 'object'),
    CONSTRAINT fiscal_provider_configs_no_secret_keys_check CHECK (
        NOT (capabilities ?| ARRAY['secret','password','token','api_key','authorization','certificate','private_key'])
    ),
    CONSTRAINT fiscal_provider_configs_enabled_provider_check CHECK (NOT enabled OR provider_code IS NOT NULL)
);
ALTER TABLE public.fiscal_provider_configs DROP CONSTRAINT fiscal_provider_configs_no_secret_keys_check;
ALTER TABLE public.fiscal_provider_configs ADD CONSTRAINT fiscal_provider_configs_no_secret_keys_check CHECK (
    capabilities::text !~* '"(secret|password|token|api_key|authorization|certificate|private_key)"\s*:'
);

CREATE TABLE public.fiscal_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    billing_cfdi_id uuid NOT NULL REFERENCES public.billing_cfdis(id) ON DELETE CASCADE,
    request_type text NOT NULL,
    status text NOT NULL DEFAULT 'queued',
    idempotency_key text NOT NULL,
    payload_snapshot jsonb NOT NULL,
    attempt_count integer NOT NULL DEFAULT 0,
    max_attempts integer NOT NULL DEFAULT 3,
    next_attempt_at timestamptz,
    locked_at timestamptz,
    completed_at timestamptz,
    requested_by uuid,
    safe_error_code text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fiscal_requests_type_check CHECK (request_type IN ('stamp','status','cancel','fetch_xml','fetch_pdf')),
    CONSTRAINT fiscal_requests_status_check CHECK (status IN (
        'queued','submitting','processing','completed','technical_error','business_rejected','cancelled'
    )),
    CONSTRAINT fiscal_requests_idempotency_check CHECK (idempotency_key ~ '^[0-9a-f]{64}$'),
    CONSTRAINT fiscal_requests_snapshot_object_check CHECK (jsonb_typeof(payload_snapshot) = 'object'),
    CONSTRAINT fiscal_requests_attempts_check CHECK (attempt_count >= 0 AND max_attempts BETWEEN 1 AND 5)
);
CREATE UNIQUE INDEX fiscal_requests_identity_uidx
    ON public.fiscal_requests (tenant_id, billing_cfdi_id, request_type, idempotency_key);
CREATE UNIQUE INDEX fiscal_requests_one_active_type_uidx
    ON public.fiscal_requests (tenant_id, billing_cfdi_id, request_type)
    WHERE status IN ('queued','submitting','processing');
CREATE INDEX fiscal_requests_queue_idx
    ON public.fiscal_requests (status, next_attempt_at, created_at)
    WHERE status IN ('queued','technical_error');

CREATE TABLE public.fiscal_provider_attempts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    request_id uuid NOT NULL REFERENCES public.fiscal_requests(id) ON DELETE CASCADE,
    attempt_no integer NOT NULL CHECK (attempt_no > 0),
    started_at timestamptz NOT NULL,
    completed_at timestamptz,
    http_status integer CHECK (http_status IS NULL OR http_status BETWEEN 100 AND 599),
    provider_code text,
    normalized_result jsonb NOT NULL DEFAULT '{}'::jsonb,
    safe_error_code text,
    duration_ms integer CHECK (duration_ms IS NULL OR duration_ms >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fiscal_provider_attempts_result_object_check CHECK (jsonb_typeof(normalized_result) = 'object'),
    CONSTRAINT fiscal_provider_attempts_request_attempt_key UNIQUE (request_id, attempt_no)
);
CREATE INDEX fiscal_provider_attempts_tenant_request_idx
    ON public.fiscal_provider_attempts (tenant_id, request_id, attempt_no DESC);

COMMENT ON TABLE public.fiscal_provider_configs IS 'Non-secret provider selection only. Credentials and certificates belong to server runtime secrets.';
COMMENT ON COLUMN public.fiscal_requests.payload_snapshot IS 'Immutable provider-neutral fiscal input; never an external provider payload.';
COMMENT ON COLUMN public.fiscal_provider_attempts.normalized_result IS 'Redacted canonical metadata only; no headers, credentials, certificates, XML or raw provider bodies.';

CREATE OR REPLACE FUNCTION private.fiscal0_status_transition_allowed(p_from text, p_to text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO pg_catalog
AS $function$
    SELECT p_from = p_to OR CASE p_from
        WHEN 'draft' THEN p_to IN ('ready_for_api')
        WHEN 'ready_for_api' THEN p_to IN ('draft','queued')
        WHEN 'queued' THEN p_to IN ('submitting','api_error')
        WHEN 'submitting' THEN p_to IN ('processing','stamped','rejected','api_error')
        WHEN 'processing' THEN p_to IN ('stamped','rejected','api_error')
        WHEN 'api_error' THEN p_to IN ('draft','queued','processing','stamped')
        WHEN 'rejected' THEN p_to IN ('draft')
        WHEN 'stamped' THEN p_to IN ('cancellation_requested')
        WHEN 'cancellation_requested' THEN p_to IN ('cancelled','cancellation_rejected','stamped')
        WHEN 'cancellation_rejected' THEN p_to IN ('cancellation_requested','stamped')
        ELSE false
    END;
$function$;

CREATE OR REPLACE FUNCTION private.fiscal0_guard_cfdi()
RETURNS trigger LANGUAGE plpgsql SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT private.fiscal0_status_transition_allowed(OLD.fiscal_status, NEW.fiscal_status) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'invalid_fiscal_transition';
    END IF;
    IF OLD.fiscal_snapshot IS NOT NULL AND NEW.fiscal_snapshot IS DISTINCT FROM OLD.fiscal_snapshot
       AND NOT (NEW.fiscal_status = 'draft' AND OLD.fiscal_status IN ('api_error','rejected')) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'fiscal_snapshot_immutable';
    END IF;
    IF OLD.fiscal_status = 'stamped' AND NEW.uuid IS DISTINCT FROM OLD.uuid THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'stamped_uuid_immutable';
    END IF;
    IF OLD.xml_document_file_id IS NOT NULL AND NEW.xml_document_file_id IS DISTINCT FROM OLD.xml_document_file_id THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'stamped_xml_immutable';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS fiscal0_guard_cfdi ON public.billing_cfdis;
CREATE TRIGGER fiscal0_guard_cfdi BEFORE UPDATE ON public.billing_cfdis
    FOR EACH ROW EXECUTE FUNCTION private.fiscal0_guard_cfdi();

CREATE OR REPLACE FUNCTION private.fiscal0_attempts_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path TO pg_catalog
AS $function$
BEGIN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'fiscal_attempts_immutable';
END;
$function$;
DROP TRIGGER IF EXISTS fiscal0_attempts_immutable ON public.fiscal_provider_attempts;
CREATE TRIGGER fiscal0_attempts_immutable BEFORE UPDATE OR DELETE ON public.fiscal_provider_attempts
    FOR EACH ROW EXECUTE FUNCTION private.fiscal0_attempts_immutable();

CREATE OR REPLACE FUNCTION private.fiscal0_validate(p_cfdi public.billing_cfdis)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_missing jsonb := '[]'::jsonb; v_concept jsonb;
BEGIN
    IF NULLIF(trim(COALESCE(p_cfdi.fiscal_input#>>'{issuer,rfc}', p_cfdi.rfc_emisor)), '') IS NULL THEN
        v_missing := v_missing || '"issuer.rfc"'::jsonb;
    END IF;
    IF NULLIF(trim(COALESCE(p_cfdi.fiscal_input#>>'{receiver,rfc}', p_cfdi.rfc_receptor)), '') IS NULL THEN
        v_missing := v_missing || '"receiver.rfc"'::jsonb;
    END IF;
    IF p_cfdi.currency NOT IN ('MXN','USD') THEN v_missing := v_missing || '"currency"'::jsonb; END IF;
    IF p_cfdi.total <= 0 OR p_cfdi.subtotal <= 0 OR p_cfdi.total < p_cfdi.subtotal THEN
        v_missing := v_missing || '"positive_totals"'::jsonb;
    END IF;
    IF jsonb_typeof(p_cfdi.fiscal_input->'concepts') <> 'array'
       OR jsonb_array_length(COALESCE(p_cfdi.fiscal_input->'concepts','[]'::jsonb)) = 0 THEN
        v_missing := v_missing || '"concepts"'::jsonb;
    ELSE
        FOR v_concept IN SELECT value FROM jsonb_array_elements(p_cfdi.fiscal_input->'concepts') LOOP
            IF COALESCE(NULLIF(v_concept->>'description',''),'') = ''
               OR COALESCE(NULLIF(v_concept->>'amount','')::numeric,0) <= 0 THEN
                v_missing := v_missing || '"valid_concepts"'::jsonb; EXIT;
            END IF;
        END LOOP;
    END IF;
    IF p_cfdi.operation_id IS NULL AND NOT EXISTS (
        SELECT 1 FROM public.billing_documents bd
        WHERE bd.tenant_id = p_cfdi.tenant_id AND bd.linked_cfdi_id = p_cfdi.id
    ) THEN v_missing := v_missing || '"invoice_relation"'::jsonb; END IF;
    IF NULLIF(trim(COALESCE(p_cfdi.fiscal_input#>>'{payment,method}', '')), '') IS NULL THEN
        v_missing := v_missing || '"payment.method"'::jsonb;
    END IF;
    RETURN jsonb_build_object('valid', jsonb_array_length(v_missing)=0, 'missing_fields', v_missing, 'cfdi_version', p_cfdi.cfdi_version);
EXCEPTION WHEN invalid_text_representation THEN
    RETURN jsonb_build_object('valid', false, 'missing_fields', jsonb_build_array('valid_concepts'), 'cfdi_version', p_cfdi.cfdi_version);
END;
$function$;

CREATE OR REPLACE FUNCTION private.fiscal0_snapshot(p_cfdi public.billing_cfdis)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'schema','rotero.fiscal-input','schema_version',1,'cfdi_version',(p_cfdi).cfdi_version,
        'billing_cfdi_id',(p_cfdi).id,'tenant_id',(p_cfdi).tenant_id,'operation_id',(p_cfdi).operation_id,
        'issuer',COALESCE((p_cfdi).fiscal_input->'issuer',jsonb_build_object('rfc',(p_cfdi).rfc_emisor)),
        'receiver',COALESCE((p_cfdi).fiscal_input->'receiver',jsonb_build_object('rfc',(p_cfdi).rfc_receptor,'name',(p_cfdi).receptor_name)),
        'concepts',(p_cfdi).fiscal_input->'concepts','taxes',(p_cfdi).fiscal_input->'taxes',
        'payment',(p_cfdi).fiscal_input->'payment','related_cfdis',(p_cfdi).fiscal_input->'related_cfdis',
        'currency',(p_cfdi).currency,'subtotal',(p_cfdi).subtotal,'total',(p_cfdi).total,
        'exchange_rate',(p_cfdi).exchange_rate,
        'carta_porte',CASE WHEN (p_cfdi).has_carta_porte THEN (
            SELECT jsonb_strip_nulls(jsonb_build_object(
                'carta_porte_id',cp.id,'transport_type',cp.trans_type,'carrier_name',cp.carrier_name,
                'vehicle_plate',cp.vehicle_plate,'origin',cp.origin,'destination',cp.destination,'goods_description',cp.goods_desc
            )) FROM public.billing_carta_porte cp WHERE cp.cfdi_id=(p_cfdi).id
        ) ELSE NULL END
    ));
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_fiscal_readiness(p_cfdi_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_cfdi public.billing_cfdis%ROWTYPE; v_config public.fiscal_provider_configs%ROWTYPE;
BEGIN
    SELECT * INTO v_cfdi FROM public.billing_cfdis WHERE id=p_cfdi_id;
    IF v_cfdi.id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_cfdi.tenant_id,ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT * INTO v_config FROM public.fiscal_provider_configs WHERE tenant_id=v_cfdi.tenant_id;
    RETURN jsonb_build_object(
        'cfdi_id',v_cfdi.id,'fiscal_status',v_cfdi.fiscal_status,'validation',private.fiscal0_validate(v_cfdi),
        'provider',jsonb_build_object('configured',COALESCE(v_config.enabled,false) AND v_config.provider_code IS NOT NULL,
            'code',v_config.provider_code,'environment',COALESCE(v_config.environment,'sandbox')),
        'request_fingerprint',v_cfdi.request_fingerprint,'provider_document_id',v_cfdi.provider_document_id,
        'fiscal_uuid',v_cfdi.uuid,'last_checked_at',v_cfdi.fiscal_last_checked_at,
        'safe_error_code',v_cfdi.fiscal_error_code,'safe_error_message',v_cfdi.fiscal_error_message_safe,
        'xml_document_file_id',v_cfdi.xml_document_file_id,'pdf_document_file_id',v_cfdi.pdf_document_file_id,
        'last_attempt',(SELECT jsonb_build_object('request_id',r.id,'request_type',r.request_type,'status',r.status,'attempt_count',r.attempt_count,
            'safe_error_code',r.safe_error_code,'updated_at',r.updated_at) FROM public.fiscal_requests r
            WHERE r.billing_cfdi_id=v_cfdi.id ORDER BY r.created_at DESC LIMIT 1)
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_update_cfdi_fiscal_input(p_cfdi_id uuid, p_fiscal_input jsonb, p_cfdi_version text DEFAULT '4.0')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_cfdi public.billing_cfdis%ROWTYPE;
BEGIN
    SELECT * INTO v_cfdi FROM public.billing_cfdis WHERE id=p_cfdi_id FOR UPDATE;
    IF v_cfdi.id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_cfdi.tenant_id,ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF v_cfdi.fiscal_status <> 'draft' THEN RETURN jsonb_build_object('error','invalid_transition'); END IF;
    IF jsonb_typeof(p_fiscal_input) <> 'object' OR p_cfdi_version !~ '^[0-9]+\.[0-9]+$' THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
    UPDATE public.billing_cfdis SET fiscal_input=p_fiscal_input,cfdi_version=p_cfdi_version,
        fiscal_error_code=NULL,fiscal_error_message_safe=NULL WHERE id=p_cfdi_id;
    PERFORM public.rpc_write_audit(v_cfdi.tenant_id,'fiscal_input_updated','billing_cfdi',p_cfdi_id,jsonb_build_object('cfdi_version',p_cfdi_version));
    RETURN jsonb_build_object('success',true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_prepare_cfdi_for_api(p_cfdi_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_cfdi public.billing_cfdis%ROWTYPE; v_validation jsonb; v_snapshot jsonb; v_fingerprint text;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(p_cfdi_id::text,0));
    SELECT * INTO v_cfdi FROM public.billing_cfdis WHERE id=p_cfdi_id FOR UPDATE;
    IF v_cfdi.id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_cfdi.tenant_id,ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF v_cfdi.fiscal_status <> 'draft' THEN RETURN jsonb_build_object('error','invalid_transition'); END IF;
    v_validation := private.fiscal0_validate(v_cfdi);
    IF NOT (v_validation->>'valid')::boolean THEN RETURN jsonb_build_object('error','validation_failed','validation',v_validation); END IF;
    v_snapshot := private.fiscal0_snapshot(v_cfdi);
    v_fingerprint := encode(extensions.digest(convert_to(v_snapshot::text,'UTF8'),'sha256'),'hex');
    UPDATE public.billing_cfdis SET fiscal_status='ready_for_api',fiscal_snapshot=v_snapshot,
        fiscal_snapshot_created_at=now(),request_fingerprint=v_fingerprint,fiscal_error_code=NULL,
        fiscal_error_message_safe=NULL WHERE id=p_cfdi_id;
    PERFORM public.rpc_write_audit(v_cfdi.tenant_id,'fiscal_ready_for_api','billing_cfdi',p_cfdi_id,jsonb_build_object('request_fingerprint',v_fingerprint));
    RETURN jsonb_build_object('success',true,'fiscal_status','ready_for_api','request_fingerprint',v_fingerprint);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_queue_fiscal_stamp(p_cfdi_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_cfdi public.billing_cfdis%ROWTYPE; v_config public.fiscal_provider_configs%ROWTYPE; v_request public.fiscal_requests%ROWTYPE; v_idempotency text;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(p_cfdi_id::text,0));
    SELECT * INTO v_cfdi FROM public.billing_cfdis WHERE id=p_cfdi_id FOR UPDATE;
    IF v_cfdi.id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_cfdi.tenant_id,ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF v_cfdi.fiscal_status IN ('queued','submitting','processing') THEN
        SELECT * INTO v_request FROM public.fiscal_requests WHERE billing_cfdi_id=p_cfdi_id AND request_type='stamp'
          AND status IN ('queued','submitting','processing') ORDER BY created_at DESC LIMIT 1;
        RETURN jsonb_build_object('success',true,'accepted',false,'error','already_processing','request_id',v_request.id);
    END IF;
    IF v_cfdi.fiscal_status='stamped' THEN RETURN jsonb_build_object('error','already_stamped'); END IF;
    IF v_cfdi.fiscal_status <> 'ready_for_api' THEN RETURN jsonb_build_object('error','invalid_transition'); END IF;
    SELECT * INTO v_config FROM public.fiscal_provider_configs WHERE tenant_id=v_cfdi.tenant_id;
    IF v_config.id IS NULL OR NOT v_config.enabled OR v_config.provider_code IS NULL THEN
        RETURN jsonb_build_object('error','provider_not_configured','retryable',true);
    END IF;
    IF v_config.environment='production' AND current_setting('app.settings.environment',true) IS DISTINCT FROM 'production' THEN
        RETURN jsonb_build_object('error','provider_not_configured','retryable',true);
    END IF;
    v_idempotency := encode(extensions.digest(convert_to('stamp:'||v_cfdi.id::text||':'||v_cfdi.request_fingerprint,'UTF8'),'sha256'),'hex');
    INSERT INTO public.fiscal_requests(tenant_id,billing_cfdi_id,request_type,idempotency_key,payload_snapshot,next_attempt_at,requested_by)
    VALUES(v_cfdi.tenant_id,v_cfdi.id,'stamp',v_idempotency,v_cfdi.fiscal_snapshot,now(),(SELECT auth.uid()))
    ON CONFLICT (tenant_id,billing_cfdi_id,request_type,idempotency_key) DO UPDATE SET updated_at=public.fiscal_requests.updated_at
    RETURNING * INTO v_request;
    UPDATE public.billing_cfdis SET fiscal_status='queued',fiscal_provider=v_config.provider_code,
        fiscal_requested_at=COALESCE(fiscal_requested_at,now()) WHERE id=p_cfdi_id;
    PERFORM public.rpc_write_audit(v_cfdi.tenant_id,'fiscal_stamp_queued','billing_cfdi',p_cfdi_id,jsonb_build_object('request_id',v_request.id));
    RETURN jsonb_build_object('success',true,'accepted',true,'request_id',v_request.id,'status',v_request.status);
EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('success',true,'accepted',false,'error','already_processing');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_retry_fiscal_request(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_request public.fiscal_requests%ROWTYPE; v_cfdi public.billing_cfdis%ROWTYPE; v_config public.fiscal_provider_configs%ROWTYPE;
BEGIN
    SELECT * INTO v_request FROM public.fiscal_requests WHERE id=p_request_id FOR UPDATE;
    IF v_request.id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    SELECT * INTO v_cfdi FROM public.billing_cfdis WHERE id=v_request.billing_cfdi_id FOR UPDATE;
    IF NOT public.tanda1_user_has_role(v_request.tenant_id,ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF v_request.status <> 'technical_error' OR v_request.attempt_count >= v_request.max_attempts OR v_request.request_type <> 'stamp' THEN
        RETURN jsonb_build_object('error','invalid_transition');
    END IF;
    SELECT * INTO v_config FROM public.fiscal_provider_configs WHERE tenant_id=v_request.tenant_id;
    IF v_config.id IS NULL OR NOT v_config.enabled THEN RETURN jsonb_build_object('error','provider_not_configured','retryable',true); END IF;
    UPDATE public.fiscal_requests SET status='queued',next_attempt_at=now(),safe_error_code=NULL,updated_at=now() WHERE id=p_request_id;
    UPDATE public.billing_cfdis SET fiscal_status='queued',fiscal_error_code=NULL,fiscal_error_message_safe=NULL WHERE id=v_cfdi.id;
    PERFORM public.rpc_write_audit(v_request.tenant_id,'fiscal_manual_retry','fiscal_request',p_request_id,jsonb_build_object('attempt_count',v_request.attempt_count));
    RETURN jsonb_build_object('success',true,'accepted',true,'request_id',p_request_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_reset_cfdi_fiscal_draft(p_cfdi_id uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_cfdi public.billing_cfdis%ROWTYPE; v_reason text:=NULLIF(trim(p_reason),'');
BEGIN
    SELECT * INTO v_cfdi FROM public.billing_cfdis WHERE id=p_cfdi_id FOR UPDATE;
    IF v_cfdi.id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_cfdi.tenant_id,ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF v_reason IS NULL THEN RETURN jsonb_build_object('error','validation_failed','missing_fields',jsonb_build_array('reason')); END IF;
    IF v_cfdi.fiscal_status<>'rejected' THEN RETURN jsonb_build_object('error','invalid_transition'); END IF;
    UPDATE public.billing_cfdis SET fiscal_status='draft',fiscal_snapshot=NULL,fiscal_snapshot_created_at=NULL,
      request_fingerprint=NULL,provider_document_id=NULL,fiscal_error_code=NULL,fiscal_error_message_safe=NULL
    WHERE id=p_cfdi_id;
    PERFORM public.rpc_write_audit(v_cfdi.tenant_id,'fiscal_rejected_returned_to_draft','billing_cfdi',p_cfdi_id,jsonb_build_object('reason',v_reason));
    RETURN jsonb_build_object('success',true,'fiscal_status','draft');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_request_fiscal_cancellation(p_cfdi_id uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_cfdi public.billing_cfdis%ROWTYPE; v_config public.fiscal_provider_configs%ROWTYPE; v_request public.fiscal_requests%ROWTYPE; v_reason text:=NULLIF(trim(p_reason),''); v_key text; v_payload jsonb;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(p_cfdi_id::text,1));
    SELECT * INTO v_cfdi FROM public.billing_cfdis WHERE id=p_cfdi_id FOR UPDATE;
    IF v_cfdi.id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_cfdi.tenant_id,ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF v_reason IS NULL THEN RETURN jsonb_build_object('error','validation_failed','missing_fields',jsonb_build_array('cancellation_reason')); END IF;
    IF v_cfdi.fiscal_status='cancellation_requested' THEN
        SELECT * INTO v_request FROM public.fiscal_requests WHERE billing_cfdi_id=p_cfdi_id AND request_type='cancel' AND status IN ('queued','submitting','processing') ORDER BY created_at DESC LIMIT 1;
        RETURN jsonb_build_object('success',true,'accepted',false,'error','already_processing','request_id',v_request.id);
    END IF;
    IF v_cfdi.fiscal_status NOT IN ('stamped','cancellation_rejected') OR v_cfdi.uuid IS NULL THEN RETURN jsonb_build_object('error','invalid_transition'); END IF;
    SELECT * INTO v_config FROM public.fiscal_provider_configs WHERE tenant_id=v_cfdi.tenant_id;
    IF v_config.id IS NULL OR NOT v_config.enabled THEN RETURN jsonb_build_object('error','provider_not_configured','retryable',true); END IF;
    v_payload:=jsonb_build_object('billing_cfdi_id',v_cfdi.id,'fiscal_uuid',v_cfdi.uuid,'provider_document_id',v_cfdi.provider_document_id,'reason',v_reason);
    v_key:=encode(extensions.digest(convert_to('cancel:'||v_cfdi.id::text||':'||v_reason,'UTF8'),'sha256'),'hex');
    INSERT INTO public.fiscal_requests(tenant_id,billing_cfdi_id,request_type,idempotency_key,payload_snapshot,next_attempt_at,requested_by)
    VALUES(v_cfdi.tenant_id,v_cfdi.id,'cancel',v_key,v_payload,now(),(SELECT auth.uid()))
    ON CONFLICT (tenant_id,billing_cfdi_id,request_type,idempotency_key) DO UPDATE SET
      status='queued',next_attempt_at=now(),completed_at=NULL,safe_error_code=NULL,updated_at=now()
    RETURNING * INTO v_request;
    UPDATE public.billing_cfdis SET fiscal_status='cancellation_requested' WHERE id=p_cfdi_id;
    PERFORM public.rpc_write_audit(v_cfdi.tenant_id,'fiscal_cancellation_requested','billing_cfdi',p_cfdi_id,jsonb_build_object('request_id',v_request.id,'reason',v_reason));
    RETURN jsonb_build_object('success',true,'accepted',true,'request_id',v_request.id);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('success',true,'accepted',false,'error','already_processing');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_queue_fiscal_status_check(p_cfdi_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_cfdi public.billing_cfdis%ROWTYPE; v_config public.fiscal_provider_configs%ROWTYPE; v_request_id uuid; v_key text; v_payload jsonb;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(p_cfdi_id::text,2));
    SELECT * INTO v_cfdi FROM public.billing_cfdis WHERE id=p_cfdi_id FOR UPDATE;
    IF v_cfdi.id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_cfdi.tenant_id,ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF v_cfdi.provider_document_id IS NULL OR v_cfdi.fiscal_status NOT IN ('processing','api_error','stamped','cancellation_requested','cancellation_rejected') THEN RETURN jsonb_build_object('error','invalid_transition'); END IF;
    SELECT * INTO v_config FROM public.fiscal_provider_configs WHERE tenant_id=v_cfdi.tenant_id;
    IF v_config.id IS NULL OR NOT v_config.enabled THEN RETURN jsonb_build_object('error','provider_not_configured','retryable',true); END IF;
    v_payload:=jsonb_build_object('billing_cfdi_id',v_cfdi.id,'provider_document_id',v_cfdi.provider_document_id,'known_fiscal_status',v_cfdi.fiscal_status);
    v_key:=encode(extensions.digest(convert_to('status:'||v_cfdi.id::text||':'||date_trunc('minute',now())::text,'UTF8'),'sha256'),'hex');
    INSERT INTO public.fiscal_requests(tenant_id,billing_cfdi_id,request_type,idempotency_key,payload_snapshot,next_attempt_at,requested_by)
    VALUES(v_cfdi.tenant_id,v_cfdi.id,'status',v_key,v_payload,now(),(SELECT auth.uid())) RETURNING id INTO v_request_id;
    PERFORM public.rpc_write_audit(v_cfdi.tenant_id,'fiscal_status_check_queued','billing_cfdi',p_cfdi_id,jsonb_build_object('request_id',v_request_id));
    RETURN jsonb_build_object('success',true,'accepted',true,'request_id',v_request_id);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('success',true,'accepted',false,'error','already_processing');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_fiscal_operational_status(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN jsonb_build_object(
        'queue_depth',(SELECT count(*) FROM public.fiscal_requests WHERE tenant_id=p_tenant_id AND status='queued'),
        'technical_failures',(SELECT count(*) FROM public.fiscal_requests WHERE tenant_id=p_tenant_id AND status='technical_error'),
        'stale_processing',(SELECT count(*) FROM public.fiscal_requests WHERE tenant_id=p_tenant_id AND status IN ('submitting','processing') AND updated_at<now()-interval '30 minutes'),
        'provider_not_configured',NOT COALESCE((SELECT enabled FROM public.fiscal_provider_configs WHERE tenant_id=p_tenant_id),false)
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_fiscal_provider_config(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN COALESCE((SELECT jsonb_build_object('provider_code',provider_code,'enabled',enabled,'environment',environment,'capabilities',capabilities,'updated_at',updated_at)
      FROM public.fiscal_provider_configs WHERE tenant_id=p_tenant_id),jsonb_build_object('provider_code',NULL,'enabled',false,'environment','sandbox','capabilities','{}'::jsonb));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_update_fiscal_provider_config(p_tenant_id uuid,p_provider_code text,p_enabled boolean,p_environment text,p_capabilities jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_id uuid; v_provider text:=NULLIF(lower(trim(p_provider_code)),'');
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF p_environment NOT IN ('sandbox','production') OR jsonb_typeof(p_capabilities)<>'object'
       OR p_capabilities ?| ARRAY['secret','password','token','api_key','authorization','certificate','private_key']
       OR v_provider='mock' OR (v_provider IS NOT NULL AND v_provider !~ '^[a-z][a-z0-9_]{1,62}$') THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
    IF p_enabled AND v_provider IS NULL THEN RETURN jsonb_build_object('error','provider_not_configured'); END IF;
    INSERT INTO public.fiscal_provider_configs(tenant_id,provider_code,enabled,environment,capabilities,created_by,updated_by)
    VALUES(p_tenant_id,v_provider,p_enabled,p_environment,p_capabilities,(SELECT auth.uid()),(SELECT auth.uid()))
    ON CONFLICT(tenant_id) DO UPDATE SET provider_code=EXCLUDED.provider_code,enabled=EXCLUDED.enabled,
      environment=EXCLUDED.environment,capabilities=EXCLUDED.capabilities,updated_by=EXCLUDED.updated_by,updated_at=now()
    RETURNING id INTO v_id;
    PERFORM public.rpc_write_audit(p_tenant_id,'fiscal_provider_config_updated','fiscal_provider_config',v_id,jsonb_build_object('provider_code',v_provider,'enabled',p_enabled,'environment',p_environment));
    RETURN jsonb_build_object('success',true,'id',v_id,'provider_code',v_provider,'enabled',p_enabled,'environment',p_environment);
END;
$function$;

-- Owner-only worker boundary. It consumes canonical normalized results; it is
-- intentionally not executable by authenticated/service_role in FISCAL.0.
CREATE OR REPLACE FUNCTION private.fiscal0_claim_requests(p_limit integer DEFAULT 10)
RETURNS SETOF public.fiscal_requests LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_request public.fiscal_requests%ROWTYPE;
BEGIN
  FOR v_request IN
    SELECT * FROM public.fiscal_requests
    WHERE (status='queued' OR (status='technical_error' AND next_attempt_at<=now() AND attempt_count<max_attempts))
    ORDER BY COALESCE(next_attempt_at,created_at),created_at
    FOR UPDATE SKIP LOCKED LIMIT LEAST(GREATEST(p_limit,1),50)
  LOOP
    IF v_request.status='technical_error' AND v_request.request_type='stamp' THEN
      UPDATE public.billing_cfdis SET fiscal_status='queued' WHERE id=v_request.billing_cfdi_id AND fiscal_status='api_error';
    END IF;
    UPDATE public.fiscal_requests SET status='submitting',locked_at=now(),updated_at=now() WHERE id=v_request.id RETURNING * INTO v_request;
    IF v_request.request_type='stamp' THEN
      UPDATE public.billing_cfdis SET fiscal_status='submitting' WHERE id=v_request.billing_cfdi_id AND fiscal_status='queued';
    END IF;
    RETURN NEXT v_request;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION private.fiscal0_apply_provider_result(p_request_id uuid,p_result jsonb,p_started_at timestamptz DEFAULT now())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_request public.fiscal_requests%ROWTYPE; v_cfdi public.billing_cfdis%ROWTYPE; v_outcome text:=p_result->>'outcome'; v_attempt integer; v_safe text; v_final text;
BEGIN
    IF jsonb_typeof(p_result)<>'object' OR v_outcome NOT IN ('processing','stamped','business_rejection','technical_error','cancelled','cancellation_rejected','not_found') THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
    SELECT * INTO v_request FROM public.fiscal_requests WHERE id=p_request_id FOR UPDATE;
    IF v_request.id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    SELECT * INTO v_cfdi FROM public.billing_cfdis WHERE id=v_request.billing_cfdi_id FOR UPDATE;
    v_attempt:=v_request.attempt_count+1;
    v_safe:=CASE v_outcome WHEN 'business_rejection' THEN 'provider_rejected' WHEN 'technical_error' THEN COALESCE(p_result->>'safe_error_code','provider_unavailable') WHEN 'cancellation_rejected' THEN 'cancellation_failed' WHEN 'not_found' THEN 'status_conflict' ELSE NULL END;
    INSERT INTO public.fiscal_provider_attempts(tenant_id,request_id,attempt_no,started_at,completed_at,http_status,provider_code,normalized_result,safe_error_code,duration_ms)
    VALUES(v_request.tenant_id,v_request.id,v_attempt,p_started_at,now(),NULLIF(p_result->>'http_status','')::integer,NULLIF(p_result->>'provider_code',''),
      p_result - ARRAY['raw_body','authorization','headers','secret','certificate','xml_base64','pdf_base64'],v_safe,
      GREATEST(0,(extract(epoch FROM (now()-p_started_at))*1000)::integer));
    v_final:=CASE v_outcome WHEN 'processing' THEN 'processing' WHEN 'stamped' THEN 'completed' WHEN 'business_rejection' THEN 'business_rejected'
      WHEN 'technical_error' THEN 'technical_error' WHEN 'cancelled' THEN 'completed' WHEN 'cancellation_rejected' THEN 'business_rejected' WHEN 'not_found' THEN 'completed' END;
    UPDATE public.fiscal_requests SET status=v_final,attempt_count=v_attempt,completed_at=CASE WHEN v_final IN ('completed','business_rejected') THEN now() ELSE NULL END,
      next_attempt_at=CASE WHEN v_final='technical_error' AND v_attempt<max_attempts THEN now()+make_interval(mins=>power(2,v_attempt)::integer*5) ELSE NULL END,
      safe_error_code=v_safe,updated_at=now() WHERE id=v_request.id;
    IF v_outcome='processing' THEN
      UPDATE public.billing_cfdis SET fiscal_status='processing',provider_document_id=COALESCE(provider_document_id,p_result->>'provider_document_id'),fiscal_last_checked_at=now() WHERE id=v_cfdi.id;
    ELSIF v_outcome='stamped' THEN
      UPDATE public.billing_cfdis SET fiscal_status=CASE WHEN fiscal_status IN ('cancellation_requested','cancelled') THEN fiscal_status ELSE 'stamped' END,uuid=COALESCE(uuid,p_result->>'fiscal_uuid'),provider_document_id=COALESCE(provider_document_id,p_result->>'provider_document_id'),
        fiscal_stamped_at=COALESCE(fiscal_stamped_at,now()),fiscal_last_checked_at=now(),fiscal_error_code=NULL,fiscal_error_message_safe=NULL WHERE id=v_cfdi.id;
    ELSIF v_outcome='business_rejection' THEN
      UPDATE public.billing_cfdis SET fiscal_status='rejected',fiscal_error_code='provider_rejected',fiscal_error_message_safe='El proveedor rechazó la solicitud fiscal.',fiscal_last_checked_at=now() WHERE id=v_cfdi.id;
    ELSIF v_outcome='technical_error' THEN
      UPDATE public.billing_cfdis SET fiscal_status=CASE WHEN v_request.request_type='stamp' THEN 'api_error' ELSE fiscal_status END,
        fiscal_error_code=v_safe,fiscal_error_message_safe='No fue posible completar la comunicación fiscal.',fiscal_last_checked_at=now() WHERE id=v_cfdi.id;
    ELSIF v_outcome='cancelled' THEN
      UPDATE public.billing_cfdis SET fiscal_status='cancelled',fiscal_cancelled_at=COALESCE(fiscal_cancelled_at,now()),fiscal_last_checked_at=now(),fiscal_error_code=NULL,fiscal_error_message_safe=NULL WHERE id=v_cfdi.id;
    ELSIF v_outcome='cancellation_rejected' THEN
      UPDATE public.billing_cfdis SET fiscal_status='cancellation_rejected',fiscal_error_code='cancellation_failed',fiscal_error_message_safe='El proveedor no confirmó la cancelación.',fiscal_last_checked_at=now() WHERE id=v_cfdi.id;
    ELSIF v_outcome='not_found' THEN
      UPDATE public.billing_cfdis SET fiscal_last_checked_at=now(),fiscal_error_code='status_conflict',fiscal_error_message_safe='El proveedor no encontró el documento; se requiere revisión manual.' WHERE id=v_cfdi.id;
    END IF;
    PERFORM public.rpc_write_audit(v_request.tenant_id,'fiscal_provider_attempt','fiscal_request',v_request.id,jsonb_build_object('attempt_no',v_attempt,'outcome',v_outcome,'safe_error_code',v_safe));
    RETURN jsonb_build_object('success',true,'outcome',v_outcome,'attempt_no',v_attempt);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE OR REPLACE FUNCTION private.fiscal0_link_artifact(p_request_id uuid,p_kind text,p_file_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_request public.fiscal_requests%ROWTYPE; v_cfdi public.billing_cfdis%ROWTYPE; v_file public.document_files%ROWTYPE;
BEGIN
    IF p_kind NOT IN ('xml','pdf') THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
    SELECT * INTO v_request FROM public.fiscal_requests WHERE id=p_request_id;
    SELECT * INTO v_cfdi FROM public.billing_cfdis WHERE id=v_request.billing_cfdi_id FOR UPDATE;
    SELECT * INTO v_file FROM public.document_files WHERE id=p_file_id;
    IF v_request.id IS NULL OR v_cfdi.id IS NULL OR v_file.id IS NULL OR v_file.tenant_id<>v_cfdi.tenant_id
       OR v_file.storage_bucket<>'tenant-documents' OR v_file.status<>'active' OR v_file.checksum_sha256 IS NULL
       OR (p_kind='xml' AND v_file.file_kind<>'fiscal_xml') OR (p_kind='pdf' AND v_file.file_kind<>'fiscal_pdf') THEN
      RETURN jsonb_build_object('error','invalid_document_file');
    END IF;
    IF p_kind='xml' THEN UPDATE public.billing_cfdis SET xml_document_file_id=p_file_id WHERE id=v_cfdi.id;
    ELSE UPDATE public.billing_cfdis SET pdf_document_file_id=p_file_id WHERE id=v_cfdi.id; END IF;
    PERFORM public.rpc_write_audit(v_cfdi.tenant_id,'fiscal_artifact_stored','billing_cfdi',v_cfdi.id,jsonb_build_object('kind',p_kind,'document_file_id',p_file_id));
    RETURN jsonb_build_object('success',true);
END;
$function$;

-- Extend F3's private entity resolver for the canonical billing_cfdis aggregate.
ALTER TABLE public.document_files DROP CONSTRAINT document_files_source_type_check;
ALTER TABLE public.document_files ADD CONSTRAINT document_files_source_type_check CHECK (source_entity_type IN (
  'operation','quote','customer','provider','billing_document','billing_cfdi','generated_document','finance_invoice','claim'
));

CREATE OR REPLACE FUNCTION private.f3_entity_belongs_to_tenant(p_tenant_id uuid,p_entity_type text,p_entity_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_exists boolean:=false;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN RETURN false; END IF;
  CASE p_entity_type
    WHEN 'operation' THEN SELECT EXISTS(SELECT 1 FROM public.operations WHERE id=p_entity_id AND tenant_id=p_tenant_id) INTO v_exists;
    WHEN 'quote' THEN SELECT EXISTS(SELECT 1 FROM public.crm_deals WHERE id=p_entity_id AND tenant_id=p_tenant_id AND quote_reference IS NOT NULL) INTO v_exists;
    WHEN 'customer' THEN SELECT EXISTS(SELECT 1 FROM public.customers WHERE id=p_entity_id AND tenant_id=p_tenant_id) INTO v_exists;
    WHEN 'provider' THEN SELECT EXISTS(SELECT 1 FROM public.logistics_providers WHERE id=p_entity_id AND tenant_id=p_tenant_id) INTO v_exists;
    WHEN 'generated_document' THEN SELECT EXISTS(SELECT 1 FROM public.generated_documents WHERE id=p_entity_id AND tenant_id=p_tenant_id) INTO v_exists;
    WHEN 'billing_document' THEN SELECT EXISTS(SELECT 1 FROM public.billing_documents WHERE id=p_entity_id AND tenant_id=p_tenant_id) INTO v_exists;
    WHEN 'billing_cfdi' THEN SELECT EXISTS(SELECT 1 FROM public.billing_cfdis WHERE id=p_entity_id AND tenant_id=p_tenant_id) INTO v_exists;
    WHEN 'finance_invoice' THEN SELECT EXISTS(SELECT 1 FROM public.finance_invoices WHERE id=p_entity_id AND tenant_id=p_tenant_id) INTO v_exists;
    WHEN 'claim' THEN SELECT EXISTS(SELECT 1 FROM public.service_claims WHERE id=p_entity_id AND tenant_id=p_tenant_id) INTO v_exists;
    ELSE v_exists:=false;
  END CASE;
  RETURN v_exists;
END;
$function$;

ALTER TABLE public.fiscal_provider_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fiscal_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fiscal_provider_attempts ENABLE ROW LEVEL SECURITY;
CREATE POLICY fiscal_provider_configs_select ON public.fiscal_provider_configs FOR SELECT TO authenticated
  USING ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin','finance'])));
CREATE POLICY fiscal_requests_select ON public.fiscal_requests FOR SELECT TO authenticated
  USING ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin','finance'])));
CREATE POLICY fiscal_attempts_select ON public.fiscal_provider_attempts FOR SELECT TO authenticated
  USING ((SELECT public.tanda1_user_has_role(tenant_id,ARRAY['admin','finance'])));

REVOKE ALL ON TABLE public.fiscal_provider_configs,public.fiscal_requests,public.fiscal_provider_attempts FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fiscal0_status_transition_allowed(text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fiscal0_guard_cfdi() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fiscal0_attempts_immutable() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fiscal0_validate(public.billing_cfdis) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fiscal0_snapshot(public.billing_cfdis) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fiscal0_claim_requests(integer) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fiscal0_apply_provider_result(uuid,jsonb,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private.fiscal0_link_artifact(uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;

REVOKE EXECUTE ON FUNCTION public.rpc_get_fiscal_readiness(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_update_cfdi_fiscal_input(uuid,jsonb,text) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_prepare_cfdi_for_api(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_queue_fiscal_stamp(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_retry_fiscal_request(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_reset_cfdi_fiscal_draft(uuid,text) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_request_fiscal_cancellation(uuid,text) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_queue_fiscal_status_check(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_fiscal_operational_status(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_get_fiscal_provider_config(uuid) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_update_fiscal_provider_config(uuid,text,boolean,text,jsonb) FROM PUBLIC,anon,service_role;

GRANT EXECUTE ON FUNCTION public.rpc_get_fiscal_readiness(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_cfdi_fiscal_input(uuid,jsonb,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_prepare_cfdi_for_api(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_queue_fiscal_stamp(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_retry_fiscal_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_reset_cfdi_fiscal_draft(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_request_fiscal_cancellation(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_queue_fiscal_status_check(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_fiscal_operational_status(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_fiscal_provider_config(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_fiscal_provider_config(uuid,text,boolean,text,jsonb) TO authenticated;
