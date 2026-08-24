-- F8 Rates, Lanes & Partner 360. Additive, admin-only Commercial contracts.
-- No Auth, Edge, public Tracking or existing function identity is modified.

ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS payment_terms_days integer NOT NULL DEFAULT 0;
ALTER TABLE public.logistics_providers ADD COLUMN IF NOT EXISTS payment_terms_days integer NOT NULL DEFAULT 0;
ALTER TABLE public.logistics_providers ADD COLUMN IF NOT EXISTS preferred_currency text NOT NULL DEFAULT 'MXN';

ALTER TABLE public.customers ADD CONSTRAINT customers_f8_payment_terms_check CHECK (payment_terms_days BETWEEN 0 AND 365);
ALTER TABLE public.logistics_providers ADD CONSTRAINT providers_f8_payment_terms_check CHECK (payment_terms_days BETWEEN 0 AND 365);
ALTER TABLE public.logistics_providers ADD CONSTRAINT providers_f8_currency_check CHECK (preferred_currency IN ('MXN','USD'));

CREATE TABLE public.commercial_lanes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    scope text NOT NULL,
    origin_place jsonb NOT NULL,
    destination_place jsonb NOT NULL,
    origin_key text NOT NULL,
    destination_key text NOT NULL,
    label text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT commercial_lanes_scope_check CHECK (scope IN ('national','international')),
    CONSTRAINT commercial_lanes_places_check CHECK (jsonb_typeof(origin_place)='object' AND jsonb_typeof(destination_place)='object'),
    CONSTRAINT commercial_lanes_keys_check CHECK (length(origin_key) BETWEEN 3 AND 400 AND length(destination_key) BETWEEN 3 AND 400),
    CONSTRAINT commercial_lanes_distinct_check CHECK (origin_key <> destination_key),
    CONSTRAINT commercial_lanes_identity_key UNIQUE (tenant_id, scope, origin_key, destination_key)
);

CREATE TABLE public.commercial_rate_cards (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    rate_type text NOT NULL,
    provider_id uuid REFERENCES public.logistics_providers(id) ON DELETE RESTRICT,
    customer_id uuid REFERENCES public.customers(id) ON DELETE RESTRICT,
    lane_id uuid NOT NULL REFERENCES public.commercial_lanes(id) ON DELETE RESTRICT,
    service_catalog_item_id uuid NOT NULL REFERENCES public.service_catalog_items(id) ON DELETE RESTRICT,
    reference text NOT NULL,
    status text NOT NULL DEFAULT 'draft',
    current_version_id uuid,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT commercial_rate_cards_type_check CHECK (rate_type IN ('BUY','SELL')),
    CONSTRAINT commercial_rate_cards_counterparty_check CHECK (
        (rate_type='BUY' AND provider_id IS NOT NULL AND customer_id IS NULL)
        OR (rate_type='SELL' AND customer_id IS NOT NULL AND provider_id IS NULL)
    ),
    CONSTRAINT commercial_rate_cards_status_check CHECK (status IN ('draft','active','archived')),
    CONSTRAINT commercial_rate_cards_reference_key UNIQUE (tenant_id, reference)
);

CREATE TABLE public.commercial_rate_versions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    rate_card_id uuid NOT NULL REFERENCES public.commercial_rate_cards(id) ON DELETE RESTRICT,
    version integer NOT NULL CHECK (version > 0),
    currency text NOT NULL,
    valid_from date NOT NULL,
    valid_to date,
    base_amount numeric(14,2) NOT NULL DEFAULT 0,
    minimum_amount numeric(14,2),
    notes text,
    transit_estimate text,
    equipment_note text,
    supersedes_version_id uuid REFERENCES public.commercial_rate_versions(id) ON DELETE RESTRICT,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT commercial_rate_versions_currency_check CHECK (currency IN ('MXN','USD')),
    CONSTRAINT commercial_rate_versions_dates_check CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT commercial_rate_versions_amounts_check CHECK (base_amount >= 0 AND (minimum_amount IS NULL OR minimum_amount >= 0)),
    CONSTRAINT commercial_rate_versions_number_key UNIQUE (rate_card_id, version)
);

ALTER TABLE public.commercial_rate_cards
    ADD CONSTRAINT commercial_rate_cards_current_version_fk
    FOREIGN KEY (current_version_id) REFERENCES public.commercial_rate_versions(id) ON DELETE RESTRICT;

CREATE TABLE public.commercial_rate_charges (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    rate_version_id uuid NOT NULL REFERENCES public.commercial_rate_versions(id) ON DELETE RESTRICT,
    position integer NOT NULL DEFAULT 0,
    charge_type text NOT NULL,
    description text NOT NULL,
    amount numeric(14,2) NOT NULL,
    currency text NOT NULL,
    unit_basis text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT commercial_rate_charges_type_check CHECK (charge_type IN ('base','fuel','toll','handling','loading_unloading','detention','customs_support','insurance','other')),
    CONSTRAINT commercial_rate_charges_amount_check CHECK (amount >= 0),
    CONSTRAINT commercial_rate_charges_currency_check CHECK (currency IN ('MXN','USD')),
    CONSTRAINT commercial_rate_charges_description_check CHECK (length(btrim(description)) BETWEEN 1 AND 200)
);

CREATE TABLE public.crm_quote_rate_snapshots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    deal_id uuid NOT NULL REFERENCES public.crm_deals(id) ON DELETE RESTRICT,
    rate_card_id uuid NOT NULL REFERENCES public.commercial_rate_cards(id) ON DELETE RESTRICT,
    rate_version_id uuid NOT NULL REFERENCES public.commercial_rate_versions(id) ON DELETE RESTRICT,
    rate_type text NOT NULL CHECK (rate_type IN ('BUY','SELL')),
    provider_id uuid REFERENCES public.logistics_providers(id) ON DELETE RESTRICT,
    customer_id uuid REFERENCES public.customers(id) ON DELETE RESTRICT,
    lane_id uuid NOT NULL REFERENCES public.commercial_lanes(id) ON DELETE RESTRICT,
    service_catalog_item_id uuid NOT NULL REFERENCES public.service_catalog_items(id) ON DELETE RESTRICT,
    charges_snapshot jsonb NOT NULL,
    total_amount numeric(14,2) NOT NULL CHECK (total_amount >= 0),
    currency text NOT NULL CHECK (currency IN ('MXN','USD')),
    selected_at timestamptz NOT NULL DEFAULT now(),
    selected_by uuid NOT NULL,
    CONSTRAINT crm_quote_rate_snapshots_charges_check CHECK (jsonb_typeof(charges_snapshot)='array')
);

