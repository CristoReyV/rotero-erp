\set ON_ERROR_STOP on

BEGIN;

DO $contract$
DECLARE v_signature text; v_oid oid; v_definition text; v_table text;
BEGIN
    FOREACH v_signature IN ARRAY ARRAY[
        'public.rpc_finance_overview(uuid)',
        'public.rpc_finance_overview(uuid,jsonb)',
        'public.rpc_list_finance_invoices(uuid,integer,text,text)',
        'public.rpc_list_finance_invoices(uuid,jsonb)',
        'public.rpc_create_finance_invoice(uuid,jsonb)',
        'public.rpc_record_payment(uuid,jsonb)',
        'public.rpc_update_finance_invoice_status(uuid,uuid,text)',
        'public.rpc_void_finance_invoice(uuid,uuid,text)',
        'public.rpc_get_finance_invoice_detail(uuid,uuid)',
        'public.rpc_list_finance_payments(uuid,jsonb)',
        'public.rpc_list_finance_due_alerts(uuid,jsonb)',
        'public.rpc_get_operation_finance_summary(uuid,uuid)',
        'public.rpc_finance_profitability(uuid,jsonb)',
        'public.rpc_export_finance_ledger(uuid,jsonb)',
        'public.rpc_create_payment_complement(uuid,jsonb)',
        'public.rpc_list_payment_complements(uuid,jsonb)'
    ] LOOP
        v_oid:=to_regprocedure(v_signature);
        IF v_oid IS NULL THEN RAISE EXCEPTION 'F4 CONTRACT FAILED: missing %',v_signature; END IF;
        IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=v_oid AND prosecdef AND proconfig @> ARRAY['search_path=pg_catalog, public']::text[]) THEN
            RAISE EXCEPTION 'F4 CONTRACT FAILED: unsafe function %',v_signature;
        END IF;
        IF NOT has_function_privilege('authenticated',v_oid,'EXECUTE')
           OR has_function_privilege('anon',v_oid,'EXECUTE')
           OR has_function_privilege('service_role',v_oid,'EXECUTE') THEN
            RAISE EXCEPTION 'F4 CONTRACT FAILED: ACL %',v_signature;
        END IF;
    END LOOP;
    FOREACH v_table IN ARRAY ARRAY['finance_invoices','finance_payments','billing_credit_notes','billing_payment_complements'] LOOP
        IF to_regclass('public.'||v_table) IS NULL OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('public.'||v_table) AND relrowsecurity) THEN
            RAISE EXCEPTION 'F4 CONTRACT FAILED: table/RLS %',v_table;
        END IF;
        IF has_table_privilege('authenticated','public.'||v_table,'SELECT,INSERT,UPDATE,DELETE')
           OR has_table_privilege('anon','public.'||v_table,'SELECT,INSERT,UPDATE,DELETE')
           OR has_table_privilege('service_role','public.'||v_table,'SELECT,INSERT,UPDATE,DELETE') THEN
            RAISE EXCEPTION 'F4 CONTRACT FAILED: direct table privilege %',v_table;
        END IF;
    END LOOP;
    v_definition:=pg_get_functiondef('public.rpc_record_payment(uuid,jsonb)'::regprocedure);
    IF v_definition NOT LIKE '%FOR UPDATE%' OR v_definition NOT LIKE '%payment_exceeds_balance%' THEN
        RAISE EXCEPTION 'F4 CONCURRENCY FAILED: payment lock/error boundary absent';
    END IF;
    IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.document_files'::regclass AND conname='document_files_source_type_check' AND pg_get_constraintdef(oid) LIKE '%finance_invoice%') THEN
        RAISE EXCEPTION 'F4 DOCUMENTS FAILED: finance_invoice source contract missing';
    END IF;
END;
$contract$;

DO $fixtures$
DECLARE v_tenant uuid; v_other uuid; v_admin uuid:=gen_random_uuid(); v_finance uuid:=gen_random_uuid(); v_operator uuid:=gen_random_uuid();
    v_customer uuid; v_provider uuid; v_foreign_customer uuid; v_operation uuid; v_credit_invoice uuid;
