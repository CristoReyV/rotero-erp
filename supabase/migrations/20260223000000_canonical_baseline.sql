-- ROTERO ERP canonical database baseline (DB.0B)
-- Creates a deterministic, data-free schema from an empty Supabase database.

BEGIN;

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ---------------------------------------------------------------------------
-- Tenant and identity boundary
-- ---------------------------------------------------------------------------

CREATE TABLE public.tenants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    slug text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.memberships (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    role text NOT NULL DEFAULT 'viewer',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT memberships_role_check CHECK (role IN ('admin', 'operator', 'finance', 'viewer')),
    CONSTRAINT memberships_user_tenant_key UNIQUE (user_id, tenant_id)
);

CREATE INDEX memberships_tenant_role_idx ON public.memberships (tenant_id, role);
CREATE INDEX memberships_user_idx ON public.memberships (user_id);

CREATE TABLE public.tenant_settings (
    tenant_id uuid PRIMARY KEY REFERENCES public.tenants(id) ON DELETE CASCADE,
    brand_name text NOT NULL DEFAULT 'ROTERO',
    primary_color text NOT NULL DEFAULT '#0F2B5B',
    logo_url text,
    timezone text NOT NULL DEFAULT 'America/Mexico_City',
    notifications_enabled boolean NOT NULL DEFAULT true,
    allow_demo_mode boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.invitations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    email text NOT NULL,
    role text NOT NULL DEFAULT 'viewer',
    token_hash text NOT NULL UNIQUE,
    created_by uuid NOT NULL,
    expires_at timestamptz NOT NULL,
    accepted_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT invitations_role_check CHECK (role IN ('admin', 'operator', 'finance', 'viewer')),
    CONSTRAINT invitations_email_check CHECK (email = lower(btrim(email)) AND position('@' IN email) > 1)
);

CREATE INDEX invitations_tenant_created_idx ON public.invitations (tenant_id, created_at DESC);

CREATE TABLE public.audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    actor_id uuid,
    action text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_log_metadata_object_check CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX audit_log_tenant_created_idx ON public.audit_log (tenant_id, created_at DESC);
CREATE INDEX audit_log_entity_idx ON public.audit_log (tenant_id, entity_type, entity_id);

-- ---------------------------------------------------------------------------
-- Broker-first operational network and commercial catalogs
-- ---------------------------------------------------------------------------

CREATE TABLE public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    display_name text NOT NULL,
    legal_name text,
    contact_name text,
    contact_email text,
    contact_phone text,
    tax_id text,
    billing_email text,
    notes text,
    is_active boolean NOT NULL DEFAULT true,
    preferred_currency text NOT NULL DEFAULT 'MXN',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customers_currency_check CHECK (preferred_currency IN ('MXN', 'USD'))
);

CREATE UNIQUE INDEX customers_tenant_display_name_uidx
    ON public.customers (tenant_id, lower(display_name));
CREATE INDEX customers_tenant_active_idx ON public.customers (tenant_id, is_active);
CREATE INDEX customers_tenant_tax_id_idx ON public.customers (tenant_id, tax_id) WHERE tax_id IS NOT NULL;

CREATE TABLE public.logistics_providers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    display_name text NOT NULL,
    legal_name text,
    tax_id text,
    contact_name text,
    contact_email text,
    contact_phone text,
    billing_email text,
    notes text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX logistics_providers_tenant_display_name_uidx
    ON public.logistics_providers (tenant_id, lower(display_name));
CREATE INDEX logistics_providers_tenant_active_idx
    ON public.logistics_providers (tenant_id, is_active);

CREATE TABLE public.service_catalog_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    service_type text NOT NULL,
    service_class text NOT NULL DEFAULT '',
    presentation text NOT NULL DEFAULT '',
    packaging text NOT NULL DEFAULT '',
    modality text NOT NULL DEFAULT '',
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX service_catalog_items_natural_key_uidx
    ON public.service_catalog_items (
        tenant_id,
        lower(service_type),
        lower(service_class),
        lower(presentation),
        lower(packaging),
        lower(modality)
    );
CREATE INDEX service_catalog_items_tenant_active_idx
    ON public.service_catalog_items (tenant_id, is_active);

CREATE TABLE public.drivers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    provider_id uuid REFERENCES public.logistics_providers(id) ON DELETE SET NULL,
    display_name text NOT NULL,
    phone text,
    license_ref text,
    status text NOT NULL DEFAULT 'available',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT drivers_status_check CHECK (status IN ('available', 'assigned', 'inactive'))
);

CREATE TABLE public.vehicles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    provider_id uuid REFERENCES public.logistics_providers(id) ON DELETE SET NULL,
    unit_code text NOT NULL,
    plate_ref text,
    vehicle_type text,
    status text NOT NULL DEFAULT 'available',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT vehicles_status_check CHECK (status IN ('available', 'assigned', 'maintenance', 'inactive')),
    CONSTRAINT vehicles_tenant_unit_key UNIQUE (tenant_id, unit_code)
);

CREATE INDEX drivers_tenant_status_idx ON public.drivers (tenant_id, status);
CREATE INDEX vehicles_tenant_status_idx ON public.vehicles (tenant_id, status);

