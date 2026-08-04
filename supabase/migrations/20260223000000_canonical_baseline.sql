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
    actor_user_id uuid,
    actor_email text,
    actor_name text,
    action text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_log_metadata_object_check CHECK (jsonb_typeof(metadata) = 'object'),
    CONSTRAINT audit_log_details_object_check CHECK (jsonb_typeof(details) = 'object')
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
    company text,
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
    type text NOT NULL,
    body text,
    created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT crm_deal_activity_type_check CHECK (type IN ('note', 'call', 'email', 'meeting', 'status_change'))
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
    stage text NOT NULL DEFAULT 'lead',
    label text NOT NULL,
    is_done boolean NOT NULL DEFAULT false,
    completed_by uuid,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT crm_deal_checklist_stage_check CHECK (stage IN ('lead', 'qualified', 'proposal', 'won', 'lost'))
);

CREATE TABLE public.tenant_setup_status (
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    module_name text NOT NULL,
    is_configured boolean NOT NULL DEFAULT false,
    config_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_by uuid,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, module_name),
    CONSTRAINT tenant_setup_status_config_object_check CHECK (jsonb_typeof(config_data) = 'object')
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
    status text NOT NULL DEFAULT 'planned',
    origin_place jsonb,
    destination_place jsonb,
    eta timestamptz,
    driver_id uuid REFERENCES public.drivers(id) ON DELETE SET NULL,
    vehicle_id uuid REFERENCES public.vehicles(id) ON DELETE SET NULL,
    planned_departure timestamptz,
    priority text DEFAULT 'normal',
    required_documents jsonb DEFAULT '[]'::jsonb,
    driver_name text,
    vehicle_ref text,
    assigned_at timestamptz,
    closed_at timestamptz,
    cancelled_at timestamptz,
    service_type text,
    operational_window_start timestamptz,
    operational_window_end timestamptz,
    notes text,
    cargo_summary jsonb DEFAULT '{}'::jsonb,
    source_deal_id uuid,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    operation_scope text NOT NULL DEFAULT 'national',
    execution_type text NOT NULL DEFAULT 'third_party',
    provider_id uuid REFERENCES public.logistics_providers(id) ON DELETE SET NULL,
    provider_name text,
    external_driver jsonb NOT NULL DEFAULT '{}'::jsonb,
    external_vehicle jsonb NOT NULL DEFAULT '{}'::jsonb,
    provider_cost_amount numeric(14,2),
    customer_price_amount numeric(14,2),
    pricing_currency text NOT NULL DEFAULT 'MXN',
    service_catalog_item_id uuid REFERENCES public.service_catalog_items(id) ON DELETE SET NULL,
    service_catalog_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    boxes_placed_days integer,
    documentation_received_at timestamptz,
    documentation_received_note text,
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
        (provider_cost_amount IS NULL OR provider_cost_amount >= 0) AND
        (customer_price_amount IS NULL OR customer_price_amount >= 0)
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
    country_code char(2),
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
    uuid text,
    serie text,
    folio text,
    status text NOT NULL DEFAULT 'draft',
    currency text NOT NULL DEFAULT 'MXN',
    subtotal numeric(14,2) NOT NULL DEFAULT 0,
    total numeric(14,2) NOT NULL DEFAULT 0,
    rfc_emisor text NOT NULL,
    rfc_receptor text NOT NULL,
    receptor_name text,
    has_carta_porte boolean NOT NULL DEFAULT false,
    has_complemento_pago boolean NOT NULL DEFAULT false,
    issued_at timestamptz,
    cancelled_at timestamptz,
    pac_provider text,
    notes text,
    exchange_rate numeric(18,6),
    exchange_rate_date date,
    subtotal_mxn numeric(14,2),
    iva_mxn numeric(14,2),
    total_mxn numeric(14,2),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT billing_cfdis_status_check CHECK (status IN ('draft', 'timbrado', 'cancelado', 'error')),
    CONSTRAINT billing_cfdis_currency_check CHECK (currency IN ('MXN', 'USD')),
    CONSTRAINT billing_cfdis_amounts_check CHECK (subtotal >= 0 AND total >= 0),
    CONSTRAINT billing_cfdis_exchange_rate_check CHECK (exchange_rate IS NULL OR exchange_rate > 0)
);

CREATE UNIQUE INDEX billing_cfdis_tenant_uuid_uidx
    ON public.billing_cfdis (tenant_id, uuid) WHERE uuid IS NOT NULL;
CREATE INDEX billing_cfdis_tenant_status_idx ON public.billing_cfdis (tenant_id, status, created_at DESC);

CREATE TABLE public.billing_carta_porte (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    cfdi_id uuid NOT NULL UNIQUE REFERENCES public.billing_cfdis(id) ON DELETE CASCADE,
    trans_type text,
    vehicle_plate text,
    carrier_name text,
    origin text,
    destination text,
    goods_desc text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.operation_billing (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    operation_id uuid NOT NULL UNIQUE REFERENCES public.operations(id) ON DELETE CASCADE,
    status text NOT NULL DEFAULT 'draft',
    billing_reference text,
    issued_at timestamptz,
    issued_by uuid,
    linked_cfdi_id uuid REFERENCES public.billing_cfdis(id) ON DELETE SET NULL,
    notes text,
    admin_closed_at timestamptz,
    admin_closed_by uuid,
    admin_close_override boolean NOT NULL DEFAULT false,
    voided_at timestamptz,
    voided_by uuid,
    void_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT operation_billing_status_check CHECK (status IN ('draft', 'issued', 'voided'))
);

CREATE INDEX operation_billing_tenant_status_idx ON public.operation_billing (tenant_id, status, created_at DESC);

CREATE TABLE public.finance_invoices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    provider_id uuid REFERENCES public.logistics_providers(id) ON DELETE SET NULL,
    operation_id uuid REFERENCES public.operations(id) ON DELETE SET NULL,
    linked_cfdi_id uuid REFERENCES public.billing_cfdis(id) ON DELETE SET NULL,
    billing_document_id uuid,
    payroll_period_id uuid,
    direction text NOT NULL,
    counterparty_name text NOT NULL,
    reference text,
    amount numeric(14,2) NOT NULL,
    currency text NOT NULL DEFAULT 'MXN',
    status text NOT NULL DEFAULT 'open',
    due_date date,
    paid_at timestamptz,
    received_at timestamptz,
    notes text,
    exchange_rate numeric(18,6),
    exchange_rate_date date,
    amount_mxn numeric(14,2),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT finance_invoices_direction_check CHECK (direction IN ('ar', 'ap')),
    CONSTRAINT finance_invoices_status_check CHECK (status IN ('draft', 'open', 'paid', 'overdue', 'void')),
    CONSTRAINT finance_invoices_currency_check CHECK (currency IN ('MXN', 'USD')),
    CONSTRAINT finance_invoices_amount_check CHECK (amount >= 0),
    CONSTRAINT finance_invoices_exchange_rate_check CHECK (exchange_rate IS NULL OR exchange_rate > 0)
);

CREATE INDEX finance_invoices_tenant_status_idx ON public.finance_invoices (tenant_id, status, created_at DESC);

CREATE TABLE public.finance_payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    invoice_id uuid NOT NULL REFERENCES public.finance_invoices(id) ON DELETE CASCADE,
    amount numeric(14,2) NOT NULL,
    paid_at timestamptz NOT NULL DEFAULT now(),
    method text NOT NULL DEFAULT 'transfer',
    note text,
    bank_reference text,
    currency text NOT NULL DEFAULT 'MXN',
    exchange_rate numeric(18,6),
    exchange_rate_date date,
    amount_mxn numeric(14,2),
    created_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT finance_payments_amount_check CHECK (amount > 0),
    CONSTRAINT finance_payments_currency_check CHECK (currency IN ('MXN', 'USD')),
    CONSTRAINT finance_payments_method_check CHECK (method IN ('transfer', 'cash', 'card', 'other')),
    CONSTRAINT finance_payments_exchange_rate_check CHECK (exchange_rate IS NULL OR exchange_rate > 0)
);

CREATE INDEX finance_payments_tenant_invoice_idx ON public.finance_payments (tenant_id, invoice_id, paid_at DESC);

