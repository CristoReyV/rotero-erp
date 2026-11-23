import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { getTrackingErrorMessage, TrackingServiceError } from '@/services/trackingAdmin.service';
import {
    createOneTimeTrackingLink, getTrackingDisplayState, normalizeCreateResult, normalizeTrackingList,
    TRACKING_SCOPE_OPTIONS, type OneTimeTrackingLink, type TrackingScope, type TrackingTokenMetadata,
} from '@/services/trackingContracts';
import { useAuthStore } from '@/store/authStore';
import { hasCompanyCapability, scopedResponse, useCompanyStore } from '@/store/companyStore';

export function CompanyTrackingLinks({ operationId, onChange }: {
    operationId: string;
    onChange: () => Promise<void>;
}) {
    const tenant = useAuthStore((state) => state.activeTenant);
    const role = useAuthStore((state) => state.getRole());
    const mode = useCompanyStore((state) => state.mode);
    const allowed = mode === 'company' && (role === 'admin' || role === 'operator')
        && hasCompanyCapability('operations.read') && hasCompanyCapability('tracking.manage');
    const [links, setLinks] = useState<TrackingTokenMetadata[]>([]);
    const [revealed, setRevealed] = useState<OneTimeTrackingLink | null>(null);
    const [status, setStatus] = useState('');
    const [error, setError] = useState('');
    const [ready, setReady] = useState(false);
    const [working, setWorking] = useState(false);
    const locked = useRef(false);
    const loadSequence = useRef(0);

    const load = useCallback(async () => {
        if (!tenant || !allowed) return;
        const sequence = ++loadSequence.current;
        try {
            const result = await scopedResponse(async () => {
                const { data, error: failure } = await supabase.rpc('rpc_delivery_tracking_links', {
                    p_tenant_id: tenant, p_operation_id: operationId,
                });
                if (failure || data?.error) throw new Error('tracking_unavailable');
                return normalizeTrackingList(data);
            });
            if (sequence === loadSequence.current) {
                setLinks(result);
                setReady(true);
            }
        } catch {
            if (sequence === loadSequence.current) {
                setLinks([]);
                setRevealed(null);
                setReady(false);
                setError('El servicio de enlaces no está disponible para esta operación.');
            }
        }
    }, [tenant, allowed, operationId]);

    useEffect(() => {
        void load();
        return () => { loadSequence.current++; };
    }, [load]);

    const change = async (scope: TrackingScope, action: 'issue' | 'rotate' | 'revoke', expected?: string) => {
        if (!tenant || !allowed || !ready || locked.current) return;
        if (action !== 'issue' && !window.confirm('El enlace actual dejará de funcionar. ¿Continuar?')) return;
        locked.current = true;
        setWorking(true);
        setError('');
        setStatus('');
        setRevealed(null);
        try {
            const data = await scopedResponse(async () => {
                const { data: result, error: failure } = await supabase.rpc('rpc_delivery_tracking_action', {
                    p_tenant_id: tenant,
                    p_operation_id: operationId,
                    p_scope: scope,
                    p_ttl_hours: TRACKING_SCOPE_OPTIONS.find((option) => option.value === scope)?.defaultTtlHours,
                    p_action: action,
                    p_expected_token_id: expected ?? null,
                });
                if (failure || result?.error) {
                    if (result?.error === 'assignment_required') throw new Error('Asigna el proveedor y confirma la salida planeada antes de crear el enlace del chofer.');
                    if (result?.error === 'operation_inactive') throw new Error('El estado de la operación impide emitir un enlace nuevo.');
                    if (result?.error === 'conflict') throw new TrackingServiceError('conflict');
                    throw new TrackingServiceError('invalid_response');
                }
                return result;
            });
            if (action === 'revoke') {
                if (data?.success !== true) throw new TrackingServiceError('invalid_response');
                setStatus('Enlace revocado.');
            } else {
                const result = normalizeCreateResult(data);
                setRevealed(createOneTimeTrackingLink(result, window.location.origin));
                setStatus(result.kind === 'created'
                    ? 'Copia el enlace ahora. El enlace no vuelve a mostrarse.'
                    : 'Ya existe un enlace vigente. Rótalo si no conservas la dirección.');
            }
            await onChange();
        } catch (cause) {
            setError(cause instanceof TrackingServiceError
                ? getTrackingErrorMessage(cause)
                : cause instanceof Error && /^(Asigna |El estado )/.test(cause.message)
                    ? cause.message
                    : 'Verifica los enlaces vigentes antes de repetir la acción.');
        } finally {
            await load();
            setWorking(false);
            locked.current = false;
        }
    };

    if (!allowed) return null;
    return (
        <section aria-label="Enlaces de Tracking" className="space-y-3 rounded-xl border p-4">
            <h3 className="font-bold">Enlaces de Tracking</h3>
            {error && <p role="alert" className="text-sm text-red-700">{error}</p>}
            {status && <p role="status" className="text-sm">{status}</p>}
            {!ready && <button type="button" onClick={() => void load()} className="text-sm text-primary underline">Consultar enlaces</button>}
            {ready && TRACKING_SCOPE_OPTIONS.map(({ value, label }) => {
                const active = links.find((link) => link.scope === value && getTrackingDisplayState(link) === 'active');
                const last = links.find((link) => link.scope === value);
                return (
                    <div key={value} className="flex flex-wrap items-center justify-between gap-2">
                        <div>
                            <p className="text-sm font-semibold">{label}</p>
                            <p className="text-xs text-slate-600">
                                {active?.expiresAt ? 'Vigente hasta ' + new Date(active.expiresAt).toLocaleString('es-MX')
                                    : last && getTrackingDisplayState(last) === 'revoked' ? 'Último enlace revocado'
                                    : last ? 'Último enlace vencido' : 'Sin enlace'}
                            </p>
                        </div>
                        <div className="flex flex-wrap gap-3 text-sm text-primary">
                            {active ? <>
                                <button type="button" disabled={working} onClick={() => void change(value, 'rotate', active.id)}>Rotar</button>
                                <button type="button" disabled={working} onClick={() => void change(value, 'revoke', active.id)}>Revocar</button>
                            </> : (
                                <button type="button" disabled={working} onClick={() => void change(value, 'issue')}>Generar enlace</button>
                            )}
                        </div>
                    </div>
                );
            })}
            {revealed && (
                <div className="space-y-2">
                    <input aria-label="Enlace recién generado" readOnly value={revealed.link}
                        onFocus={(event) => event.currentTarget.select()} className="w-full rounded border p-2 text-sm" />
                    <button type="button" className="text-sm text-primary underline" onClick={() => setRevealed(null)}>Ocultar enlace</button>
                </div>
            )}
        </section>
    );
}