CREATE TABLE public.crm_deals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    title text NOT NULL,
    company_name text,
    contact_name text,
    contact_email text,
    contact_phone text,
    value numeric(14,2),
    currency text NOT NULL DEFAULT 'MXN',
    stage text NOT NULL DEFAULT 'lead',
    priority text NOT NULL DEFAULT 'medium',
    owner_user_id uuid,
    notes text,
    last_touch_at timestamptz,
    quote_status text NOT NULL DEFAULT 'draft',
    quote_reference text,
    quote_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    approved_at timestamptz,
    approved_by uuid,
    approval_note text,
    rejected_at timestamptz,
    rejected_by uuid,
    rejection_note text,
    converted_operation_id uuid,
    converted_at timestamptz,
    converted_by uuid,
    conversion_note text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT crm_deals_currency_check CHECK (currency IN ('MXN', 'USD')),
    CONSTRAINT crm_deals_stage_check CHECK (stage IN ('lead', 'qualified', 'proposal', 'won', 'lost')),
    CONSTRAINT crm_deals_priority_check CHECK (priority IN ('low', 'medium', 'high')),
    CONSTRAINT crm_deals_quote_status_check CHECK (quote_status IN ('draft', 'review', 'approved', 'rejected', 'converted')),
    CONSTRAINT crm_deals_quote_payload_object_check CHECK (jsonb_typeof(quote_payload) = 'object')
);

CREATE INDEX crm_deals_tenant_stage_idx ON public.crm_deals (tenant_id, stage, updated_at DESC);
CREATE UNIQUE INDEX crm_deals_tenant_quote_reference_uidx
    ON public.crm_deals (tenant_id, quote_reference) WHERE quote_reference IS NOT NULL;

CREATE TABLE public.crm_deal_activity (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    deal_id uuid NOT NULL REFERENCES public.crm_deals(id) ON DELETE CASCADE,
    actor_id uuid,
    activity_type text NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.crm_deal_notes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    deal_id uuid NOT NULL REFERENCES public.crm_deals(id) ON DELETE CASCADE,
    author_id uuid,
    note text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.crm_deal_checklist_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    deal_id uuid NOT NULL REFERENCES public.crm_deals(id) ON DELETE CASCADE,
    label text NOT NULL,
    is_complete boolean NOT NULL DEFAULT false,
    completed_by uuid,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Operations and logistics file
-- ---------------------------------------------------------------------------

CREATE TABLE public.operations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    reference_code text NOT NULL,
    route_summary text,
    client_display_name text,
    destination_city text,
    eta_display text,
    status text NOT NULL DEFAULT 'draft',
    origin_place jsonb,
    destination_place jsonb,
    eta timestamptz,
    driver_id uuid REFERENCES public.drivers(id) ON DELETE SET NULL,
    vehicle_id uuid REFERENCES public.vehicles(id) ON DELETE SET NULL,
    planned_departure timestamptz,
    priority text NOT NULL DEFAULT 'normal',
    required_documents jsonb NOT NULL DEFAULT '[]'::jsonb,
    driver_name text,
    vehicle_ref text,
    assigned_at timestamptz,
    closed_at timestamptz,
    cancelled_at timestamptz,
    service_type text,
    operational_window_start timestamptz,
    operational_window_end timestamptz,
    notes text,
    cargo_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    source_deal_id uuid,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    operation_scope text NOT NULL DEFAULT 'national',
    execution_type text NOT NULL DEFAULT 'third_party',
    provider_id uuid REFERENCES public.logistics_providers(id) ON DELETE SET NULL,
    provider_name text,
    external_driver jsonb NOT NULL DEFAULT '{}'::jsonb,
    external_vehicle jsonb NOT NULL DEFAULT '{}'::jsonb,
    provider_cost numeric(14,2),
    customer_price numeric(14,2),
    pricing_currency text NOT NULL DEFAULT 'MXN',
    service_catalog_item_id uuid REFERENCES public.service_catalog_items(id) ON DELETE SET NULL,
    service_catalog_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    boxes_placed_days integer NOT NULL DEFAULT 0,
    documentation_received_at timestamptz,
    documentation_note text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT operations_tenant_reference_key UNIQUE (tenant_id, reference_code),
    CONSTRAINT operations_status_check CHECK (status IN ('draft', 'planned', 'assigned', 'in_transit', 'delivered', 'cancelled', 'closed')),
    CONSTRAINT operations_priority_check CHECK (priority IN ('low', 'normal', 'high')),
    CONSTRAINT operations_scope_check CHECK (operation_scope IN ('national', 'international')),
    CONSTRAINT operations_execution_type_check CHECK (execution_type IN ('third_party', 'own_fleet')),
    CONSTRAINT operations_currency_check CHECK (pricing_currency IN ('MXN', 'USD')),
    CONSTRAINT operations_boxes_placed_days_check CHECK (boxes_placed_days >= 0),
    CONSTRAINT operations_required_documents_array_check CHECK (jsonb_typeof(required_documents) = 'array'),
    CONSTRAINT operations_cargo_summary_object_check CHECK (jsonb_typeof(cargo_summary) = 'object'),
    CONSTRAINT operations_external_driver_object_check CHECK (jsonb_typeof(external_driver) = 'object'),
    CONSTRAINT operations_external_vehicle_object_check CHECK (jsonb_typeof(external_vehicle) = 'object'),
    CONSTRAINT operations_service_snapshot_object_check CHECK (jsonb_typeof(service_catalog_snapshot) = 'object'),
    CONSTRAINT operations_pricing_nonnegative_check CHECK (
        (provider_cost IS NULL OR provider_cost >= 0) AND
        (customer_price IS NULL OR customer_price >= 0)
    )
);

ALTER TABLE public.operations
    ADD CONSTRAINT operations_source_deal_fk
    FOREIGN KEY (source_deal_id) REFERENCES public.crm_deals(id) ON DELETE SET NULL;

