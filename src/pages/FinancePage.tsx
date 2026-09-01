import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertCircle, Download, Loader2, RefreshCw, ShieldAlert } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';
import { PageHeader } from '@/components/PageHeader';
import { SavedViewsMenu } from '@/components/productivity/SavedViewsMenu';
import { BulkActionBar } from '@/components/productivity/BulkActionBar';
import { DueAlertsPanel } from '@/components/finance/DueAlertsPanel';
import { FinanceInvoiceDrawer } from '@/components/finance/FinanceInvoiceDrawer';
import { FinanceOverview } from '@/components/finance/FinanceOverview';
import { InvoiceCreateModal } from '@/components/finance/InvoiceCreateModal';
import { PayablesWorkspace } from '@/components/finance/PayablesWorkspace';
import { PaymentActivity } from '@/components/finance/PaymentActivity';
import { PaymentDrawer } from '@/components/finance/PaymentDrawer';
import { ProfitabilityWorkspace } from '@/components/finance/ProfitabilityWorkspace';
import { ReceivablesWorkspace } from '@/components/finance/ReceivablesWorkspace';
import { canAccessRoteroModule } from '@/constants/roles';
import {
    downloadFinanceCsv, exportFinanceLedger, getFinanceOverview, getFinanceProfitability,
    listFinanceDueAlerts, listFinanceInvoices, listFinancePayments,
} from '@/services/finance.service';
import { listOperations } from '@/services/operations.service';
import { useAuthStore } from '@/store/authStore';
import type { FinanceCurrency, FinanceDueAlert, FinanceInvoice, FinanceOverview as Overview, FinancePayment, FinanceProfitability, InvoiceDirection, InvoiceStatus } from '@/types/finance';
import type { Operation } from '@/types/operations';
import { recordDataAction } from '@/services/dataOperations.service';
import { downloadCsvContent, serializeCsv } from '@/utils/csv';

type FinanceTab = 'overview' | 'ar' | 'ap' | 'payments' | 'due' | 'profitability';
const TABS: Array<{ value: FinanceTab; label: string }> = [
    { value: 'overview', label: 'Resumen' }, { value: 'ar', label: 'Por cobrar' }, { value: 'ap', label: 'Por pagar' },
    { value: 'payments', label: 'Pagos' }, { value: 'due', label: 'Vencimientos' }, { value: 'profitability', label: 'Rentabilidad' },
];
const isTab = (value: string | null): value is FinanceTab => TABS.some((tab) => tab.value === value);