BEGIN
    INSERT INTO auth.users(instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
      ('00000000-0000-0000-0000-000000000000',v_admin,'authenticated','authenticated','f4-admin@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_finance,'authenticated','authenticated','f4-finance@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_operator,'authenticated','authenticated','f4-operator@example.invalid',now(),'{}','{}',now(),now());
    INSERT INTO public.tenants(name,slug) VALUES('F4 Tenant','f4-tenant'),('F4 Other','f4-other');
    SELECT id INTO v_tenant FROM public.tenants WHERE slug='f4-tenant'; SELECT id INTO v_other FROM public.tenants WHERE slug='f4-other';
    INSERT INTO public.memberships(tenant_id,user_id,role) VALUES(v_tenant,v_admin,'admin'),(v_tenant,v_finance,'finance'),(v_tenant,v_operator,'operator');
    INSERT INTO public.customers(tenant_id,display_name) VALUES(v_tenant,'Cliente Canónico F4') RETURNING id INTO v_customer;
    INSERT INTO public.customers(tenant_id,display_name) VALUES(v_other,'Cliente Foráneo') RETURNING id INTO v_foreign_customer;
    INSERT INTO public.logistics_providers(tenant_id,display_name) VALUES(v_tenant,'Proveedor Canónico F4') RETURNING id INTO v_provider;
    INSERT INTO public.operations(tenant_id,reference_code,customer_id,provider_id,customer_price_amount,provider_cost_amount,pricing_currency,status)
      VALUES(v_tenant,'OP-F4-001',v_customer,v_provider,1000,600,'MXN','planned') RETURNING id INTO v_operation;
    INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,amount,currency,status,due_date,customer_id)
      VALUES(v_tenant,'ar','Cliente Canónico F4',100,'MXN','open',current_date+10,v_customer) RETURNING id INTO v_credit_invoice;
    INSERT INTO public.billing_credit_notes(tenant_id,note_type,customer_id,finance_invoice_id,total,currency,total_mxn,status,reason)
      VALUES(v_tenant,'customer_credit',v_customer,v_credit_invoice,25,'MXN',25,'applied','Ajuste comercial autorizado');
    PERFORM set_config('f4.tenant',v_tenant::text,true); PERFORM set_config('f4.other',v_other::text,true);
    PERFORM set_config('f4.admin',v_admin::text,true); PERFORM set_config('f4.finance',v_finance::text,true); PERFORM set_config('f4.operator',v_operator::text,true);
    PERFORM set_config('f4.customer',v_customer::text,true); PERFORM set_config('f4.foreign_customer',v_foreign_customer::text,true);
    PERFORM set_config('f4.provider',v_provider::text,true); PERFORM set_config('f4.operation',v_operation::text,true);
    PERFORM set_config('f4.credit_invoice',v_credit_invoice::text,true);
END;
$fixtures$;

SET LOCAL ROLE authenticated;