ALTER TABLE public.crm_deals
    ADD CONSTRAINT crm_deals_converted_operation_fk
    FOREIGN KEY (converted_operation_id) REFERENCES public.operations(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX operations_source_deal_uidx
    ON public.operations (source_deal_id) WHERE source_deal_id IS NOT NULL;
CREATE UNIQUE INDEX crm_deals_converted_operation_uidx
    ON public.crm_deals (converted_operation_id) WHERE converted_operation_id IS NOT NULL;
CREATE INDEX operations_tenant_created_idx ON public.operations (tenant_id, created_at DESC);
CREATE INDEX operations_tenant_status_idx ON public.operations (tenant_id, status, created_at DESC);
CREATE INDEX operations_tenant_customer_idx ON public.operations (tenant_id, customer_id);
CREATE INDEX operations_driver_idx ON public.operations (driver_id) WHERE driver_id IS NOT NULL;
CREATE INDEX operations_execution_idx ON public.operations (tenant_id, execution_type);
CREATE INDEX operations_service_catalog_idx ON public.operations (service_catalog_item_id) WHERE service_catalog_item_id IS NOT NULL;
CREATE INDEX operations_window_idx ON public.operations (tenant_id, operational_window_start, operational_window_end);

-- ---------------------------------------------------------------------------
-- Tracking
-- ---------------------------------------------------------------------------

CREATE TABLE public.tracking_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    operation_id uuid NOT NULL REFERENCES public.operations(id) ON DELETE CASCADE,
    scope text NOT NULL,
    token_hash text NOT NULL UNIQUE,
    state text NOT NULL DEFAULT 'active',
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid NOT NULL,
    expires_at timestamptz NOT NULL,
    delivered_at timestamptz,
    revoked_at timestamptz,
    revoked_by uuid,
    rotated_into uuid REFERENCES public.tracking_tokens(id) ON DELETE SET NULL,
    last_used_at timestamptz,
    event_count integer NOT NULL DEFAULT 0,
    ip_hash_last text,
    user_agent_last text,
    CONSTRAINT tracking_tokens_scope_check CHECK (scope IN ('public:read', 'driver:write')),
    CONSTRAINT tracking_tokens_state_check CHECK (state IN ('active', 'soft_expired', 'hard_expired', 'revoked', 'rotated')),
    CONSTRAINT tracking_tokens_event_count_check CHECK (event_count >= 0)
);

CREATE UNIQUE INDEX tracking_tokens_active_operation_scope_uidx
    ON public.tracking_tokens (operation_id, scope) WHERE state = 'active';
CREATE INDEX tracking_tokens_operation_idx ON public.tracking_tokens (operation_id, created_at DESC);
CREATE INDEX tracking_tokens_expiry_idx ON public.tracking_tokens (state, expires_at);

CREATE TABLE public.tracking_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    token_id uuid NOT NULL REFERENCES public.tracking_tokens(id) ON DELETE CASCADE,
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    operation_id uuid NOT NULL REFERENCES public.operations(id) ON DELETE CASCADE,
    event_type text NOT NULL,
    source text NOT NULL,
    client_timestamp timestamptz NOT NULL,
    server_timestamp timestamptz NOT NULL DEFAULT now(),
    lat numeric(9,6),
    lng numeric(9,6),
    accuracy_m numeric(7,2),
    municipality text,
    state_name text,
    country_code char(2) NOT NULL DEFAULT 'MX',
    incident_type text,
    incident_note text,
    is_suspicious boolean NOT NULL DEFAULT false,
    offline_queued boolean NOT NULL DEFAULT false,
    CONSTRAINT tracking_events_type_check CHECK (event_type IN ('departure', 'in_transit', 'arrival', 'delivered', 'incident', 'location_reset')),
    CONSTRAINT tracking_events_source_check CHECK (source IN ('gps', 'manual', 'none')),
    CONSTRAINT tracking_events_incident_fields_check CHECK (
        (event_type = 'incident' AND incident_type IS NOT NULL) OR
        (event_type <> 'incident' AND incident_type IS NULL AND incident_note IS NULL)
    ),
    CONSTRAINT tracking_events_incident_note_length_check CHECK (incident_note IS NULL OR length(incident_note) <= 280),
    CONSTRAINT tracking_events_coords_check CHECK (
        (source = 'gps' AND lat IS NOT NULL AND lng IS NOT NULL) OR source IN ('manual', 'none')
    )
);

CREATE INDEX tracking_events_timeline_idx ON public.tracking_events (operation_id, server_timestamp DESC);
CREATE INDEX tracking_events_idempotency_idx ON public.tracking_events (token_id, event_type, client_timestamp);
CREATE INDEX tracking_events_token_type_idx ON public.tracking_events (token_id, event_type, server_timestamp DESC);

CREATE TABLE public.tracking_route_points (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    operation_id uuid NOT NULL REFERENCES public.operations(id) ON DELETE CASCADE,
    token_id uuid NOT NULL REFERENCES public.tracking_tokens(id) ON DELETE CASCADE,
    lat double precision NOT NULL,
    lng double precision NOT NULL,
    accuracy_m double precision,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    source text NOT NULL,
    CONSTRAINT tracking_route_points_source_check CHECK (source IN ('gps', 'network'))
);

CREATE INDEX tracking_route_points_operation_time_idx
    ON public.tracking_route_points (tenant_id, operation_id, recorded_at DESC);
CREATE INDEX tracking_route_points_token_time_idx
    ON public.tracking_route_points (token_id, recorded_at DESC);

CREATE TABLE public.tracking_access_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    token_hash text NOT NULL,
    accessed_at timestamptz NOT NULL DEFAULT now(),
    ip_hash text,
    user_agent text,
    country_code char(2)
);

CREATE INDEX tracking_access_log_hash_idx ON public.tracking_access_log (token_hash, accessed_at DESC);

-- ---------------------------------------------------------------------------
-- Billing and finance (ERP-only; no SAT/PAC production integration)
-- ---------------------------------------------------------------------------

