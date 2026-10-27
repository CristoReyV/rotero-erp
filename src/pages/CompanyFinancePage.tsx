import { hasCompanyCapability } from '@/store/companyStore';
import FinancePage from './FinancePage';
import CompanyReceivablesPage from './CompanyReceivablesPage';

export default function CompanyFinancePage() {
    return hasCompanyCapability('financial.full.read') ? <FinancePage /> : <CompanyReceivablesPage />;
}
