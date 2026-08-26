\set ON_ERROR_STOP on
BEGIN;

DO $snapshot_contract$
DECLARE
  tenant uuid;
  customer uuid;
  operation_one uuid;
  operation_two uuid;
  cfdi_none uuid;
  cfdi_one uuid;
  cfdi_null uuid;
  cfdi_same uuid;
  cfdi_ambiguous uuid;
  snapshot jsonb;
  repeated_snapshot jsonb;
  validation jsonb;
  function_source text;
  input_payload jsonb := jsonb_build_object(
    'issuer',jsonb_build_object('rfc','AAA010101AAA'),
    'receiver',jsonb_build_object('rfc','BBB010101BBB','name','Cliente Fiscal'),
    'concepts',jsonb_build_array(jsonb_build_object('description','Servicio logístico contratado','amount',1000)),
    'taxes',jsonb_build_array(jsonb_build_object('kind','IVA','amount',160)),
    'payment',jsonb_build_object('method','PUE')
  );
BEGIN
  SELECT prosrc INTO function_source FROM pg_proc
  WHERE oid = 'private.fiscal0_snapshot(uuid)'::regprocedure;
  IF function_source IS NULL OR function_source !~ 'billing_documents'
     OR function_source !~ 'linked_cfdi_id' OR function_source ~ 'p_cfdi[.]operation_id'
     OR to_regprocedure('private.fiscal0_snapshot(public.billing_cfdis)') IS NOT NULL
     OR to_regprocedure('private.fiscal0_validate(public.billing_cfdis)') IS NOT NULL THEN
    RAISE EXCEPTION 'FISCAL0 UUID helper / Billing bridge regression';
  END IF;

  INSERT INTO public.tenants(name,slug) VALUES('Fiscal0 Relation Contract','fiscal0-relation-contract') RETURNING id INTO tenant;
  INSERT INTO public.customers(tenant_id,display_name) VALUES(tenant,'Cliente Fiscal') RETURNING id INTO customer;
  INSERT INTO public.operations(tenant_id,reference_code,customer_id,status,execution_type,customer_price_amount,provider_cost_amount,pricing_currency)
  VALUES (tenant,'OP-FISCAL0-ONE',customer,'planned','third_party',1160,700,'MXN'),
         (tenant,'OP-FISCAL0-TWO',customer,'planned','third_party',1160,700,'MXN');
  SELECT id INTO operation_one FROM public.operations WHERE tenant_id=tenant AND reference_code='OP-FISCAL0-ONE';
  SELECT id INTO operation_two FROM public.operations WHERE tenant_id=tenant AND reference_code='OP-FISCAL0-TWO';

  INSERT INTO public.billing_cfdis(tenant_id,uuid,serie,folio,rfc_emisor,rfc_receptor,receptor_name,subtotal,total,currency,exchange_rate,has_carta_porte,fiscal_input)
  SELECT tenant,gen_random_uuid()::text,'FR',folio,'AAA010101AAA','BBB010101BBB','Cliente Fiscal',1000,1160,'MXN',1,folio='ONE',input_payload
  FROM unnest(ARRAY['NONE','ONE','NULL','SAME','AMBIGUOUS']) AS folio;
  SELECT id INTO cfdi_none FROM public.billing_cfdis WHERE tenant_id=tenant AND folio='NONE';
  SELECT id INTO cfdi_one FROM public.billing_cfdis WHERE tenant_id=tenant AND folio='ONE';
  SELECT id INTO cfdi_null FROM public.billing_cfdis WHERE tenant_id=tenant AND folio='NULL';
  SELECT id INTO cfdi_same FROM public.billing_cfdis WHERE tenant_id=tenant AND folio='SAME';
  SELECT id INTO cfdi_ambiguous FROM public.billing_cfdis WHERE tenant_id=tenant AND folio='AMBIGUOUS';

  INSERT INTO public.billing_documents(tenant_id,operation_id,linked_cfdi_id,status) VALUES
    (tenant,operation_one,cfdi_one,'stamped'),(tenant,NULL,cfdi_null,'stamped'),
    (tenant,operation_one,cfdi_same,'stamped'),(tenant,operation_one,cfdi_same,'stamped'),
    (tenant,operation_one,cfdi_ambiguous,'stamped'),(tenant,operation_two,cfdi_ambiguous,'stamped');
  INSERT INTO public.billing_carta_porte(tenant_id,cfdi_id,trans_type,vehicle_plate,carrier_name,origin,destination,goods_desc)
  VALUES(tenant,cfdi_one,'Autotransporte','ABC123','Proveedor contratado','Monterrey','Querétaro','Carga general');

  validation := private.fiscal0_validate(cfdi_none);
  IF (validation->>'valid')::boolean OR NOT (validation->'missing_fields' ? 'invoice_relation') THEN
    RAISE EXCEPTION 'FISCAL0 no-document relation contract %',validation;
  END IF;

  snapshot := private.fiscal0_snapshot(cfdi_one);
  repeated_snapshot := private.fiscal0_snapshot(cfdi_one);
  IF private.fiscal0_validate(cfdi_one)->>'valid' <> 'true' OR snapshot IS DISTINCT FROM repeated_snapshot
     OR snapshot->>'schema' <> 'rotero.fiscal-input' OR snapshot->>'schema_version' <> '1'
     OR snapshot->>'cfdi_version' <> '4.0' OR snapshot->>'billing_cfdi_id' <> cfdi_one::text
     OR snapshot->>'tenant_id' <> tenant::text OR snapshot->>'operation_id' <> operation_one::text
     OR snapshot#>>'{issuer,rfc}' <> 'AAA010101AAA' OR snapshot#>>'{receiver,rfc}' <> 'BBB010101BBB'
     OR jsonb_array_length(snapshot->'concepts') <> 1 OR snapshot#>>'{payment,method}' <> 'PUE'
     OR snapshot->>'currency' <> 'MXN' OR (snapshot->>'subtotal')::numeric <> 1000 OR (snapshot->>'total')::numeric <> 1160
     OR snapshot#>>'{carta_porte,transport_type}' <> 'Autotransporte' OR snapshot#>>'{carta_porte,origin}' <> 'Monterrey'
     OR snapshot ?| ARRAY['provider','endpoint','credential','secret','token'] THEN
    RAISE EXCEPTION 'FISCAL0 provider-neutral snapshot contract';
  END IF;

  snapshot := private.fiscal0_snapshot(cfdi_null);
  IF private.fiscal0_validate(cfdi_null)->>'valid' <> 'true' OR snapshot ? 'operation_id' THEN
    RAISE EXCEPTION 'FISCAL0 linked document without operation contract';
  END IF;
  snapshot := private.fiscal0_snapshot(cfdi_same);
  IF private.fiscal0_validate(cfdi_same)->>'valid' <> 'true' OR snapshot->>'operation_id' <> operation_one::text THEN
    RAISE EXCEPTION 'FISCAL0 same-operation cardinality contract';
  END IF;

  validation := private.fiscal0_validate(cfdi_ambiguous);
  IF (validation->>'valid')::boolean OR NOT (validation->'missing_fields' ? 'ambiguous_operation_relation') THEN
    RAISE EXCEPTION 'FISCAL0 ambiguous relation validation contract %',validation;
  END IF;
  BEGIN
    PERFORM private.fiscal0_snapshot(cfdi_ambiguous);
    RAISE EXCEPTION 'FISCAL0 ambiguous snapshot was not blocked';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM <> 'ambiguous_operation_relation' THEN RAISE; END IF;
  END;
END $snapshot_contract$;

ROLLBACK;