CREATE TABLE public.billing_cfdis (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    operation_id uuid REFERENCES public.operations(id) ON DELETE SET NULL,
    uuid_fiscal text,
    serie text,
    folio text,
    tipo text NOT NULL DEFAULT 'I',
    status text NOT NULL DEFAULT 'draft',
    currency text NOT NULL DEFAULT 'MXN',
    subtotal numeric(14,2) NOT NULL DEFAULT 0,
    tax_total numeric(14,2) NOT NULL DEFAULT 0,
    total numeric(14,2) NOT NULL DEFAULT 0,
    rfc_emisor text,
    rfc_receptor text,
    issued_at timestamptz,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT billing_cfdis_status_check CHECK (status IN ('draft', 'ready', 'issued', 'cancelled')),
    CONSTRAINT billing_cfdis_currency_check CHECK (currency IN ('MXN', 'USD')),
    CONSTRAINT billing_cfdis_amounts_check CHECK (subtotal >= 0 AND tax_total >= 0 AND total >= 0),
    CONSTRAINT billing_cfdis_payload_object_check CHECK (jsonb_typeof(payload) = 'object')
);

CREATE UNIQUE INDEX billing_cfdis_tenant_uuid_uidx
    ON public.billing_cfdis (tenant_id, uuid_fiscal) WHERE uuid_fiscal IS NOT NULL;
CREATE INDEX billing_cfdis_tenant_status_idx ON public.billing_cfdis (tenant_id, status, created_at DESC);

CREATE TABLE public.billing_carta_porte (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    cfdi_id uuid NOT NULL UNIQUE REFERENCES public.billing_cfdis(id) ON DELETE CASCADE,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    status text NOT NULL DEFAULT 'draft',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT billing_carta_porte_status_check CHECK (status IN ('draft', 'ready', 'issued', 'cancelled')),
    CONSTRAINT billing_carta_porte_payload_object_check CHECK (jsonb_typeof(payload) = 'object')
);

CREATE TABLE public.operation_billing (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    operation_id uuid NOT NULL UNIQUE REFERENCES public.operations(id) ON DELETE CASCADE,
    status text NOT NULL DEFAULT 'pending',
    currency text NOT NULL DEFAULT 'MXN',
    amount numeric(14,2) NOT NULL DEFAULT 0,
    linked_cfdi_id uuid REFERENCES public.billing_cfdis(id) ON DELETE SET NULL,
    admin_closed_at timestamptz,
    admin_closed_by uuid,
    voided_at timestamptz,
    voided_by uuid,
    void_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT operation_billing_status_check CHECK (status IN ('pending', 'ready', 'issued', 'void')),
    CONSTRAINT operation_billing_currency_check CHECK (currency IN ('MXN', 'USD')),
    CONSTRAINT operation_billing_amount_check CHECK (amount >= 0)
);

CREATE INDEX operation_billing_tenant_status_idx ON public.operation_billing (tenant_id, status, created_at DESC);

CREATE TABLE public.finance_invoices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    operation_id uuid REFERENCES public.operations(id) ON DELETE SET NULL,
    invoice_number text NOT NULL,
    status text NOT NULL DEFAULT 'draft',
    currency text NOT NULL DEFAULT 'MXN',
    amount numeric(14,2) NOT NULL,
    due_date date,
    issued_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT finance_invoices_tenant_number_key UNIQUE (tenant_id, invoice_number),
    CONSTRAINT finance_invoices_status_check CHECK (status IN ('draft', 'issued', 'partial', 'paid', 'overdue', 'cancelled')),
    CONSTRAINT finance_invoices_currency_check CHECK (currency IN ('MXN', 'USD')),
    CONSTRAINT finance_invoices_amount_check CHECK (amount >= 0)
);

CREATE INDEX finance_invoices_tenant_status_idx ON public.finance_invoices (tenant_id, status, created_at DESC);

CREATE TABLE public.finance_payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    invoice_id uuid NOT NULL REFERENCES public.finance_invoices(id) ON DELETE CASCADE,
    amount numeric(14,2) NOT NULL,
    currency text NOT NULL DEFAULT 'MXN',
    paid_at timestamptz NOT NULL DEFAULT now(),
    method text,
    reference text,
    created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT finance_payments_amount_check CHECK (amount > 0),
    CONSTRAINT finance_payments_currency_check CHECK (currency IN ('MXN', 'USD'))
);

CREATE INDEX finance_payments_tenant_invoice_idx ON public.finance_payments (tenant_id, invoice_id, paid_at DESC);

-- Existing non-core modules are preserved as small canonical catalogs because
-- current application RPCs reference them. No operational rows are created.
CREATE TABLE public.inventory_lots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    sku text NOT NULL,
    description text,
    quantity numeric(14,3) NOT NULL DEFAULT 0,
    unit text NOT NULL DEFAULT 'unit',
    status text NOT NULL DEFAULT 'available',
    received_at timestamptz NOT NULL DEFAULT now(),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_lots_quantity_check CHECK (quantity >= 0)
);

CREATE INDEX inventory_lots_tenant_sku_idx ON public.inventory_lots (tenant_id, sku);

CREATE TABLE public.customs_pedimentos (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    pedimento_number text NOT NULL,
    status text NOT NULL DEFAULT 'draft',
    customs_office text,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customs_pedimentos_tenant_number_key UNIQUE (tenant_id, pedimento_number)
);

