import { useCallback, useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { Activity, Bot, CheckCircle2, Clock3, Loader2, Play, Save, ShieldCheck } from 'lucide-react';
import {
    evaluateAutomations,
    getAutomationHealth,
    listAutomationRules,
    updateAutomationRule,
} from '@/services/automation.service';
import { useAuthStore } from '@/store/authStore';
import type {
    AutomationEvaluation,
    AutomationHealth,
    AutomationRule,
    AutomationRuleUpdate,
} from '@/types/automation';

const severityOptions = [
    { value: 'low', label: 'Baja' },
    { value: 'medium', label: 'Media' },
    { value: 'high', label: 'Alta' },
    { value: 'critical', label: 'Crítica' },
] as const;
const unitOptions = [
    { value: 'hours', label: 'horas' },
    { value: 'days', label: 'días' },
] as const;
const roleLabels = { admin: 'Solo Admin', finance: 'Solo Finance', admin_finance: 'Admin + Finance' };

export default function AutomationsPage() {
    const tenantId = useAuthStore(state => state.activeTenant);
    const [rules, setRules] = useState<AutomationRule[]>([]);
    const [health, setHealth] = useState<AutomationHealth | null>(null);
    const [evaluation, setEvaluation] = useState<AutomationEvaluation | null>(null);
    const [loading, setLoading] = useState(true);
    const [running, setRunning] = useState(false);
    const [savingId, setSavingId] = useState<string | null>(null);
    const [error, setError] = useState<string | null>(null);

    const load = useCallback(async () => {
        if (!tenantId) return;
        setLoading(true);
        setError(null);
        try {
            const [nextRules, nextHealth] = await Promise.all([
                listAutomationRules(tenantId),
                getAutomationHealth(tenantId),
            ]);
            setRules(nextRules);
            setHealth(nextHealth);
        } catch (cause) {
            setError(cause instanceof Error ? cause.message : 'No fue posible cargar automatizaciones.');
        } finally {
            setLoading(false);
        }
    }, [tenantId]);

    useEffect(() => { void load(); }, [load]);
    const change = <K extends keyof AutomationRule>(id: string, key: K, value: AutomationRule[K]) => {
        setRules(current => current.map(rule => rule.id === id ? { ...rule, [key]: value } : rule));
    };
    const save = async (rule: AutomationRule) => {
        if (!tenantId) return;
        setSavingId(rule.id);
        setError(null);
        const payload: AutomationRuleUpdate = {
            is_enabled: rule.is_enabled,
            target_role: rule.target_role,
            severity: rule.severity,
            threshold_value: rule.threshold_value,
            threshold_unit: rule.threshold_unit,
            escalation_delay_value: rule.escalation_delay_value,
            escalation_delay_unit: rule.escalation_delay_unit,
            escalation_severity: rule.escalation_severity,
            digest_enabled: rule.digest_enabled,
        };
        try {
            await updateAutomationRule(tenantId, rule.id, payload);
            await load();
        } catch (cause) {
            setError(cause instanceof Error ? cause.message : 'No fue posible guardar la regla.');
        } finally {
            setSavingId(null);
        }
    };
    const evaluate = async () => {
        if (!tenantId) return;
        setRunning(true);
        setError(null);
        try {
            setEvaluation(await evaluateAutomations(tenantId));
            await load();
        } catch (cause) {
            setError(cause instanceof Error ? cause.message : 'No fue posible evaluar automatizaciones.');
        } finally {
            setRunning(false);
        }
    };

    if (!tenantId) return <Empty text="Selecciona una organización activa." />;
    if (loading && !health) return <Empty text="Cargando automatizaciones…" loading />;
    return <div className="space-y-5">
        <header className="flex flex-col gap-4 xl:flex-row xl:items-end xl:justify-between">
            <div>
                <p className="text-xs font-black uppercase tracking-[.22em] text-primary">Productividad proactiva</p>
                <h2 className="mt-1 flex items-center gap-2 text-2xl font-black text-slate-900"><Bot size={23} /> Automatizaciones</h2>
                <p className="mt-1 text-sm text-slate-500">Configura umbrales seguros; el motor solo observa, notifica y resuelve alertas.</p>
            </div>
            <button onClick={() => void evaluate()} disabled={running} className="flex items-center justify-center gap-2 rounded-xl bg-primary px-5 py-3 text-xs font-black text-white disabled:opacity-50">
                {running ? <Loader2 size={16} className="animate-spin" /> : <Play size={16} />} Evaluar ahora
            </button>
        </header>
        {error && <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div>}
        <div className="grid gap-4 md:grid-cols-3">
            <HealthCard icon={ShieldCheck} label="Scheduler" value={health?.scheduler_enabled ? 'Contrato listo' : 'Pendiente de activar en release'} detail={health?.jobs.map(job => job.schedule).join(' · ') || 'Sin jobs activos'} />
            <HealthCard icon={Activity} label="Reglas habilitadas" value={String(health?.rules_enabled ?? 0)} detail={health?.last_automation_run ? 'Última evaluación: ' + formatDate(health.last_automation_run.completed_at ?? health.last_automation_run.started_at) : 'Sin ejecuciones registradas'} />
            <HealthCard icon={Clock3} label="Digest diario" value={health?.last_digest_run?.status === 'completed' ? 'Generado' : 'Pendiente'} detail={health?.last_digest_run ? formatDate(health.last_digest_run.completed_at ?? health.last_digest_run.started_at) : 'Se genera una vez por día local'} />
        </div>
        {evaluation && <div className="rounded-2xl border border-emerald-200 bg-emerald-50 p-4">
            <p className="flex items-center gap-2 text-sm font-black text-emerald-800"><CheckCircle2 size={16} /> Evaluación completada</p>
            <p className="mt-1 text-xs text-emerald-700">{evaluation.rules_evaluated} reglas · {evaluation.candidates} candidatos · {evaluation.created} nuevas · {evaluation.updated} actualizadas · {evaluation.resolved} resueltas · {evaluation.escalated} escaladas</p>
        </div>}
        <div className="space-y-4">
            {rules.map(rule => <RuleCard key={rule.id} rule={rule} saving={savingId === rule.id} onChange={change} onSave={save} />)}
        </div>
    </div>;
}

function RuleCard({ rule, saving, onChange, onSave }: {
    key?: string;
    rule: AutomationRule;
    saving: boolean;
    onChange: <K extends keyof AutomationRule>(id: string, key: K, value: AutomationRule[K]) => void;
    onSave: (rule: AutomationRule) => Promise<void>;
}) {
    const roleLocked = rule.module === 'commercial' || rule.module === 'finance';
    return <section className="rounded-2xl border bg-white p-5 shadow-sm">
        <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
            <div>
                <div className="flex items-center gap-2"><span className="rounded-md bg-primary-50 px-2 py-1 text-[9px] font-black uppercase text-primary">{rule.module}</span><code className="text-[10px] text-slate-400">{rule.code}</code></div>
                <h3 className="mt-2 text-sm font-black text-slate-800">{rule.name}</h3>
            </div>
            <label className="flex items-center gap-2 text-xs font-bold text-slate-600">
                <input type="checkbox" checked={rule.is_enabled} onChange={event => onChange(rule.id, 'is_enabled', event.target.checked)} className="h-4 w-4 accent-primary" />
                {rule.is_enabled ? 'Activa' : 'Inactiva'}
            </label>
        </div>
        <div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
            <Field label="Umbral"><div className="flex gap-2"><NumberInput value={rule.threshold_value} onChange={value => onChange(rule.id, 'threshold_value', value)} /><Select value={rule.threshold_unit} options={unitOptions} onChange={value => onChange(rule.id, 'threshold_unit', value as AutomationRule['threshold_unit'])} /></div></Field>
            <Field label="Severidad"><Select value={rule.severity} options={severityOptions} onChange={value => onChange(rule.id, 'severity', value as AutomationRule['severity'])} /></Field>
            <Field label="Escalar después"><div className="flex gap-2"><NumberInput value={rule.escalation_delay_value} onChange={value => onChange(rule.id, 'escalation_delay_value', value)} /><Select value={rule.escalation_delay_unit} options={unitOptions} onChange={value => onChange(rule.id, 'escalation_delay_unit', value as AutomationRule['escalation_delay_unit'])} /></div></Field>
            <Field label="Escalar a"><Select value={rule.escalation_severity} options={severityOptions} onChange={value => onChange(rule.id, 'escalation_severity', value as AutomationRule['escalation_severity'])} /></Field>
            <Field label="Destinatarios"><Select disabled={roleLocked} value={rule.target_role} options={Object.entries(roleLabels).map(([value, label]) => ({ value, label }))} onChange={value => onChange(rule.id, 'target_role', value as AutomationRule['target_role'])} /></Field>
        </div>
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t pt-4">
            <label className="flex items-center gap-2 text-xs font-bold text-slate-600"><input type="checkbox" checked={rule.digest_enabled} onChange={event => onChange(rule.id, 'digest_enabled', event.target.checked)} className="h-4 w-4 accent-primary" /> Incluir en resumen diario</label>
            <button onClick={() => void onSave(rule)} disabled={saving} className="flex items-center gap-2 rounded-xl border px-4 py-2 text-xs font-black text-slate-600 hover:border-primary hover:text-primary disabled:opacity-50">{saving ? <Loader2 size={14} className="animate-spin" /> : <Save size={14} />} Guardar regla</button>
        </div>
    </section>;
}

function HealthCard({ icon: Icon, label, value, detail }: { icon: typeof Activity; label: string; value: string; detail: string }) {
    return <div className="rounded-2xl border bg-white p-4"><p className="flex items-center gap-2 text-[10px] font-black uppercase text-slate-400"><Icon size={14} /> {label}</p><p className="mt-2 text-lg font-black text-slate-800">{value}</p><p className="mt-1 text-[11px] text-slate-400">{detail}</p></div>;
}
function Field({ label, children }: { label: string; children: ReactNode }) { return <label className="space-y-1.5"><span className="text-[10px] font-black uppercase text-slate-400">{label}</span>{children}</label>; }
function NumberInput({ value, onChange }: { value: number; onChange: (value: number) => void }) { return <input type="number" min={0} max={3650} value={value} onChange={event => onChange(Math.max(0, Number(event.target.value) || 0))} className="min-w-0 flex-1 rounded-xl border px-3 py-2 text-xs outline-none focus:border-primary" />; }
function Select({ value, options, onChange, disabled = false }: { value: string; options: ReadonlyArray<{ value: string; label: string }>; onChange: (value: string) => void; disabled?: boolean }) { return <select value={value} disabled={disabled} onChange={event => onChange(event.target.value)} className="min-w-0 flex-1 rounded-xl border bg-white px-3 py-2 text-xs outline-none focus:border-primary disabled:bg-slate-50 disabled:text-slate-400">{options.map(option => <option key={option.value} value={option.value}>{option.label}</option>)}</select>; }
function Empty({ text, loading = false }: { text: string; loading?: boolean }) { return <div className="flex min-h-[40vh] items-center justify-center gap-3 rounded-2xl border bg-white text-sm text-slate-400">{loading && <Loader2 className="animate-spin" size={18} />}{text}</div>; }
function formatDate(value: string) { return new Date(value).toLocaleString('es-MX'); }
