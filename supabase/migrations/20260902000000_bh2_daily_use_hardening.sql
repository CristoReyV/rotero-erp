-- BH2: bounded Partner360 histories, deterministic partner contacts and
-- tenant-aware business dates. Forward-only; no historical data is deleted.

CREATE TEMP TABLE bh2_rpc_snapshot AS
SELECT p.oid AS function_oid,p.oid::regprocedure::text AS identity,
  jsonb_build_object(
    'arguments',pg_get_function_arguments(p.oid),
    'arg_names',to_jsonb(p.proargnames),
    'arg_modes',to_jsonb(p.proargmodes),
    'all_arg_types',to_jsonb(p.proallargtypes),
    'defaults',p.pronargdefaults,
    'result',pg_get_function_result(p.oid),
    'security_definer',p.prosecdef,
    'search_path',to_jsonb(p.proconfig)
  ) AS contract
FROM pg_catalog.pg_proc p
WHERE p.oid=ANY(ARRAY[
  'public.rpc_upsert_business_contact(uuid,uuid,jsonb)'::regprocedure,
  'public.rpc_get_customer_partner_360(uuid)'::regprocedure,
  'public.rpc_get_provider_360(uuid)'::regprocedure,
  'public.rpc_get_partner_compliance_bundle(uuid,text,uuid)'::regprocedure,
  'public.rpc_get_rate_360(uuid)'::regprocedure,
  'public.rpc_get_service_claim(uuid)'::regprocedure
]);

CREATE OR REPLACE FUNCTION private.bh2_tenant_timezone(p_tenant_id uuid)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_timezone text;
BEGIN
  SELECT NULLIF(btrim(s.timezone),'') INTO v_timezone
  FROM public.tenant_settings s WHERE s.tenant_id=p_tenant_id;
  v_timezone:=COALESCE(v_timezone,'America/Mexico_City');
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name=v_timezone) THEN
    v_timezone:='America/Mexico_City';
  END IF;
  RETURN v_timezone;
END;
$function$;

CREATE OR REPLACE FUNCTION private.bh2_business_date(p_tenant_id uuid,p_at timestamptz DEFAULT now())
RETURNS date
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public
AS $function$
  SELECT (p_at AT TIME ZONE private.bh2_tenant_timezone(p_tenant_id))::date;
$function$;

