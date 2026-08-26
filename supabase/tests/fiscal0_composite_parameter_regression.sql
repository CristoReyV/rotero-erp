\set ON_ERROR_STOP on
BEGIN;

DO $snapshot_contract$
DECLARE
  tenant uuid;
  customer uuid;
  operation_id uuid;
  cfdi_id uuid;
  cfdi_row public.billing_cfdis%ROWTYPE;
  snapshot jsonb;
  repeated_snapshot jsonb;
  function_source text;
BEGIN
  SELECT prosrc INTO function_source
  FROM pg_proc
  WHERE oid = 'private.fiscal0_snapshot(public.billing_cfdis)'::regprocedure;

  IF function_source IS NULL
     OR function_source LIKE '%p_cfdi.%'
     OR function_source NOT LIKE '%(p_cfdi).cfdi_version%' THEN
    RAISE EXCEPTION 'FISCAL0 snapshot composite access regression';
  END IF;

  INSERT INTO public.tenants(name,slug)
  VALUES('Fiscal0 Composite Contract','fiscal0-composite-contract')
  RETURNING id INTO tenant;
  INSERT INTO public.customers(tenant_id,display_name)
  VALUES(tenant,'Cliente Composite') RETURNING id INTO customer;
  INSERT INTO public.operations(
    tenant_id,reference_code,customer_id,status,execution_type,
    customer_price_amount,provider_cost_amount,pricing_currency
  ) VALUES(
    tenant,'OP-FISCAL0-COMPOSITE',customer,'planned','third_party',1160,700,'MXN'
  ) RETURNING id INTO operation_id;
  INSERT INTO public.billing_cfdis(
    tenant_id,operation_id,serie,folio,rfc_emisor,rfc_receptor,receptor_name,
    subtotal,total,currency,exchange_rate,has_carta_porte,fiscal_input
  ) VALUES(
    tenant,operation_id,'FC','1','AAA010101AAA','BBB010101BBB','Cliente Composite',
    1000,1160,'MXN',1,true,
    jsonb_build_object(
      'issuer',jsonb_build_object('rfc','AAA010101AAA'),
      'receiver',jsonb_build_object('rfc','BBB010101BBB','name','Cliente Composite'),
      'concepts',jsonb_build_array(jsonb_build_object('description','Servicio logístico contratado','amount',1000)),
      'taxes',jsonb_build_array(jsonb_build_object('kind','IVA','amount',160)),
      'payment',jsonb_build_object('method','PUE'),
      'related_cfdis',jsonb_build_array('11111111-1111-4111-8111-111111111111')
    )
  ) RETURNING id INTO cfdi_id;
  INSERT INTO public.billing_carta_porte(
    tenant_id,cfdi_id,trans_type,vehicle_plate,carrier_name,origin,destination,goods_desc
  ) VALUES(
    tenant,cfdi_id,'Autotransporte','ABC123','Proveedor contratado','Monterrey','Querétaro','Carga general'
  );

  SELECT * INTO cfdi_row FROM public.billing_cfdis WHERE id=cfdi_id;
  snapshot := private.fiscal0_snapshot(cfdi_row);
  repeated_snapshot := private.fiscal0_snapshot(cfdi_row);

  IF snapshot IS DISTINCT FROM repeated_snapshot
     OR snapshot->>'schema' <> 'rotero.fiscal-input'
     OR snapshot->>'schema_version' <> '1'
     OR snapshot->>'cfdi_version' <> '4.0'
     OR snapshot->>'billing_cfdi_id' <> cfdi_id::text
     OR snapshot->>'tenant_id' <> tenant::text
     OR snapshot->>'operation_id' <> operation_id::text
     OR snapshot#>>'{issuer,rfc}' <> 'AAA010101AAA'
     OR snapshot#>>'{receiver,rfc}' <> 'BBB010101BBB'
     OR jsonb_array_length(snapshot->'concepts') <> 1
     OR snapshot#>>'{payment,method}' <> 'PUE'
     OR snapshot->>'currency' <> 'MXN'
     OR (snapshot->>'subtotal')::numeric <> 1000
     OR (snapshot->>'total')::numeric <> 1160
     OR snapshot#>>'{carta_porte,transport_type}' <> 'Autotransporte'
     OR snapshot#>>'{carta_porte,origin}' <> 'Monterrey'
     OR snapshot ?| ARRAY['provider','endpoint','credential','secret','token'] THEN
    RAISE EXCEPTION 'FISCAL0 provider-neutral snapshot contract %',snapshot;
  END IF;
END $snapshot_contract$;

ROLLBACK;