-- Existing non-core modules are preserved as small canonical catalogs because
-- current application RPCs reference them. No operational rows are created.
CREATE TABLE public.inventory_lots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    sku text NOT NULL,
    description text,
    warehouse text,
    lot_code text,
    qty_on_hand numeric(14,3) NOT NULL DEFAULT 0,
    qty_reserved numeric(14,3) NOT NULL DEFAULT 0,
    unit_cost numeric(14,2),
    currency text NOT NULL DEFAULT 'MXN',
    unit text NOT NULL DEFAULT 'Piezas',
    status text NOT NULL DEFAULT 'available',
    received_at timestamptz NOT NULL DEFAULT now(),
    pedimento_ref text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT inventory_lots_quantities_check CHECK (qty_on_hand >= 0 AND qty_reserved >= 0),
    CONSTRAINT inventory_lots_unit_cost_check CHECK (unit_cost IS NULL OR unit_cost >= 0),
    CONSTRAINT inventory_lots_currency_check CHECK (currency IN ('MXN', 'USD')),
    CONSTRAINT inventory_lots_status_check CHECK (status IN ('available', 'blocked', 'depleted'))
);

CREATE INDEX inventory_lots_tenant_sku_idx ON public.inventory_lots (tenant_id, sku);

CREATE TABLE public.customs_pedimentos (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    pedimento_number text NOT NULL,
    operation_id uuid REFERENCES public.operations(id) ON DELETE SET NULL,
    aduana text,
    regimen text,
    tipo_operacion text,
    status text NOT NULL DEFAULT 'draft',
    fecha_pago date,
    fecha_entrada date,
    fecha_salida date,
    total_value numeric(14,2),
    currency text NOT NULL DEFAULT 'MXN',
    descargo_method text NOT NULL DEFAULT 'peps',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customs_pedimentos_tenant_number_key UNIQUE (tenant_id, pedimento_number),
    CONSTRAINT customs_pedimentos_currency_check CHECK (currency IN ('MXN', 'USD')),
    CONSTRAINT customs_pedimentos_value_check CHECK (total_value IS NULL OR total_value >= 0)
);