CREATE OR REPLACE FUNCTION private.bh2_partner_primary_contact(
  p_tenant_id uuid,p_entity_type text,p_entity_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_contact jsonb;
BEGIN
  SELECT to_jsonb(x)||jsonb_build_object('source','structured') INTO v_contact
  FROM (
    SELECT c.id,c.name,c.contact_role,c.email,c.phone,c.is_primary,c.is_active,c.notes
    FROM public.business_contacts c
    WHERE c.tenant_id=p_tenant_id AND c.is_active
      AND ((p_entity_type='customer' AND c.customer_id=p_entity_id)
        OR (p_entity_type='provider' AND c.provider_id=p_entity_id))
    ORDER BY c.is_primary DESC,c.created_at,c.id LIMIT 1
  ) x;
  IF v_contact IS NOT NULL THEN RETURN v_contact; END IF;
  IF p_entity_type='customer' THEN
    SELECT CASE WHEN num_nonnulls(NULLIF(btrim(c.contact_name),''),NULLIF(btrim(c.contact_email),''),NULLIF(btrim(c.contact_phone),''))=0 THEN NULL
      ELSE jsonb_build_object('id',NULL,'name',c.contact_name,'contact_role','commercial','email',c.contact_email,'phone',c.contact_phone,'is_primary',true,'is_active',true,'notes',NULL,'source','canonical_fallback') END
    INTO v_contact FROM public.customers c WHERE c.tenant_id=p_tenant_id AND c.id=p_entity_id;
  ELSIF p_entity_type='provider' THEN
    SELECT CASE WHEN num_nonnulls(NULLIF(btrim(p.contact_name),''),NULLIF(btrim(p.contact_email),''),NULLIF(btrim(p.contact_phone),''))=0 THEN NULL
      ELSE jsonb_build_object('id',NULL,'name',p.contact_name,'contact_role','operations','email',p.contact_email,'phone',p.contact_phone,'is_primary',true,'is_active',true,'notes',NULL,'source','canonical_fallback') END
    INTO v_contact FROM public.logistics_providers p WHERE p.tenant_id=p_tenant_id AND p.id=p_entity_id;
  END IF;
  RETURN v_contact;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_upsert_business_contact(p_tenant_id uuid,p_contact_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE
  v_id uuid; v_customer uuid; v_provider uuid; v_existing public.business_contacts%ROWTYPE;
  v_primary boolean; v_active boolean; v_promote uuid; v_selected public.business_contacts%ROWTYPE;
BEGIN
  IF NOT private.f8_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  IF jsonb_typeof(COALESCE(p_payload,'null'::jsonb))<>'object' THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
  BEGIN
    v_customer:=NULLIF(p_payload->>'customer_id','')::uuid;
    v_provider:=NULLIF(p_payload->>'provider_id','')::uuid;
    v_primary:=COALESCE((p_payload->>'is_primary')::boolean,false);
    v_active:=COALESCE((p_payload->>'is_active')::boolean,true);
  EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;
  IF (v_customer IS NOT NULL)::integer+(v_provider IS NOT NULL)::integer<>1
     OR NULLIF(btrim(p_payload->>'name'),'') IS NULL
     OR p_payload->>'contact_role' NOT IN ('commercial','operations','billing','management','other') THEN
    RETURN jsonb_build_object('error','invalid_payload');
  END IF;
  IF v_customer IS NOT NULL THEN
    PERFORM 1 FROM public.customers c WHERE c.id=v_customer AND c.tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error','invalid_customer'); END IF;
  ELSE
    PERFORM 1 FROM public.logistics_providers p WHERE p.id=v_provider AND p.tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error','invalid_provider'); END IF;
  END IF;
  IF p_contact_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.business_contacts c WHERE c.id=p_contact_id AND c.tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND OR v_existing.customer_id IS DISTINCT FROM v_customer OR v_existing.provider_id IS DISTINCT FROM v_provider THEN
      RETURN jsonb_build_object('error','not_found');
    END IF;
    IF NOT p_payload?'is_active' THEN v_active:=v_existing.is_active; END IF;
    IF NOT p_payload?'is_primary' THEN v_primary:=v_existing.is_primary; END IF;
  END IF;
  IF v_active AND NOT v_primary AND NOT EXISTS(
    SELECT 1 FROM public.business_contacts c WHERE c.tenant_id=p_tenant_id AND c.is_active AND c.is_primary
      AND c.id IS DISTINCT FROM p_contact_id AND (c.customer_id=v_customer OR c.provider_id=v_provider)
  ) THEN v_primary:=true; END IF;
  IF v_primary AND v_active THEN
    UPDATE public.business_contacts SET is_primary=false,updated_at=now()
    WHERE tenant_id=p_tenant_id AND is_active AND id IS DISTINCT FROM p_contact_id
      AND (customer_id=v_customer OR provider_id=v_provider);
  ELSE v_primary:=false;
  END IF;
  IF p_contact_id IS NULL THEN
    INSERT INTO public.business_contacts(tenant_id,customer_id,provider_id,name,contact_role,email,phone,is_primary,is_active,notes,created_by)
    VALUES(p_tenant_id,v_customer,v_provider,btrim(p_payload->>'name'),p_payload->>'contact_role',NULLIF(btrim(p_payload->>'email'),''),NULLIF(btrim(p_payload->>'phone'),''),v_primary,v_active,NULLIF(btrim(p_payload->>'notes'),''),auth.uid())
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.business_contacts SET name=btrim(p_payload->>'name'),contact_role=p_payload->>'contact_role',
      email=NULLIF(btrim(p_payload->>'email'),''),phone=NULLIF(btrim(p_payload->>'phone'),''),is_primary=v_primary,is_active=v_active,
      notes=NULLIF(btrim(p_payload->>'notes'),''),updated_at=now()
    WHERE id=p_contact_id RETURNING id INTO v_id;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.business_contacts c WHERE c.tenant_id=p_tenant_id AND c.is_active AND c.is_primary AND (c.customer_id=v_customer OR c.provider_id=v_provider)) THEN
    SELECT c.id INTO v_promote FROM public.business_contacts c
    WHERE c.tenant_id=p_tenant_id AND c.is_active AND (c.customer_id=v_customer OR c.provider_id=v_provider)
    ORDER BY c.created_at,c.id LIMIT 1;
    IF v_promote IS NOT NULL THEN UPDATE public.business_contacts SET is_primary=true,updated_at=now() WHERE id=v_promote; END IF;
  END IF;
  SELECT * INTO v_selected FROM public.business_contacts c
  WHERE c.tenant_id=p_tenant_id AND c.is_active AND c.is_primary AND (c.customer_id=v_customer OR c.provider_id=v_provider);
  IF FOUND THEN
    IF v_customer IS NOT NULL THEN
      UPDATE public.customers SET contact_name=v_selected.name,contact_email=v_selected.email,contact_phone=v_selected.phone,updated_at=now()
      WHERE id=v_customer AND tenant_id=p_tenant_id;
    ELSE
      UPDATE public.logistics_providers SET contact_name=v_selected.name,contact_email=v_selected.email,contact_phone=v_selected.phone,updated_at=now()
      WHERE id=v_provider AND tenant_id=p_tenant_id;
    END IF;
  END IF;
  INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id)
  VALUES(p_tenant_id,auth.uid(),'partner_contact_upserted','business_contact',v_id);
  RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN unique_violation OR check_violation OR not_null_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE INDEX IF NOT EXISTS crm_deals_partner_history_idx ON public.crm_deals(tenant_id,customer_id,created_at DESC,id DESC) WHERE quote_reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS operations_customer_history_idx ON public.operations(tenant_id,customer_id,created_at DESC,id DESC) WHERE customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS operations_provider_history_idx ON public.operations(tenant_id,provider_id,created_at DESC,id DESC) WHERE provider_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS rate_cards_customer_history_idx ON public.commercial_rate_cards(tenant_id,customer_id,created_at DESC,id DESC) WHERE customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS rate_cards_provider_history_idx ON public.commercial_rate_cards(tenant_id,provider_id,created_at DESC,id DESC) WHERE provider_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.rpc_list_partner_history_page(
  p_tenant_id uuid,p_entity_type text,p_entity_id uuid,p_history_type text,p_cursor jsonb DEFAULT NULL,p_limit integer DEFAULT 25
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE
  v_limit integer:=LEAST(GREATEST(COALESCE(p_limit,25),1),100); v_at timestamptz:='infinity'; v_id uuid:='ffffffff-ffff-ffff-ffff-ffffffffffff';
  v_raw jsonb:='[]'::jsonb; v_items jsonb:='[]'::jsonb; v_more boolean:=false; v_last jsonb;
BEGIN
  IF NOT private.f8_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  IF p_entity_type NOT IN ('customer','provider') OR p_history_type NOT IN ('quotes','operations','rates','activity','compliance','contracts','claims') THEN RETURN jsonb_build_object('error','invalid_history'); END IF;
  IF (p_entity_type='customer' AND NOT EXISTS(SELECT 1 FROM public.customers c WHERE c.tenant_id=p_tenant_id AND c.id=p_entity_id))
    OR (p_entity_type='provider' AND NOT EXISTS(SELECT 1 FROM public.logistics_providers p WHERE p.tenant_id=p_tenant_id AND p.id=p_entity_id)) THEN RETURN jsonb_build_object('error','not_found'); END IF;
  IF p_entity_type='provider' AND p_history_type='quotes' THEN RETURN jsonb_build_object('error','invalid_history'); END IF;
  IF p_cursor IS NOT NULL THEN
    IF jsonb_typeof(p_cursor)<>'object' OR p_cursor->>'tenant_id' IS DISTINCT FROM p_tenant_id::text OR p_cursor->>'entity_type' IS DISTINCT FROM p_entity_type OR p_cursor->>'entity_id' IS DISTINCT FROM p_entity_id::text OR p_cursor->>'history_type' IS DISTINCT FROM p_history_type THEN RETURN jsonb_build_object('error','invalid_cursor'); END IF;
    BEGIN v_at:=(p_cursor->>'sort_at')::timestamptz;v_id:=(p_cursor->>'id')::uuid; EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow THEN RETURN jsonb_build_object('error','invalid_cursor'); END;
  END IF;
  IF p_history_type='quotes' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.sort_at DESC,x.id DESC),'[]'::jsonb) INTO v_raw FROM (
      SELECT d.id,d.quote_reference,d.title,d.quote_status AS status,d.currency,d.value,d.created_at AS sort_at
      FROM public.crm_deals d WHERE d.tenant_id=p_tenant_id AND d.customer_id=p_entity_id AND d.quote_reference IS NOT NULL AND (d.created_at,d.id)<(v_at,v_id)
      ORDER BY d.created_at DESC,d.id DESC LIMIT v_limit+1) x;
  ELSIF p_history_type='operations' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.sort_at DESC,x.id DESC),'[]'::jsonb) INTO v_raw FROM (
      SELECT o.id,o.reference_code AS reference,o.status,o.execution_type,o.planned_departure,o.created_at AS sort_at
      FROM public.operations o WHERE o.tenant_id=p_tenant_id AND ((p_entity_type='customer' AND o.customer_id=p_entity_id) OR (p_entity_type='provider' AND o.provider_id=p_entity_id)) AND (o.created_at,o.id)<(v_at,v_id)
      ORDER BY o.created_at DESC,o.id DESC LIMIT v_limit+1) x;
  ELSIF p_history_type='rates' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.sort_at DESC,x.id DESC),'[]'::jsonb) INTO v_raw FROM (
      SELECT r.id,r.reference,r.status,r.rate_type,v.currency,v.valid_to,private.f8_rate_total(v.id) AS total_amount,r.created_at AS sort_at
      FROM public.commercial_rate_cards r JOIN public.commercial_rate_versions v ON v.id=r.current_version_id
      WHERE r.tenant_id=p_tenant_id AND ((p_entity_type='customer' AND r.customer_id=p_entity_id) OR (p_entity_type='provider' AND r.provider_id=p_entity_id)) AND (r.created_at,r.id)<(v_at,v_id)
      ORDER BY r.created_at DESC,r.id DESC LIMIT v_limit+1) x;
  ELSIF p_history_type='activity' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.sort_at DESC,x.id DESC),'[]'::jsonb) INTO v_raw FROM (
      SELECT a.id,a.action,a.entity_type,a.entity_id,a.created_at AS sort_at FROM public.audit_log a
      WHERE a.tenant_id=p_tenant_id AND (a.entity_id=p_entity_id OR (p_entity_type='customer' AND a.entity_id IN(SELECT d.id FROM public.crm_deals d WHERE d.customer_id=p_entity_id)) OR a.entity_id IN(SELECT o.id FROM public.operations o WHERE (p_entity_type='customer' AND o.customer_id=p_entity_id) OR (p_entity_type='provider' AND o.provider_id=p_entity_id))) AND (a.created_at,a.id)<(v_at,v_id)
      ORDER BY a.created_at DESC,a.id DESC LIMIT v_limit+1) x;
  ELSIF p_history_type='compliance' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.sort_at DESC,x.id DESC),'[]'::jsonb) INTO v_raw FROM (
      SELECT r.id,r.requirement_id,q.name AS requirement_name,r.document_file_id,f.file_name,r.review_status,private.f9_record_status(r.review_status,r.valid_to,q.warning_days,r.waiver_until,private.bh2_business_date(p_tenant_id)) AS derived_status,r.valid_from,r.valid_to,r.waiver_until,r.review_note,r.created_at AS sort_at
      FROM public.partner_compliance_records r JOIN public.partner_compliance_requirements q ON q.id=r.requirement_id LEFT JOIN public.document_files f ON f.id=r.document_file_id
      WHERE r.tenant_id=p_tenant_id AND ((p_entity_type='customer' AND r.customer_id=p_entity_id) OR (p_entity_type='provider' AND r.provider_id=p_entity_id)) AND (r.created_at,r.id)<(v_at,v_id)
      ORDER BY r.created_at DESC,r.id DESC LIMIT v_limit+1) x;
  ELSIF p_history_type='contracts' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.sort_at DESC,x.id DESC),'[]'::jsonb) INTO v_raw FROM (
      SELECT c.id,c.contract_type,c.title,c.reference,c.document_file_id,f.file_name,c.responsible_contact_id,c.starts_on,c.ends_on,c.notice_days,c.status,private.f9_contract_status(c.status,c.ends_on,c.notice_days,private.bh2_business_date(p_tenant_id)) AS derived_status,c.renewed_from_id,c.notes,c.created_at AS sort_at
      FROM public.partner_contracts c LEFT JOIN public.document_files f ON f.id=c.document_file_id
      WHERE c.tenant_id=p_tenant_id AND ((p_entity_type='customer' AND c.customer_id=p_entity_id) OR (p_entity_type='provider' AND c.provider_id=p_entity_id)) AND (c.created_at,c.id)<(v_at,v_id)
      ORDER BY c.created_at DESC,c.id DESC LIMIT v_limit+1) x;
  ELSE
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.sort_at DESC,x.id DESC),'[]'::jsonb) INTO v_raw FROM (
      SELECT c.id,c.claim_number,c.claim_type,c.priority,c.status,c.subject,c.responsibility,c.reported_at AS sort_at,private.f10_sla(c,now()) AS sla,
        COALESCE((SELECT jsonb_agg(jsonb_build_object('currency',e.currency,'amount',e.amount) ORDER BY e.currency) FROM (SELECT f.currency,sum(f.amount) amount FROM public.service_claim_financials f WHERE f.claim_id=c.id AND f.status<>'cancelled' GROUP BY f.currency)e),'[]'::jsonb) exposure_by_currency
      FROM public.service_claims c WHERE c.tenant_id=p_tenant_id AND ((p_entity_type='customer' AND c.customer_id=p_entity_id) OR (p_entity_type='provider' AND c.provider_id=p_entity_id)) AND (c.reported_at,c.id)<(v_at,v_id)
      ORDER BY c.reported_at DESC,c.id DESC LIMIT v_limit+1) x;
  END IF;
  v_more:=jsonb_array_length(v_raw)>v_limit;
  SELECT COALESCE(jsonb_agg(value ORDER BY ordinality),'[]'::jsonb) INTO v_items FROM jsonb_array_elements(v_raw) WITH ORDINALITY WHERE ordinality<=v_limit;
  IF v_more THEN
    v_last:=v_items->(jsonb_array_length(v_items)-1);
    RETURN jsonb_build_object('items',v_items,'has_more',true,'next_cursor',jsonb_build_object('tenant_id',p_tenant_id,'entity_type',p_entity_type,'entity_id',p_entity_id,'history_type',p_history_type,'sort_at',v_last->>'sort_at','id',v_last->>'id'));
  END IF;
  RETURN jsonb_build_object('items',v_items,'has_more',false,'next_cursor',NULL);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_customer_partner_360(p_customer_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE c public.customers%ROWTYPE;v_primary jsonb;v_date date;
BEGIN
  SELECT * INTO c FROM public.customers WHERE id=p_customer_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
  IF NOT private.f8_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  v_primary:=private.bh2_partner_primary_contact(c.tenant_id,'customer',c.id);v_date:=private.bh2_business_date(c.tenant_id);
  RETURN jsonb_build_object('customer',to_jsonb(c),'primary_contact',v_primary,
    'contacts',CASE WHEN EXISTS(SELECT 1 FROM public.business_contacts x WHERE x.tenant_id=c.tenant_id AND x.customer_id=c.id AND x.is_active) THEN COALESCE((SELECT jsonb_agg(to_jsonb(x)||jsonb_build_object('source','structured') ORDER BY x.is_primary DESC,x.name,x.id) FROM public.business_contacts x WHERE x.tenant_id=c.tenant_id AND x.customer_id=c.id AND x.is_active),'[]'::jsonb) ELSE CASE WHEN v_primary IS NULL THEN '[]'::jsonb ELSE jsonb_build_array(v_primary) END END,
    'history_counts',jsonb_build_object('quotes',(SELECT count(*) FROM public.crm_deals d WHERE d.tenant_id=c.tenant_id AND d.customer_id=c.id AND d.quote_reference IS NOT NULL),'operations',(SELECT count(*) FROM public.operations o WHERE o.tenant_id=c.tenant_id AND o.customer_id=c.id),'rates',(SELECT count(*) FROM public.commercial_rate_cards r WHERE r.tenant_id=c.tenant_id AND r.customer_id=c.id),'activity',(SELECT count(*) FROM public.audit_log a WHERE a.tenant_id=c.tenant_id AND (a.entity_id=c.id OR a.entity_id IN(SELECT d.id FROM public.crm_deals d WHERE d.customer_id=c.id) OR a.entity_id IN(SELECT o.id FROM public.operations o WHERE o.customer_id=c.id))),'compliance',(SELECT count(*) FROM public.partner_compliance_records r WHERE r.tenant_id=c.tenant_id AND r.customer_id=c.id),'contracts',(SELECT count(*) FROM public.partner_contracts k WHERE k.tenant_id=c.tenant_id AND k.customer_id=c.id),'claims',(SELECT count(*) FROM public.service_claims s WHERE s.tenant_id=c.tenant_id AND s.customer_id=c.id),'documents',(SELECT count(*) FROM public.document_relations dr WHERE dr.tenant_id=c.tenant_id AND ((dr.source_entity_type='customer' AND dr.source_entity_id=c.id) OR (dr.target_entity_type='customer' AND dr.target_entity_id=c.id)))),
    'quotes','[]'::jsonb,'operations','[]'::jsonb,'rates','[]'::jsonb,'activity','[]'::jsonb,
    'profitability',COALESCE((SELECT jsonb_agg(jsonb_build_object('currency',q.pricing_currency,'sell',q.sell,'cost',q.cost,'expected_margin',q.sell-q.cost,'operations',q.operations)) FROM (SELECT o.pricing_currency,sum(coalesce(o.customer_price_amount,0)) sell,sum(coalesce(o.provider_cost_amount,0)) cost,count(*) operations FROM public.operations o WHERE o.customer_id=c.id GROUP BY o.pricing_currency)q),'[]'::jsonb),
    'finance',COALESCE((SELECT jsonb_agg(jsonb_build_object('currency',q.currency,'registered',q.registered,'collected',q.collected,'outstanding',q.registered-q.collected,'overdue',q.overdue)) FROM (SELECT i.currency,sum(i.amount) registered,sum(coalesce((SELECT sum(p.amount) FROM public.finance_payments p WHERE p.invoice_id=i.id),0)) collected,sum(CASE WHEN i.status='open' AND i.due_date<v_date THEN greatest(i.amount-coalesce((SELECT sum(p.amount) FROM public.finance_payments p WHERE p.invoice_id=i.id),0),0) ELSE 0 END) overdue FROM public.finance_invoices i WHERE i.customer_id=c.id AND i.direction='ar' AND i.status<>'void' GROUP BY i.currency)q),'[]'::jsonb),'business_date',v_date,'timezone',private.bh2_tenant_timezone(c.tenant_id));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_provider_360(p_provider_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE p public.logistics_providers%ROWTYPE;v_primary jsonb;v_date date;
BEGIN
  SELECT * INTO p FROM public.logistics_providers WHERE id=p_provider_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
  IF NOT private.f8_admin(p.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  v_primary:=private.bh2_partner_primary_contact(p.tenant_id,'provider',p.id);v_date:=private.bh2_business_date(p.tenant_id);
  RETURN jsonb_build_object('provider',to_jsonb(p),'primary_contact',v_primary,
    'contacts',CASE WHEN EXISTS(SELECT 1 FROM public.business_contacts x WHERE x.tenant_id=p.tenant_id AND x.provider_id=p.id AND x.is_active) THEN COALESCE((SELECT jsonb_agg(to_jsonb(x)||jsonb_build_object('source','structured') ORDER BY x.is_primary DESC,x.name,x.id) FROM public.business_contacts x WHERE x.tenant_id=p.tenant_id AND x.provider_id=p.id AND x.is_active),'[]'::jsonb) ELSE CASE WHEN v_primary IS NULL THEN '[]'::jsonb ELSE jsonb_build_array(v_primary) END END,
    'history_counts',jsonb_build_object('operations',(SELECT count(*) FROM public.operations o WHERE o.tenant_id=p.tenant_id AND o.provider_id=p.id),'rates',(SELECT count(*) FROM public.commercial_rate_cards r WHERE r.tenant_id=p.tenant_id AND r.provider_id=p.id),'activity',(SELECT count(*) FROM public.audit_log a WHERE a.tenant_id=p.tenant_id AND (a.entity_id=p.id OR a.entity_id IN(SELECT o.id FROM public.operations o WHERE o.provider_id=p.id))),'compliance',(SELECT count(*) FROM public.partner_compliance_records r WHERE r.tenant_id=p.tenant_id AND r.provider_id=p.id),'contracts',(SELECT count(*) FROM public.partner_contracts k WHERE k.tenant_id=p.tenant_id AND k.provider_id=p.id),'claims',(SELECT count(*) FROM public.service_claims s WHERE s.tenant_id=p.tenant_id AND s.provider_id=p.id),'documents',(SELECT count(*) FROM public.document_relations dr WHERE dr.tenant_id=p.tenant_id AND ((dr.source_entity_type='provider' AND dr.source_entity_id=p.id) OR (dr.target_entity_type='provider' AND dr.target_entity_id=p.id)))),
    'operations','[]'::jsonb,'rates','[]'::jsonb,'activity','[]'::jsonb,
    'performance',(SELECT jsonb_build_object('operations',count(*),'active',count(*) FILTER(WHERE o.status NOT IN('closed','cancelled')),'closed',count(*) FILTER(WHERE o.status='closed'),'cancelled',count(*) FILTER(WHERE o.status='cancelled'),'open_incidents',(SELECT count(*) FROM public.operation_incidents i JOIN public.operations oi ON oi.id=i.operation_id WHERE oi.provider_id=p.id AND i.status='open'),'blocking_incidents',(SELECT count(*) FROM public.operation_incidents i JOIN public.operations oi ON oi.id=i.operation_id WHERE oi.provider_id=p.id AND i.status='open' AND i.is_blocking)) FROM public.operations o WHERE o.provider_id=p.id),
    'finance',COALESCE((SELECT jsonb_agg(jsonb_build_object('currency',q.currency,'registered',q.registered,'paid',q.paid,'outstanding',q.registered-q.paid,'overdue',q.overdue)) FROM (SELECT i.currency,sum(i.amount) registered,sum(coalesce((SELECT sum(fp.amount) FROM public.finance_payments fp WHERE fp.invoice_id=i.id),0)) paid,sum(CASE WHEN i.status='open' AND i.due_date<v_date THEN greatest(i.amount-coalesce((SELECT sum(fp.amount) FROM public.finance_payments fp WHERE fp.invoice_id=i.id),0),0) ELSE 0 END) overdue FROM public.finance_invoices i WHERE i.provider_id=p.id AND i.direction='ap' AND i.status<>'void' GROUP BY i.currency)q),'[]'::jsonb),'business_date',v_date,'timezone',private.bh2_tenant_timezone(p.tenant_id));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_partner_compliance_bundle(p_tenant_id uuid,p_partner_type text,p_partner_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_date date:=private.bh2_business_date(p_tenant_id);v_records jsonb;v_contracts jsonb;
BEGIN
  IF NOT private.f9_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  v_records:=public.rpc_list_partner_history_page(p_tenant_id,p_partner_type,p_partner_id,'compliance',NULL,25);
  v_contracts:=public.rpc_list_partner_history_page(p_tenant_id,p_partner_type,p_partner_id,'contracts',NULL,25);
  IF v_records?'error' THEN RETURN v_records; END IF;
  RETURN private.f9_partner_status(p_tenant_id,p_partner_type,p_partner_id,v_date)||jsonb_build_object('records',v_records->'items','contracts',v_contracts->'items','records_page',v_records,'contracts_page',v_contracts,'business_date',v_date,'timezone',private.bh2_tenant_timezone(p_tenant_id));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_rate_360(p_rate_card_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v public.commercial_rate_cards%ROWTYPE;
BEGIN
 SELECT * INTO v FROM public.commercial_rate_cards WHERE id=p_rate_card_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
 IF NOT private.f8_admin(v.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 RETURN jsonb_build_object('card',to_jsonb(v),'lane',(SELECT to_jsonb(l) FROM public.commercial_lanes l WHERE l.id=v.lane_id),'service',(SELECT to_jsonb(s) FROM public.service_catalog_items s WHERE s.id=v.service_catalog_item_id),'counterparty',CASE WHEN v.rate_type='BUY' THEN (SELECT to_jsonb(p) FROM public.logistics_providers p WHERE p.id=v.provider_id) ELSE (SELECT to_jsonb(c) FROM public.customers c WHERE c.id=v.customer_id) END,
  'versions',COALESCE((SELECT jsonb_agg(to_jsonb(rv)||jsonb_build_object('total_amount',private.f8_rate_total(rv.id),'charges',COALESCE((SELECT jsonb_agg(to_jsonb(ch) ORDER BY ch.position) FROM public.commercial_rate_charges ch WHERE ch.rate_version_id=rv.id),'[]'::jsonb)) ORDER BY rv.version DESC) FROM (SELECT * FROM public.commercial_rate_versions WHERE rate_card_id=v.id ORDER BY version DESC LIMIT 50)rv),'[]'::jsonb),
  'usage',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.selected_at DESC) FROM (SELECT s.deal_id,d.quote_reference,s.selected_at,s.total_amount,s.currency FROM public.crm_quote_rate_snapshots s JOIN public.crm_deals d ON d.id=s.deal_id WHERE s.rate_card_id=v.id ORDER BY s.selected_at DESC,s.id DESC LIMIT 50)x),'[]'::jsonb),
  'history_counts',jsonb_build_object('versions',(SELECT count(*) FROM public.commercial_rate_versions rv WHERE rv.rate_card_id=v.id),'usage',(SELECT count(*) FROM public.crm_quote_rate_snapshots s WHERE s.rate_card_id=v.id)));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_service_claim(p_claim_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE c public.service_claims%ROWTYPE;v_operation jsonb;v_quote jsonb;v_rate jsonb;
BEGIN
 SELECT * INTO c FROM public.service_claims WHERE id=p_claim_id;IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found');END IF;IF NOT private.f10_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized');END IF;
 SELECT jsonb_build_object('id',o.id,'reference',o.reference_code,'status',o.status,'route','/operations?operationId='||o.id,'service_type',o.service_type,'service_catalog_snapshot',o.service_catalog_snapshot,'origin_place',o.origin_place,'destination_place',o.destination_place,'planned_departure',o.planned_departure,'operational_window_start',o.operational_window_start,'operational_window_end',o.operational_window_end,'eta',o.eta,'pricing_currency',o.pricing_currency,'sell_amount',o.customer_price_amount,'provider_cost',o.provider_cost_amount,'source_deal_id',o.source_deal_id,
 'pod_present',EXISTS(SELECT 1 FROM public.operation_documents od WHERE od.operation_id=o.id AND od.document_type='proof_of_delivery' AND od.status='present'),
 'incidents',COALESCE((SELECT jsonb_agg(to_jsonb(i) ORDER BY i.reported_at DESC) FROM (SELECT * FROM public.operation_incidents WHERE operation_id=o.id ORDER BY reported_at DESC,id DESC LIMIT 50)i),'[]'::jsonb),
 'operation_documents',COALESCE((SELECT jsonb_agg(to_jsonb(od) ORDER BY od.updated_at DESC) FROM (SELECT * FROM public.operation_documents WHERE operation_id=o.id ORDER BY updated_at DESC,id DESC LIMIT 50)od),'[]'::jsonb),
 'private_documents',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT f.id,f.file_name,f.file_kind,f.status,f.created_at FROM public.document_files f WHERE f.tenant_id=o.tenant_id AND f.status='active' AND ((f.source_entity_type='operation' AND f.source_entity_id=o.id) OR EXISTS(SELECT 1 FROM public.document_relations dr WHERE dr.document_file_id=f.id AND dr.target_entity_type='operation' AND dr.target_entity_id=o.id)) ORDER BY f.created_at DESC,f.id DESC LIMIT 50)x),'[]'::jsonb)) INTO v_operation FROM public.operations o WHERE o.id=c.operation_id;
 SELECT jsonb_build_object('id',d.id,'reference',d.quote_reference,'status',d.quote_status,'currency',d.currency,'sell_amount',COALESCE(NULLIF(d.quote_payload->>'customer_price_amount','')::numeric,d.value),'provider_cost',NULLIF(d.quote_payload->>'provider_cost_amount','')::numeric,'route','/commercial?view=quotes&quoteId='||d.id) INTO v_quote FROM public.crm_deals d WHERE d.id=(SELECT source_deal_id FROM public.operations WHERE id=c.operation_id);
 SELECT jsonb_build_object('rate_card_id',s.rate_card_id,'rate_version_id',s.rate_version_id,'rate_type',s.rate_type,'currency',s.currency,'total_amount',s.total_amount,'selected_at',s.selected_at) INTO v_rate FROM public.crm_quote_rate_snapshots s WHERE s.deal_id=(SELECT source_deal_id FROM public.operations WHERE id=c.operation_id) ORDER BY s.selected_at DESC LIMIT 1;
 RETURN to_jsonb(c)||jsonb_build_object('sla',private.f10_sla(c,now()),'customer',(SELECT to_jsonb(x) FROM (SELECT id,display_name FROM public.customers WHERE id=c.customer_id)x),'provider',(SELECT to_jsonb(x) FROM (SELECT id,display_name FROM public.logistics_providers WHERE id=c.provider_id)x),'operation',v_operation,'quote',v_quote,'rate_snapshot',v_rate,
  'source_incident',(SELECT to_jsonb(x) FROM (SELECT id,category,title,description,status,is_blocking,reported_at,resolved_at FROM public.operation_incidents WHERE id=c.source_incident_id)x),'compliance_requirement',(SELECT to_jsonb(x) FROM (SELECT id,code,name,category,is_required,is_blocking FROM public.partner_compliance_requirements WHERE id=c.compliance_requirement_id)x),'partner_contract',(SELECT to_jsonb(x) FROM (SELECT id,title,reference,status,starts_on,ends_on FROM public.partner_contracts WHERE id=c.partner_contract_id)x),
  'events',COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.occurred_at DESC,e.id DESC) FROM (SELECT * FROM public.service_claim_events WHERE claim_id=c.id ORDER BY occurred_at DESC,id DESC LIMIT 100)e),'[]'::jsonb),
  'actions',COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY (a.status='done'),a.due_at NULLS LAST,a.created_at) FROM (SELECT * FROM public.service_claim_actions WHERE claim_id=c.id ORDER BY (status='done'),due_at NULLS LAST,created_at LIMIT 100)a),'[]'::jsonb),
  'financials',COALESCE((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.created_at DESC) FROM (SELECT * FROM public.service_claim_financials WHERE claim_id=c.id ORDER BY created_at DESC,id DESC LIMIT 100)f),'[]'::jsonb),
  'exposure_by_currency',COALESCE((SELECT jsonb_agg(jsonb_build_object('currency',x.currency,'amount',x.amount) ORDER BY x.currency) FROM (SELECT currency,sum(amount) amount FROM public.service_claim_financials WHERE claim_id=c.id AND status<>'cancelled' GROUP BY currency)x),'[]'::jsonb),
  'contacts',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.occurred_at DESC) FROM (SELECT l.*,b.name contact_name,b.email,b.phone FROM public.service_claim_contacts l JOIN public.business_contacts b ON b.id=l.business_contact_id WHERE l.claim_id=c.id ORDER BY l.occurred_at DESC,l.id DESC LIMIT 100)x),'[]'::jsonb),
  'available_contacts',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',b.id,'party',CASE WHEN b.customer_id IS NOT NULL THEN 'customer' ELSE 'provider' END,'name',b.name,'email',b.email,'phone',b.phone) ORDER BY b.name) FROM public.business_contacts b WHERE b.tenant_id=c.tenant_id AND b.is_active AND ((b.customer_id IS NOT NULL AND b.customer_id=c.customer_id) OR (b.provider_id IS NOT NULL AND b.provider_id=c.provider_id))),'[]'::jsonb),
  'available_responsibles',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',m.user_id,'label',COALESCE(u.email,m.user_id::text)) ORDER BY COALESCE(u.email,m.user_id::text)) FROM public.memberships m LEFT JOIN auth.users u ON u.id=m.user_id WHERE m.tenant_id=c.tenant_id AND m.role='admin'),'[]'::jsonb),
  'documents',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT f.* FROM public.document_relations r JOIN public.document_files f ON f.id=r.document_file_id WHERE r.tenant_id=c.tenant_id AND r.target_entity_type='claim' AND r.target_entity_id=c.id AND f.status='active' ORDER BY f.created_at DESC,f.id DESC LIMIT 50)x),'[]'::jsonb),
  'history_counts',jsonb_build_object('events',(SELECT count(*) FROM public.service_claim_events e WHERE e.claim_id=c.id),'actions',(SELECT count(*) FROM public.service_claim_actions a WHERE a.claim_id=c.id),'contacts',(SELECT count(*) FROM public.service_claim_contacts l WHERE l.claim_id=c.id),'financials',(SELECT count(*) FROM public.service_claim_financials f WHERE f.claim_id=c.id)));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_internal_notifications_page(p_tenant_id uuid,p_unread_only boolean DEFAULT false,p_cursor jsonb DEFAULT NULL,p_limit integer DEFAULT 25)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_limit integer:=LEAST(GREATEST(COALESCE(p_limit,25),1),100);v_at timestamptz:='infinity';v_id uuid:='ffffffff-ffff-ffff-ffff-ffffffffffff';v_cursor_unread boolean;v_raw jsonb;v_items jsonb;v_more boolean;v_last jsonb;