CREATE TABLE public.customs_descargo_lines (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    pedimento_id uuid NOT NULL REFERENCES public.customs_pedimentos(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customs_descargo_lines_sequence_check CHECK (sequence_no > 0),
    CONSTRAINT customs_descargo_lines_key UNIQUE (pedimento_id, sequence_no)
);

-- ---------------------------------------------------------------------------
-- Shared deterministic triggers
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$function$;

CREATE TRIGGER tenants_settings_touch_updated_at
    BEFORE UPDATE ON public.tenant_settings
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER customers_touch_updated_at
    BEFORE UPDATE ON public.customers
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER logistics_providers_touch_updated_at
    BEFORE UPDATE ON public.logistics_providers
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER service_catalog_items_touch_updated_at
    BEFORE UPDATE ON public.service_catalog_items
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER drivers_touch_updated_at
    BEFORE UPDATE ON public.drivers
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER vehicles_touch_updated_at
    BEFORE UPDATE ON public.vehicles
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER crm_deals_touch_updated_at
    BEFORE UPDATE ON public.crm_deals
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER operations_touch_updated_at
    BEFORE UPDATE ON public.operations
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER billing_cfdis_touch_updated_at
    BEFORE UPDATE ON public.billing_cfdis
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER billing_carta_porte_touch_updated_at
    BEFORE UPDATE ON public.billing_carta_porte
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER operation_billing_touch_updated_at
    BEFORE UPDATE ON public.operation_billing
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER finance_invoices_touch_updated_at
    BEFORE UPDATE ON public.finance_invoices
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER inventory_lots_touch_updated_at
    BEFORE UPDATE ON public.inventory_lots
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER customs_pedimentos_touch_updated_at
    BEFORE UPDATE ON public.customs_pedimentos
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- RBAC helpers and safe identity contracts
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.tanda1_user_is_member(p_tenant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.memberships AS m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
    );
$function$;

CREATE FUNCTION public.tanda1_user_has_role(p_tenant_id uuid, p_roles text[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.memberships AS m
        WHERE m.user_id = auth.uid()
          AND m.tenant_id = p_tenant_id
          AND m.role = ANY(p_roles)
    );
$function$;

CREATE FUNCTION public.rpc_get_my_context()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT jsonb_build_object(
        'user_id', auth.uid(),
        'email', (SELECT u.email FROM auth.users AS u WHERE u.id = auth.uid()),
        'memberships', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'tenant_id', m.tenant_id,
                'tenant_name', t.name,
                'role', m.role
            ) ORDER BY t.name)
            FROM public.memberships AS m
            JOIN public.tenants AS t ON t.id = m.tenant_id
            WHERE m.user_id = auth.uid()
        ), '[]'::jsonb)
    );
$function$;

-- Scoped replacement for the unsafe public.users catalog view.
CREATE FUNCTION public.rpc_list_members(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'user_id', m.user_id,
            'role', m.role,
            'created_at', m.created_at,
            'email', u.email,
            'name', u.raw_user_meta_data ->> 'full_name'
        ) ORDER BY m.created_at)
        FROM public.memberships AS m
        JOIN auth.users AS u ON u.id = m.user_id
        WHERE m.tenant_id = p_tenant_id
    ), '[]'::jsonb);
END;
$function$;

-- ---------------------------------------------------------------------------
-- Essential operations RPCs
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.rpc_list_operations(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at DESC)
        FROM public.operations AS o
        WHERE o.tenant_id = p_tenant_id
    ), '[]'::jsonb);
END;
$function$;

