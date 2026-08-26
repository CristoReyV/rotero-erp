import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { Link, useSearchParams } from "react-router-dom";
import {
  Activity,
  Contact,
  Landmark,
  Loader2,
  Plus,
  Route,
  Wallet,
  X,
} from "lucide-react";
import {
  getCustomerPartner360,
  getProvider360,
  listPartnerHistoryPage,
  updatePartnerTerms,
  upsertBusinessContact,
} from "@/services/rates.service";
import type { BusinessContact, Partner360, PartnerHistoryKind, PartnerHistoryPage } from "@/types/rates";
import { PartnerCompliancePanel } from "@/components/commercial/PartnerCompliancePanel";
import { PartnerClaimsPanel } from "@/components/claims/PartnerClaimsPanel";
type Tab =
  | "summary"
  | "contacts"
  | "quotes"
  | "operations"
  | "finance"
  | "rates"
  | "performance"
  | "activity"
  | "compliance"
  | "contracts"
  | "claims";
const tabs: Record<"customer" | "provider", Array<[Tab, string]>> = {
  customer: [
    ["summary", "Resumen"],
    ["contacts", "Contactos"],
    ["quotes", "Cotizaciones"],
    ["operations", "Operaciones"],
    ["finance", "Finanzas"],
    ["rates", "Tarifas"],
    ["compliance", "Cumplimiento"],
    ["contracts", "Contratos"],
    ["claims", "Reclamaciones"],
    ["activity", "Actividad"],
  ],
  provider: [
    ["summary", "Resumen"],
    ["contacts", "Contactos"],
    ["rates", "Tarifas"],
    ["operations", "Operaciones"],
    ["finance", "Finanzas"],
    ["performance", "Desempeño"],
    ["compliance", "Cumplimiento"],
    ["contracts", "Contratos"],
    ["claims", "Reclamaciones"],
    ["activity", "Actividad"],
  ],
};
export function Partner360Panel({
  tenantId,
  entityType,
  entityId,
}: {
  tenantId: string;
  entityType: "customer" | "provider";
  entityId: string;
}) {
  const [params,setParams]=useSearchParams();
  const requestedTab=params.get("partnerTab") as Tab|null;
  const allowedTabs=tabs[entityType].map(([id])=>id);
  const [data, setData] = useState<Partner360 | null>(null),
    [tab, setTabState] = useState<Tab>(requestedTab&&allowedTabs.includes(requestedTab)?requestedTab:"summary"),
    [busy, setBusy] = useState(true),
    [error, setError] = useState(""),
    [contact, setContact] = useState(false),
    [histories,setHistories]=useState<Partial<Record<PartnerHistoryKind,PartnerHistoryPage>>>({}),
    [historyBusy,setHistoryBusy]=useState<PartnerHistoryKind|null>(null),
    [historyError,setHistoryError]=useState("");
  const requestId=useRef(0);
  const setTab=(nextTab:Tab)=>{setTabState(nextTab);const next=new URLSearchParams(params);next.set("partnerTab",nextTab);setParams(next,{replace:true});};
  const load = useCallback(async () => {
    const current=++requestId.current;
    setBusy(true);
    try {
      const next=
        entityType === "customer"
          ? await getCustomerPartner360(entityId)
          : await getProvider360(entityId);
      if(current!==requestId.current)return;
      setData(next);
      setHistories({});
      setError("");
    } catch (e) {
      if(current===requestId.current)setError(
        e instanceof Error ? e.message : "No fue posible cargar Partner 360",
      );
    } finally {
      if(current===requestId.current)setBusy(false);
    }
  }, [entityId, entityType]);
  useEffect(() => {
    void load();
  }, [load]);
  const historyType=(['quotes','operations','rates','activity'] as PartnerHistoryKind[]).includes(tab as PartnerHistoryKind)?tab as PartnerHistoryKind:null;
  const loadHistory=useCallback(async(kind:PartnerHistoryKind,more=false)=>{
    const current=histories[kind];setHistoryBusy(kind);setHistoryError("");
    try{const page=await listPartnerHistoryPage(tenantId,entityType,entityId,kind,more?current?.next_cursor??null:null);setHistories(value=>({...value,[kind]:more&&value[kind]?{...page,items:[...value[kind]!.items,...page.items]}:page}));}
    catch(cause){setHistoryError(cause instanceof Error?cause.message:"No fue posible cargar el historial.");}
    finally{setHistoryBusy(null);}
  },[entityId,entityType,histories,tenantId]);
  useEffect(()=>{if(historyType&&!histories[historyType])void loadHistory(historyType);},[histories,historyType,loadHistory]);
  if (busy)
    return (
      <div className="flex h-32 items-center justify-center">
        <Loader2 className="animate-spin text-primary" />
      </div>
    );
  if (error || !data)
    return (
      <div className="rounded-xl bg-red-50 p-3 text-sm text-red-700">
        {error}
      </div>
    );
  const entity =
    (entityType === "customer" ? data.customer : data.provider) ?? {};
  const days = Number(entity.payment_terms_days ?? 0);
  const partnerName = encodeURIComponent(String(entity.display_name ?? ""));
  return (
    <section className="space-y-4 rounded-2xl border bg-white p-5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-[10px] font-black uppercase text-primary">
            {entityType === "customer" ? "Customer" : "Provider"} 360
          </p>
          <h3 className="font-black">Relación comercial completa</h3>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link
            to={`/commercial?view=${entityType === "customer" ? "quotes" : "rates"}&action=${entityType === "customer" ? "new-quote" : "new-buy-rate"}&${entityType}Id=${entityId}`}
            className="rounded-lg border px-3 py-2 text-xs font-bold"
          >
            {entityType === "customer" ? "Nueva cotización" : "Nueva tarifa"}
          </Link>
          <Link
            to={`/finance?view=${entityType === "customer" ? "ar" : "ap"}&action=new&${entityType}Id=${entityId}&counterpartyName=${partnerName}&suggestedTerms=${days}`}
            className="rounded-lg border px-3 py-2 text-xs font-bold"
          >
            Nueva {entityType === "customer" ? "AR" : "AP"}
          </Link>
          <button
            onClick={() => setContact(true)}
            className="flex items-center gap-1 rounded-lg bg-primary px-3 py-2 text-xs font-bold text-white"
          >
            <Plus size={12} />
            Contacto
          </button>
        </div>
      </div>
      <nav className="flex gap-1 overflow-x-auto">
        {tabs[entityType].map(([id, label]) => (
          <button
            key={id}
            onClick={() => setTab(id)}
            className={`rounded-lg px-3 py-2 text-xs font-bold ${tab === id ? "bg-slate-900 text-white" : "bg-slate-50 text-slate-500"}`}
          >
            {label}
          </button>
        ))}
      </nav>
      {tab === "summary" && (
        <div className="grid gap-3 md:grid-cols-3">
          <Metric
            icon={Contact}
            label="Contactos"
            value={data.contacts.length}
          />
          <Metric
            icon={Route}
            label="Operaciones"
            value={data.history_counts?.operations??0}
          />
          <Metric
            icon={Wallet}
            label="Términos sugeridos"
            value={`${days} días`}
          />
          <label className="text-xs font-bold md:col-span-3">
            Actualizar términos de pago sugeridos
            <input
              type="number"
              min="0"
              max="365"
              defaultValue={days}
              onBlur={(e) =>
                void updatePartnerTerms(
                  tenantId,
                  entityType,
                  entityId,
                  Number(e.target.value),
                ).then(load)
              }
              className="ml-2 w-24 rounded-lg border p-2"
            />
          </label>
          <p className="text-xs text-slate-400 md:col-span-3">
            Estos términos sólo prefijan nuevas altas Finance; no modifican
            facturas existentes.
          </p>
        </div>
      )}
      {tab === "contacts" && (
        <List
          rows={data.contacts}
          empty="Sin contactos estructurados; se conservan los datos legacy como fallback."
        />
      )}
      {tab === "quotes" && (
        <PagedHistory page={histories.quotes} loading={historyBusy==='quotes'} error={historyError} empty="Sin cotizaciones." onMore={()=>void loadHistory('quotes',true)}/>
      )}
      {tab === "operations" && (
        <PagedHistory page={histories.operations} loading={historyBusy==='operations'} error={historyError} empty="Sin operaciones." onMore={()=>void loadHistory('operations',true)}/>
      )}
      {tab === "finance" && <CurrencyRows rows={data.finance} />}{" "}
      {tab === "rates" && <PagedHistory page={histories.rates} loading={historyBusy==='rates'} error={historyError} empty="Sin tarifas." onMore={()=>void loadHistory('rates',true)}/>}
      {tab === "performance" && (
        <pre className="overflow-x-auto rounded-xl bg-slate-50 p-3 text-xs">
          {JSON.stringify(data.performance ?? {}, null, 2)}
        </pre>
      )}
      {(tab === "compliance" || tab === "contracts") && (
        <PartnerCompliancePanel
          tenantId={tenantId}
          entityType={entityType}
          entityId={entityId}
          initialTab={tab}
        />
      )}
      {tab === "claims" && <PartnerClaimsPanel tenantId={tenantId} entityType={entityType} entityId={entityId} />}
      {tab === "activity" && (
        <PagedHistory page={histories.activity} loading={historyBusy==='activity'} error={historyError} empty="Sin actividad registrada." onMore={()=>void loadHistory('activity',true)}/>
      )}
      {contact && (
        <ContactModal
          tenantId={tenantId}
          entityType={entityType}
          entityId={entityId}
          onClose={() => setContact(false)}
          onSaved={async () => {
            setContact(false);
            await load();
          }}
        />
      )}
    </section>
  );
}
function Metric({
  icon: Icon,
  label,
  value,
}: {
  icon: typeof Activity;
  label: string;
  value: string | number;
}) {
  return (
    <div className="rounded-xl bg-slate-50 p-3">
      <Icon size={15} className="text-primary" />
      <p className="mt-2 text-xl font-black">{value}</p>
      <p className="text-[10px] uppercase text-slate-400">{label}</p>
    </div>
  );
}
function List({
  rows,
  empty,
}: {
  rows: Array<Record<string, unknown>|BusinessContact>;
  empty: string;
}) {
  if (!rows.length)
    return <p className="py-6 text-center text-sm text-slate-400">{empty}</p>;
  return (
    <div className="grid gap-2 md:grid-cols-2">
      {rows.slice(0, 50).map((source, i) => { const row=source as unknown as Record<string,unknown>; return (
        <div
          key={String(row.id ?? i)}
          className="rounded-xl border p-3 text-xs"
        >
          <b>
            {String(
              row.display_name ??
                row.name ??
                row.reference ??
                row.quote_reference ??
                row.reference_code ??
                row.action ??
                "Registro",
            )}
          </b>
          <p className="mt-1 text-slate-400">
            {String(
              row.status ??
                row.contact_role ??
                row.entity_type ??
                row.currency ??
                "",
            )}
          </p>
        </div>
      )})}
    </div>
  );
}
function PagedHistory({page,loading,error,empty,onMore}:{page?:PartnerHistoryPage;loading:boolean;error:string;empty:string;onMore:()=>void}){
  if(!page&&loading)return <div className="flex h-28 items-center justify-center"><Loader2 className="animate-spin text-primary"/></div>;
  return <div className="space-y-3">{error&&<p className="rounded-lg bg-red-50 p-3 text-xs text-red-700">{error}</p>}<List rows={page?.items??[]} empty={empty}/>{page?.has_more&&<div className="flex justify-center"><button type="button" disabled={loading} onClick={onMore} className="rounded-xl border px-4 py-2 text-xs font-bold disabled:opacity-50">{loading?'Cargando…':'Cargar más'}</button></div>}</div>;
}
function CurrencyRows({ rows }: { rows: Record<string, unknown>[] }) {
  if (!rows.length)
    return <p className="text-sm text-slate-400">Sin movimientos Finance.</p>;
  return (
    <div className="grid gap-3 md:grid-cols-2">
      {rows.map((r, i) => (
        <div key={String(r.currency ?? i)} className="rounded-xl border p-3">
          <div className="flex items-center gap-2 text-primary">
            <Landmark size={15} />
            <b>{String(r.currency)}</b>
          </div>
          {Object.entries(r)
            .filter(([k]) => k !== "currency")
            .map(([k, v]) => (
              <p key={k} className="mt-1 flex justify-between text-xs">
                <span>{k}</span>
                <b>{Number(v).toLocaleString("es-MX")}</b>
              </p>
            ))}
        </div>
      ))}
    </div>
  );
}
function ContactModal({
  tenantId,
  entityType,
  entityId,
  onClose,
  onSaved,
}: {
  tenantId: string;
  entityType: "customer" | "provider";
  entityId: string;
  onClose: () => void;
  onSaved: () => Promise<void>;
}) {
  const [form, setForm] = useState({
      name: "",
      contact_role: "commercial",
      email: "",
      phone: "",
      is_primary: false,
      notes: "",
    }),
    [busy, setBusy] = useState(false),[error,setError]=useState("");
  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError("");
    try{await upsertBusinessContact(tenantId, null, {...form,[`${entityType}_id`]: entityId});await onSaved();}
    catch(cause){setError(cause instanceof Error?cause.message:"No fue posible guardar el contacto.");setBusy(false);}
  };
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/45 p-4">
      <form
        onSubmit={submit}
        className="w-full max-w-lg rounded-2xl bg-white p-6"
      >
        <div className="flex justify-between">
          <h3 className="font-black">Nuevo contacto</h3>
          <button type="button" onClick={onClose} aria-label="Cerrar formulario de contacto">
            <X />
          </button>
        </div>
        {error&&<p className="mt-3 rounded-lg bg-red-50 p-2 text-xs text-red-700">{error}</p>}
        <div className="mt-4 grid gap-3 md:grid-cols-2">
          <Field
            label="Nombre *"
            value={form.name}
            onChange={(v) => setForm({ ...form, name: v })}
          />
          <label className="text-xs font-bold">
            Rol
            <select
              value={form.contact_role}
              onChange={(e) =>
                setForm({ ...form, contact_role: e.target.value })
              }
              className="mt-1 w-full rounded-xl border p-2.5"
            >
              <option value="commercial">Comercial</option>
              <option value="operations">Operaciones</option>
              <option value="billing">Facturación</option>
              <option value="management">Dirección</option>
              <option value="other">Otro</option>
            </select>
          </label>
          <Field
            label="Correo"
            value={form.email}
            onChange={(v) => setForm({ ...form, email: v })}
          />
          <Field
            label="Teléfono"
            value={form.phone}
            onChange={(v) => setForm({ ...form, phone: v })}
          />
          <label className="text-xs">
            <input
              type="checkbox"
              checked={form.is_primary}
              onChange={(e) =>
                setForm({ ...form, is_primary: e.target.checked })
              }
            />{" "}
            Contacto principal
          </label>
        </div>
        <button
          disabled={busy || !form.name}
          className="mt-5 w-full rounded-xl bg-primary p-3 text-sm font-black text-white"
        >
          {busy?'Guardando…':'Guardar contacto'}
        </button>
      </form>
    </div>
  );
}
function Field({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <label className="text-xs font-bold">
      {label}
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="mt-1 w-full rounded-xl border p-2.5"
      />
    </label>
  );
}
