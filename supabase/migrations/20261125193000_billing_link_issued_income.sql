-- Links already issued income; no fiscal transport or receivable writes.
BEGIN;

CREATE FUNCTION private.delivery_issued_income_links(
    p_tenant_id uuid, p_cfdi_id uuid, p_operation_ids uuid[], p_requested_folios text[],
    p_xml_base64 text, p_apply boolean
) RETURNS jsonb
LANGUAGE plpgsql SET search_path = '' AS $body$
DECLARE
    company uuid;
    actor uuid;
    cfdi public.billing_cfdis%ROWTYPE;
    file public.document_files%ROWTYPE;
    billing_document public.billing_documents%ROWTYPE;
    receivable public.finance_invoices%ROWTYPE;
    op record;
    canonical_document_id uuid;
    receivable_id uuid;
    operation_count integer := 0;
    pending_links integer := 0;
    linked_count integer := 0;
    linked_operation uuid;
    xml_bytes bytea;
    xml_text text;
    invoice_xml xml;
    invoice record;
    folios text[];
    reason text;
    outcome text;
    results jsonb := '[]';
BEGIN
    actor := auth.uid();
    IF actor IS NULL OR NOT COALESCE(private.delivery_required(p_tenant_id), false)
       OR NOT public.tanda1_user_has_role(p_tenant_id, ARRAY['admin', 'finance'])
       OR NOT COALESCE(private.delivery_finance_write_target(p_tenant_id, 'cfdi', NULL), false)
    THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    company := (private.delivery_company_ids())[1];

    IF p_cfdi_id IS NULL
       OR (p_apply AND (p_operation_ids IS NULL OR cardinality(p_operation_ids) NOT BETWEEN 1 AND 100
           OR array_ndims(p_operation_ids) IS DISTINCT FROM 1
           OR cardinality(p_operation_ids) <> (SELECT count(DISTINCT id) FROM unnest(p_operation_ids) AS ids(id))))
       OR (p_requested_folios IS NOT NULL AND (
           cardinality(p_requested_folios) NOT BETWEEN 1 AND 100
           OR array_ndims(p_requested_folios) IS DISTINCT FROM 1
           OR cardinality(p_requested_folios) <> (SELECT count(DISTINCT folio) FROM unnest(p_requested_folios) AS items(folio))
           OR EXISTS(SELECT FROM unnest(p_requested_folios) AS items(folio) WHERE octet_length(folio) NOT BETWEEN 1 AND 1024)))
       OR ((p_apply OR p_requested_folios IS NOT NULL)
           AND (p_xml_base64 IS NULL OR octet_length(p_xml_base64) NOT BETWEEN 1 AND 2666668))
    THEN RETURN jsonb_build_object('error', 'invalid_payload'); END IF;

    IF p_apply THEN
        -- Serialize with existing company classification and Finance writes in this tenant.
        PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant_id::text, 7007));
    END IF;
    IF company IS NULL OR NOT COALESCE(private.delivery_finance_write_target(p_tenant_id, 'cfdi', p_cfdi_id), false)
    THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    -- Keep the same issued state and artifact binding throughout the link.
    SELECT * INTO cfdi FROM public.billing_cfdis
    WHERE id = p_cfdi_id AND tenant_id = p_tenant_id AND company_id = company
      AND company_classification_status = 'resolved'
    FOR SHARE;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;
    IF cfdi.fiscal_status <> 'stamped' OR cfdi.status = 'cancelado'
       OR cfdi.cancelled_at IS NOT NULL OR cfdi.fiscal_cancelled_at IS NOT NULL
       OR cfdi.fiscal_stamped_at IS NULL OR cfdi.fiscal_environment = 'sandbox'
       OR cfdi.uuid IS NULL OR cfdi.uuid !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    THEN RETURN jsonb_build_object('error', 'invoice_not_issued'); END IF;

    SELECT * INTO file FROM public.document_files
    WHERE id = cfdi.xml_document_file_id AND tenant_id = p_tenant_id AND company_id = company
      AND status = 'active' AND storage_bucket = 'tenant-documents' AND file_kind = 'fiscal_xml'
      AND source_module = 'billing' AND source_entity_type = 'billing_cfdi' AND source_entity_id = cfdi.id
    FOR SHARE;
    IF NOT FOUND OR file.checksum_sha256 IS NULL
    THEN RETURN jsonb_build_object('error', 'verified_xml_required'); END IF;

    FOR billing_document IN
        SELECT * FROM public.billing_documents
        WHERE tenant_id = p_tenant_id AND linked_cfdi_id = cfdi.id AND status NOT IN ('cancelled', 'voided')
        ORDER BY id FOR SHARE
    LOOP
        IF canonical_document_id IS NOT NULL OR billing_document.company_id IS DISTINCT FROM company
           OR billing_document.company_classification_status <> 'resolved'
           OR billing_document.document_direction <> 'ingreso' OR billing_document.document_type <> 'cfdi_ingreso'
        THEN RETURN jsonb_build_object('error', 'income_document_required'); END IF;
        canonical_document_id := billing_document.id;
    END LOOP;
    IF canonical_document_id IS NULL THEN RETURN jsonb_build_object('error', 'income_document_required'); END IF;

    FOR receivable IN
        SELECT * FROM public.finance_invoices
        WHERE tenant_id = p_tenant_id AND direction = 'ar' AND status <> 'void'
          AND (linked_cfdi_id = cfdi.id OR finance_invoices.billing_document_id = canonical_document_id)
        ORDER BY id FOR SHARE
    LOOP
        IF receivable_id IS NOT NULL OR receivable.company_id IS DISTINCT FROM company
           OR receivable.company_classification_status <> 'resolved' OR receivable.status = 'draft'
           OR receivable.currency <> cfdi.currency OR receivable.amount IS DISTINCT FROM cfdi.total
           OR (receivable.linked_cfdi_id IS NOT NULL AND receivable.linked_cfdi_id <> cfdi.id)
           OR (receivable.billing_document_id IS NOT NULL AND receivable.billing_document_id <> canonical_document_id)
        THEN RETURN jsonb_build_object('error', 'single_receivable_required'); END IF;
        receivable_id := receivable.id;
    END LOOP;
    IF receivable_id IS NULL THEN RETURN jsonb_build_object('error', 'single_receivable_required'); END IF;

    IF NOT p_apply AND p_requested_folios IS NULL THEN
        SELECT COALESCE(jsonb_agg(o.reference_code ORDER BY o.reference_code), '[]'::jsonb) INTO results
        FROM public.operation_billing b
        JOIN public.operations o ON o.id = b.operation_id AND o.tenant_id = b.tenant_id
        WHERE b.tenant_id = p_tenant_id AND b.linked_cfdi_id = cfdi.id AND b.status = 'issued'
          AND o.company_id = company AND o.company_classification_status = 'resolved';
        RETURN jsonb_build_object('xml_file_id', file.id, 'linked_folios', results);
    END IF;

    BEGIN
        xml_bytes := decode(p_xml_base64, 'base64');
        IF octet_length(xml_bytes) > 2000000 OR octet_length(xml_bytes) <> file.size_bytes
           OR encode(pg_catalog.sha256(xml_bytes), 'hex') <> file.checksum_sha256
        THEN RETURN jsonb_build_object('error', 'xml_integrity_mismatch'); END IF;
        xml_text := convert_from(xml_bytes, 'UTF8');
        IF xml_text ~* '<!DOCTYPE|<!ENTITY'
        THEN RETURN jsonb_build_object('error', 'invalid_xml'); END IF;
        invoice_xml := XMLPARSE(DOCUMENT xml_text);
        SELECT * INTO invoice
        FROM XMLTABLE(
            XMLNAMESPACES ('http://www.sat.gob.mx/cfd/4' AS cfdi,
                           'http://www.sat.gob.mx/TimbreFiscalDigital' AS tfd),
            '/cfdi:Comprobante' PASSING invoice_xml
            COLUMNS version text PATH '@Version', kind text PATH '@TipoDeComprobante',
                currency text PATH '@Moneda', total numeric PATH '@Total',
                issuer text PATH 'cfdi:Emisor/@Rfc', receiver text PATH 'cfdi:Receptor/@Rfc',
                uuid text PATH 'cfdi:Complemento/tfd:TimbreFiscalDigital/@UUID'
        );
        IF NOT FOUND OR invoice.version IS DISTINCT FROM '4.0' OR invoice.kind IS DISTINCT FROM 'I'
           OR lower(invoice.uuid) IS DISTINCT FROM lower(cfdi.uuid)
           OR invoice.issuer IS DISTINCT FROM cfdi.rfc_emisor OR invoice.receiver IS DISTINCT FROM cfdi.rfc_receptor
           OR invoice.currency IS DISTINCT FROM cfdi.currency OR invoice.total IS DISTINCT FROM cfdi.total
        THEN RETURN jsonb_build_object('error', 'income_xml_mismatch'); END IF;
        SELECT array_agg(folio) FILTER (WHERE folio IS NOT NULL) INTO folios
        FROM XMLTABLE(
            XMLNAMESPACES ('http://www.sat.gob.mx/cfd/4' AS cfdi),
            '/cfdi:Comprobante/cfdi:Conceptos/cfdi:Concepto' PASSING invoice_xml
            COLUMNS folio text PATH '@NoIdentificacion'
        );
    EXCEPTION WHEN data_exception THEN
        RETURN jsonb_build_object('error', 'invalid_xml');
    END;

    IF p_apply THEN
        -- Lock only scoped operations in a common order. Review never changes Billing.
        PERFORM id FROM public.operations
        WHERE tenant_id = p_tenant_id AND company_id = company AND company_classification_status = 'resolved'
          AND id = ANY(p_operation_ids)
        ORDER BY id FOR UPDATE;
        GET DIAGNOSTICS operation_count = ROW_COUNT;
        IF operation_count <> cardinality(p_operation_ids)
        THEN RETURN jsonb_build_object('error', 'unauthorized'); END IF;

        PERFORM operation_id FROM public.operation_billing
        WHERE operation_id = ANY(p_operation_ids)
        ORDER BY operation_id FOR UPDATE;
    END IF;

    FOR op IN
        WITH requested AS (
            SELECT id, NULL::text AS folio, priority
            FROM unnest(p_operation_ids) WITH ORDINALITY AS ids(id, priority)
            UNION ALL
            SELECT NULL::uuid, folio, priority
            FROM unnest(p_requested_folios) WITH ORDINALITY AS items(folio, priority)
        )
        SELECT o.id, COALESCE(o.reference_code, r.folio) AS folio, o.status,
            b.id AS billing_id, b.tenant_id AS billing_tenant, b.status AS billing_status, b.linked_cfdi_id
        FROM requested r
        LEFT JOIN public.operations o
          ON o.tenant_id = p_tenant_id AND o.company_id = company AND o.company_classification_status = 'resolved'
         AND (o.id = r.id OR o.reference_code = r.folio)
        LEFT JOIN public.operation_billing b ON b.operation_id = o.id
        ORDER BY r.priority
    LOOP
        reason := NULL;
        outcome := 'ready';
        IF op.id IS NULL THEN
            reason := 'folio_not_available';
        ELSIF NOT COALESCE(op.folio = ANY(folios), false) THEN
            reason := 'folio_missing_from_invoice';
        ELSIF op.billing_status = 'issued' AND op.billing_tenant = p_tenant_id AND op.linked_cfdi_id = cfdi.id
              AND op.status IN ('delivered', 'closed') THEN
            outcome := 'already_linked';
        ELSIF op.status <> 'delivered' THEN
            reason := 'operation_not_delivered';
        ELSIF op.billing_id IS NOT NULL AND (
            op.billing_tenant <> p_tenant_id OR op.billing_status <> 'draft'
            OR (op.linked_cfdi_id IS NOT NULL AND op.linked_cfdi_id <> cfdi.id)
        ) THEN
            reason := 'billing_link_conflict';
        END IF;

        IF p_apply THEN
            IF reason IS NOT NULL THEN RETURN jsonb_build_object('error', reason); END IF;
            IF outcome = 'ready' THEN pending_links := pending_links + 1; END IF;
        ELSE
            results := results || jsonb_build_array(jsonb_build_object('folio', op.folio,
                'operation_id', CASE WHEN reason IS NULL THEN op.id END,
                'status', CASE WHEN reason IS NULL THEN outcome ELSE 'rejected' END, 'reason', reason));
        END IF;
    END LOOP;
    IF NOT p_apply THEN RETURN jsonb_build_object('results', results); END IF;

    FOR linked_operation IN
        INSERT INTO public.operation_billing AS existing (
            tenant_id, operation_id, status, linked_cfdi_id, billing_reference, issued_at, issued_by
        )
        SELECT p_tenant_id, ids.id, 'issued', cfdi.id, cfdi.uuid, cfdi.fiscal_stamped_at, actor
        FROM unnest(p_operation_ids) AS ids(id) ORDER BY ids.id
        ON CONFLICT (operation_id) DO UPDATE
          SET status = EXCLUDED.status, linked_cfdi_id = EXCLUDED.linked_cfdi_id,
              billing_reference = EXCLUDED.billing_reference, issued_at = EXCLUDED.issued_at, issued_by = EXCLUDED.issued_by
        WHERE existing.tenant_id = p_tenant_id AND existing.status = 'draft'
          AND (existing.linked_cfdi_id IS NULL OR existing.linked_cfdi_id = cfdi.id)
        RETURNING operation_id
    LOOP
        PERFORM public.rpc_write_audit(p_tenant_id, 'operation_income_invoice_linked', 'operation',
            linked_operation, jsonb_build_object('cfdi_id', cfdi.id, 'finance_invoice_id', receivable_id));
        linked_count := linked_count + 1;
    END LOOP;
    IF linked_count <> pending_links THEN
        RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'operation_billing_changed';
    END IF;
    RETURN jsonb_build_object('success', true, 'linked_count', linked_count);
END $body$;

REVOKE ALL ON FUNCTION private.delivery_issued_income_links(uuid, uuid, uuid[], text[], text, boolean)
FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.rpc_delivery_review_issued_income(
    p_tenant_id uuid, p_cfdi_id uuid, p_folios text[] DEFAULT NULL, p_xml_base64 text DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
    SELECT private.delivery_issued_income_links(p_tenant_id, p_cfdi_id, NULL, p_folios, p_xml_base64, false)
$$;

CREATE FUNCTION public.rpc_delivery_link_issued_income(
    p_tenant_id uuid, p_cfdi_id uuid, p_operation_ids uuid[], p_xml_base64 text
) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
    SELECT private.delivery_issued_income_links(p_tenant_id, p_cfdi_id, p_operation_ids, NULL, p_xml_base64, true)
$$;

REVOKE ALL ON FUNCTION public.rpc_delivery_review_issued_income(uuid, uuid, text[], text),
    public.rpc_delivery_link_issued_income(uuid, uuid, uuid[], text)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_review_issued_income(uuid, uuid, text[], text),
    public.rpc_delivery_link_issued_income(uuid, uuid, uuid[], text)
TO authenticated;

COMMIT;