CREATE FUNCTION public.rpc_get_operation(p_operation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_operation public.operations%ROWTYPE;
BEGIN
    SELECT o.* INTO v_operation
    FROM public.operations AS o
    WHERE o.id = p_operation_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;
    IF NOT public.tanda1_user_is_member(v_operation.tenant_id) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    RETURN to_jsonb(v_operation);
END;
$function$;

CREATE FUNCTION public.rpc_create_operation(
    p_tenant_id uuid,
    p_reference_code text,
    p_route_summary text DEFAULT NULL,
    p_client_display_name text DEFAULT NULL,
    p_destination_city text DEFAULT NULL,
    p_eta_display text DEFAULT NULL,
    p_status text DEFAULT 'draft',
    p_origin_place jsonb DEFAULT NULL,
    p_destination_place jsonb DEFAULT NULL,
    p_eta timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_id uuid;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    INSERT INTO public.operations (
        tenant_id, reference_code, route_summary, client_display_name,
        destination_city, eta_display, status, origin_place,
        destination_place, eta
    ) VALUES (
        p_tenant_id, p_reference_code, p_route_summary, p_client_display_name,
        p_destination_city, p_eta_display, p_status, p_origin_place,
        p_destination_place, p_eta
    ) RETURNING id INTO v_id;

    RETURN jsonb_build_object('id', v_id);
EXCEPTION
    WHEN unique_violation THEN
        RETURN jsonb_build_object('error', 'reference_conflict');
    WHEN check_violation THEN
        RETURN jsonb_build_object('error', 'invalid_payload');
END;
$function$;

CREATE FUNCTION public.rpc_get_operation_requirements(p_operation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_operation public.operations%ROWTYPE;
BEGIN
    SELECT o.* INTO v_operation FROM public.operations AS o WHERE o.id = p_operation_id;
    IF NOT FOUND OR NOT public.tanda1_user_is_member(v_operation.tenant_id) THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;
    RETURN jsonb_build_object(
        'has_driver_assigned', v_operation.driver_id IS NOT NULL OR v_operation.external_driver <> '{}'::jsonb,
        'has_driver_token', EXISTS (
            SELECT 1 FROM public.tracking_tokens t
            WHERE t.operation_id = p_operation_id AND t.scope = 'driver:write' AND t.state = 'active'
        ),
        'has_public_token', EXISTS (
            SELECT 1 FROM public.tracking_tokens t
            WHERE t.operation_id = p_operation_id AND t.scope = 'public:read' AND t.state = 'active'
        ),
        'has_delivered_event', EXISTS (
            SELECT 1 FROM public.tracking_events e
            WHERE e.operation_id = p_operation_id AND e.event_type = 'delivered'
        )
    );
END;
$function$;

-- ---------------------------------------------------------------------------
-- Tracking contracts. Internal functions intentionally match the pre-M4.1
-- signatures so PR #10 can replace them without any archived migration.
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.tracking_hash_token(p_token text)
RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path TO pg_catalog, public, extensions
AS $function$
    SELECT encode(extensions.digest(p_token, 'sha256'), 'hex');
$function$;

CREATE FUNCTION public.tracking_validate_token(p_token text, p_required_scope text)
RETURNS TABLE (
    token_id uuid,
    tenant_id uuid,
    operation_id uuid,
    token_scope text,
    token_state text,
    expires_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public, extensions
AS $function$
    SELECT t.id, t.tenant_id, t.operation_id, t.scope, t.state, t.expires_at
    FROM public.tracking_tokens AS t
    WHERE t.token_hash = public.tracking_hash_token(p_token)
      AND t.scope = p_required_scope
    LIMIT 1;
$function$;

CREATE FUNCTION public.rpc_create_tracking_token(
    p_tenant_id uuid,
    p_operation_id uuid,
    p_scope text,
    p_ttl_hours integer,
    p_force_rotate boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public, extensions
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_operation_tenant uuid;
    v_literal text;
    v_hash text;
    v_new_id uuid;
    v_existing public.tracking_tokens%ROWTYPE;
    v_ttl interval;
BEGIN
    IF v_actor IS NULL OR NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF p_scope NOT IN ('public:read', 'driver:write') THEN
        RETURN jsonb_build_object('error', 'invalid_scope');
    END IF;
    IF p_ttl_hours IS NOT NULL AND p_ttl_hours <= 0 THEN
        RETURN jsonb_build_object('error', 'invalid_ttl');
    END IF;
    IF p_ttl_hours IS NOT NULL AND (
        (p_scope = 'public:read' AND p_ttl_hours > 720) OR
        (p_scope = 'driver:write' AND p_ttl_hours > 72)
    ) THEN
        RETURN jsonb_build_object('error', 'ttl_exceeds_max');
    END IF;

    SELECT o.tenant_id INTO v_operation_tenant
    FROM public.operations AS o
    WHERE o.id = p_operation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'not_found');
    END IF;
    IF v_operation_tenant IS DISTINCT FROM p_tenant_id THEN
        RETURN jsonb_build_object('error', 'forbidden');
    END IF;

    SELECT t.* INTO v_existing
    FROM public.tracking_tokens AS t
    WHERE t.operation_id = p_operation_id
      AND t.scope = p_scope
      AND t.state = 'active'
    FOR UPDATE;

    IF v_existing.id IS NOT NULL AND NOT COALESCE(p_force_rotate, false) THEN
        RETURN jsonb_build_object(
            'token_id', v_existing.id,
            'scope', v_existing.scope,
            'expires_at', v_existing.expires_at,
            'already_existed', true
        );
    END IF;

    v_ttl := CASE
        WHEN p_ttl_hours IS NOT NULL THEN make_interval(hours => p_ttl_hours)
        WHEN p_scope = 'public:read' THEN interval '7 days'
        ELSE interval '48 hours'
    END;

    IF v_existing.id IS NOT NULL THEN
        UPDATE public.tracking_tokens
        SET state = 'rotated', revoked_at = now(), revoked_by = v_actor
        WHERE id = v_existing.id;
    END IF;

    v_literal := gen_random_uuid()::text;
    v_hash := public.tracking_hash_token(v_literal);
    INSERT INTO public.tracking_tokens (
        tenant_id, operation_id, scope, token_hash, state,
        created_by, expires_at
    ) VALUES (
        p_tenant_id, p_operation_id, p_scope, v_hash, 'active',
        v_actor, now() + v_ttl
    ) RETURNING id INTO v_new_id;

    IF v_existing.id IS NOT NULL THEN
        UPDATE public.tracking_tokens SET rotated_into = v_new_id WHERE id = v_existing.id;
    END IF;

    RETURN jsonb_build_object(
        'token_id', v_new_id,
        'token', v_literal,
        'scope', p_scope,
        'expires_at', now() + v_ttl,
        'rotated_previous', v_existing.id IS NOT NULL,
        'already_existed', false
    );
EXCEPTION
    WHEN unique_violation THEN
        RETURN jsonb_build_object('error', 'conflict');
    WHEN OTHERS THEN
        RETURN jsonb_build_object('error', 'internal_error');
END;
$function$;

CREATE FUNCTION public.rpc_create_tracking_token(
    p_tenant_id uuid,
    p_operation_id uuid,
    p_scope text
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT public.rpc_create_tracking_token(
        p_tenant_id, p_operation_id, p_scope, NULL::integer, false
    );
$function$;

CREATE FUNCTION public.rpc_revoke_tracking_token(p_token_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_token public.tracking_tokens%ROWTYPE;
BEGIN
    IF v_actor IS NULL THEN
        RETURN jsonb_build_object('success', false, 'status', 'forbidden');
    END IF;
    SELECT t.* INTO v_token FROM public.tracking_tokens AS t WHERE t.id = p_token_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'status', 'not_found');
    END IF;
    IF NOT public.tanda1_user_has_role(v_token.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('success', false, 'status', 'forbidden');
    END IF;
    IF v_token.state = 'revoked' THEN
        RETURN jsonb_build_object('success', true, 'status', 'already_revoked', 'already_revoked', true);
    END IF;
    IF v_token.state = 'rotated' THEN
        RETURN jsonb_build_object('success', false, 'status', 'rotated');
    END IF;
    IF v_token.state <> 'active' THEN
        RETURN jsonb_build_object('success', false, 'status', v_token.state);
    END IF;
    UPDATE public.tracking_tokens
    SET state = 'revoked', revoked_at = now(), revoked_by = v_actor
    WHERE id = p_token_id;
    RETURN jsonb_build_object('success', true, 'status', 'revoked');
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'status', 'internal_error');
END;
$function$;

CREATE FUNCTION public.rpc_list_tracking_tokens(p_tenant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator', 'viewer']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'id', t.id,
            'operation_id', t.operation_id,
            'scope', t.scope,
            'state', t.state,
            'created_at', t.created_at,
            'expires_at', t.expires_at,
            'last_used_at', t.last_used_at,
            'reference_code', o.reference_code,
            'route_summary', o.route_summary,
            'client_display_name', o.client_display_name,
            'operation_status', o.status
        ) ORDER BY t.created_at DESC)
        FROM public.tracking_tokens AS t
        JOIN public.operations AS o ON o.id = t.operation_id
        WHERE t.tenant_id = p_tenant_id
    ), '[]'::jsonb);
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('error', 'internal_error');
END;
$function$;

CREATE FUNCTION public.rpc_get_public_tracking(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public, extensions
AS $function$
DECLARE
    v_token record;
    v_operation public.operations%ROWTYPE;
BEGIN
    SELECT * INTO v_token FROM public.tracking_validate_token(p_token, 'public:read');
    IF v_token.token_id IS NULL THEN
        RETURN jsonb_build_object('http', 404, 'error', 'not_found');
    END IF;
    IF v_token.token_state <> 'active' OR v_token.expires_at <= now() THEN
        RETURN jsonb_build_object('http', 403, 'error', 'expired');
    END IF;
    SELECT o.* INTO v_operation FROM public.operations AS o WHERE o.id = v_token.operation_id;
    UPDATE public.tracking_tokens SET last_used_at = now() WHERE id = v_token.token_id;
    RETURN jsonb_build_object(
        'http', 200,
        'operation', jsonb_build_object(
            'reference_code', v_operation.reference_code,
            'route_summary', v_operation.route_summary,
            'client_display_name', v_operation.client_display_name,
            'status', v_operation.status,
            'eta_display', v_operation.eta_display
        ),
        'events', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'event_type', e.event_type,
                'server_timestamp', e.server_timestamp,
                'municipality', e.municipality,
                'state_name', e.state_name
            ) ORDER BY e.server_timestamp)
            FROM public.tracking_events AS e
            WHERE e.operation_id = v_token.operation_id
              AND NOT e.is_suspicious
        ), '[]'::jsonb)
    );
