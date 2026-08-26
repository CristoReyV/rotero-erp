\set ON_ERROR_STOP on

DO $staging_shape$
DECLARE
  v_pre_fiscal_columns text[] := ARRAY[
    'id','tenant_id','uuid','serie','folio','rfc_emisor','rfc_receptor','receptor_name','subtotal','total',
    'currency','status','has_carta_porte','has_complemento_pago','issued_at','cancelled_at','pac_provider','notes',
    'created_at','updated_at','exchange_rate','exchange_rate_date','subtotal_mxn','iva_mxn','total_mxn'
  ];
  v_actual_prefix text[];
  v_missing integer;
BEGIN
  IF (SELECT count(*) FROM supabase_migrations.schema_migrations) <> 37
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations) <> '20260902000000' THEN
    RAISE EXCEPTION 'FISCAL0 staging-shape fixture must start from the 37-migration BH2 history';
  END IF;
  SELECT (array_agg(column_name ORDER BY ordinal_position))[1:25] INTO v_actual_prefix
  FROM information_schema.columns WHERE table_schema='public' AND table_name='billing_cfdis';
  IF v_actual_prefix IS DISTINCT FROM v_pre_fiscal_columns
     OR EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='billing_cfdis' AND column_name='operation_id') THEN
    RAISE EXCEPTION 'FISCAL0 fixture is not the exact 25-column staging billing_cfdis shape: %',v_actual_prefix;
  END IF;
  WITH required(table_name,column_name) AS (VALUES
    ('billing_cfdis','id'),('billing_cfdis','tenant_id'),('billing_cfdis','uuid'),('billing_cfdis','rfc_emisor'),
    ('billing_cfdis','rfc_receptor'),('billing_cfdis','receptor_name'),('billing_cfdis','subtotal'),('billing_cfdis','total'),
    ('billing_cfdis','currency'),('billing_cfdis','has_carta_porte'),('billing_cfdis','exchange_rate'),
    ('billing_documents','tenant_id'),('billing_documents','operation_id'),('billing_documents','linked_cfdi_id'),
    ('billing_carta_porte','id'),('billing_carta_porte','cfdi_id'),('billing_carta_porte','trans_type'),
    ('billing_carta_porte','carrier_name'),('billing_carta_porte','vehicle_plate'),('billing_carta_porte','origin'),
    ('billing_carta_porte','destination'),('billing_carta_porte','goods_desc'),
    ('document_files','id'),('document_files','tenant_id'),('document_files','storage_bucket'),
    ('document_files','status'),('document_files','checksum_sha256'),('document_files','file_kind'),('document_files','source_entity_type'),
    ('operations','id'),('operations','tenant_id'),('customers','id'),('customers','tenant_id'),
    ('finance_invoices','id'),('finance_invoices','tenant_id'),
    ('crm_deals','id'),('crm_deals','tenant_id'),('crm_deals','quote_reference'),
    ('logistics_providers','id'),('logistics_providers','tenant_id'),
    ('generated_documents','id'),('generated_documents','tenant_id'),
    ('service_claims','id'),('service_claims','tenant_id')
  )
  SELECT count(*) INTO v_missing FROM required r
  LEFT JOIN information_schema.columns c ON c.table_schema='public' AND c.table_name=r.table_name AND c.column_name=r.column_name
  WHERE c.column_name IS NULL;
  IF v_missing <> 0 THEN RAISE EXCEPTION 'FISCAL0 unresolved staging column references: %',v_missing; END IF;
  IF to_regclass('public.fiscal_requests') IS NULL
     OR to_regclass('public.fiscal_provider_attempts') IS NULL
     OR to_regprocedure('private.fiscal0_snapshot(uuid)') IS NULL
     OR to_regprocedure('private.fiscal0_validate(uuid)') IS NULL THEN
    RAISE EXCEPTION 'FISCAL0 corrected migration did not compile on the BH2 staging shape';
  END IF;
END $staging_shape$;

\ir fiscal0_composite_parameter_regression.sql
