-- MULTI-08: close classified Finance write responses without inventing work grants.
-- Unknown historical ownership retains the legacy contract, explicitly outside
-- enterprise protection. No permission to write follows from financial.full.read.
BEGIN;
-- Accept only the uniform CRLF transport form of the exact reviewed source.
CREATE FUNCTION pg_temp.multi08_write_source(value text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE WHEN position(chr(13) IN value)>0 AND replace(replace(value,chr(13)||chr(10),chr(10)),chr(10),chr(13)||chr(10))=value
 THEN replace(value,chr(13)||chr(10),chr(10)) ELSE value END;
$$;
GRANT SELECT(linked_cfdi_id) ON public.finance_invoices,public.billing_documents TO rotero_finance_scope_owner;
CREATE FUNCTION private.multi08_legacy_write_target(p_tenant uuid,p_kind text,p_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE s record; q record;
BEGIN
 IF p_id IS NULL THEN RETURN true; END IF;
 IF private.fiscal02_is_lab_entity(p_kind,p_id) THEN RETURN false; END IF;
 IF p_kind='cfdi' THEN
  -- A canonical CFDI has no approved company classification yet. Its linked
  -- financial graph must remain wholly unclassified to retain the old contract.
  FOR q IN SELECT 'invoice' kind,id FROM public.finance_invoices WHERE linked_cfdi_id=p_id
   UNION ALL SELECT 'document',id FROM public.billing_documents WHERE linked_cfdi_id=p_id LOOP
   IF NOT private.multi08_legacy_write_target(p_tenant,q.kind,q.id) THEN RETURN false; END IF;
  END LOOP;
  RETURN true;
 END IF;
 SELECT * INTO s FROM private.multi07_entity_scope(p_kind,p_id);
 RETURN FOUND AND s.tenant_id=p_tenant AND s.coherent AND cardinality(s.company_ids)=0;
END $fn$;
REVOKE ALL ON FUNCTION private.multi08_legacy_write_target(uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT CREATE ON SCHEMA private TO rotero_finance_scope_owner;
ALTER FUNCTION private.multi08_legacy_write_target(uuid,text,uuid) OWNER TO rotero_finance_scope_owner;
DO $grant$ DECLARE actor text:=current_user; BEGIN
 SET LOCAL ROLE rotero_finance_scope_owner;
 EXECUTE format('GRANT EXECUTE ON FUNCTION private.multi08_legacy_write_target(uuid,text,uuid) TO %I',actor);
 EXECUTE format('SET LOCAL ROLE %I',actor);
END $grant$;
REVOKE CREATE ON SCHEMA private FROM rotero_finance_scope_owner;
-- Five exact reviewed main bodies; keep their signatures, ACL, owners, role gate,
-- fiscal02 sources, and legacy response contracts. Inject before value reads.
DO $patch$ DECLARE proc oid:='public.rpc_create_finance_invoice(uuid,jsonb)'::regprocedure; BEGIN
 IF NOT EXISTS(SELECT FROM pg_proc WHERE oid=proc AND md5(pg_temp.multi08_write_source(prosrc))='5e8a190a291f0969c948d0a8d6e5b0ef' AND prosecdef AND proowner=current_user::regrole AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN RAISE EXCEPTION 'unsupported_multi08_write_body'; END IF;
END $patch$;
CREATE OR REPLACE FUNCTION public.rpc_create_finance_invoice(p_tenant_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_id uuid; v_direction text; v_status text; v_currency text; v_amount numeric;
    v_customer_id uuid; v_provider_id uuid; v_operation_id uuid; v_billing_document_id uuid; v_cfdi_id uuid;
    v_customer_name text; v_provider_name text; v_counterparty text; v_operation public.operations%ROWTYPE;
    v_expected numeric; v_registered numeric := 0; v_override boolean := false; v_override_reason text;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant_id::text,7007));
    IF p_payload ?| ARRAY['company_id','tenant_id','company_classification_status','company_classification_event_id'] THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
    BEGIN
        IF NOT (private.multi08_legacy_write_target(p_tenant_id,'operation',NULLIF(p_payload->>'operation_id','')::uuid) AND private.multi08_legacy_write_target(p_tenant_id,'document',NULLIF(p_payload->>'billing_document_id','')::uuid) AND private.multi08_legacy_write_target(p_tenant_id,'cfdi',NULLIF(p_payload->>'linked_cfdi_id','')::uuid)) THEN RETURN jsonb_build_object('error','company_finance_write_pending'); END IF;
    EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;

    BEGIN
        v_direction := lower(NULLIF(trim(p_payload->>'direction'),''));
        v_status := lower(COALESCE(NULLIF(trim(p_payload->>'status'),''),'open'));
        v_currency := upper(COALESCE(NULLIF(trim(p_payload->>'currency'),''),'MXN'));
        v_amount := NULLIF(p_payload->>'amount','')::numeric;
        v_customer_id := NULLIF(p_payload->>'customer_id','')::uuid;
        v_provider_id := NULLIF(p_payload->>'provider_id','')::uuid;
        v_operation_id := NULLIF(p_payload->>'operation_id','')::uuid;
        v_billing_document_id := NULLIF(p_payload->>'billing_document_id','')::uuid;
        v_cfdi_id := NULLIF(p_payload->>'linked_cfdi_id','')::uuid;
        v_override := COALESCE(NULLIF(p_payload->>'over_registration_override','')::boolean, false);
    EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;
    IF v_direction NOT IN ('ar','ap') OR v_status NOT IN ('draft','open') OR v_currency NOT IN ('MXN','USD') OR v_amount IS NULL OR v_amount <= 0 THEN
        RETURN jsonb_build_object('error','invalid_payload');
    END IF;
    IF v_customer_id IS NOT NULL THEN SELECT display_name INTO v_customer_name FROM public.customers WHERE id = v_customer_id AND tenant_id = p_tenant_id; IF NOT FOUND THEN RETURN jsonb_build_object('error','invalid_customer'); END IF; END IF;
    IF v_provider_id IS NOT NULL THEN SELECT display_name INTO v_provider_name FROM public.logistics_providers WHERE id = v_provider_id AND tenant_id = p_tenant_id; IF NOT FOUND THEN RETURN jsonb_build_object('error','invalid_provider'); END IF; END IF;
    IF v_operation_id IS NOT NULL THEN
        SELECT * INTO v_operation FROM public.operations WHERE id = v_operation_id AND tenant_id = p_tenant_id FOR UPDATE;
        IF NOT FOUND THEN RETURN jsonb_build_object('error','invalid_operation'); END IF;
        IF v_operation.pricing_currency <> v_currency THEN RETURN jsonb_build_object('error','operation_currency_mismatch'); END IF;
        IF v_direction = 'ar' THEN
            v_expected := v_operation.customer_price_amount;
            IF v_operation.customer_id IS NOT NULL AND v_customer_id IS NOT NULL AND v_operation.customer_id <> v_customer_id THEN RETURN jsonb_build_object('error','operation_counterparty_mismatch'); END IF;
            v_customer_id := COALESCE(v_customer_id, v_operation.customer_id);
            IF v_customer_id IS NOT NULL THEN SELECT display_name INTO v_customer_name FROM public.customers WHERE id = v_customer_id AND tenant_id = p_tenant_id; END IF;
        ELSE
            v_expected := v_operation.provider_cost_amount;
            IF v_operation.provider_id IS NOT NULL AND v_provider_id IS NOT NULL AND v_operation.provider_id <> v_provider_id THEN RETURN jsonb_build_object('error','operation_counterparty_mismatch'); END IF;
            v_provider_id := COALESCE(v_provider_id, v_operation.provider_id);
            IF v_provider_id IS NOT NULL THEN SELECT display_name INTO v_provider_name FROM public.logistics_providers WHERE id = v_provider_id AND tenant_id = p_tenant_id; END IF;
        END IF;
        SELECT COALESCE(sum(amount),0) INTO v_registered FROM private.fiscal02_legacy_finance_invoices
        WHERE tenant_id = p_tenant_id AND operation_id = v_operation_id AND direction = v_direction AND currency = v_currency AND status <> 'void';
        v_override_reason := NULLIF(trim(p_payload->>'over_registration_reason'),'');
        IF v_expected IS NOT NULL AND v_registered + v_amount > v_expected AND (NOT v_override OR v_override_reason IS NULL) THEN
            RETURN jsonb_build_object('error','operation_amount_exceeded','expected_amount',v_expected,'registered_amount',v_registered);
        END IF;
    END IF;
    IF v_billing_document_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM private.fiscal02_legacy_billing_documents WHERE id=v_billing_document_id AND tenant_id=p_tenant_id) THEN RETURN jsonb_build_object('error','invalid_billing_document'); END IF;
    IF v_cfdi_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM private.fiscal02_readable_cfdis WHERE id=v_cfdi_id AND tenant_id=p_tenant_id) THEN RETURN jsonb_build_object('error','invalid_cfdi'); END IF;
    v_counterparty := CASE WHEN v_direction='ar' THEN v_customer_name ELSE v_provider_name END;
    v_counterparty := COALESCE(v_counterparty, NULLIF(trim(p_payload->>'counterparty_name'),''));
    IF v_counterparty IS NULL THEN RETURN jsonb_build_object('error','counterparty_required'); END IF;

    INSERT INTO public.finance_invoices (
        tenant_id,direction,counterparty_name,reference,amount,currency,status,due_date,received_at,notes,
        customer_id,provider_id,operation_id,billing_document_id,linked_cfdi_id,
        exchange_rate,exchange_rate_date,exchange_rate_source,over_registration_override,over_registration_reason,created_by
    ) VALUES (
        p_tenant_id,v_direction,v_counterparty,NULLIF(trim(p_payload->>'reference'),''),v_amount,v_currency,v_status,
        NULLIF(p_payload->>'due_date','')::date,NULLIF(p_payload->>'received_at','')::timestamptz,NULLIF(trim(p_payload->>'notes'),''),
        v_customer_id,v_provider_id,v_operation_id,v_billing_document_id,v_cfdi_id,
        NULLIF(p_payload->>'exchange_rate','')::numeric,NULLIF(p_payload->>'exchange_rate_date','')::date,
        COALESCE(NULLIF(trim(p_payload->>'exchange_rate_source'),''),'manual'),v_override,v_override_reason,(SELECT auth.uid())
    ) RETURNING id INTO v_id;
    PERFORM public.rpc_write_audit(p_tenant_id,'finance_invoice_created','finance_invoice',v_id,
        jsonb_build_object('direction',v_direction,'amount',v_amount,'currency',v_currency,'operation_id',v_operation_id,'over_registration_override',v_override));
    RETURN jsonb_build_object('id',v_id,'success',true);
EXCEPTION
    WHEN check_violation OR foreign_key_violation OR invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload');
    WHEN invalid_parameter_value THEN RETURN jsonb_build_object('error','exchange_rate_required_for_usd');
END;
$function$
;
DO $patch$ DECLARE proc oid:='public.rpc_create_payment_complement(uuid,jsonb)'::regprocedure; BEGIN
 IF NOT EXISTS(SELECT FROM pg_proc WHERE oid=proc AND md5(pg_temp.multi08_write_source(prosrc))='e4b1c8d1d1a9a759a5dcec8dfc99f9e3' AND prosecdef AND proowner=current_user::regrole AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN RAISE EXCEPTION 'unsupported_multi08_write_body'; END IF;
END $patch$;
CREATE OR REPLACE FUNCTION public.rpc_create_payment_complement(p_tenant_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_payment public.finance_payments%ROWTYPE; v_invoice public.finance_invoices%ROWTYPE; v_id uuid; v_payment_id uuid;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant_id::text,7007));
    IF p_payload ?| ARRAY['company_id','tenant_id','company_classification_status','company_classification_event_id'] THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
    BEGIN
        IF NOT (private.multi08_legacy_write_target(p_tenant_id,'payment',NULLIF(p_payload->>'finance_payment_id','')::uuid)) THEN RETURN jsonb_build_object('error','company_finance_write_pending'); END IF;
    EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;

    BEGIN v_payment_id:=NULLIF(p_payload->>'finance_payment_id','')::uuid; EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;
    SELECT * INTO v_payment FROM private.fiscal02_legacy_finance_payments WHERE id=v_payment_id AND tenant_id=p_tenant_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error','payment_not_found'); END IF;
    SELECT * INTO v_invoice FROM private.fiscal02_legacy_finance_invoices WHERE id=v_payment.invoice_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF v_invoice.direction<>'ar' THEN RETURN jsonb_build_object('error','complement_only_for_ar'); END IF;
    IF EXISTS(SELECT 1 FROM private.fiscal02_legacy_billing_payment_complements WHERE finance_payment_id=v_payment.id AND status<>'cancelled') THEN RETURN jsonb_build_object('error','complement_already_exists'); END IF;
    INSERT INTO public.billing_payment_complements(tenant_id,finance_invoice_id,finance_payment_id,cfdi_id,invoice_billing_document_id,payment_date,method,
        bank_reference,currency,amount,exchange_rate,exchange_rate_date,amount_mxn,status,notes,created_by)
    VALUES(p_tenant_id,v_invoice.id,v_payment.id,v_invoice.linked_cfdi_id,v_invoice.billing_document_id,v_payment.paid_at,v_payment.method,
        v_payment.bank_reference,v_payment.currency,v_payment.amount,v_payment.exchange_rate,v_payment.exchange_rate_date,v_payment.amount_mxn,'ready',v_payment.note,(SELECT auth.uid()))
    RETURNING id INTO v_id;
    PERFORM public.rpc_write_audit(p_tenant_id,'payment_complement_prepared','payment_complement',v_id,jsonb_build_object('payment_id',v_payment.id));
    RETURN jsonb_build_object('id',v_id,'status','ready','handoff','billing','success',true);
END;
$function$
;
DO $patch$ DECLARE proc oid:='public.rpc_record_payment(uuid,jsonb)'::regprocedure; BEGIN
 IF NOT EXISTS(SELECT FROM pg_proc WHERE oid=proc AND md5(pg_temp.multi08_write_source(prosrc))='553d654533096c861f317158b10ade12' AND prosecdef AND proowner=current_user::regrole AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN RAISE EXCEPTION 'unsupported_multi08_write_body'; END IF;
END $patch$;
CREATE OR REPLACE FUNCTION public.rpc_record_payment(p_tenant_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_invoice public.finance_invoices%ROWTYPE; v_invoice_id uuid; v_id uuid; v_complement_id uuid;
    v_amount numeric; v_balance numeric; v_currency text; v_paid_at timestamptz;
    v_prepare boolean; v_method text; v_exchange_rate numeric; v_exchange_rate_date date;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant_id::text,7007));
    IF p_payload ?| ARRAY['company_id','tenant_id','company_classification_status','company_classification_event_id'] THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
    BEGIN
        IF NOT (private.multi08_legacy_write_target(p_tenant_id,'invoice',NULLIF(p_payload->>'invoice_id','')::uuid)) THEN RETURN jsonb_build_object('error','company_finance_write_pending'); END IF;
    EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;

    BEGIN
        v_invoice_id := NULLIF(p_payload->>'invoice_id','')::uuid;
        v_amount := NULLIF(p_payload->>'amount','')::numeric;
        v_paid_at := COALESCE(NULLIF(p_payload->>'paid_at','')::timestamptz, now());
        v_exchange_rate := NULLIF(p_payload->>'exchange_rate','')::numeric;
        v_exchange_rate_date := NULLIF(p_payload->>'exchange_rate_date','')::date;
    EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;
    SELECT * INTO v_invoice FROM private.fiscal02_legacy_finance_invoices WHERE id=v_invoice_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error','invoice_not_found'); END IF;
    IF v_invoice.status IN ('draft','void') THEN RETURN jsonb_build_object('error','invoice_not_payable'); END IF;
    IF v_amount IS NULL OR v_amount <= 0 THEN RETURN jsonb_build_object('error','invalid_payment_amount'); END IF;
    SELECT balance_amount INTO v_balance FROM private.f4_invoice_totals(v_invoice.id);
    IF v_balance <= 0 OR v_invoice.status='paid' THEN RETURN jsonb_build_object('error','invoice_already_settled'); END IF;
    IF round(v_amount,2) > round(v_balance,2) THEN RETURN jsonb_build_object('error','payment_exceeds_balance','balance',v_balance); END IF;
    v_currency := upper(COALESCE(NULLIF(trim(p_payload->>'currency'),''),v_invoice.currency));
    IF v_currency <> v_invoice.currency THEN RETURN jsonb_build_object('error','payment_currency_mismatch'); END IF;
    v_method := lower(COALESCE(NULLIF(trim(p_payload->>'method'),''),'transfer'));
    IF v_method NOT IN ('transfer','cash','card','other') THEN RETURN jsonb_build_object('error','invalid_payment_method'); END IF;
    IF v_currency='USD' THEN
        v_exchange_rate := COALESCE(v_exchange_rate,v_invoice.exchange_rate);
        v_exchange_rate_date := COALESCE(v_exchange_rate_date,v_invoice.exchange_rate_date);
        IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 OR v_exchange_rate_date IS NULL THEN RETURN jsonb_build_object('error','exchange_rate_required_for_usd'); END IF;
    END IF;
    INSERT INTO public.finance_payments (tenant_id,invoice_id,amount,paid_at,method,note,bank_reference,currency,exchange_rate,exchange_rate_date,exchange_rate_source,created_by)
    VALUES (p_tenant_id,v_invoice.id,round(v_amount,2),v_paid_at,v_method,NULLIF(trim(p_payload->>'note'),''),NULLIF(trim(p_payload->>'bank_reference'),''),
        v_currency,v_exchange_rate,v_exchange_rate_date,COALESCE(NULLIF(trim(p_payload->>'exchange_rate_source'),''),'manual'),(SELECT auth.uid()))
    RETURNING id INTO v_id;
    v_prepare := COALESCE(NULLIF(p_payload->>'prepare_complement','')::boolean,v_invoice.direction='ar');
    IF v_prepare AND v_invoice.direction='ar' THEN
        INSERT INTO public.billing_payment_complements (tenant_id,finance_invoice_id,finance_payment_id,cfdi_id,invoice_billing_document_id,
            payment_date,method,bank_reference,currency,amount,exchange_rate,exchange_rate_date,amount_mxn,status,notes,created_by)
        SELECT p_tenant_id,v_invoice.id,p.id,v_invoice.linked_cfdi_id,v_invoice.billing_document_id,p.paid_at,p.method,p.bank_reference,p.currency,
            p.amount,p.exchange_rate,p.exchange_rate_date,p.amount_mxn,'ready',p.note,(SELECT auth.uid()) FROM private.fiscal02_legacy_finance_payments p WHERE p.id=v_id
        RETURNING id INTO v_complement_id;
    END IF;
    v_balance := round(v_balance-v_amount,2);
    IF v_balance <= 0 THEN UPDATE public.finance_invoices SET status='paid',paid_at=v_paid_at WHERE id=v_invoice.id; END IF;
    PERFORM public.rpc_write_audit(p_tenant_id,'finance_payment_recorded','finance_payment',v_id,
        jsonb_build_object('invoice_id',v_invoice.id,'amount',v_amount,'currency',v_currency,'remaining_balance',GREATEST(v_balance,0),'complement_id',v_complement_id));
    RETURN jsonb_build_object('id',v_id,'complement_id',v_complement_id,'remaining_balance',GREATEST(v_balance,0),'success',true);
EXCEPTION
    WHEN unique_violation THEN RETURN jsonb_build_object('error','payment_already_registered');
    WHEN check_violation OR foreign_key_violation OR invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload');
    WHEN invalid_parameter_value THEN RETURN jsonb_build_object('error','exchange_rate_required_for_usd');
END;
$function$
;
DO $patch$ DECLARE proc oid:='public.rpc_update_finance_invoice_status(uuid,uuid,text)'::regprocedure; BEGIN
 IF NOT EXISTS(SELECT FROM pg_proc WHERE oid=proc AND md5(pg_temp.multi08_write_source(prosrc))='6d438d851a46fd788f38828102266933' AND prosecdef AND proowner=current_user::regrole AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN RAISE EXCEPTION 'unsupported_multi08_write_body'; END IF;
END $patch$;
CREATE OR REPLACE FUNCTION public.rpc_update_finance_invoice_status(p_tenant_id uuid, p_id uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_invoice public.finance_invoices%ROWTYPE;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant_id::text,7007));
    BEGIN
        IF NOT (private.multi08_legacy_write_target(p_tenant_id,'invoice',p_id)) THEN RETURN jsonb_build_object('error','company_finance_write_pending'); END IF;
    EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;

    SELECT * INTO v_invoice FROM private.fiscal02_legacy_finance_invoices WHERE id=p_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF p_status IN ('paid','overdue') THEN RETURN jsonb_build_object('error','payment_driven_status'); END IF;
    IF p_status='void' THEN RETURN jsonb_build_object('error','void_reason_required'); END IF;
    IF NOT (v_invoice.status='draft' AND p_status='open') THEN RETURN jsonb_build_object('error','invalid_status_transition'); END IF;
    UPDATE public.finance_invoices SET status='open' WHERE id=p_id;
    PERFORM public.rpc_write_audit(p_tenant_id,'finance_invoice_opened','finance_invoice',p_id,'{}'::jsonb);
    RETURN jsonb_build_object('success',true);
EXCEPTION WHEN invalid_parameter_value THEN RETURN jsonb_build_object('error','exchange_rate_required_for_usd');
END;
$function$
;
DO $patch$ DECLARE proc oid:='public.rpc_void_finance_invoice(uuid,uuid,text)'::regprocedure; BEGIN
 IF NOT EXISTS(SELECT FROM pg_proc WHERE oid=proc AND md5(pg_temp.multi08_write_source(prosrc))='458c794e5f3c2df9bfa78db7d465c40c' AND prosecdef AND proowner=current_user::regrole AND proconfig=ARRAY['search_path=pg_catalog, public']) THEN RAISE EXCEPTION 'unsupported_multi08_write_body'; END IF;
END $patch$;
CREATE OR REPLACE FUNCTION public.rpc_void_finance_invoice(p_tenant_id uuid, p_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_invoice public.finance_invoices%ROWTYPE; v_paid numeric; v_credit numeric;
BEGIN
    IF NOT private.f4_user_can_manage_finance(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant_id::text,7007));
    BEGIN
        IF NOT (private.multi08_legacy_write_target(p_tenant_id,'invoice',p_id)) THEN RETURN jsonb_build_object('error','company_finance_write_pending'); END IF;
    EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;

    IF NULLIF(trim(p_reason),'') IS NULL THEN RETURN jsonb_build_object('error','void_reason_required'); END IF;
    SELECT * INTO v_invoice FROM private.fiscal02_legacy_finance_invoices WHERE id=p_id AND tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
    SELECT paid_amount,credit_amount INTO v_paid,v_credit FROM private.f4_invoice_totals(p_id);
    IF v_invoice.status IN ('paid','void') OR v_paid > 0 OR v_credit > 0 THEN RETURN jsonb_build_object('error','invoice_cannot_be_voided'); END IF;
    UPDATE public.finance_invoices SET status='void',voided_at=now(),voided_by=(SELECT auth.uid()),void_reason=trim(p_reason) WHERE id=p_id;
    PERFORM public.rpc_write_audit(p_tenant_id,'finance_invoice_voided','finance_invoice',p_id,jsonb_build_object('reason',trim(p_reason)));
    RETURN jsonb_build_object('success',true);
END;
$function$
;
COMMIT;