BEGIN
  IF private.f5_current_role(p_tenant_id) NOT IN('admin','finance') THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  IF p_cursor IS NOT NULL THEN
    IF jsonb_typeof(p_cursor)<>'object' OR p_cursor->>'tenant_id' IS DISTINCT FROM p_tenant_id::text OR p_cursor->>'user_id' IS DISTINCT FROM auth.uid()::text THEN RETURN jsonb_build_object('error','invalid_cursor'); END IF;
    BEGIN v_cursor_unread:=(p_cursor->>'unread_only')::boolean;v_at:=(p_cursor->>'first_seen_at')::timestamptz;v_id:=(p_cursor->>'id')::uuid; EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow THEN RETURN jsonb_build_object('error','invalid_cursor'); END;
    IF v_cursor_unread IS DISTINCT FROM COALESCE(p_unread_only,false) THEN RETURN jsonb_build_object('error','invalid_cursor'); END IF;
  END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(n) ORDER BY n.first_seen_at DESC,n.id DESC),'[]'::jsonb) INTO v_raw FROM (
    SELECT id,area AS module,trigger_type AS kind,priority,title,body,route,related_entity_type AS entity_type,related_entity_id AS entity_id,COALESCE(NULLIF(metadata->>'occurred_at','')::timestamptz,first_seen_at) AS occurred_at,due_at,read_at,first_seen_at AS created_at,is_automated,automation_rule_code,first_seen_at,last_seen_at,escalation_level,escalated_at,metadata
    FROM public.internal_notifications WHERE tenant_id=p_tenant_id AND user_id=auth.uid() AND status<>'dismissed' AND resolved_at IS NULL AND (NOT COALESCE(p_unread_only,false) OR status='unread') AND (first_seen_at,id)<(v_at,v_id)
    ORDER BY first_seen_at DESC,id DESC LIMIT v_limit+1)n;
  v_more:=jsonb_array_length(v_raw)>v_limit;
  SELECT COALESCE(jsonb_agg(value ORDER BY ordinality),'[]'::jsonb) INTO v_items FROM jsonb_array_elements(v_raw) WITH ORDINALITY WHERE ordinality<=v_limit;
  IF v_more THEN v_last:=v_items->(jsonb_array_length(v_items)-1); END IF;
  RETURN jsonb_build_object('items',v_items,'has_more',v_more,'next_cursor',CASE WHEN v_more THEN jsonb_build_object('tenant_id',p_tenant_id,'user_id',auth.uid(),'unread_only',COALESCE(p_unread_only,false),'first_seen_at',v_last->>'first_seen_at','id',v_last->>'id') ELSE NULL END,'unread_count',(SELECT count(*) FROM public.internal_notifications WHERE tenant_id=p_tenant_id AND user_id=auth.uid() AND status='unread' AND resolved_at IS NULL));