CREATE TABLE public.business_contacts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES public.customers(id) ON DELETE CASCADE,
    provider_id uuid REFERENCES public.logistics_providers(id) ON DELETE CASCADE,
    name text NOT NULL,
    contact_role text NOT NULL,
    email text,
    phone text,
    is_primary boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    notes text,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT business_contacts_owner_check CHECK ((customer_id IS NOT NULL)::integer + (provider_id IS NOT NULL)::integer = 1),
    CONSTRAINT business_contacts_role_check CHECK (contact_role IN ('commercial','operations','billing','management','other')),
    CONSTRAINT business_contacts_name_check CHECK (length(btrim(name)) BETWEEN 1 AND 160)
);

CREATE UNIQUE INDEX business_contacts_customer_primary_uidx ON public.business_contacts(customer_id) WHERE customer_id IS NOT NULL AND is_primary AND is_active;
CREATE UNIQUE INDEX business_contacts_provider_primary_uidx ON public.business_contacts(provider_id) WHERE provider_id IS NOT NULL AND is_primary AND is_active;
CREATE INDEX commercial_lanes_search_idx ON public.commercial_lanes(tenant_id, is_active, label);
CREATE INDEX commercial_rate_cards_directory_idx ON public.commercial_rate_cards(tenant_id, rate_type, status, updated_at DESC);
CREATE INDEX commercial_rate_cards_provider_idx ON public.commercial_rate_cards(tenant_id, provider_id) WHERE provider_id IS NOT NULL;
CREATE INDEX commercial_rate_cards_customer_idx ON public.commercial_rate_cards(tenant_id, customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX commercial_rate_versions_validity_idx ON public.commercial_rate_versions(rate_card_id, valid_from, valid_to);
CREATE INDEX commercial_rate_charges_version_idx ON public.commercial_rate_charges(rate_version_id, position);
CREATE INDEX crm_quote_rate_snapshots_deal_idx ON public.crm_quote_rate_snapshots(tenant_id, deal_id, selected_at DESC);
CREATE INDEX business_contacts_owner_idx ON public.business_contacts(tenant_id, customer_id, provider_id, is_active);

ALTER TABLE public.commercial_lanes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_rate_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_rate_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_rate_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_quote_rate_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_contacts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.commercial_lanes, public.commercial_rate_cards, public.commercial_rate_versions,
    public.commercial_rate_charges, public.crm_quote_rate_snapshots, public.business_contacts
FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.f8_place_key(p_place jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO pg_catalog, public AS $function$
    SELECT lower(regexp_replace(concat_ws('|',
        nullif(btrim(p_place->>'country'),''), nullif(btrim(p_place->>'state'),''),
        nullif(btrim(p_place->>'municipality'),''), nullif(btrim(p_place->>'facility'),'')), '\s+', ' ', 'g'));
$function$;

CREATE OR REPLACE FUNCTION private.f8_admin(p_tenant_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
    SELECT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin']);
$function$;

CREATE OR REPLACE FUNCTION private.f8_rate_total(p_version_id uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
    SELECT COALESCE(sum(c.amount),0)::numeric FROM public.commercial_rate_charges c WHERE c.rate_version_id=p_version_id;
$function$;

CREATE OR REPLACE FUNCTION private.f8_protect_used_rate()
RETURNS trigger LANGUAGE plpgsql SET search_path TO pg_catalog, public AS $function$
DECLARE v_version_id uuid;
BEGIN
    IF TG_TABLE_NAME='commercial_rate_versions' THEN
        v_version_id := OLD.id;
    ELSE
        v_version_id := OLD.rate_version_id;
    END IF;
    IF EXISTS (SELECT 1 FROM public.crm_quote_rate_snapshots s WHERE s.rate_version_id=v_version_id) THEN
        RAISE EXCEPTION 'used_rate_version_is_immutable';
    END IF;
    RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;
$function$;

CREATE TRIGGER f8_protect_used_version BEFORE UPDATE OR DELETE ON public.commercial_rate_versions FOR EACH ROW EXECUTE FUNCTION private.f8_protect_used_rate();
CREATE TRIGGER f8_protect_used_charge BEFORE UPDATE OR DELETE ON public.commercial_rate_charges FOR EACH ROW EXECUTE FUNCTION private.f8_protect_used_rate();

CREATE OR REPLACE FUNCTION public.rpc_list_rate_reference_data(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
BEGIN
    IF NOT private.f8_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN jsonb_build_object(
      'lanes', COALESCE((SELECT jsonb_agg(to_jsonb(l) ORDER BY l.label) FROM public.commercial_lanes l WHERE l.tenant_id=p_tenant_id AND l.is_active),'[]'::jsonb),
      'services', COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.service_type,s.service_class) FROM public.service_catalog_items s WHERE s.tenant_id=p_tenant_id AND s.is_active),'[]'::jsonb),
      'customers', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'display_name',c.display_name,'is_active',c.is_active) ORDER BY c.display_name) FROM public.customers c WHERE c.tenant_id=p_tenant_id),'[]'::jsonb),
      'providers', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name,'is_active',p.is_active) ORDER BY p.display_name) FROM public.logistics_providers p WHERE p.tenant_id=p_tenant_id),'[]'::jsonb));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_upsert_lane(p_tenant_id uuid, p_lane_id uuid, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
DECLARE v_id uuid; v_scope text:=p_payload->>'scope'; v_origin jsonb:=p_payload->'origin_place'; v_destination jsonb:=p_payload->'destination_place'; v_ok text; v_dk text;
BEGIN
    IF NOT private.f8_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF v_scope NOT IN ('national','international') OR jsonb_typeof(v_origin)<>'object' OR jsonb_typeof(v_destination)<>'object'
       OR nullif(btrim(v_origin->>'municipality'),'') IS NULL OR nullif(btrim(v_origin->>'state'),'') IS NULL
       OR nullif(btrim(v_destination->>'municipality'),'') IS NULL OR nullif(btrim(v_destination->>'state'),'') IS NULL THEN
       RETURN jsonb_build_object('error','invalid_lane');
    END IF;
    v_ok:=private.f8_place_key(v_origin); v_dk:=private.f8_place_key(v_destination);
    IF v_ok=v_dk THEN RETURN jsonb_build_object('error','invalid_lane'); END IF;
    IF p_lane_id IS NULL THEN
      INSERT INTO public.commercial_lanes(tenant_id,scope,origin_place,destination_place,origin_key,destination_key,label,created_by)
      VALUES(p_tenant_id,v_scope,v_origin,v_destination,v_ok,v_dk,
        concat_ws(' → ',concat_ws(', ',v_origin->>'municipality',v_origin->>'state'),concat_ws(', ',v_destination->>'municipality',v_destination->>'state')),auth.uid()) RETURNING id INTO v_id;
    ELSE
      UPDATE public.commercial_lanes SET scope=v_scope,origin_place=v_origin,destination_place=v_destination,origin_key=v_ok,destination_key=v_dk,
        label=concat_ws(' → ',concat_ws(', ',v_origin->>'municipality',v_origin->>'state'),concat_ws(', ',v_destination->>'municipality',v_destination->>'state')),updated_at=now()
      WHERE id=p_lane_id AND tenant_id=p_tenant_id RETURNING id INTO v_id;
      IF v_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    END IF;
    INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id) VALUES(p_tenant_id,auth.uid(),'lane_upserted','commercial_lane',v_id);
    RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('error','duplicate_lane'); WHEN check_violation OR invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_lane');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_create_rate(p_tenant_id uuid, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