CREATE TABLE public.customs_descargo_lines (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    pedimento_id uuid NOT NULL REFERENCES public.customs_pedimentos(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    sku text NOT NULL,
    lot_code text,
    qty numeric(14,3) NOT NULL,
    unit text NOT NULL DEFAULT 'Piezas',
    inventory_lot_id uuid REFERENCES public.inventory_lots(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customs_descargo_lines_sequence_check CHECK (sequence_no > 0),
    CONSTRAINT customs_descargo_lines_qty_check CHECK (qty > 0),
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
CREATE TRIGGER tenant_setup_status_touch_updated_at
    BEFORE UPDATE ON public.tenant_setup_status
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
    p_status text DEFAULT 'planned',
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

CREATE FUNCTION public.rpc_assign_operation(
    p_tenant_id uuid, p_operation_id uuid, p_driver_id uuid, p_vehicle_id uuid,
    p_planned_departure timestamptz, p_priority text DEFAULT 'normal'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    UPDATE public.operations AS o
    SET driver_id = p_driver_id, vehicle_id = p_vehicle_id,
        planned_departure = p_planned_departure, priority = p_priority,
        assigned_at = now(), status = CASE WHEN o.status IN ('planned', 'draft') THEN 'assigned' ELSE o.status END
    WHERE o.id = p_operation_id AND o.tenant_id = p_tenant_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE FUNCTION public.rpc_assign_operation_v2(
    p_tenant_id uuid, p_operation_id uuid, p_driver_id uuid, p_driver_name text,
    p_vehicle_id uuid, p_vehicle_ref text, p_planned_departure timestamptz,
    p_priority text DEFAULT 'normal'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    UPDATE public.operations AS o
    SET driver_id = p_driver_id, driver_name = NULLIF(p_driver_name, ''),
        vehicle_id = p_vehicle_id, vehicle_ref = NULLIF(p_vehicle_ref, ''),
        planned_departure = p_planned_departure, priority = p_priority,
        assigned_at = now(), status = CASE WHEN o.status IN ('planned', 'draft') THEN 'assigned' ELSE o.status END
    WHERE o.id = p_operation_id AND o.tenant_id = p_tenant_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE FUNCTION public.rpc_update_operation_details(p_operation_id uuid, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT o.tenant_id INTO v_tenant_id FROM public.operations AS o WHERE o.id = p_operation_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    UPDATE public.operations AS o SET
        route_summary = COALESCE(p_patch->>'route_summary', o.route_summary),
        client_display_name = COALESCE(p_patch->>'client_display_name', o.client_display_name),
        destination_city = COALESCE(p_patch->>'destination_city', o.destination_city),
        eta_display = COALESCE(p_patch->>'eta_display', o.eta_display),
        priority = COALESCE(p_patch->>'priority', o.priority),
        execution_type = COALESCE(p_patch->>'execution_type', o.execution_type),
        provider_name = COALESCE(p_patch->>'provider_name', o.provider_name),
        notes = COALESCE(p_patch->>'notes', o.notes),
        documentation_received_note = COALESCE(p_patch->>'documentation_received_note', o.documentation_received_note),
        external_driver = COALESCE(p_patch->'external_driver', o.external_driver),
        external_vehicle = COALESCE(p_patch->'external_vehicle', o.external_vehicle),
        required_documents = COALESCE(p_patch->'required_documents', o.required_documents),
        cargo_summary = COALESCE(p_patch->'cargo_summary', o.cargo_summary),
        provider_cost_amount = COALESCE((p_patch->>'provider_cost_amount')::numeric, o.provider_cost_amount),
        customer_price_amount = COALESCE((p_patch->>'customer_price_amount')::numeric, o.customer_price_amount)
    WHERE o.id = p_operation_id;
    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR check_violation THEN
    RETURN jsonb_build_object('error', 'invalid_payload');
END;
$function$;

CREATE FUNCTION public.rpc_transition_operation_status(p_operation_id uuid, p_to_status text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_operation public.operations%ROWTYPE;
BEGIN
    SELECT o.* INTO v_operation FROM public.operations AS o WHERE o.id = p_operation_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_operation.tenant_id, ARRAY['admin', 'operator']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF p_to_status NOT IN ('planned', 'assigned', 'in_transit', 'delivered', 'cancelled', 'closed') THEN
        RETURN jsonb_build_object('error', 'invalid_status');
    END IF;
    IF p_to_status = 'in_transit' AND v_operation.driver_id IS NULL
       AND COALESCE(v_operation.external_driver, '{}'::jsonb) = '{}'::jsonb THEN
        RETURN jsonb_build_object('error', 'missing_driver');
    END IF;
    UPDATE public.operations SET status = p_to_status,
        closed_at = CASE WHEN p_to_status = 'closed' THEN now() ELSE closed_at END,
        cancelled_at = CASE WHEN p_to_status = 'cancelled' THEN now() ELSE cancelled_at END
    WHERE id = p_operation_id;
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE FUNCTION public.rpc_override_operation_status(p_operation_id uuid, p_to_status text, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT o.tenant_id INTO v_tenant_id FROM public.operations AS o WHERE o.id = p_operation_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin']) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL OR p_to_status NOT IN ('planned', 'assigned', 'in_transit', 'delivered', 'cancelled', 'closed') THEN
        RETURN jsonb_build_object('error', 'invalid_override');
    END IF;
    UPDATE public.operations SET status = p_to_status WHERE id = p_operation_id;
    INSERT INTO public.audit_log (tenant_id, actor_user_id, action, entity_type, entity_id, metadata, details)
    VALUES (v_tenant_id, auth.uid(), 'operation_status_override', 'operation', p_operation_id,
            jsonb_build_object('to_status', p_to_status), jsonb_build_object('reason', p_reason));
    RETURN jsonb_build_object('success', true);
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

CREATE FUNCTION public.rpc_create_tracking_token(
    p_tenant_id uuid,
    p_operation_id uuid,
    p_scope text,
    p_ttl_hours integer
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT public.rpc_create_tracking_token(
        p_tenant_id, p_operation_id, p_scope, p_ttl_hours, false
    );
$function$;

CREATE FUNCTION public.rpc_create_tracking_token(
    p_tenant_id uuid,
    p_operation_id uuid,
    p_scope text,
    p_force_rotate boolean
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
    SELECT public.rpc_create_tracking_token(
        p_tenant_id, p_operation_id, p_scope, NULL::integer, p_force_rotate
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
    v_last_event public.tracking_events%ROWTYPE;
    v_events jsonb;
    v_route_points jsonb;
    v_status text;
    v_soft_expired boolean;
BEGIN
    SELECT * INTO v_token FROM public.tracking_validate_token(p_token, 'public:read');
    IF v_token.token_id IS NULL THEN
        RETURN jsonb_build_object('status', 'not_found');
    END IF;
    IF v_token.token_state = 'revoked' THEN
        RETURN jsonb_build_object('status', 'revoked');
    END IF;
    IF v_token.token_state IN ('hard_expired', 'rotated') OR v_token.expires_at + interval '48 hours' <= now() THEN
        RETURN jsonb_build_object('status', 'hard_expired');
    END IF;
    SELECT o.* INTO v_operation FROM public.operations AS o WHERE o.id = v_token.operation_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('status', 'not_found'); END IF;

    SELECT e.* INTO v_last_event FROM public.tracking_events AS e
    WHERE e.operation_id = v_token.operation_id AND e.event_type <> 'incident' AND NOT e.is_suspicious
    ORDER BY e.server_timestamp DESC LIMIT 1;

    SELECT COALESCE(jsonb_agg(to_jsonb(x) - 'rank' - 'total' ORDER BY x.rank), '[]'::jsonb)
    INTO v_events FROM (
        SELECT 'evt-' || row_number() OVER (ORDER BY e.server_timestamp) AS id,
            CASE e.event_type WHEN 'departure' THEN 'Salida de almacén' WHEN 'in_transit' THEN 'En camino'
                WHEN 'arrival' THEN 'En punto de entrega' WHEN 'delivered' THEN 'Entregado'
                WHEN 'incident' THEN 'Retraso reportado' ELSE 'Actualización' END AS title,
            CASE WHEN e.municipality IS NOT NULL THEN concat_ws(', ', e.municipality, e.state_name)
                ELSE 'Actualización logística' END AS subtitle,
            e.server_timestamp AS timestamp,
            CASE WHEN row_number() OVER (ORDER BY e.server_timestamp) = count(*) OVER () THEN 'current' ELSE 'done' END AS status,
            CASE e.event_type WHEN 'departure' THEN 'truck' WHEN 'delivered' THEN 'check-circle'
                WHEN 'incident' THEN 'alert-triangle' ELSE 'map-pin' END AS icon,
            row_number() OVER (ORDER BY e.server_timestamp) AS rank,
            count(*) OVER () AS total
        FROM public.tracking_events AS e
        WHERE e.operation_id = v_token.operation_id AND NOT e.is_suspicious
        ORDER BY e.server_timestamp LIMIT 20
    ) AS x;

    SELECT COALESCE(jsonb_agg(jsonb_build_object('lat', round(x.lat::numeric,2), 'lng', round(x.lng::numeric,2)) ORDER BY x.recorded_at), '[]'::jsonb)
    INTO v_route_points FROM (
        SELECT r.lat,r.lng,r.recorded_at FROM public.tracking_route_points AS r
        WHERE r.operation_id=v_token.operation_id ORDER BY r.recorded_at DESC LIMIT 200
    ) AS x;

    v_status := CASE v_last_event.event_type WHEN 'departure' THEN 'En Tránsito' WHEN 'in_transit' THEN 'En Tránsito'
        WHEN 'arrival' THEN 'En Destino' WHEN 'delivered' THEN 'Entregado' ELSE 'En Espera' END;
    v_soft_expired := v_token.token_state = 'soft_expired' OR v_token.expires_at <= now();
    UPDATE public.tracking_tokens SET last_used_at = now() WHERE id = v_token.token_id;
    RETURN jsonb_build_object(
        'status', CASE WHEN v_soft_expired THEN 'soft_expired' ELSE 'success' END,
        'expired', v_soft_expired,
        'data', jsonb_strip_nulls(jsonb_build_object(
            'orderRef', v_operation.reference_code,
            'route', v_operation.route_summary,
            'currentStatus', v_status,
            'eta', v_operation.eta_display,
            'events', v_events,
            'currentLocation', CASE WHEN v_last_event.event_type <> 'delivered' AND v_last_event.municipality IS NOT NULL
                AND v_last_event.lat IS NOT NULL AND v_last_event.lng IS NOT NULL
                THEN jsonb_build_object('lat',round(v_last_event.lat,2),'lng',round(v_last_event.lng,2)) END,
            'routePoints', CASE WHEN v_last_event.event_type <> 'delivered' THEN v_route_points END
        ))
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
    v_last_event public.tracking_events%ROWTYPE;
    v_status text;
BEGIN
    SELECT * INTO v_token FROM public.tracking_validate_token(p_token, 'driver:write');
    IF v_token.token_id IS NULL THEN
        RETURN jsonb_build_object('status', 'not_found');
    END IF;
    IF v_token.token_state = 'revoked' THEN RETURN jsonb_build_object('status', 'revoked'); END IF;
    IF v_token.token_state <> 'active' OR v_token.expires_at <= now() THEN
        RETURN jsonb_build_object('status', 'expired');
    END IF;
    SELECT o.* INTO v_operation FROM public.operations AS o WHERE o.id = v_token.operation_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('status', 'not_found'); END IF;
    SELECT e.* INTO v_last_event FROM public.tracking_events AS e
    WHERE e.operation_id=v_token.operation_id AND e.event_type<>'incident'
    ORDER BY e.server_timestamp DESC LIMIT 1;
    v_status := CASE v_last_event.event_type WHEN 'departure' THEN 'in_transit' WHEN 'in_transit' THEN 'in_transit'
        WHEN 'arrival' THEN 'at_destination' WHEN 'delivered' THEN 'delivered' ELSE 'assigned' END;
    UPDATE public.tracking_tokens SET last_used_at = now() WHERE id = v_token.token_id;
    RETURN jsonb_build_object(
        'status', 'success',
        'data', jsonb_strip_nulls(jsonb_build_object(
            'orderRef', v_operation.reference_code,
            'route', v_operation.route_summary,
            'currentStatus', v_status,
            'eta', CASE WHEN v_status <> 'delivered' THEN v_operation.eta_display END,
            'clientName', left(v_operation.client_display_name,20),
            'destinationCity', v_operation.destination_city,
            'lastEvent', CASE WHEN v_last_event.municipality IS NOT NULL THEN jsonb_build_object(
                'municipality',concat_ws(', ',v_last_event.municipality,v_last_event.state_name),
                'timestamp',v_last_event.server_timestamp) END
        ))
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
-- Dashboard, reports, and authenticated route RPCs
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.rpc_dashboard_overview(p_tenant_id uuid,p_start_date timestamptz DEFAULT NULL,p_end_date timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN jsonb_build_object('kpis',jsonb_build_object(
        'ops_total',(SELECT count(*) FROM public.operations AS o WHERE o.tenant_id=p_tenant_id AND (p_start_date IS NULL OR o.created_at>=p_start_date) AND (p_end_date IS NULL OR o.created_at<=p_end_date)),
        'ops_in_transit',(SELECT count(*) FROM public.operations AS o WHERE o.tenant_id=p_tenant_id AND o.status='in_transit' AND (p_start_date IS NULL OR o.created_at>=p_start_date) AND (p_end_date IS NULL OR o.created_at<=p_end_date)),
        'billing_total',COALESCE((SELECT sum(c.total) FROM public.billing_cfdis AS c WHERE c.tenant_id=p_tenant_id AND c.status='timbrado' AND (p_start_date IS NULL OR c.created_at>=p_start_date) AND (p_end_date IS NULL OR c.created_at<=p_end_date)),0),
        'inventory_value',COALESCE((SELECT sum(i.qty_on_hand*COALESCE(i.unit_cost,0)) FROM public.inventory_lots AS i WHERE i.tenant_id=p_tenant_id),0)),
        'chart',jsonb_build_object('data','[]'::jsonb,'labels','[]'::jsonb));
END;
$function$;

CREATE FUNCTION public.rpc_dashboard_recent_activity(p_tenant_id uuid,p_start_date timestamptz DEFAULT NULL,p_end_date timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.reference_code,'client',COALESCE(o.client_display_name,'N/A'),
        'status',o.status,'route',COALESCE(o.route_summary,o.destination_city,'N/A'),'eta',COALESCE(o.eta_display,'')) ORDER BY o.updated_at DESC)
        FROM (SELECT * FROM public.operations AS x WHERE x.tenant_id=p_tenant_id AND (p_start_date IS NULL OR x.created_at>=p_start_date)
            AND (p_end_date IS NULL OR x.created_at<=p_end_date) ORDER BY x.updated_at DESC LIMIT 10) AS o),'[]'::jsonb);
END;
$function$;

CREATE FUNCTION public.rpc_dashboard_alerts(p_tenant_id uuid,p_start_date timestamptz DEFAULT NULL,p_end_date timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_alerts jsonb := '[]'::jsonb;
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF EXISTS (SELECT 1 FROM public.finance_invoices AS i WHERE i.tenant_id=p_tenant_id AND i.status='overdue') THEN
        v_alerts:=v_alerts||jsonb_build_array(jsonb_build_object('type','warning','title','Facturas vencidas','description','Hay cuentas vencidas por revisar'));
    END IF;
    IF EXISTS (SELECT 1 FROM public.inventory_lots AS i WHERE i.tenant_id=p_tenant_id AND i.qty_on_hand-i.qty_reserved<=10) THEN
        v_alerts:=v_alerts||jsonb_build_array(jsonb_build_object('type','info','title','Stock bajo','description','Hay lotes con disponibilidad baja'));
    END IF;
    RETURN v_alerts;
END;
$function$;

CREATE FUNCTION public.rpc_reports_financial_summary(p_tenant_id uuid,p_period text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_revenue numeric; v_expenses numeric;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(sum(i.amount) FILTER (WHERE i.direction='ar'),0),
           COALESCE(sum(i.amount) FILTER (WHERE i.direction='ap'),0)
    INTO v_revenue,v_expenses FROM public.finance_invoices AS i WHERE i.tenant_id=p_tenant_id;
    RETURN jsonb_build_object('revenue_by_month','[]'::jsonb,'ar_open_by_month','[]'::jsonb,'ap_open_by_month','[]'::jsonb,
        'cashflow_by_month','[]'::jsonb,'total_revenue_ytd',COALESCE(v_revenue,0),'total_expenses_ytd',COALESCE(v_expenses,0),
        'net_position',COALESCE(v_revenue,0)-COALESCE(v_expenses,0));
END;
$function$;

CREATE FUNCTION public.rpc_reports_pipeline_summary(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_total bigint; v_won bigint;
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT count(*),count(*) FILTER(WHERE d.stage='won') INTO v_total,v_won FROM public.crm_deals AS d WHERE d.tenant_id=p_tenant_id;
    RETURN jsonb_build_object('deals_by_stage',jsonb_build_object(
        'lead',(SELECT count(*) FROM public.crm_deals AS d WHERE d.tenant_id=p_tenant_id AND d.stage='lead'),
        'contacted',(SELECT count(*) FROM public.crm_deals AS d WHERE d.tenant_id=p_tenant_id AND d.stage='qualified'),
        'proposal',(SELECT count(*) FROM public.crm_deals AS d WHERE d.tenant_id=p_tenant_id AND d.stage='proposal'),
        'won',v_won),'total_pipeline_value',COALESCE((SELECT sum(d.value) FROM public.crm_deals AS d WHERE d.tenant_id=p_tenant_id AND d.stage<>'lost'),0),
        'conversion_rate',CASE WHEN v_total=0 THEN 0 ELSE round(v_won::numeric*100/v_total,2) END);
END;
$function$;

CREATE FUNCTION public.rpc_reports_inventory_summary(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN jsonb_build_object('inventory_total_value',COALESCE((SELECT sum(i.qty_on_hand*COALESCE(i.unit_cost,0)) FROM public.inventory_lots AS i WHERE i.tenant_id=p_tenant_id),0),
        'blocked_count',(SELECT count(*) FROM public.inventory_lots AS i WHERE i.tenant_id=p_tenant_id AND i.status='blocked'),
        'low_stock_count',(SELECT count(*) FROM public.inventory_lots AS i WHERE i.tenant_id=p_tenant_id AND i.qty_on_hand-i.qty_reserved<=10),
        'top_skus_by_value',COALESCE((SELECT jsonb_agg(jsonb_build_object('sku',x.sku,'value',x.value) ORDER BY x.value DESC) FROM (
            SELECT i.sku,sum(i.qty_on_hand*COALESCE(i.unit_cost,0)) AS value FROM public.inventory_lots AS i WHERE i.tenant_id=p_tenant_id GROUP BY i.sku ORDER BY value DESC LIMIT 5) AS x),'[]'::jsonb));
END;
$function$;

CREATE FUNCTION public.rpc_reports_operations_summary(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN jsonb_build_object('operations_per_month','[]'::jsonb,'avg_delivery_time',COALESCE((SELECT avg(extract(epoch FROM (o.updated_at-o.created_at))/3600) FROM public.operations AS o WHERE o.tenant_id=p_tenant_id AND o.status IN ('delivered','closed')),0),
        'active_routes_count',(SELECT count(*) FROM public.operations AS o WHERE o.tenant_id=p_tenant_id AND o.status IN ('assigned','in_transit')));
END;
$function$;

CREATE FUNCTION public.rpc_list_route_points(p_operation_id uuid,p_start timestamptz DEFAULT NULL,p_end timestamptz DEFAULT NULL,p_limit integer DEFAULT 2000)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT o.tenant_id INTO v_tenant_id FROM public.operations AS o WHERE o.id=p_operation_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_is_member(v_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('lat',x.lat,'lng',x.lng,'recorded_at',x.recorded_at,'accuracy_m',x.accuracy_m,'source',x.source) ORDER BY x.recorded_at)
        FROM (SELECT r.lat,r.lng,r.recorded_at,r.accuracy_m,r.source FROM public.tracking_route_points AS r WHERE r.operation_id=p_operation_id
            AND (p_start IS NULL OR r.recorded_at>=p_start) AND (p_end IS NULL OR r.recorded_at<=p_end)
            ORDER BY r.recorded_at DESC LIMIT LEAST(GREATEST(p_limit,1),5000)) AS x),'[]'::jsonb);
END;
$function$;

-- ---------------------------------------------------------------------------
-- Commercial / CRM RPCs consumed by the ERP

CREATE FUNCTION public.rpc_list_deals(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.updated_at DESC) FROM public.crm_deals AS d WHERE d.tenant_id=p_tenant_id
        AND (NOT (p_filters ? 'stage') OR d.stage=p_filters->>'stage')
        AND (NOT (p_filters ? 'owner') OR d.owner_user_id=(p_filters->>'owner')::uuid)
        AND (NOT (p_filters ? 'priority') OR d.priority=p_filters->>'priority')
        AND (NOT (p_filters ? 'searchText') OR d.title ILIKE '%'||(p_filters->>'searchText')||'%'
             OR d.company ILIKE '%'||(p_filters->>'searchText')||'%')), '[]'::jsonb);
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_filters');
END;
$function$;

CREATE FUNCTION public.rpc_create_deal(p_tenant_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_id uuid;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    INSERT INTO public.crm_deals (tenant_id,title,company,contact_name,contact_email,contact_phone,value,currency,stage,priority,notes,owner_user_id)
    VALUES (p_tenant_id,p_payload->>'title',p_payload->>'company',p_payload->>'contact_name',p_payload->>'contact_email',p_payload->>'contact_phone',
        (p_payload->>'value')::numeric,COALESCE(p_payload->>'currency','MXN'),COALESCE(p_payload->>'stage','lead'),
        COALESCE(p_payload->>'priority','medium'),p_payload->>'notes',(p_payload->>'owner_user_id')::uuid) RETURNING id INTO v_id;
    RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN invalid_text_representation OR not_null_violation OR check_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE FUNCTION public.rpc_update_deal(p_deal_id uuid,p_patch jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT d.tenant_id INTO v_tenant_id FROM public.crm_deals AS d WHERE d.id=p_deal_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    UPDATE public.crm_deals AS d SET title=COALESCE(p_patch->>'title',d.title),company=COALESCE(p_patch->>'company',d.company),
        contact_name=COALESCE(p_patch->>'contact_name',d.contact_name),contact_email=COALESCE(p_patch->>'contact_email',d.contact_email),
        contact_phone=COALESCE(p_patch->>'contact_phone',d.contact_phone),value=COALESCE((p_patch->>'value')::numeric,d.value),
        currency=COALESCE(p_patch->>'currency',d.currency),stage=COALESCE(p_patch->>'stage',d.stage),
        priority=COALESCE(p_patch->>'priority',d.priority),notes=COALESCE(p_patch->>'notes',d.notes),
        owner_user_id=COALESCE((p_patch->>'owner_user_id')::uuid,d.owner_user_id),last_touch_at=now() WHERE d.id=p_deal_id;
    RETURN jsonb_build_object('success',true);
EXCEPTION WHEN invalid_text_representation OR check_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE FUNCTION public.rpc_move_deal(p_deal_id uuid,p_new_stage text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid; v_old_stage text;
BEGIN
    SELECT d.tenant_id,d.stage INTO v_tenant_id,v_old_stage FROM public.crm_deals AS d WHERE d.id=p_deal_id FOR UPDATE;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF p_new_stage NOT IN ('lead','qualified','proposal','won','lost') THEN RETURN jsonb_build_object('error','invalid_stage'); END IF;
    UPDATE public.crm_deals SET stage=p_new_stage,last_touch_at=now() WHERE id=p_deal_id;
    INSERT INTO public.crm_deal_activity (tenant_id,deal_id,type,body,created_by)
    VALUES (v_tenant_id,p_deal_id,'status_change',v_old_stage||' -> '||p_new_stage,auth.uid());
    RETURN jsonb_build_object('success',true);
END;
$function$;

CREATE FUNCTION public.rpc_get_deal(p_deal_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT d.tenant_id INTO v_tenant_id FROM public.crm_deals AS d WHERE d.id=p_deal_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_is_member(v_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN (SELECT to_jsonb(d)||jsonb_build_object('owner_name',u.raw_user_meta_data->>'full_name')
        FROM public.crm_deals AS d LEFT JOIN auth.users AS u ON u.id=d.owner_user_id WHERE d.id=p_deal_id);
END;
$function$;

CREATE FUNCTION public.rpc_list_deal_activities(p_deal_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT d.tenant_id INTO v_tenant_id FROM public.crm_deals AS d WHERE d.id=p_deal_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_is_member(v_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(a)||jsonb_build_object('creator_name',u.raw_user_meta_data->>'full_name') ORDER BY a.created_at DESC)
        FROM public.crm_deal_activity AS a LEFT JOIN auth.users AS u ON u.id=a.created_by WHERE a.deal_id=p_deal_id),'[]'::jsonb);
END;
$function$;

CREATE FUNCTION public.rpc_add_deal_activity(p_deal_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid; v_id uuid;
BEGIN
    SELECT d.tenant_id INTO v_tenant_id FROM public.crm_deals AS d WHERE d.id=p_deal_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    INSERT INTO public.crm_deal_activity (tenant_id,deal_id,type,body,created_by)
    VALUES (v_tenant_id,p_deal_id,p_payload->>'type',p_payload->>'body',auth.uid()) RETURNING id INTO v_id;
    RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN not_null_violation OR check_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE FUNCTION public.rpc_add_deal_note(p_deal_id uuid,p_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid; v_id uuid;
BEGIN
    SELECT d.tenant_id INTO v_tenant_id FROM public.crm_deals AS d WHERE d.id=p_deal_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF NULLIF(btrim(p_note),'') IS NULL THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
    INSERT INTO public.crm_deal_notes (tenant_id,deal_id,author_id,note) VALUES (v_tenant_id,p_deal_id,auth.uid(),p_note) RETURNING id INTO v_id;
    RETURN jsonb_build_object('id',v_id);
END;
$function$;

CREATE FUNCTION public.rpc_list_deal_notes(p_deal_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT d.tenant_id INTO v_tenant_id FROM public.crm_deals AS d WHERE d.id=p_deal_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_is_member(v_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id',n.id,'note',n.note,'author_name',u.raw_user_meta_data->>'full_name','created_at',n.created_at) ORDER BY n.created_at DESC)
        FROM public.crm_deal_notes AS n LEFT JOIN auth.users AS u ON u.id=n.author_id WHERE n.deal_id=p_deal_id),'[]'::jsonb);
END;
$function$;

CREATE FUNCTION public.rpc_list_deal_checklist(p_deal_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT d.tenant_id INTO v_tenant_id FROM public.crm_deals AS d WHERE d.id=p_deal_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_is_member(v_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'stage',c.stage,'label',c.label,'is_done',c.is_done,'updated_at',c.created_at) ORDER BY c.created_at)
        FROM public.crm_deal_checklist_items AS c WHERE c.deal_id=p_deal_id),'[]'::jsonb);
END;
$function$;

CREATE FUNCTION public.rpc_toggle_deal_checklist_item(p_item_id uuid,p_is_done boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT c.tenant_id INTO v_tenant_id FROM public.crm_deal_checklist_items AS c WHERE c.id=p_item_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    UPDATE public.crm_deal_checklist_items SET is_done=p_is_done,completed_by=CASE WHEN p_is_done THEN auth.uid() ELSE NULL END,
        completed_at=CASE WHEN p_is_done THEN now() ELSE NULL END WHERE id=p_item_id;
    RETURN jsonb_build_object('success',true);
END;
$function$;

-- ---------------------------------------------------------------------------
-- Billing, finance, inventory, and customs RPCs consumed by the ERP

CREATE FUNCTION public.rpc_list_cfdis(p_tenant_id uuid, p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'finance']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.created_at DESC) FROM public.billing_cfdis AS c
        WHERE c.tenant_id = p_tenant_id
          AND (NOT (p_filters ? 'status') OR c.status = p_filters->>'status')
          AND (NOT (p_filters ? 'rfc') OR c.rfc_emisor ILIKE '%' || (p_filters->>'rfc') || '%' OR c.rfc_receptor ILIKE '%' || (p_filters->>'rfc') || '%')
          AND (NOT (p_filters ? 'searchText') OR c.folio ILIKE '%' || (p_filters->>'searchText') || '%'
               OR c.receptor_name ILIKE '%' || (p_filters->>'searchText') || '%')), '[]'::jsonb);
END;
$function$;

CREATE FUNCTION public.rpc_get_cfdi_detail(p_cfdi_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_cfdi public.billing_cfdis%ROWTYPE;
BEGIN
    SELECT c.* INTO v_cfdi FROM public.billing_cfdis AS c WHERE c.id = p_cfdi_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_cfdi.tenant_id, ARRAY['admin', 'finance']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    RETURN to_jsonb(v_cfdi) || jsonb_build_object('carta_porte',
        (SELECT to_jsonb(cp) FROM public.billing_carta_porte AS cp WHERE cp.cfdi_id = p_cfdi_id));
END;
$function$;

CREATE FUNCTION public.rpc_create_cfdi(p_tenant_id uuid, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_id uuid;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'finance']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    INSERT INTO public.billing_cfdis (tenant_id, operation_id, uuid, serie, folio, rfc_emisor, rfc_receptor,
        receptor_name, subtotal, total, currency, status, has_carta_porte, has_complemento_pago, issued_at, pac_provider, notes)
    VALUES (p_tenant_id, (p_payload->>'operation_id')::uuid, p_payload->>'uuid', p_payload->>'serie', p_payload->>'folio',
        p_payload->>'rfc_emisor', p_payload->>'rfc_receptor', p_payload->>'receptor_name', COALESCE((p_payload->>'subtotal')::numeric, 0),
        (p_payload->>'total')::numeric, COALESCE(p_payload->>'currency', 'MXN'), COALESCE(p_payload->>'status', 'draft'),
        COALESCE((p_payload->>'has_carta_porte')::boolean, false), COALESCE((p_payload->>'has_complemento_pago')::boolean, false),
        (p_payload->>'issued_at')::timestamptz, p_payload->>'pac_provider', p_payload->>'notes') RETURNING id INTO v_id;
    RETURN jsonb_build_object('id', v_id);
EXCEPTION WHEN invalid_text_representation OR not_null_violation OR check_violation OR foreign_key_violation THEN
    RETURN jsonb_build_object('error', 'invalid_payload');
    WHEN unique_violation THEN RETURN jsonb_build_object('error', 'uuid_conflict');
END;
$function$;

CREATE FUNCTION public.rpc_update_cfdi(p_cfdi_id uuid, p_patch jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT c.tenant_id INTO v_tenant_id FROM public.billing_cfdis AS c WHERE c.id = p_cfdi_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'finance']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    UPDATE public.billing_cfdis AS c SET
        status = COALESCE(p_patch->>'status', c.status),
        cancelled_at = CASE WHEN p_patch ? 'cancelled_at' THEN (p_patch->>'cancelled_at')::timestamptz ELSE c.cancelled_at END,
        notes = CASE WHEN p_patch ? 'notes' THEN p_patch->>'notes' ELSE c.notes END,
        has_carta_porte = COALESCE((p_patch->>'has_carta_porte')::boolean, c.has_carta_porte),
        has_complemento_pago = COALESCE((p_patch->>'has_complemento_pago')::boolean, c.has_complemento_pago)
    WHERE c.id = p_cfdi_id;
    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN invalid_text_representation OR check_violation THEN RETURN jsonb_build_object('error', 'invalid_payload');
END;
$function$;

CREATE FUNCTION public.rpc_upsert_carta_porte(p_cfdi_id uuid, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid; v_id uuid;
BEGIN
    SELECT c.tenant_id INTO v_tenant_id FROM public.billing_cfdis AS c WHERE c.id = p_cfdi_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id, ARRAY['admin', 'finance']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    INSERT INTO public.billing_carta_porte (tenant_id, cfdi_id, trans_type, vehicle_plate, carrier_name, origin, destination, goods_desc)
    VALUES (v_tenant_id, p_cfdi_id, p_payload->>'trans_type', p_payload->>'vehicle_plate', p_payload->>'carrier_name',
        p_payload->>'origin', p_payload->>'destination', p_payload->>'goods_desc')
    ON CONFLICT (cfdi_id) DO UPDATE SET trans_type = EXCLUDED.trans_type, vehicle_plate = EXCLUDED.vehicle_plate,
        carrier_name = EXCLUDED.carrier_name, origin = EXCLUDED.origin, destination = EXCLUDED.destination,
        goods_desc = EXCLUDED.goods_desc RETURNING id INTO v_id;
    UPDATE public.billing_cfdis SET has_carta_porte = true WHERE id = p_cfdi_id;
    RETURN jsonb_build_object('id', v_id);
END;
$function$;

CREATE FUNCTION public.rpc_finance_overview(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'finance']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    RETURN jsonb_build_object(
        'total_ar_open', COALESCE((SELECT sum(i.amount) FROM public.finance_invoices AS i WHERE i.tenant_id=p_tenant_id AND i.direction='ar' AND i.status IN ('open','overdue')),0),
        'total_ap_open', COALESCE((SELECT sum(i.amount) FROM public.finance_invoices AS i WHERE i.tenant_id=p_tenant_id AND i.direction='ap' AND i.status IN ('open','overdue')),0),
        'total_overdue', COALESCE((SELECT sum(i.amount) FROM public.finance_invoices AS i WHERE i.tenant_id=p_tenant_id AND i.status='overdue'),0),
        'paid_this_month', COALESCE((SELECT sum(p.amount) FROM public.finance_payments AS p WHERE p.tenant_id=p_tenant_id AND date_trunc('month',p.paid_at)=date_trunc('month',now())),0),
        'count_open_invoices', (SELECT count(*) FROM public.finance_invoices AS i WHERE i.tenant_id=p_tenant_id AND i.status IN ('open','overdue')),
        'chart', jsonb_build_object('labels','[]'::jsonb,'values','[]'::jsonb));
END;
$function$;

CREATE FUNCTION public.rpc_list_finance_invoices(p_tenant_id uuid, p_limit integer DEFAULT 50, p_status text DEFAULT NULL, p_direction text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (
        SELECT * FROM public.finance_invoices AS i WHERE i.tenant_id=p_tenant_id
          AND (p_status IS NULL OR i.status=p_status) AND (p_direction IS NULL OR i.direction=p_direction)
        ORDER BY i.created_at DESC LIMIT LEAST(GREATEST(p_limit,1),200)) AS x), '[]'::jsonb);
END;
$function$;

CREATE FUNCTION public.rpc_create_finance_invoice(p_tenant_id uuid, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_id uuid;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    INSERT INTO public.finance_invoices (tenant_id,direction,counterparty_name,reference,amount,currency,status,due_date,notes,
        customer_id,provider_id,operation_id,linked_cfdi_id)
    VALUES (p_tenant_id,p_payload->>'direction',p_payload->>'counterparty_name',p_payload->>'reference',(p_payload->>'amount')::numeric,
        COALESCE(p_payload->>'currency','MXN'),COALESCE(p_payload->>'status','open'),(p_payload->>'due_date')::date,p_payload->>'notes',
        (p_payload->>'customer_id')::uuid,(p_payload->>'provider_id')::uuid,(p_payload->>'operation_id')::uuid,(p_payload->>'linked_cfdi_id')::uuid)
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN invalid_text_representation OR not_null_violation OR check_violation OR foreign_key_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE FUNCTION public.rpc_record_payment(p_tenant_id uuid, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_invoice public.finance_invoices%ROWTYPE; v_id uuid; v_total numeric;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT i.* INTO v_invoice FROM public.finance_invoices AS i WHERE i.id=(p_payload->>'invoice_id')::uuid AND i.tenant_id=p_tenant_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
    INSERT INTO public.finance_payments (tenant_id,invoice_id,amount,paid_at,method,note,bank_reference,currency,created_by)
    VALUES (p_tenant_id,v_invoice.id,(p_payload->>'amount')::numeric,COALESCE((p_payload->>'paid_at')::timestamptz,now()),
        COALESCE(p_payload->>'method','transfer'),p_payload->>'note',p_payload->>'bank_reference',COALESCE(p_payload->>'currency',v_invoice.currency),auth.uid())
    RETURNING id INTO v_id;
    SELECT COALESCE(sum(p.amount),0) INTO v_total FROM public.finance_payments AS p WHERE p.invoice_id=v_invoice.id;
    IF v_total >= v_invoice.amount THEN UPDATE public.finance_invoices SET status='paid',paid_at=now() WHERE id=v_invoice.id; END IF;
    RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN invalid_text_representation OR check_violation OR foreign_key_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE FUNCTION public.rpc_update_finance_invoice_status(p_tenant_id uuid,p_id uuid,p_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin','finance']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    UPDATE public.finance_invoices SET status=p_status,paid_at=CASE WHEN p_status='paid' THEN COALESCE(paid_at,now()) ELSE paid_at END
    WHERE id=p_id AND tenant_id=p_tenant_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error','not_found'); END IF;
    RETURN jsonb_build_object('success',true);
EXCEPTION WHEN check_violation THEN RETURN jsonb_build_object('error','invalid_status');
END;
$function$;

CREATE FUNCTION public.rpc_list_inventory_lots(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(i) ORDER BY i.received_at) FROM public.inventory_lots AS i
        WHERE i.tenant_id=p_tenant_id AND (NOT (p_filters ? 'sku') OR i.sku ILIKE '%'||(p_filters->>'sku')||'%')), '[]'::jsonb);
END;
$function$;

CREATE FUNCTION public.rpc_create_inventory_lot(p_tenant_id uuid,p_sku text,p_lot_code text,p_qty_on_hand numeric,p_warehouse text,
    p_received_at timestamptz,p_currency text,p_pedimento_ref text,p_description text,p_unit text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_id uuid;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    INSERT INTO public.inventory_lots (tenant_id,sku,lot_code,qty_on_hand,warehouse,received_at,currency,pedimento_ref,description,unit)
    VALUES (p_tenant_id,p_sku,p_lot_code,p_qty_on_hand,p_warehouse,p_received_at,p_currency,p_pedimento_ref,p_description,p_unit) RETURNING id INTO v_id;
    RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN not_null_violation OR check_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE FUNCTION public.rpc_update_inventory_lot(p_id uuid,p_patch jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT i.tenant_id INTO v_tenant_id FROM public.inventory_lots AS i WHERE i.id=p_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    UPDATE public.inventory_lots AS i SET qty_reserved=COALESCE((p_patch->>'qty_reserved')::numeric,i.qty_reserved),
        status=COALESCE(p_patch->>'status',i.status),warehouse=COALESCE(p_patch->>'warehouse',i.warehouse),
        description=COALESCE(p_patch->>'description',i.description) WHERE i.id=p_id;
    RETURN jsonb_build_object('success',true);
EXCEPTION WHEN invalid_text_representation OR check_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE FUNCTION public.rpc_list_pedimentos(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.created_at DESC) FROM public.customs_pedimentos AS p
        WHERE p.tenant_id=p_tenant_id AND (NOT (p_filters ? 'pedimento_number') OR p.pedimento_number ILIKE '%'||(p_filters->>'pedimento_number')||'%')), '[]'::jsonb);
END;
$function$;

CREATE FUNCTION public.rpc_create_pedimento(p_tenant_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_id uuid;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    INSERT INTO public.customs_pedimentos (tenant_id,pedimento_number,operation_id,aduana,regimen,tipo_operacion,status,fecha_pago,total_value,currency)
    VALUES (p_tenant_id,p_payload->>'pedimento_number',(p_payload->>'operation_id')::uuid,p_payload->>'aduana',p_payload->>'regimen',
        p_payload->>'tipo_operacion',COALESCE(p_payload->>'status','draft'),(p_payload->>'fecha_pago')::date,
        (p_payload->>'total_value')::numeric,COALESCE(p_payload->>'currency','MXN')) RETURNING id INTO v_id;
    RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN invalid_text_representation OR not_null_violation OR check_violation OR foreign_key_violation THEN RETURN jsonb_build_object('error','invalid_payload');
    WHEN unique_violation THEN RETURN jsonb_build_object('error','pedimento_conflict');
END;
$function$;

CREATE FUNCTION public.rpc_update_pedimento(p_id uuid,p_patch jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT p.tenant_id INTO v_tenant_id FROM public.customs_pedimentos AS p WHERE p.id=p_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    UPDATE public.customs_pedimentos AS p SET status=COALESCE(p_patch->>'status',p.status),aduana=COALESCE(p_patch->>'aduana',p.aduana),
        regimen=COALESCE(p_patch->>'regimen',p.regimen),fecha_pago=COALESCE((p_patch->>'fecha_pago')::date,p.fecha_pago),
        fecha_entrada=COALESCE((p_patch->>'fecha_entrada')::date,p.fecha_entrada),fecha_salida=COALESCE((p_patch->>'fecha_salida')::date,p.fecha_salida),
        total_value=COALESCE((p_patch->>'total_value')::numeric,p.total_value),currency=COALESCE(p_patch->>'currency',p.currency) WHERE p.id=p_id;
    RETURN jsonb_build_object('success',true);
EXCEPTION WHEN invalid_text_representation OR check_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

CREATE FUNCTION public.rpc_list_descargo_lines(p_pedimento_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT p.tenant_id INTO v_tenant_id FROM public.customs_pedimentos AS p WHERE p.id=p_pedimento_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_is_member(v_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.sequence_no) FROM public.customs_descargo_lines AS d WHERE d.pedimento_id=p_pedimento_id),'[]'::jsonb);
END;
$function$;

CREATE FUNCTION public.rpc_add_descargo_line(p_pedimento_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid; v_id uuid; v_sequence integer;
BEGIN
    SELECT p.tenant_id INTO v_tenant_id FROM public.customs_pedimentos AS p WHERE p.id=p_pedimento_id FOR UPDATE;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(max(d.sequence_no),0)+1 INTO v_sequence FROM public.customs_descargo_lines AS d WHERE d.pedimento_id=p_pedimento_id;
    INSERT INTO public.customs_descargo_lines (tenant_id,pedimento_id,sequence_no,sku,lot_code,qty,unit,inventory_lot_id)
    VALUES (v_tenant_id,p_pedimento_id,v_sequence,p_payload->>'sku',p_payload->>'lot_code',(p_payload->>'qty')::numeric,
        COALESCE(p_payload->>'unit','Piezas'),(p_payload->>'inventory_lot_id')::uuid) RETURNING id INTO v_id;
    RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN invalid_text_representation OR not_null_violation OR check_violation OR foreign_key_violation THEN RETURN jsonb_build_object('error','invalid_payload');
END;
$function$;

-- ---------------------------------------------------------------------------
-- Settings, membership, invitations, audit, and module gating RPCs

CREATE FUNCTION public.rpc_get_tenant_settings(p_tenant_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    RETURN COALESCE((SELECT to_jsonb(s) FROM public.tenant_settings AS s WHERE s.tenant_id = p_tenant_id),
        jsonb_build_object('tenant_id', p_tenant_id, 'brand_name', 'ROTERO', 'primary_color', '#0F2B5B',
            'logo_url', NULL, 'timezone', 'America/Mexico_City', 'notifications_enabled', true,
            'allow_demo_mode', false, 'created_at', now(), 'updated_at', now()));
END;
$function$;

CREATE FUNCTION public.rpc_update_tenant_settings(p_tenant_id uuid, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    INSERT INTO public.tenant_settings (tenant_id, brand_name, primary_color, logo_url, timezone, notifications_enabled, allow_demo_mode)
    VALUES (p_tenant_id, COALESCE(p_payload->>'brand_name', 'ROTERO'), COALESCE(p_payload->>'primary_color', '#0F2B5B'),
        p_payload->>'logo_url', COALESCE(p_payload->>'timezone', 'America/Mexico_City'),
        COALESCE((p_payload->>'notifications_enabled')::boolean, true), COALESCE((p_payload->>'allow_demo_mode')::boolean, false))
    ON CONFLICT (tenant_id) DO UPDATE SET
        brand_name = COALESCE(p_payload->>'brand_name', public.tenant_settings.brand_name),
        primary_color = COALESCE(p_payload->>'primary_color', public.tenant_settings.primary_color),
        logo_url = CASE WHEN p_payload ? 'logo_url' THEN p_payload->>'logo_url' ELSE public.tenant_settings.logo_url END,
        timezone = COALESCE(p_payload->>'timezone', public.tenant_settings.timezone),
        notifications_enabled = COALESCE((p_payload->>'notifications_enabled')::boolean, public.tenant_settings.notifications_enabled),
        allow_demo_mode = COALESCE((p_payload->>'allow_demo_mode')::boolean, public.tenant_settings.allow_demo_mode);
    RETURN jsonb_build_object('success', true);
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object('error', 'invalid_payload');
END;
$function$;

CREATE FUNCTION public.rpc_update_member_role(p_tenant_id uuid, p_member_user_id uuid, p_new_role text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    IF p_new_role NOT IN ('admin', 'operator', 'finance', 'viewer') THEN RETURN jsonb_build_object('error', 'invalid_role'); END IF;
    UPDATE public.memberships SET role = p_new_role WHERE tenant_id = p_tenant_id AND user_id = p_member_user_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE FUNCTION public.rpc_deactivate_member(p_tenant_id uuid, p_member_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    IF p_member_user_id = auth.uid() THEN RETURN jsonb_build_object('error', 'cannot_deactivate_self'); END IF;
    DELETE FROM public.memberships WHERE tenant_id = p_tenant_id AND user_id = p_member_user_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'not_found'); END IF;
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE FUNCTION public.rpc_create_invitation(p_tenant_id uuid, p_email text, p_role text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public, extensions
AS $function$
DECLARE v_token text; v_id uuid;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    IF p_role NOT IN ('admin', 'operator', 'finance', 'viewer') OR position('@' IN lower(btrim(p_email))) <= 1 THEN
        RETURN jsonb_build_object('error', 'invalid_payload');
    END IF;
    v_token := encode(extensions.gen_random_bytes(24), 'hex');
    INSERT INTO public.invitations (tenant_id, email, role, token_hash, created_by, expires_at)
    VALUES (p_tenant_id, lower(btrim(p_email)), p_role, encode(extensions.digest(v_token, 'sha256'), 'hex'), auth.uid(), now() + interval '7 days')
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('id', v_id, 'token', v_token);
END;
$function$;

CREATE FUNCTION public.rpc_accept_invitation(p_token text, p_password text, p_full_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public, extensions
AS $function$
DECLARE v_invitation public.invitations%ROWTYPE; v_email text;
BEGIN
    IF auth.uid() IS NULL THEN RETURN jsonb_build_object('error', 'authentication_required'); END IF;
    SELECT u.email INTO v_email FROM auth.users AS u WHERE u.id = auth.uid();
    SELECT i.* INTO v_invitation FROM public.invitations AS i
    WHERE i.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
      AND i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.expires_at > now()
    FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'invalid_or_expired'); END IF;
    IF lower(v_email) <> v_invitation.email THEN RETURN jsonb_build_object('error', 'email_mismatch'); END IF;
    INSERT INTO public.memberships (tenant_id, user_id, role)
    VALUES (v_invitation.tenant_id, auth.uid(), v_invitation.role)
    ON CONFLICT (user_id, tenant_id) DO UPDATE SET role = EXCLUDED.role;
    UPDATE public.invitations SET accepted_at = now() WHERE id = v_invitation.id;
    INSERT INTO public.audit_log (tenant_id, actor_user_id, actor_email, actor_name, action, entity_type, entity_id, metadata)
    VALUES (v_invitation.tenant_id, auth.uid(), v_email, NULLIF(p_full_name, ''), 'invitation_accepted', 'membership', auth.uid(),
        jsonb_build_object('invitation_id', v_invitation.id));
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE FUNCTION public.rpc_list_audit_log(
    p_tenant_id uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0,
    p_entity_type text DEFAULT NULL, p_action text DEFAULT NULL,
    p_start timestamptz DEFAULT NULL, p_end timestamptz DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'viewer']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    RETURN jsonb_build_object(
        'items', COALESCE((SELECT jsonb_agg(x.row_json ORDER BY x.created_at DESC) FROM (
            SELECT a.created_at, jsonb_build_object('id', a.id, 'action', a.action, 'entity_type', a.entity_type,
                'entity_id', a.entity_id, 'created_at', a.created_at, 'metadata', a.metadata,
                'actor_id', a.actor_user_id, 'actor_email', a.actor_email, 'actor_name', a.actor_name) AS row_json
            FROM public.audit_log AS a WHERE a.tenant_id = p_tenant_id
              AND (p_entity_type IS NULL OR a.entity_type = p_entity_type) AND (p_action IS NULL OR a.action = p_action)
              AND (p_start IS NULL OR a.created_at >= p_start) AND (p_end IS NULL OR a.created_at <= p_end)
            ORDER BY a.created_at DESC LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0)
        ) AS x), '[]'::jsonb),
        'total', (SELECT count(*) FROM public.audit_log AS a WHERE a.tenant_id = p_tenant_id
            AND (p_entity_type IS NULL OR a.entity_type = p_entity_type) AND (p_action IS NULL OR a.action = p_action)
            AND (p_start IS NULL OR a.created_at >= p_start) AND (p_end IS NULL OR a.created_at <= p_end)),
        'distinct_entities', COALESCE((SELECT jsonb_agg(x.entity_type) FROM (SELECT DISTINCT a.entity_type FROM public.audit_log AS a WHERE a.tenant_id = p_tenant_id) AS x), '[]'::jsonb),
        'distinct_actions', COALESCE((SELECT jsonb_agg(x.action) FROM (SELECT DISTINCT a.action FROM public.audit_log AS a WHERE a.tenant_id = p_tenant_id) AS x), '[]'::jsonb));
END;
$function$;

CREATE FUNCTION public.rpc_validate_module_access(p_tenant_id uuid, p_module_name text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_row public.tenant_setup_status%ROWTYPE;
BEGIN
    IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error', 'unauthorized', 'is_configured', false); END IF;
    SELECT s.* INTO v_row FROM public.tenant_setup_status AS s WHERE s.tenant_id = p_tenant_id AND s.module_name = p_module_name;
    RETURN jsonb_build_object('is_configured', COALESCE(v_row.is_configured, false), 'config_data', COALESCE(v_row.config_data, '{}'::jsonb));
END;
$function$;

CREATE FUNCTION public.rpc_demo_configure_module(p_tenant_id uuid, p_module_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_demo boolean;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin']) THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    SELECT s.allow_demo_mode INTO v_demo FROM public.tenant_settings AS s WHERE s.tenant_id = p_tenant_id;
    IF v_demo IS NOT TRUE THEN RETURN jsonb_build_object('error', 'demo_mode_disabled'); END IF;
    IF p_module_name NOT IN ('inventory', 'customs', 'billing') THEN RETURN jsonb_build_object('error', 'invalid_module'); END IF;
    INSERT INTO public.tenant_setup_status (tenant_id, module_name, is_configured, config_data, updated_by)
    VALUES (p_tenant_id, p_module_name, true, jsonb_build_object('mode', 'demo'), auth.uid())
    ON CONFLICT (tenant_id, module_name) DO UPDATE SET is_configured = true, config_data = EXCLUDED.config_data,
        updated_by = EXCLUDED.updated_by, updated_at = now();
    RETURN jsonb_build_object('success', true);
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
ALTER TABLE public.tenant_setup_status ENABLE ROW LEVEL SECURITY;
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
CREATE POLICY tenant_setup_status_select_members ON public.tenant_setup_status
    FOR SELECT TO authenticated USING (public.tanda1_user_is_member(tenant_id));
CREATE POLICY tenant_setup_status_manage_admin ON public.tenant_setup_status
    FOR ALL TO authenticated
    USING (public.tanda1_user_has_role(tenant_id, ARRAY['admin']))
    WITH CHECK (public.tanda1_user_has_role(tenant_id, ARRAY['admin']));

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
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated, service_role;

-- The public tracking Edge Function records only a one-way token hash and
-- request metadata. This is the sole approved direct table write.
GRANT INSERT (token_hash, ip_hash, user_agent, country_code)
    ON public.tracking_access_log TO service_role;

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
GRANT EXECUTE ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_tracking_token(uuid, uuid, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_revoke_tracking_token(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_tracking_tokens(uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_assign_operation(uuid, uuid, uuid, uuid, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_assign_operation_v2(uuid, uuid, uuid, text, uuid, text, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_operation_details(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_transition_operation_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_override_operation_status(uuid, text, text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_dashboard_overview(uuid, timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_dashboard_recent_activity(uuid, timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_dashboard_alerts(uuid, timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_reports_financial_summary(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_reports_pipeline_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_reports_inventory_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_reports_operations_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_route_points(uuid, timestamptz, timestamptz, integer) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_list_deals(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_deal(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_deal(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_move_deal(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_deal(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_deal_activities(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_add_deal_activity(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_add_deal_note(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_deal_notes(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_deal_checklist(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_toggle_deal_checklist_item(uuid, boolean) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_list_cfdis(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_cfdi_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_cfdi(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_cfdi(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_upsert_carta_porte(uuid, jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_finance_overview(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_finance_invoices(uuid, integer, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_finance_invoice(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_payment(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_finance_invoice_status(uuid, uuid, text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_list_inventory_lots(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_inventory_lot(uuid, text, text, numeric, text, timestamptz, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_inventory_lot(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_pedimentos(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_pedimento(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_pedimento(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_descargo_lines(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_add_descargo_line(uuid, jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_get_tenant_settings(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_tenant_settings(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_update_member_role(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_deactivate_member(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_invitation(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_accept_invitation(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_list_audit_log(uuid, integer, integer, text, text, timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_validate_module_access(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_demo_configure_module(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.rpc_get_public_tracking(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_get_driver_view(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpc_post_driver_event(text, text, text, numeric, numeric, numeric, text, text, character, text, text, timestamptz, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_get_public_tracking(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_get_driver_view(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.rpc_post_driver_event(text, text, text, numeric, numeric, numeric, text, text, character, text, text, timestamptz, boolean) TO service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