END;
$function$;

REVOKE ALL ON FUNCTION private.bh2_tenant_timezone(uuid),private.bh2_business_date(uuid,timestamptz),private.bh2_partner_primary_contact(uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_partner_history_page(uuid,text,uuid,text,jsonb,integer),public.rpc_list_internal_notifications_page(uuid,boolean,jsonb,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_partner_history_page(uuid,text,uuid,text,jsonb,integer),public.rpc_list_internal_notifications_page(uuid,boolean,jsonb,integer) TO authenticated;

DO $collision_gate$
BEGIN
  IF (SELECT count(*) FROM bh2_rpc_snapshot)<>6 OR EXISTS(
    SELECT 1 FROM bh2_rpc_snapshot s
    LEFT JOIN pg_catalog.pg_proc p ON p.oid=s.function_oid
    WHERE p.oid IS NULL OR p.oid::regprocedure::text IS DISTINCT FROM s.identity
      OR jsonb_build_object(
        'arguments',pg_get_function_arguments(p.oid),
        'arg_names',to_jsonb(p.proargnames),
        'arg_modes',to_jsonb(p.proargmodes),
        'all_arg_types',to_jsonb(p.proallargtypes),
        'defaults',p.pronargdefaults,
        'result',pg_get_function_result(p.oid),
        'security_definer',p.prosecdef,
        'search_path',to_jsonb(p.proconfig)
      ) IS DISTINCT FROM s.contract
  ) THEN RAISE EXCEPTION 'BH2 replaced RPC identity/collision contract changed'; END IF;
END;
$collision_gate$;

DROP TABLE bh2_rpc_snapshot;
