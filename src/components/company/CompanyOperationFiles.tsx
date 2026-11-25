import { CompanyDocumentManager } from './CompanyDocumentManager';
import type { DocumentParent } from '@/services/companyDocuments.service';

export function CompanyOperationFiles({ operationId, entityType = 'operation', onChanged }: { operationId: string; entityType?: string; onChanged?: () => Promise<void> }) {
    if (!['operation', 'finance_invoice', 'billing_document'].includes(entityType)) {
        return <p>Este expediente todavía requiere clasificación empresarial.</p>;
    }
    return <CompanyDocumentManager entityType={entityType as DocumentParent} entityId={operationId} onChanged={onChanged} />;
}