END;
$function$;

CREATE FUNCTION public.rpc_get_driver_view(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public, extensions
AS $function$
DECLARE
    v_token record;
    v_operation public.operations%ROWTYPE;
BEGIN
    SELECT * INTO v_token FROM public.tracking_validate_token(p_token, 'driver:write');
    IF v_token.token_id IS NULL THEN
        RETURN jsonb_build_object('http', 404, 'error', 'not_found');
    END IF;
    IF v_token.token_state <> 'active' OR v_token.expires_at <= now() THEN
        RETURN jsonb_build_object('http', 403, 'error', 'expired');
    END IF;
    SELECT o.* INTO v_operation FROM public.operations AS o WHERE o.id = v_token.operation_id;
    UPDATE public.tracking_tokens SET last_used_at = now() WHERE id = v_token.token_id;
    RETURN jsonb_build_object(
        'http', 200,
        'operation_id', v_operation.id,
        'reference_code', v_operation.reference_code,
        'status', v_operation.status,
        'origin_place', v_operation.origin_place,
        'destination_place', v_operation.destination_place
    );
END;
$function$;

CREATE FUNCTION public.rpc_post_driver_event(
    p_token text,
    p_action text,
    p_source text DEFAULT 'gps',
    p_lat numeric DEFAULT NULL,
    p_lng numeric DEFAULT NULL,
    p_accuracy numeric DEFAULT NULL,
    p_municipality text DEFAULT NULL,
    p_state_name text DEFAULT NULL,
    p_country_code char DEFAULT 'MX',
    p_incident_type text DEFAULT NULL,
    p_incident_note text DEFAULT NULL,
    p_client_timestamp timestamptz DEFAULT now(),
    p_offline_queued boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public, extensions
AS $function$
DECLARE
    v_token record;
    v_event_id uuid;
BEGIN
    SELECT * INTO v_token FROM public.tracking_validate_token(p_token, 'driver:write');
    IF v_token.token_id IS NULL THEN
        RETURN jsonb_build_object('http', 404, 'accepted', false, 'reason', 'not_found');
    END IF;
    IF v_token.token_state <> 'active' OR v_token.expires_at <= now() THEN
        RETURN jsonb_build_object('http', 403, 'accepted', false, 'reason', 'expired');
    END IF;
    IF p_action NOT IN ('departure', 'in_transit', 'arrival', 'delivered', 'incident', 'location_reset') THEN
        RETURN jsonb_build_object('http', 400, 'accepted', false, 'reason', 'invalid_action');
    END IF;
    IF p_source NOT IN ('gps', 'manual', 'none') THEN
        RETURN jsonb_build_object('http', 400, 'accepted', false, 'reason', 'invalid_source');
    END IF;

    INSERT INTO public.tracking_events (
        token_id, tenant_id, operation_id, event_type, source,
        client_timestamp, lat, lng, accuracy_m, municipality, state_name,
        country_code, incident_type, incident_note, offline_queued
    ) VALUES (
        v_token.token_id, v_token.tenant_id, v_token.operation_id, p_action, p_source,
        COALESCE(p_client_timestamp, now()), p_lat, p_lng, p_accuracy, p_municipality,
        p_state_name, COALESCE(p_country_code, 'MX'), p_incident_type, p_incident_note,
        COALESCE(p_offline_queued, false)
    ) RETURNING id INTO v_event_id;

    UPDATE public.tracking_tokens
    SET last_used_at = now(), event_count = event_count + 1,
        delivered_at = CASE WHEN p_action = 'delivered' THEN now() ELSE delivered_at END
    WHERE id = v_token.token_id;

    RETURN jsonb_build_object('http', 200, 'accepted', true, 'eventId', v_event_id);
EXCEPTION
    WHEN check_violation THEN
        RETURN jsonb_build_object('http', 400, 'accepted', false, 'reason', 'invalid_payload');
    WHEN unique_violation THEN
        RETURN jsonb_build_object('http', 200, 'accepted', false, 'reason', 'duplicate');
    WHEN OTHERS THEN
        RETURN jsonb_build_object('http', 500, 'accepted', false, 'reason', 'internal_error');
END;
$function$;

-- ---------------------------------------------------------------------------
-- RLS policies. Table privileges remain revoked: application access is RPC-first.
-- ---------------------------------------------------------------------------

ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.logistics_providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_catalog_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deal_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deal_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deal_checklist_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tracking_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tracking_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tracking_route_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tracking_access_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_cfdis ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_carta_porte ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.operation_billing ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.finance_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.finance_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_lots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customs_pedimentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customs_descargo_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenants_select_members ON public.tenants
    FOR SELECT TO authenticated
    USING (public.tanda1_user_is_member(id));

CREATE POLICY memberships_select_own ON public.memberships
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY tenant_settings_select_members ON public.tenant_settings
    FOR SELECT TO authenticated
    USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY tenant_settings_manage_admin ON public.tenant_settings
    FOR ALL TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin']))
    WITH CHECK (public.tanda1_user_has_role(tenant_id, ARRAY['admin']));

CREATE POLICY invitations_select_admin_operator ON public.invitations
    FOR SELECT TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']));
CREATE POLICY audit_log_select_members ON public.audit_log
    FOR SELECT TO authenticated
    USING (public.tanda1_user_is_member(tenant_id));

CREATE POLICY customers_select_members ON public.customers
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY customers_manage_admin_operator ON public.customers
    FOR ALL TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']))
    WITH CHECK (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']));

CREATE POLICY providers_select_members ON public.logistics_providers
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY providers_manage_admin_operator ON public.logistics_providers
    FOR ALL TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']))
    WITH CHECK (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']));

CREATE POLICY service_catalog_select_members ON public.service_catalog_items
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY service_catalog_manage_admin_operator ON public.service_catalog_items
    FOR ALL TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']))
    WITH CHECK (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']));

CREATE POLICY drivers_select_members ON public.drivers
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY drivers_manage_admin_operator ON public.drivers
    FOR ALL TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']))
    WITH CHECK (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']));
CREATE POLICY vehicles_select_members ON public.vehicles
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY vehicles_manage_admin_operator ON public.vehicles
    FOR ALL TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']))
    WITH CHECK (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']));

CREATE POLICY crm_deals_select_members ON public.crm_deals
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY crm_deals_manage_admin_operator ON public.crm_deals
    FOR ALL TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']))
    WITH CHECK (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']));
CREATE POLICY crm_activity_select_members ON public.crm_deal_activity
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY crm_notes_select_members ON public.crm_deal_notes
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY crm_checklist_select_members ON public.crm_deal_checklist_items
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));

CREATE POLICY operations_select_members ON public.operations
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY operations_insert_admin_operator ON public.operations
    FOR INSERT TO authenticated
    WITH CHECK (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']));
CREATE POLICY operations_update_admin_operator ON public.operations
    FOR UPDATE TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']))
    WITH CHECK (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'operator']));
CREATE POLICY operations_delete_admin ON public.operations
    FOR DELETE TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin']));

CREATE POLICY tracking_tokens_select_members ON public.tracking_tokens
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY tracking_events_select_members ON public.tracking_events
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY tracking_route_points_select_members ON public.tracking_route_points
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));

CREATE POLICY billing_cfdis_select_finance ON public.billing_cfdis
    FOR SELECT TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'finance']));
