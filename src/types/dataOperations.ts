export type ImportEntity = 'customers' | 'providers' | 'operations';
export type ImportMode = 'create_only' | 'upsert';
export type ExportEntity = ImportEntity | 'quotes' | 'documents' | 'finance_ar' | 'finance_ap';

export interface ImportIssue { code: string; message: string }
export interface ImportValidationItem {
    row_number: number;
    external_key?: string;
    existing_entity_id?: string;
    action: 'create' | 'update' | 'skip' | 'error';
    errors: ImportIssue[];
    warnings: ImportIssue[];
    normalized?: Record<string, unknown>;
    status?: 'applied' | 'updated' | 'skipped' | 'error';
    applied_entity_id?: string;
}
export interface ImportSummary { total: number; create: number; update: number; skip: number; errors: number; warnings: number }
export interface ImportValidation { entity_type: ImportEntity; mode: ImportMode; results: ImportValidationItem[]; summary: ImportSummary }
export interface ImportBatch {
    id: string; entity_type: ImportEntity; filename: string; mode: ImportMode; total_rows: number;
    valid_rows: number; applied_rows: number; updated_rows: number; skipped_rows: number; error_rows: number;
    status: string; started_at: string; completed_at?: string | null; summary: Record<string, unknown>;
}
export interface ImportMapping { id: string; entity_type: ImportEntity; name: string; mapping: Record<string, string>; created_at: string; updated_at: string }
export interface ExportFilters { search?: string; status?: string; date_from?: string; date_to?: string }
export interface ExportPage { items: Array<Record<string, unknown>>; next_cursor: { created_at: string; id: string } | null; page_size: number; max_sync_rows: number }

export interface CsvField {
    key: string; label: string; required?: boolean; aliases?: string[]; example?: string; sensitive?: boolean;
}

export const IMPORT_ENTITY_LABELS: Record<ImportEntity, string> = {
    customers: 'Clientes', providers: 'Proveedores', operations: 'Operaciones',
};

export const EXPORT_ENTITY_LABELS: Record<ExportEntity, string> = {
    ...IMPORT_ENTITY_LABELS, quotes: 'Cotizaciones', documents: 'Documentos', finance_ar: 'Cuentas por cobrar', finance_ap: 'Cuentas por pagar',
};

export const IMPORT_FIELDS: Record<ImportEntity, CsvField[]> = {
    customers: [
        { key: 'external_key', label: 'Clave externa', aliases: ['id_externo', 'clave'], example: 'CLI-001' },
        { key: 'display_name', label: 'Nombre comercial', required: true, aliases: ['cliente', 'nombre'], example: 'Empresa Demo' },
        { key: 'legal_name', label: 'Razón social', aliases: ['razon_social'] }, { key: 'tax_id', label: 'RFC', aliases: ['rfc'] },
        { key: 'contact_name', label: 'Contacto', aliases: ['contacto'] }, { key: 'contact_email', label: 'Email contacto', aliases: ['email'] },
        { key: 'contact_phone', label: 'Teléfono', aliases: ['telefono'] }, { key: 'billing_email', label: 'Email facturación', aliases: ['email_facturacion'] },
        { key: 'preferred_currency', label: 'Moneda', aliases: ['moneda'], example: 'MXN' }, { key: 'is_active', label: 'Activo', aliases: ['activo'], example: 'true' },
        { key: 'notes', label: 'Notas', aliases: ['notas'], sensitive: true },
    ],
    providers: [
        { key: 'external_key', label: 'Clave externa', aliases: ['id_externo', 'clave'], example: 'PRV-001' },
        { key: 'display_name', label: 'Nombre comercial', required: true, aliases: ['proveedor', 'nombre'], example: 'Transportes Demo' },
        { key: 'legal_name', label: 'Razón social', aliases: ['razon_social'] }, { key: 'tax_id', label: 'RFC', aliases: ['rfc'] },
        { key: 'contact_name', label: 'Contacto', aliases: ['contacto'] }, { key: 'contact_email', label: 'Email contacto', aliases: ['email'] },
        { key: 'contact_phone', label: 'Teléfono', aliases: ['telefono'] }, { key: 'billing_email', label: 'Email facturación', aliases: ['email_facturacion'] },
        { key: 'is_active', label: 'Activo', aliases: ['activo'], example: 'true' }, { key: 'notes', label: 'Notas', aliases: ['notas'], sensitive: true },
    ],
    operations: [
        { key: 'external_key', label: 'Clave externa', required: true, aliases: ['id_externo', 'clave'], example: 'OP-001' },
        { key: 'reference_code', label: 'Referencia', aliases: ['referencia'] },
        { key: 'customer_external_key', label: 'Clave cliente', aliases: ['cliente_clave'], example: 'CLI-001' }, { key: 'customer_tax_id', label: 'RFC cliente', aliases: ['cliente_rfc'] }, { key: 'customer_name', label: 'Nombre cliente', aliases: ['cliente'] },
        { key: 'provider_external_key', label: 'Clave proveedor', aliases: ['proveedor_clave'] }, { key: 'provider_tax_id', label: 'RFC proveedor', aliases: ['proveedor_rfc'] }, { key: 'provider_name', label: 'Nombre proveedor', aliases: ['proveedor'] },
        { key: 'service_type', label: 'Tipo de servicio', required: true, aliases: ['servicio'], example: 'FTL' }, { key: 'operation_scope', label: 'Alcance', aliases: ['alcance'], example: 'national' },
        { key: 'origin_municipality', label: 'Municipio origen', required: true, aliases: ['origen', 'ciudad_origen'] }, { key: 'origin_state', label: 'Estado origen', required: true }, { key: 'origin_country_code', label: 'País origen', example: 'MX' },
        { key: 'destination_municipality', label: 'Municipio destino', required: true, aliases: ['destino', 'ciudad_destino'] }, { key: 'destination_state', label: 'Estado destino', required: true }, { key: 'destination_country_code', label: 'País destino', example: 'MX' },
        { key: 'operational_window_start', label: 'Inicio ventana', required: true, aliases: ['inicio'], example: '2026-08-28T09:00:00-06:00' },
        { key: 'operational_window_end', label: 'Fin ventana', required: true, aliases: ['fin'], example: '2026-08-28T18:00:00-06:00' },
        { key: 'cargo_description', label: 'Carga', required: true, aliases: ['carga'] }, { key: 'cargo_weight_kg', label: 'Peso kg', aliases: ['peso_kg'] },
        { key: 'pricing_currency', label: 'Moneda', example: 'MXN' }, { key: 'customer_price_amount', label: 'Venta' }, { key: 'provider_cost_amount', label: 'Costo' },
        { key: 'notes', label: 'Notas', aliases: ['notas'], sensitive: true },
    ],
};