DECLARE v_card uuid; v_version uuid; v_type text:=upper(p_payload->>'rate_type'); v_provider uuid; v_customer uuid; v_lane uuid; v_service uuid; v_currency text:=upper(p_payload->>'currency'); v_from date; v_to date; v_reference text; v_charge jsonb; v_base numeric:=0; v_position int:=0;
BEGIN
  IF NOT private.f8_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  BEGIN
    v_provider:=nullif(p_payload->>'provider_id','')::uuid; v_customer:=nullif(p_payload->>'customer_id','')::uuid;
    v_lane:=(p_payload->>'lane_id')::uuid; v_service:=(p_payload->>'service_catalog_item_id')::uuid;
    v_from:=(p_payload->>'valid_from')::date; v_to:=nullif(p_payload->>'valid_to','')::date;
  EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN RETURN jsonb_build_object('error','invalid_payload'); END;
  IF v_type NOT IN ('BUY','SELL') OR v_currency NOT IN ('MXN','USD') OR jsonb_typeof(p_payload->'charges')<>'array' OR jsonb_array_length(p_payload->'charges')=0 OR (v_to IS NOT NULL AND v_to<v_from) THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.commercial_lanes WHERE id=v_lane AND tenant_id=p_tenant_id AND is_active) THEN RETURN jsonb_build_object('error','invalid_lane'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.service_catalog_items WHERE id=v_service AND tenant_id=p_tenant_id AND is_active) THEN RETURN jsonb_build_object('error','invalid_service'); END IF;
  IF v_type='BUY' THEN
    IF v_provider IS NULL OR v_customer IS NOT NULL OR NOT EXISTS(SELECT 1 FROM public.logistics_providers WHERE id=v_provider AND tenant_id=p_tenant_id AND is_active) THEN RETURN jsonb_build_object('error','invalid_provider'); END IF;
  ELSE
    IF v_customer IS NULL OR v_provider IS NOT NULL OR NOT EXISTS(SELECT 1 FROM public.customers WHERE id=v_customer AND tenant_id=p_tenant_id AND is_active) THEN RETURN jsonb_build_object('error','invalid_customer'); END IF;
  END IF;
  v_reference:=upper(nullif(btrim(p_payload->>'reference'),''));
  IF v_reference IS NULL THEN v_reference:='RT-'||to_char(now(),'YYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6)); END IF;
  INSERT INTO public.commercial_rate_cards(tenant_id,rate_type,provider_id,customer_id,lane_id,service_catalog_item_id,reference,status,created_by)
  VALUES(p_tenant_id,v_type,v_provider,v_customer,v_lane,v_service,v_reference,COALESCE(nullif(p_payload->>'status',''),'active'),auth.uid()) RETURNING id INTO v_card;
  INSERT INTO public.commercial_rate_versions(tenant_id,rate_card_id,version,currency,valid_from,valid_to,minimum_amount,notes,transit_estimate,equipment_note,created_by)
  VALUES(p_tenant_id,v_card,1,v_currency,v_from,v_to,nullif(p_payload->>'minimum_amount','')::numeric,nullif(btrim(p_payload->>'notes'),''),nullif(btrim(p_payload->>'transit_estimate'),''),nullif(btrim(p_payload->>'equipment_note'),''),auth.uid()) RETURNING id INTO v_version;
  FOR v_charge IN SELECT value FROM jsonb_array_elements(p_payload->'charges') LOOP
    v_position:=v_position+1;
    IF (v_charge->>'charge_type') NOT IN ('base','fuel','toll','handling','loading_unloading','detention','customs_support','insurance','other') OR nullif(btrim(v_charge->>'description'),'') IS NULL OR (v_charge->>'amount')::numeric<0 THEN RAISE check_violation; END IF;
    INSERT INTO public.commercial_rate_charges(tenant_id,rate_version_id,position,charge_type,description,amount,currency,unit_basis)
    VALUES(p_tenant_id,v_version,v_position,v_charge->>'charge_type',btrim(v_charge->>'description'),(v_charge->>'amount')::numeric,v_currency,nullif(btrim(v_charge->>'unit_basis'),''));
    IF v_charge->>'charge_type'='base' THEN v_base:=v_base+(v_charge->>'amount')::numeric; END IF;
  END LOOP;
  UPDATE public.commercial_rate_versions SET base_amount=v_base WHERE id=v_version;
  UPDATE public.commercial_rate_cards SET current_version_id=v_version WHERE id=v_card;
  INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(p_tenant_id,auth.uid(),'rate_created','commercial_rate',v_card,jsonb_build_object('rate_type',v_type,'version',1));
  RETURN jsonb_build_object('id',v_card,'version_id',v_version);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('error','duplicate_reference'); WHEN check_violation OR not_null_violation OR invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_create_rate_version(p_rate_card_id uuid, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
DECLARE v_card public.commercial_rate_cards%ROWTYPE; v_previous uuid; v_version uuid; v_number int; v_currency text:=upper(p_payload->>'currency'); v_from date; v_to date; v_charge jsonb; v_base numeric:=0; v_position int:=0;
BEGIN
  SELECT * INTO v_card FROM public.commercial_rate_cards WHERE id=p_rate_card_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
  IF NOT private.f8_admin(v_card.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
  IF v_card.status='archived' THEN RETURN jsonb_build_object('error','rate_archived'); END IF;
  BEGIN v_from:=(p_payload->>'valid_from')::date; v_to:=nullif(p_payload->>'valid_to','')::date; EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN RETURN jsonb_build_object('error','invalid_payload'); END;
  IF v_currency NOT IN ('MXN','USD') OR jsonb_typeof(p_payload->'charges')<>'array' OR jsonb_array_length(p_payload->'charges')=0 OR (v_to IS NOT NULL AND v_to<v_from) THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
  SELECT COALESCE(max(version),0)+1 INTO v_number FROM public.commercial_rate_versions WHERE rate_card_id=p_rate_card_id;
  v_previous:=v_card.current_version_id;
  INSERT INTO public.commercial_rate_versions(tenant_id,rate_card_id,version,currency,valid_from,valid_to,minimum_amount,notes,transit_estimate,equipment_note,supersedes_version_id,created_by)
  VALUES(v_card.tenant_id,p_rate_card_id,v_number,v_currency,v_from,v_to,nullif(p_payload->>'minimum_amount','')::numeric,nullif(btrim(p_payload->>'notes'),''),nullif(btrim(p_payload->>'transit_estimate'),''),nullif(btrim(p_payload->>'equipment_note'),''),v_previous,auth.uid()) RETURNING id INTO v_version;
  FOR v_charge IN SELECT value FROM jsonb_array_elements(p_payload->'charges') LOOP
    v_position:=v_position+1;
    IF (v_charge->>'charge_type') NOT IN ('base','fuel','toll','handling','loading_unloading','detention','customs_support','insurance','other') OR nullif(btrim(v_charge->>'description'),'') IS NULL OR (v_charge->>'amount')::numeric<0 THEN RAISE check_violation; END IF;
    INSERT INTO public.commercial_rate_charges(tenant_id,rate_version_id,position,charge_type,description,amount,currency,unit_basis)
    VALUES(v_card.tenant_id,v_version,v_position,v_charge->>'charge_type',btrim(v_charge->>'description'),(v_charge->>'amount')::numeric,v_currency,nullif(btrim(v_charge->>'unit_basis'),''));
    IF v_charge->>'charge_type'='base' THEN v_base:=v_base+(v_charge->>'amount')::numeric; END IF;
  END LOOP;
  UPDATE public.commercial_rate_versions SET base_amount=v_base WHERE id=v_version;
  UPDATE public.commercial_rate_cards SET current_version_id=v_version,updated_at=now() WHERE id=p_rate_card_id;
  INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(v_card.tenant_id,auth.uid(),'rate_version_created','commercial_rate',p_rate_card_id,jsonb_build_object('version',v_number));
  RETURN jsonb_build_object('id',p_rate_card_id,'version_id',v_version,'version',v_number);
EXCEPTION WHEN check_violation OR not_null_violation OR invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_rates(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
DECLARE v_on date:=COALESCE(nullif(p_filters->>'valid_on','')::date,current_date);
BEGIN
 IF NOT private.f8_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 RETURN COALESCE((SELECT jsonb_agg(x ORDER BY x->>'reference') FROM (
  SELECT jsonb_build_object('id',r.id,'reference',r.reference,'rate_type',r.rate_type,'status',r.status,'provider_id',r.provider_id,'provider_name',p.display_name,'customer_id',r.customer_id,'customer_name',c.display_name,'lane_id',l.id,'lane_label',l.label,'scope',l.scope,'service_catalog_item_id',s.id,'service_name',concat_ws(' · ',s.service_type,nullif(s.service_class,'')),'version_id',v.id,'version',v.version,'currency',v.currency,'valid_from',v.valid_from,'valid_to',v.valid_to,'is_expired',(v.valid_to IS NOT NULL AND v.valid_to<current_date),'total_amount',private.f8_rate_total(v.id)) x
  FROM public.commercial_rate_cards r JOIN public.commercial_rate_versions v ON v.id=r.current_version_id JOIN public.commercial_lanes l ON l.id=r.lane_id JOIN public.service_catalog_items s ON s.id=r.service_catalog_item_id LEFT JOIN public.logistics_providers p ON p.id=r.provider_id LEFT JOIN public.customers c ON c.id=r.customer_id
  WHERE r.tenant_id=p_tenant_id
    AND (NOT(p_filters?'rate_type') OR r.rate_type=upper(p_filters->>'rate_type'))
    AND (NOT(p_filters?'status') OR r.status=p_filters->>'status')
    AND (NOT(p_filters?'provider_id') OR r.provider_id=(p_filters->>'provider_id')::uuid)
    AND (NOT(p_filters?'customer_id') OR r.customer_id=(p_filters->>'customer_id')::uuid)
    AND (NOT(p_filters?'lane_id') OR r.lane_id=(p_filters->>'lane_id')::uuid)
    AND (NOT(p_filters?'service_catalog_item_id') OR r.service_catalog_item_id=(p_filters->>'service_catalog_item_id')::uuid)
    AND (NOT(p_filters?'currency') OR v.currency=upper(p_filters->>'currency'))
    AND (NOT(p_filters?'valid_on') OR (v.valid_from<=v_on AND (v.valid_to IS NULL OR v.valid_to>=v_on)))
    AND (NOT(p_filters?'search') OR lower(r.reference||' '||l.label||' '||s.service_type||' '||coalesce(p.display_name,c.display_name,'')) LIKE '%'||lower(p_filters->>'search')||'%')
 ) q),'[]'::jsonb);
EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN RETURN jsonb_build_object('error','invalid_filters');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_rate_360(p_rate_card_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
DECLARE v public.commercial_rate_cards%ROWTYPE;
BEGIN
 SELECT * INTO v FROM public.commercial_rate_cards WHERE id=p_rate_card_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
 IF NOT private.f8_admin(v.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 RETURN jsonb_build_object('card',to_jsonb(v),'lane',(SELECT to_jsonb(l) FROM public.commercial_lanes l WHERE l.id=v.lane_id),'service',(SELECT to_jsonb(s) FROM public.service_catalog_items s WHERE s.id=v.service_catalog_item_id),'counterparty',CASE WHEN v.rate_type='BUY' THEN (SELECT to_jsonb(p) FROM public.logistics_providers p WHERE p.id=v.provider_id) ELSE (SELECT to_jsonb(c) FROM public.customers c WHERE c.id=v.customer_id) END,'versions',COALESCE((SELECT jsonb_agg(to_jsonb(rv)||jsonb_build_object('total_amount',private.f8_rate_total(rv.id),'charges',COALESCE((SELECT jsonb_agg(to_jsonb(ch) ORDER BY ch.position) FROM public.commercial_rate_charges ch WHERE ch.rate_version_id=rv.id),'[]'::jsonb)) ORDER BY rv.version DESC) FROM public.commercial_rate_versions rv WHERE rv.rate_card_id=v.id),'[]'::jsonb),'usage',COALESCE((SELECT jsonb_agg(jsonb_build_object('deal_id',s.deal_id,'quote_reference',d.quote_reference,'selected_at',s.selected_at,'total_amount',s.total_amount,'currency',s.currency) ORDER BY s.selected_at DESC) FROM public.crm_quote_rate_snapshots s JOIN public.crm_deals d ON d.id=s.deal_id WHERE s.rate_card_id=v.id),'[]'::jsonb));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_compare_provider_rates(p_tenant_id uuid, p_filters jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
DECLARE v_lane uuid; v_service uuid; v_date date; v_currency text;
BEGIN
 IF NOT private.f8_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 BEGIN v_lane:=(p_filters->>'lane_id')::uuid;v_service:=(p_filters->>'service_catalog_item_id')::uuid;v_date:=(p_filters->>'operational_date')::date; EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN RETURN jsonb_build_object('error','invalid_filters'); END;
 v_currency:=upper(p_filters->>'currency'); IF v_currency NOT IN ('MXN','USD') THEN RETURN jsonb_build_object('error','invalid_currency'); END IF;
 RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('rate_card_id',r.id,'rate_version_id',v.id,'reference',r.reference,'provider_id',p.id,'provider_name',p.display_name,'total_amount',private.f8_rate_total(v.id),'currency',v.currency,'valid_to',v.valid_to,'charges',(SELECT jsonb_agg(to_jsonb(ch) ORDER BY ch.position) FROM public.commercial_rate_charges ch WHERE ch.rate_version_id=v.id)) ORDER BY private.f8_rate_total(v.id),p.display_name)
 FROM public.commercial_rate_cards r JOIN public.commercial_rate_versions v ON v.id=r.current_version_id JOIN public.logistics_providers p ON p.id=r.provider_id AND p.is_active JOIN public.commercial_lanes l ON l.id=r.lane_id AND l.is_active
 WHERE r.tenant_id=p_tenant_id AND r.rate_type='BUY' AND r.status='active' AND r.lane_id=v_lane AND r.service_catalog_item_id=v_service AND v.currency=v_currency AND v.valid_from<=v_date AND (v.valid_to IS NULL OR v.valid_to>=v_date)),'[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_apply_rate_to_quote(p_deal_id uuid, p_rate_version_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
DECLARE d public.crm_deals%ROWTYPE; r public.commercial_rate_cards%ROWTYPE; v public.commercial_rate_versions%ROWTYPE; l public.commercial_lanes%ROWTYPE; s public.service_catalog_items%ROWTYPE; v_total numeric; v_charges jsonb;
BEGIN
 SELECT * INTO d FROM public.crm_deals WHERE id=p_deal_id FOR UPDATE; IF NOT FOUND OR d.quote_reference IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
 IF NOT private.f8_admin(d.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 IF d.quote_status<>'draft' THEN RETURN jsonb_build_object('error','quote_not_editable'); END IF;
 SELECT * INTO v FROM public.commercial_rate_versions WHERE id=p_rate_version_id; IF NOT FOUND OR v.tenant_id<>d.tenant_id THEN RETURN jsonb_build_object('error','invalid_rate'); END IF;
 SELECT * INTO r FROM public.commercial_rate_cards WHERE id=v.rate_card_id; SELECT * INTO l FROM public.commercial_lanes WHERE id=r.lane_id; SELECT * INTO s FROM public.service_catalog_items WHERE id=r.service_catalog_item_id;
 IF r.status<>'active' OR r.current_version_id<>v.id OR v.valid_from>COALESCE((d.quote_payload->>'operational_window_start')::date,current_date) OR (v.valid_to IS NOT NULL AND v.valid_to<COALESCE((d.quote_payload->>'operational_window_start')::date,current_date)) THEN RETURN jsonb_build_object('error','rate_not_eligible'); END IF;
 IF upper(COALESCE(NULLIF(d.quote_payload->>'pricing_currency',''),NULLIF(d.quote_payload->>'currency',''),d.currency))<>v.currency
    OR (NULLIF(d.quote_payload->>'service_catalog_item_id','') IS NOT NULL AND (d.quote_payload->>'service_catalog_item_id')::uuid<>r.service_catalog_item_id)
    OR (jsonb_typeof(d.quote_payload->'origin_place')='object' AND private.f8_place_key(d.quote_payload->'origin_place')<>l.origin_key)
    OR (jsonb_typeof(d.quote_payload->'destination_place')='object' AND private.f8_place_key(d.quote_payload->'destination_place')<>l.destination_key)
    OR (NULLIF(d.quote_payload->>'operation_scope','') IS NOT NULL AND d.quote_payload->>'operation_scope'<>l.scope) THEN
   RETURN jsonb_build_object('error','rate_dimension_conflict');
 END IF;
 IF r.rate_type='SELL' AND r.customer_id IS DISTINCT FROM d.customer_id THEN RETURN jsonb_build_object('error','rate_not_eligible'); END IF;
 v_total:=private.f8_rate_total(v.id); SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.position),'[]'::jsonb) INTO v_charges FROM public.commercial_rate_charges c WHERE c.rate_version_id=v.id;
 IF r.rate_type='BUY' THEN
   UPDATE public.crm_deals SET quote_payload=quote_payload||jsonb_build_object('provider_id',r.provider_id,'provider_cost_amount',v_total,'currency',v.currency,'pricing_currency',v.currency,'service_type',s.service_type,'service_catalog_item_id',s.id,'service_catalog_snapshot',public.tanda1_service_snapshot(s.service_type,s.service_class,s.presentation,s.packaging,s.modality),'origin_place',l.origin_place,'destination_place',l.destination_place,'operation_scope',l.scope),updated_at=now() WHERE id=d.id;
 ELSE
   UPDATE public.crm_deals SET value=v_total,currency=v.currency,quote_payload=quote_payload||jsonb_build_object('customer_price_amount',v_total,'currency',v.currency,'pricing_currency',v.currency,'service_type',s.service_type,'service_catalog_item_id',s.id,'service_catalog_snapshot',public.tanda1_service_snapshot(s.service_type,s.service_class,s.presentation,s.packaging,s.modality),'origin_place',l.origin_place,'destination_place',l.destination_place,'operation_scope',l.scope),updated_at=now() WHERE id=d.id;
 END IF;
 INSERT INTO public.crm_quote_rate_snapshots(tenant_id,deal_id,rate_card_id,rate_version_id,rate_type,provider_id,customer_id,lane_id,service_catalog_item_id,charges_snapshot,total_amount,currency,selected_by)
 VALUES(d.tenant_id,d.id,r.id,v.id,r.rate_type,r.provider_id,r.customer_id,r.lane_id,r.service_catalog_item_id,v_charges,v_total,v.currency,auth.uid());
 INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(d.tenant_id,auth.uid(),'quote_rate_selected','quote',d.id,jsonb_build_object('rate_card_id',r.id,'rate_version_id',v.id,'rate_type',r.rate_type));
 RETURN jsonb_build_object('success',true,'rate_type',r.rate_type,'total_amount',v_total,'currency',v.currency);
EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN RETURN jsonb_build_object('error','invalid_quote_route');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_archive_rate(p_rate_card_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
DECLARE v_tenant uuid;
BEGIN SELECT tenant_id INTO v_tenant FROM public.commercial_rate_cards WHERE id=p_rate_card_id; IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF; IF NOT private.f8_admin(v_tenant) THEN RETURN jsonb_build_object('error','unauthorized'); END IF; UPDATE public.commercial_rate_cards SET status='archived',updated_at=now() WHERE id=p_rate_card_id; INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id) VALUES(v_tenant,auth.uid(),'rate_archived','commercial_rate',p_rate_card_id); RETURN jsonb_build_object('success',true); END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_duplicate_rate(p_rate_card_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
DECLARE r public.commercial_rate_cards%ROWTYPE; v public.commercial_rate_versions%ROWTYPE; v_payload jsonb;
BEGIN SELECT * INTO r FROM public.commercial_rate_cards WHERE id=p_rate_card_id; IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF; IF NOT private.f8_admin(r.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF; SELECT * INTO v FROM public.commercial_rate_versions WHERE id=r.current_version_id; v_payload:=jsonb_build_object('rate_type',r.rate_type,'provider_id',r.provider_id,'customer_id',r.customer_id,'lane_id',r.lane_id,'service_catalog_item_id',r.service_catalog_item_id,'currency',v.currency,'valid_from',v.valid_from,'valid_to',v.valid_to,'minimum_amount',v.minimum_amount,'notes',v.notes,'status','draft','charges',(SELECT jsonb_agg(jsonb_build_object('charge_type',c.charge_type,'description',c.description,'amount',c.amount,'unit_basis',c.unit_basis) ORDER BY c.position) FROM public.commercial_rate_charges c WHERE c.rate_version_id=v.id)); RETURN public.rpc_create_rate(r.tenant_id,v_payload); END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_upsert_business_contact(p_tenant_id uuid, p_contact_id uuid, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
DECLARE v_id uuid; v_customer uuid; v_provider uuid; v_primary boolean:=COALESCE((p_payload->>'is_primary')::boolean,false);
BEGIN
 IF NOT private.f8_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 BEGIN v_customer:=nullif(p_payload->>'customer_id','')::uuid;v_provider:=nullif(p_payload->>'provider_id','')::uuid; EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload'); END;
 IF (v_customer IS NOT NULL)::int+(v_provider IS NOT NULL)::int<>1 OR nullif(btrim(p_payload->>'name'),'') IS NULL OR (p_payload->>'contact_role') NOT IN ('commercial','operations','billing','management','other') THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
 IF v_customer IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.customers WHERE id=v_customer AND tenant_id=p_tenant_id) THEN RETURN jsonb_build_object('error','invalid_customer'); END IF;
 IF v_provider IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.logistics_providers WHERE id=v_provider AND tenant_id=p_tenant_id) THEN RETURN jsonb_build_object('error','invalid_provider'); END IF;
 IF v_primary THEN UPDATE public.business_contacts SET is_primary=false,updated_at=now() WHERE tenant_id=p_tenant_id AND is_active AND (customer_id=v_customer OR provider_id=v_provider); END IF;
 IF p_contact_id IS NULL THEN INSERT INTO public.business_contacts(tenant_id,customer_id,provider_id,name,contact_role,email,phone,is_primary,is_active,notes,created_by) VALUES(p_tenant_id,v_customer,v_provider,btrim(p_payload->>'name'),p_payload->>'contact_role',nullif(btrim(p_payload->>'email'),''),nullif(btrim(p_payload->>'phone'),''),v_primary,COALESCE((p_payload->>'is_active')::boolean,true),nullif(btrim(p_payload->>'notes'),''),auth.uid()) RETURNING id INTO v_id;
 ELSE UPDATE public.business_contacts SET customer_id=v_customer,provider_id=v_provider,name=btrim(p_payload->>'name'),contact_role=p_payload->>'contact_role',email=nullif(btrim(p_payload->>'email'),''),phone=nullif(btrim(p_payload->>'phone'),''),is_primary=v_primary,is_active=COALESCE((p_payload->>'is_active')::boolean,is_active),notes=nullif(btrim(p_payload->>'notes'),''),updated_at=now() WHERE id=p_contact_id AND tenant_id=p_tenant_id RETURNING id INTO v_id; IF v_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF; END IF;
 INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id) VALUES(p_tenant_id,auth.uid(),'partner_contact_upserted','business_contact',v_id); RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN unique_violation OR check_violation OR not_null_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_partner_contacts(p_tenant_id uuid, p_entity_type text, p_entity_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
BEGIN IF NOT private.f8_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF; IF p_entity_type NOT IN ('customer','provider') THEN RETURN jsonb_build_object('error','invalid_entity_type'); END IF; RETURN COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.is_primary DESC,c.name) FROM public.business_contacts c WHERE c.tenant_id=p_tenant_id AND ((p_entity_type='customer' AND c.customer_id=p_entity_id) OR (p_entity_type='provider' AND c.provider_id=p_entity_id))),'[]'::jsonb); END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_update_partner_terms(p_tenant_id uuid, p_entity_type text, p_entity_id uuid, p_payment_terms_days integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
DECLARE v_count int;
BEGIN IF NOT private.f8_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF; IF p_payment_terms_days NOT BETWEEN 0 AND 365 OR p_entity_type NOT IN ('customer','provider') THEN RETURN jsonb_build_object('error','invalid_payload'); END IF; IF p_entity_type='customer' THEN UPDATE public.customers SET payment_terms_days=p_payment_terms_days,updated_at=now() WHERE id=p_entity_id AND tenant_id=p_tenant_id; ELSE UPDATE public.logistics_providers SET payment_terms_days=p_payment_terms_days,updated_at=now() WHERE id=p_entity_id AND tenant_id=p_tenant_id; END IF; GET DIAGNOSTICS v_count=ROW_COUNT; IF v_count=0 THEN RETURN jsonb_build_object('error','not_found'); END IF; INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata) VALUES(p_tenant_id,auth.uid(),'partner_terms_updated',p_entity_type,p_entity_id,jsonb_build_object('payment_terms_days',p_payment_terms_days)); RETURN jsonb_build_object('success',true); END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_customer_partner_360(p_customer_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
DECLARE c public.customers%ROWTYPE;
BEGIN SELECT * INTO c FROM public.customers WHERE id=p_customer_id; IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF; IF NOT private.f8_admin(c.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 RETURN jsonb_build_object('customer',to_jsonb(c),'contacts',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.is_primary DESC,x.name) FROM public.business_contacts x WHERE x.customer_id=c.id AND x.is_active),'[]'::jsonb),'quotes',COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.updated_at DESC) FROM public.crm_deals d WHERE d.customer_id=c.id AND d.quote_reference IS NOT NULL),'[]'::jsonb),'operations',COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at DESC) FROM public.operations o WHERE o.customer_id=c.id),'[]'::jsonb),'rates',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'reference',r.reference,'status',r.status,'currency',v.currency,'total_amount',private.f8_rate_total(v.id),'valid_to',v.valid_to) ORDER BY r.updated_at DESC) FROM public.commercial_rate_cards r JOIN public.commercial_rate_versions v ON v.id=r.current_version_id WHERE r.customer_id=c.id),'[]'::jsonb),'profitability',COALESCE((SELECT jsonb_agg(jsonb_build_object('currency',q.pricing_currency,'sell',q.sell,'cost',q.cost,'expected_margin',q.sell-q.cost,'operations',q.operations)) FROM (SELECT o.pricing_currency,sum(coalesce(o.customer_price_amount,0)) sell,sum(coalesce(o.provider_cost_amount,0)) cost,count(*) operations FROM public.operations o WHERE o.customer_id=c.id GROUP BY o.pricing_currency) q),'[]'::jsonb),'finance',COALESCE((SELECT jsonb_agg(jsonb_build_object('currency',q.currency,'registered',q.registered,'collected',q.collected,'outstanding',q.registered-q.collected,'overdue',q.overdue)) FROM (SELECT i.currency,sum(i.amount) registered,sum(coalesce((SELECT sum(p.amount) FROM public.finance_payments p WHERE p.invoice_id=i.id),0)) collected,sum(CASE WHEN i.status='open' AND i.due_date<current_date THEN greatest(i.amount-coalesce((SELECT sum(p.amount) FROM public.finance_payments p WHERE p.invoice_id=i.id),0),0) ELSE 0 END) overdue FROM public.finance_invoices i WHERE i.customer_id=c.id AND i.direction='ar' AND i.status<>'void' GROUP BY i.currency) q),'[]'::jsonb),'activity',COALESCE((SELECT jsonb_agg(jsonb_build_object('action',a.action,'entity_type',a.entity_type,'created_at',a.created_at) ORDER BY a.created_at DESC) FROM (SELECT * FROM public.audit_log a WHERE a.tenant_id=c.tenant_id AND (a.entity_id=c.id OR a.entity_id IN (SELECT id FROM public.crm_deals WHERE customer_id=c.id) OR a.entity_id IN (SELECT id FROM public.operations WHERE customer_id=c.id)) ORDER BY a.created_at DESC LIMIT 50) a),'[]'::jsonb));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_provider_360(p_provider_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
DECLARE p public.logistics_providers%ROWTYPE;
BEGIN SELECT * INTO p FROM public.logistics_providers WHERE id=p_provider_id; IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF; IF NOT private.f8_admin(p.tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
 RETURN jsonb_build_object('provider',to_jsonb(p),'contacts',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.is_primary DESC,x.name) FROM public.business_contacts x WHERE x.provider_id=p.id AND x.is_active),'[]'::jsonb),'rates',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'reference',r.reference,'status',r.status,'lane_id',r.lane_id,'service_catalog_item_id',r.service_catalog_item_id,'currency',v.currency,'total_amount',private.f8_rate_total(v.id),'valid_to',v.valid_to) ORDER BY r.updated_at DESC) FROM public.commercial_rate_cards r JOIN public.commercial_rate_versions v ON v.id=r.current_version_id WHERE r.provider_id=p.id),'[]'::jsonb),'operations',COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at DESC) FROM public.operations o WHERE o.provider_id=p.id),'[]'::jsonb),'performance',(SELECT jsonb_build_object('operations',count(*),'active',count(*) FILTER(WHERE o.status NOT IN ('closed','cancelled')),'closed',count(*) FILTER(WHERE o.status='closed'),'cancelled',count(*) FILTER(WHERE o.status='cancelled'),'open_incidents',(SELECT count(*) FROM public.operation_incidents i JOIN public.operations oi ON oi.id=i.operation_id WHERE oi.provider_id=p.id AND i.status='open'),'blocking_incidents',(SELECT count(*) FROM public.operation_incidents i JOIN public.operations oi ON oi.id=i.operation_id WHERE oi.provider_id=p.id AND i.status='open' AND i.is_blocking)) FROM public.operations o WHERE o.provider_id=p.id),'finance',COALESCE((SELECT jsonb_agg(jsonb_build_object('currency',q.currency,'registered',q.registered,'paid',q.paid,'outstanding',q.registered-q.paid,'overdue',q.overdue)) FROM (SELECT i.currency,sum(i.amount) registered,sum(coalesce((SELECT sum(fp.amount) FROM public.finance_payments fp WHERE fp.invoice_id=i.id),0)) paid,sum(CASE WHEN i.status='open' AND i.due_date<current_date THEN greatest(i.amount-coalesce((SELECT sum(fp.amount) FROM public.finance_payments fp WHERE fp.invoice_id=i.id),0),0) ELSE 0 END) overdue FROM public.finance_invoices i WHERE i.provider_id=p.id AND i.direction='ap' AND i.status<>'void' GROUP BY i.currency) q),'[]'::jsonb),'activity',COALESCE((SELECT jsonb_agg(jsonb_build_object('action',a.action,'entity_type',a.entity_type,'created_at',a.created_at) ORDER BY a.created_at DESC) FROM (SELECT * FROM public.audit_log a WHERE a.tenant_id=p.tenant_id AND (a.entity_id=p.id OR a.entity_id IN (SELECT id FROM public.operations WHERE provider_id=p.id)) ORDER BY a.created_at DESC LIMIT 50) a),'[]'::jsonb));
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_export_rates(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public AS $function$
BEGIN IF NOT private.f8_admin(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF; RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('reference',r.reference,'rate_type',r.rate_type,'counterparty',coalesce(p.display_name,c.display_name),'lane',l.label,'scope',l.scope,'service',s.service_type,'currency',v.currency,'total_amount',private.f8_rate_total(v.id),'valid_from',v.valid_from,'valid_to',v.valid_to,'status',r.status,'version',v.version) ORDER BY r.reference) FROM public.commercial_rate_cards r JOIN public.commercial_rate_versions v ON v.id=r.current_version_id JOIN public.commercial_lanes l ON l.id=r.lane_id JOIN public.service_catalog_items s ON s.id=r.service_catalog_item_id LEFT JOIN public.logistics_providers p ON p.id=r.provider_id LEFT JOIN public.customers c ON c.id=r.customer_id WHERE r.tenant_id=p_tenant_id AND (NOT(p_filters?'rate_type') OR r.rate_type=upper(p_filters->>'rate_type'))),'[]'::jsonb); END;
$function$;