CREATE POLICY billing_carta_porte_select_finance ON public.billing_carta_porte
    FOR SELECT TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'finance']));
CREATE POLICY operation_billing_select_finance ON public.operation_billing
    FOR SELECT TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'finance']));
CREATE POLICY finance_invoices_select_finance ON public.finance_invoices
    FOR SELECT TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'finance']));
CREATE POLICY finance_payments_select_finance ON public.finance_payments
    FOR SELECT TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin', 'finance']));

CREATE POLICY inventory_lots_select_members ON public.inventory_lots
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY customs_pedimentos_select_members ON public.customs_pedimentos
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY customs_descargo_select_members ON public.customs_descargo_lines
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));

-- Explicit RPC-first privilege surface. RLS remains defense in depth.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

REVOKE ALL ON FUNCTION public.touch_updated_at() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.tanda1_user_is_member(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.tanda1_user_has_role(uuid, text[]) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.tanda1_user_is_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tanda1_user_has_role(uuid, text[]) TO authenticated;

REVOKE ALL ON FUNCTION public.rpc_get_my_context() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.rpc_list_members(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.rpc_list_operations(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.rpc_get_operation(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.rpc_create_operation(uuid, text, text, text, text, text, text, jsonb, jsonb, timestamptz) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.rpc_get_operation_requirements(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_my_context() TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_members(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_operations(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_operation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_operation(uuid, text, text, text, text, text, text, jsonb, jsonb, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_operation_requirements(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.tracking_hash_token(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tracking_validate_token(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tracking_hash_token(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.tracking_validate_token(text, text) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, integer, boolean) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.rpc_revoke_tracking_token(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.rpc_list_tracking_tokens(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, integer, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_revoke_tracking_token(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_tracking_tokens(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.rpc_get_public_tracking(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_get_driver_view(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_post_driver_event(text, text, text, numeric, numeric, numeric, text, text, character, text, text, timestamptz, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_public_tracking(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_driver_view(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_post_driver_event(text, text, text, numeric, numeric, numeric, text, text, character, text, text, timestamptz, boolean) TO service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