DO $admin$
DECLARE v_tenant uuid:=current_setting('f4.tenant')::uuid; v_operation uuid:=current_setting('f4.operation')::uuid;
    v_result jsonb; v_ar uuid; v_ap uuid; v_general uuid; v_cent uuid; v_void uuid; v_usd uuid; v_payment uuid; v_detail jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f4.admin'),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('f4.admin'),'role','authenticated')::text,true);
    v_detail:=public.rpc_get_finance_invoice_detail(v_tenant,current_setting('f4.credit_invoice')::uuid);
    IF (v_detail#>>'{invoice,credit_amount}')::numeric<>25 OR (v_detail#>>'{invoice,balance_amount}')::numeric<>75 THEN RAISE EXCEPTION 'F4 CREDIT IMPACT FAILED: %',v_detail; END IF;

    v_result:=public.rpc_create_finance_invoice(v_tenant,jsonb_build_object('direction','ar','operation_id',v_operation,'amount',1000,'currency','MXN','status','open','due_date',current_date-2,'counterparty_name','Nombre adulterado'));
    IF v_result?'error' THEN RAISE EXCEPTION 'F4 CREATE FAILED: %',v_result; END IF; v_ar:=(v_result->>'id')::uuid;
    IF (public.rpc_get_finance_invoice_detail(v_tenant,v_ar)#>>'{invoice,counterparty_name}')<>'Cliente Canónico F4' THEN RAISE EXCEPTION 'F4 CANONICAL NAME FAILED'; END IF;
    v_result:=public.rpc_create_finance_invoice(v_tenant,jsonb_build_object('direction','ar','operation_id',v_operation,'amount',0.01,'currency','MXN','status','open'));
    IF v_result->>'error'<>'operation_amount_exceeded' THEN RAISE EXCEPTION 'F4 OVER-REGISTER FAILED: %',v_result; END IF;
    v_result:=public.rpc_create_finance_invoice(v_tenant,jsonb_build_object('direction','ar','operation_id',v_operation,'amount',0.01,'currency','MXN','status','open','over_registration_override',true,'over_registration_reason','Ajuste contractual autorizado'));
    IF v_result?'error' THEN RAISE EXCEPTION 'F4 OVERRIDE FAILED: %',v_result; END IF;
    v_result:=public.rpc_create_finance_invoice(v_tenant,jsonb_build_object('direction','ap','operation_id',v_operation,'amount',600,'currency','MXN','status','open','due_date',current_date+3));
    IF v_result?'error' THEN RAISE EXCEPTION 'F4 AP FAILED: %',v_result; END IF; v_ap:=(v_result->>'id')::uuid;
    v_result:=public.rpc_create_finance_invoice(v_tenant,jsonb_build_object('direction','ar','customer_id',current_setting('f4.foreign_customer'),'amount',10,'currency','MXN'));
    IF v_result->>'error'<>'invalid_customer' THEN RAISE EXCEPTION 'F4 TENANT FAILED: %',v_result; END IF;
    v_result:=public.rpc_create_finance_invoice(v_tenant,jsonb_build_object('direction','ar','counterparty_name','USD Draft','amount',100,'currency','USD','status','open'));
    IF v_result->>'error'<>'exchange_rate_required_for_usd' THEN RAISE EXCEPTION 'F4 FX REQUIRED FAILED: %',v_result; END IF;
    v_result:=public.rpc_create_finance_invoice(v_tenant,jsonb_build_object('direction','ar','counterparty_name','USD Válida','amount',100,'currency','USD','status','open','exchange_rate',18.5,'exchange_rate_date',current_date));
    IF v_result?'error' THEN RAISE EXCEPTION 'F4 USD FAILED: %',v_result; END IF; v_usd:=(v_result->>'id')::uuid;
    IF (public.rpc_get_finance_invoice_detail(v_tenant,v_usd)#>>'{invoice,amount_mxn}')::numeric<>1850 THEN RAISE EXCEPTION 'F4 FX CALC FAILED'; END IF;

    v_result:=public.rpc_create_finance_invoice(v_tenant,jsonb_build_object('direction','ar','counterparty_name','Parciales','amount',100,'currency','MXN','status','open'));
    v_general:=(v_result->>'id')::uuid;
    v_result:=public.rpc_record_payment(v_tenant,jsonb_build_object('invoice_id',v_general,'amount',40,'method','transfer','prepare_complement',true));
    IF v_result?'error' OR (v_result->>'remaining_balance')::numeric<>60 OR v_result->>'complement_id' IS NULL THEN RAISE EXCEPTION 'F4 PARTIAL 1 FAILED: %',v_result; END IF;
    v_payment:=(v_result->>'id')::uuid;
    v_result:=public.rpc_record_payment(v_tenant,jsonb_build_object('invoice_id',v_general,'amount',60,'method','card'));
    IF v_result?'error' OR (v_result->>'remaining_balance')::numeric<>0 THEN RAISE EXCEPTION 'F4 EXACT SETTLEMENT FAILED: %',v_result; END IF;
    v_detail:=public.rpc_get_finance_invoice_detail(v_tenant,v_general);
    IF v_detail#>>'{invoice,effective_status}'<>'paid' OR (v_detail#>>'{invoice,balance_amount}')::numeric<>0 OR jsonb_array_length(v_detail->'payments')<>2 THEN RAISE EXCEPTION 'F4 DETAIL FAILED: %',v_detail; END IF;
    IF public.rpc_record_payment(v_tenant,jsonb_build_object('invoice_id',v_general,'amount',0.01))->>'error'<>'invoice_already_settled' THEN RAISE EXCEPTION 'F4 SETTLED REJECTION FAILED'; END IF;
    IF public.rpc_create_payment_complement(v_tenant,jsonb_build_object('finance_payment_id',v_payment))->>'error'<>'complement_already_exists' THEN RAISE EXCEPTION 'F4 COMPLEMENT DUPLICATE FAILED'; END IF;

    v_result:=public.rpc_create_finance_invoice(v_tenant,jsonb_build_object('direction','ap','counterparty_name','Centavo','amount',100,'currency','MXN','status','open'));
    v_cent:=(v_result->>'id')::uuid;
    v_result:=public.rpc_record_payment(v_tenant,jsonb_build_object('invoice_id',v_cent,'amount',99.99,'method','cash'));
    IF (v_result->>'remaining_balance')::numeric<>0.01 THEN RAISE EXCEPTION 'F4 CENT SETUP FAILED: %',v_result; END IF;
    v_result:=public.rpc_record_payment(v_tenant,jsonb_build_object('invoice_id',v_cent,'amount',0.02));
    IF v_result->>'error'<>'payment_exceeds_balance' THEN RAISE EXCEPTION 'F4 CENT OVERPAY FAILED: %',v_result; END IF;
    v_result:=public.rpc_record_payment(v_tenant,jsonb_build_object('invoice_id',v_cent,'amount',0.01));
    IF v_result?'error' THEN RAISE EXCEPTION 'F4 CENT EXACT FAILED: %',v_result; END IF;

    v_result:=public.rpc_create_finance_invoice(v_tenant,jsonb_build_object('direction','ap','counterparty_name','Anulable','amount',25,'currency','MXN','status','open'));
    v_void:=(v_result->>'id')::uuid;
    IF public.rpc_update_finance_invoice_status(v_tenant,v_void,'paid')->>'error'<>'payment_driven_status' THEN RAISE EXCEPTION 'F4 MANUAL PAID FAILED'; END IF;
    IF public.rpc_void_finance_invoice(v_tenant,v_void,'') ->>'error'<>'void_reason_required' THEN RAISE EXCEPTION 'F4 VOID REASON FAILED'; END IF;
    IF public.rpc_void_finance_invoice(v_tenant,v_void,'Captura duplicada')->>'success'<>'true' THEN RAISE EXCEPTION 'F4 VOID FAILED'; END IF;
    IF public.rpc_record_payment(v_tenant,jsonb_build_object('invoice_id',v_void,'amount',1))->>'error'<>'invoice_not_payable' THEN RAISE EXCEPTION 'F4 VOID PAYMENT FAILED'; END IF;

    IF jsonb_array_length(public.rpc_list_finance_due_alerts(v_tenant,jsonb_build_object('days_ahead',7))->'items')<2 THEN RAISE EXCEPTION 'F4 DUE AR/AP FAILED'; END IF;
    IF jsonb_array_length(public.rpc_list_finance_payments(v_tenant,'{}')->'items')<4 THEN RAISE EXCEPTION 'F4 PAYMENT ACTIVITY FAILED'; END IF;
    IF jsonb_array_length(public.rpc_finance_profitability(v_tenant,'{}')->'operations')<>1 THEN RAISE EXCEPTION 'F4 PROFITABILITY FAILED'; END IF;
    IF jsonb_array_length(public.rpc_export_finance_ledger(v_tenant,'{}'::jsonb))<1 THEN RAISE EXCEPTION 'F4 EXPORT FAILED'; END IF;
    IF NOT private.f3_entity_belongs_to_tenant(v_tenant,'finance_invoice',v_ar) THEN RAISE EXCEPTION 'F4 DOCUMENT ENTITY FAILED'; END IF;
    IF public.rpc_finance_overview(v_tenant)?'error' THEN RAISE EXCEPTION 'F4 OVERVIEW FAILED'; END IF;
END;
$admin$;

DO $rbac$
DECLARE v_tenant uuid:=current_setting('f4.tenant')::uuid; v_result jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub',current_setting('f4.finance'),true);
    v_result:=public.rpc_list_finance_invoices(v_tenant,'{}'::jsonb);
    IF v_result?'error' THEN RAISE EXCEPTION 'F4 FINANCE ACCESS FAILED: %',v_result; END IF;
    PERFORM set_config('request.jwt.claim.sub',current_setting('f4.operator'),true);
    IF public.rpc_finance_overview(v_tenant)->>'error'<>'unauthorized' OR public.rpc_create_finance_invoice(v_tenant,'{}')->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'F4 OPERATOR DENIAL FAILED'; END IF;
    PERFORM set_config('request.jwt.claim.sub','',true);
    IF public.rpc_list_finance_invoices(v_tenant,'{}'::jsonb)->>'error'<>'unauthorized' THEN RAISE EXCEPTION 'F4 ANON CONTEXT FAILED'; END IF;
END;
$rbac$;

RESET ROLE;
ROLLBACK;