REVOKE ALL ON FUNCTION private.f8_place_key(jsonb), private.f8_admin(uuid), private.f8_rate_total(uuid), private.f8_protect_used_rate() FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_list_rate_reference_data(uuid), public.rpc_upsert_lane(uuid,uuid,jsonb), public.rpc_create_rate(uuid,jsonb), public.rpc_create_rate_version(uuid,jsonb), public.rpc_list_rates(uuid,jsonb), public.rpc_get_rate_360(uuid), public.rpc_compare_provider_rates(uuid,jsonb), public.rpc_apply_rate_to_quote(uuid,uuid), public.rpc_archive_rate(uuid), public.rpc_duplicate_rate(uuid), public.rpc_upsert_business_contact(uuid,uuid,jsonb), public.rpc_list_partner_contacts(uuid,text,uuid), public.rpc_update_partner_terms(uuid,text,uuid,integer), public.rpc_get_customer_partner_360(uuid), public.rpc_get_provider_360(uuid), public.rpc_export_rates(uuid,jsonb) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_rate_reference_data(uuid), public.rpc_upsert_lane(uuid,uuid,jsonb), public.rpc_create_rate(uuid,jsonb), public.rpc_create_rate_version(uuid,jsonb), public.rpc_list_rates(uuid,jsonb), public.rpc_get_rate_360(uuid), public.rpc_compare_provider_rates(uuid,jsonb), public.rpc_apply_rate_to_quote(uuid,uuid), public.rpc_archive_rate(uuid), public.rpc_duplicate_rate(uuid), public.rpc_upsert_business_contact(uuid,uuid,jsonb), public.rpc_list_partner_contacts(uuid,text,uuid), public.rpc_update_partner_terms(uuid,text,uuid,integer), public.rpc_get_customer_partner_360(uuid), public.rpc_get_provider_360(uuid), public.rpc_export_rates(uuid,jsonb) TO authenticated;