export default function FinancePage() {
    const tenantId = useAuthStore((state) => state.activeTenant); const role = useAuthStore((state) => state.getRole());
    const canView = canAccessRoteroModule(role, 'finance'); const [params,setParams]=useSearchParams(); const requested=params.get('view'); const tab:FinanceTab=isTab(requested)?requested:'overview';
    const customerId=params.get('customerId');const providerId=params.get('providerId');const partnerId=tab==='ar'?customerId:tab==='ap'?providerId:null;
    const partnerName=params.get('counterpartyName')??'';const suggestedTerms=Math.max(0,Number(params.get('suggestedTerms')??0)||0);
    const [overview,setOverview]=useState<Overview|null>(null); const [invoices,setInvoices]=useState<FinanceInvoice[]>([]); const [payments,setPayments]=useState<FinancePayment[]>([]);
    const [alerts,setAlerts]=useState<FinanceDueAlert[]>([]); const [profitability,setProfitability]=useState<FinanceProfitability|null>(null); const [operations,setOperations]=useState<Operation[]>([]);
    const [search,setSearch]=useState(''); const [status,setStatus]=useState<InvoiceStatus|''>(''); const [currency,setCurrency]=useState<FinanceCurrency|''>(''); const [daysAhead,setDaysAhead]=useState(14);
    const [loading,setLoading]=useState(false); const [error,setError]=useState<string|null>(null); const [selected,setSelected]=useState<FinanceInvoice|null>(null); const [paying,setPaying]=useState<FinanceInvoice|null>(null); const [creating,setCreating]=useState<InvoiceDirection|null>(null);
    const [bulkIds,setBulkIds]=useState<Set<string>>(new Set());

    const load=useCallback(async()=>{if(!tenantId||!canView)return;setLoading(true);setError(null);try{const direction:InvoiceDirection|undefined=tab==='ar'?'ar':tab==='ap'?'ap':undefined;const [nextOverview,nextInvoices,nextPayments,nextAlerts,nextProfitability,nextOperations]=await Promise.all([
        getFinanceOverview(tenantId), listFinanceInvoices(tenantId,{direction,search:search||undefined,status:status||undefined,currency:currency||undefined,customer_id:tab==='ar'?customerId||undefined:undefined,provider_id:tab==='ap'?providerId||undefined:undefined,limit:200}),
        listFinancePayments(tenantId,{limit:200}), listFinanceDueAlerts(tenantId,{days_ahead:daysAhead}), getFinanceProfitability(tenantId), listOperations(tenantId),
    ]);setOverview(nextOverview);setInvoices(nextInvoices);setPayments(nextPayments);setAlerts(nextAlerts);setProfitability(nextProfitability);setOperations(nextOperations);}catch(cause){setError(cause instanceof Error?cause.message:'No fue posible cargar Finance 360.');}finally{setLoading(false);}},[tenantId,canView,tab,search,status,currency,daysAhead,customerId,providerId]);
    useEffect(()=>{void load();},[load]);
    useEffect(()=>{const invoiceId=params.get('invoiceId');if(invoiceId){const invoice=invoices.find(item=>item.id===invoiceId);if(invoice)setSelected(invoice);}const action=params.get('action');if(action==='new'&&(tab==='ar'||tab==='ap')){setCreating(tab);const next=new URLSearchParams(params);next.delete('action');setParams(next,{replace:true});}},[invoices,params,setParams,tab]);
    const changeTab=(value:FinanceTab)=>{const next=new URLSearchParams(params);next.set('view',value);next.delete('invoiceId');setParams(next);setStatus('');setCurrency('');setSearch('');setBulkIds(new Set());};
    const openById=(id:string)=>{const invoice=invoices.find((item)=>item.id===id);if(invoice){setSelected(invoice);const next=new URLSearchParams(params);next.set('invoiceId',id);setParams(next,{replace:true});}};
    const filtered=useMemo(()=>invoices.filter((item)=>tab==='ar'?item.direction==='ar':tab==='ap'?item.direction==='ap':true),[invoices,tab]);
    const exportCsv=async()=>{if(!tenantId)return;try{downloadFinanceCsv(await exportFinanceLedger(tenantId,{direction:tab==='ar'?'ar':tab==='ap'?'ap':undefined,currency:currency||undefined}));}catch(cause){setError(cause instanceof Error?cause.message:'No fue posible exportar.');}};
    const toggleBulk=(id:string)=>setBulkIds((current)=>{const next=new Set(current);if(next.has(id))next.delete(id);else next.add(id);return next;}); const toggleAll=()=>setBulkIds((current)=>filtered.every((item)=>current.has(item.id))?new Set():new Set(filtered.map((item)=>item.id))); const selectedInvoices=filtered.filter((item)=>bulkIds.has(item.id));
    const exportSelected=async()=>{if(!tenantId||!selectedInvoices.length)return;const rows=selectedInvoices.map((item)=>({direction:item.direction,counterparty:item.counterparty_name,operation_reference:item.operation_reference??'',reference:item.reference??'',status:item.effective_status??item.status,due_date:item.due_date??'',currency:item.currency,amount:item.amount,paid_amount:item.paid_amount??0,balance_amount:item.balance_amount??item.amount}));downloadCsvContent(serializeCsv(rows),`finance-${tab}-seleccion-${new Date().toISOString().slice(0,10)}.csv`);await recordDataAction(tenantId,'export_requested',tab==='ar'?'finance_ar':'finance_ap',rows.length,'selected');};

    if(!canView)return <div className="space-y-6"><PageHeader title="ROTERO Finance 360" subtitle="Control financiero operativo"/><div className="rounded-2xl border border-amber-200 bg-amber-50 p-10 text-center"><ShieldAlert className="mx-auto text-amber-600"/><h2 className="mt-3 font-black text-slate-800">Acceso financiero restringido</h2><p className="mt-1 text-sm text-slate-500">Sólo Administración y Finanzas pueden consultar o modificar este módulo.</p></div></div>;

    return <div className="min-w-0 max-w-full space-y-4 sm:space-y-5"><PageHeader title="ROTERO Finance 360" subtitle="Operación → AR/AP → pagos → saldos → rentabilidad" actions={<SavedViewsMenu tenantId={tenantId} module="finance" filters={{view:tab,status,currency,search}} onApply={(filters)=>{if(typeof filters.view==='string'&&isTab(filters.view)){const next=new URLSearchParams(params);next.set('view',filters.view);next.delete('invoiceId');setParams(next,{replace:true});}setStatus(typeof filters.status==='string'?filters.status as InvoiceStatus:'');setCurrency(typeof filters.currency==='string'?filters.currency as FinanceCurrency:'');setSearch(typeof filters.search==='string'?filters.search:'');}}/>}/>
        <div className="min-w-0 rounded-2xl border bg-surface-card p-2 sm:p-4"><div className="flex min-w-0 flex-col gap-3 xl:flex-row xl:items-center xl:justify-between"><nav aria-label="Secciones de Finance" className="flex max-w-full gap-1 overflow-x-auto overscroll-x-contain pb-1 sm:flex-wrap sm:gap-2">{TABS.map((item)=><button key={item.value} onClick={()=>changeTab(item.value)} aria-pressed={tab===item.value} className={`min-h-11 shrink-0 rounded-xl px-3 text-xs font-bold sm:px-3.5 ${tab===item.value?'bg-primary text-white':'bg-surface text-slate-500 hover:text-primary'}`}>{item.label}</button>)}</nav><div className="flex gap-2 px-1 pb-1 sm:px-0 sm:pb-0"><button onClick={()=>void exportCsv()} className="inline-flex min-h-11 items-center gap-2 rounded-xl border px-3 text-xs font-bold text-slate-600"><Download size={14}/>CSV</button><button onClick={()=>void load()} aria-label="Actualizar Finance" className="inline-flex min-h-11 items-center gap-2 rounded-xl border px-3 text-xs font-bold text-slate-600"><RefreshCw size={14}/><span className="hidden sm:inline">Actualizar</span></button></div></div></div>
        <div className="rounded-xl border border-indigo-100 bg-indigo-50 px-4 py-3 text-xs text-indigo-800"><strong>Frontera fiscal:</strong> Finance registra cuentas, saldos y la preparación del complemento. Timbrado, cancelación fiscal y ejecución ante SAT continúan en Billing.</div>
        {error&&<div className="flex items-center gap-2 rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700"><AlertCircle size={17}/>{error}</div>}
        {(tab==='ar'||tab==='ap')&&<BulkActionBar count={bulkIds.size} onClear={()=>setBulkIds(new Set())} summary={['MXN','USD'].map((code)=>`${code} ${selectedInvoices.filter((item)=>item.currency===code).reduce((sum,item)=>sum+Number(item.balance_amount??item.amount),0).toLocaleString('es-MX',{minimumFractionDigits:2})}`).join(' · ')}><button onClick={()=>void exportSelected()} className="rounded-xl border px-3 py-2 text-xs font-bold">Exportar selección</button></BulkActionBar>}
        {!tenantId?<div className="rounded-2xl border bg-surface-card p-6 text-center text-sm text-slate-400 sm:p-12">Selecciona una organización activa.</div>:loading&&!overview?<div className="flex justify-center rounded-2xl border bg-surface-card p-12 sm:p-20"><Loader2 className="animate-spin text-primary"/></div>:<>
            {tab==='overview'&&overview&&<FinanceOverview overview={overview}/>}
            {tab==='ar'&&<ReceivablesWorkspace invoices={filtered} search={search} status={status} currency={currency} onSearch={setSearch} onStatus={setStatus} onCurrency={setCurrency} onOpen={(invoice)=>openById(invoice.id)} onPay={setPaying} onCreate={()=>setCreating('ar')} selectedIds={bulkIds} onToggleSelected={toggleBulk} onToggleAll={toggleAll}/>}
            {tab==='ap'&&<PayablesWorkspace invoices={filtered} search={search} status={status} currency={currency} onSearch={setSearch} onStatus={setStatus} onCurrency={setCurrency} onOpen={(invoice)=>openById(invoice.id)} onPay={setPaying} onCreate={()=>setCreating('ap')} selectedIds={bulkIds} onToggleSelected={toggleBulk} onToggleAll={toggleAll}/>}
            {tab==='payments'&&<PaymentActivity items={payments}/>}
            {tab==='due'&&<DueAlertsPanel items={alerts} daysAhead={daysAhead} onDaysAhead={setDaysAhead} onOpen={openById}/>}
            {tab==='profitability'&&<ProfitabilityWorkspace data={profitability}/>}
        </>}
        {tenantId&&<FinanceInvoiceDrawer tenantId={tenantId} invoice={selected} onClose={()=>{setSelected(null);const next=new URLSearchParams(params);next.delete('invoiceId');setParams(next,{replace:true});}} onPay={(invoice)=>{setSelected(null);setPaying(invoice);}} onChanged={()=>void load()}/>} {tenantId&&<PaymentDrawer tenantId={tenantId} invoice={paying} onClose={()=>setPaying(null)} onSaved={()=>{setPaying(null);void load();}}/>} {tenantId&&creating&&<InvoiceCreateModal tenantId={tenantId} direction={creating} operations={operations} partnerId={partnerId} partnerName={partnerName} suggestedTerms={suggestedTerms} onClose={()=>setCreating(null)} onSaved={()=>{setCreating(null);void load();}}/>}
    </div>;
}
