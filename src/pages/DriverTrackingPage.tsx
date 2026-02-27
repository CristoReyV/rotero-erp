import React, { useState, useEffect, useCallback } from 'react';
import { useParams } from 'react-router-dom';
import { Truck, MapPin, CheckCircle, AlertTriangle, Shield, Clock, AlertCircle, RefreshCw, X, Search, WifiOff, UploadCloud } from 'lucide-react';
import { fetchDriverView, postDriverEvent } from '@/services/trackingEdge.service';
import type { DriverView, DriverEventPayload, GeoPoint } from '@/types/tracking';
import { DRIVER_ANTI_NOISE, DRIVER_ORDER_STATES, INCIDENT_TYPES } from '@/types/tracking';

// --- Offline Queue Helpers ---
const getQueueKey = (token: string) => `rotero_driver_queue_${token}`;

interface QueuedEvent {
    id: string;
    payload: DriverEventPayload;
    queuedAt: string;
    retries: number;
}

const getOfflineQueue = (token: string): QueuedEvent[] => {
    try {
        const q = localStorage.getItem(getQueueKey(token));
        return q ? JSON.parse(q) : [];
    } catch {
        return [];
    }
};

const saveOfflineQueue = (token: string, queue: QueuedEvent[]) => {
    localStorage.setItem(getQueueKey(token), JSON.stringify(queue));
};

const enqueueEvent = (token: string, payload: DriverEventPayload) => {
    let queue = getOfflineQueue(token);
    if (queue.length >= DRIVER_ANTI_NOISE.offlineQueueMax) {
        alert("Demasiados pendientes. Espera a tener señal.");
        return false;
    }
    queue.push({
        id: 'offline-' + Date.now(),
        payload,
        queuedAt: new Date().toISOString(),
        retries: 0
    });
    saveOfflineQueue(token, queue);
    return true;
};

// --- Modals ---

const ActionConfirmModal = ({
    action,
    onClose,
    onConfirm
}: {
    action: DriverEventPayload['action'],
    onClose: () => void,
    onConfirm: (loc?: DriverEventPayload['location']) => void
}) => {
    const [geoStatus, setGeoStatus] = useState<'idle' | 'loading' | 'error'>('idle');

    const actionLabel = action === 'departure' ? 'Iniciar Ruta'
        : action === 'arrival' ? 'Llegué al Destino'
            : action === 'delivered' ? 'Entregado'
                : 'En camino';

    const getGPSAndConfirm = useCallback(() => {
        setGeoStatus('loading');
        if (!('geolocation' in navigator)) {
            setGeoStatus('error');
            return;
        }

        navigator.geolocation.getCurrentPosition(
            (pos) => {
                const loc = { lat: pos.coords.latitude, lng: pos.coords.longitude, accuracy: pos.coords.accuracy };
                if (loc.accuracy && loc.accuracy > DRIVER_ANTI_NOISE.minAccuracyMeters) {
                    setGeoStatus('error');
                } else {
                    onConfirm({ ...loc, source: 'gps' });
                }
            },
            () => {
                setGeoStatus('error');
            },
            { timeout: DRIVER_ANTI_NOISE.gpsTimeoutMs, enableHighAccuracy: true }
        );
    }, [onConfirm]);

    useEffect(() => {
        getGPSAndConfirm();
    }, [getGPSAndConfirm]);

    return (
        <div className="fixed inset-0 bg-slate-900/60 flex flex-col items-center justify-end sm:justify-center p-0 sm:p-4 z-[60] animate-in fade-in duration-200">
            <div className="bg-white rounded-t-3xl sm:rounded-3xl w-full max-w-sm overflow-hidden shadow-2xl animate-in slide-in-from-bottom-4 sm:slide-in-from-bottom-8 duration-300 pb-8 sm:pb-0">
                <div className="p-3 pl-5 pr-3 border-b border-slate-100 flex justify-between items-center bg-slate-50">
                    <h3 className="font-bold text-slate-800 text-lg">Reportar Estatus</h3>
                    <button onClick={onClose} className="p-3 text-slate-400 hover:text-slate-600 rounded-full hover:bg-slate-100"><X size={20} /></button>
                </div>
                <div className="p-6">
                    <div className="bg-slate-50 p-4 rounded-2xl flex items-center justify-center gap-3 font-bold text-xl text-slate-800 mb-6 border border-slate-100">
                        {action === 'departure' && <Truck className="text-blue-600" size={28} />}
                        {action === 'arrival' && <MapPin className="text-rose-500" size={28} />}
                        {action === 'delivered' && <CheckCircle className="text-emerald-500" size={28} />}
                        {action === 'in_transit' && <Truck className="text-blue-600" size={28} />}
                        {actionLabel}
                    </div>

                    <div className="flex flex-col gap-3">
                        <button
                            onClick={getGPSAndConfirm}
                            disabled={geoStatus === 'loading'}
                            className="w-full py-4 bg-blue-600 text-white font-bold rounded-2xl flex items-center justify-center gap-2 active:bg-blue-700 disabled:opacity-50 shadow-md shadow-blue-600/20"
                        >
                            {geoStatus === 'loading' ? <RefreshCw className="animate-spin" size={20} /> : <MapPin size={20} />}
                            {geoStatus === 'loading' ? 'Obteniendo ubicación precisa...' : 'Reintentar GPS'}
                        </button>

                        {geoStatus === 'error' && (
                            <p className="text-xs text-rose-500 text-center font-semibold bg-rose-50 p-3 rounded-lg border border-rose-100">No se pudo obtener la ubicación GPS precisa. Revisa los permisos e intenta de nuevo.</p>
                        )}

                        <div className="flex items-center gap-4 my-3">
                            <div className="h-px bg-slate-200 flex-1"></div>
                            <span className="text-[10px] font-bold tracking-widest text-slate-400 uppercase">o también</span>
                            <div className="h-px bg-slate-200 flex-1"></div>
                        </div>

                        <button
                            onClick={() => onConfirm(undefined)}
                            className="w-full py-4 bg-white border-2 border-slate-200 text-slate-600 font-bold rounded-2xl active:bg-slate-50 hover:border-slate-300"
                        >
                            En equipo sin GPS (Fallback)
                        </button>
                    </div>
                </div>
            </div>
        </div>
    );
};

const IncidentModal = ({ onClose, onConfirm }: { onClose: () => void, onConfirm: (type: string, note: string) => void }) => {
    const [type, setType] = useState<keyof typeof INCIDENT_TYPES>('other');
    const [note, setNote] = useState('');

    return (
        <div className="fixed inset-0 bg-slate-900/50 flex items-end sm:items-center justify-center p-4 z-50 animate-in fade-in duration-200">
            <div className="bg-white rounded-3xl w-full max-w-sm overflow-hidden shadow-2xl animate-in slide-in-from-bottom-4 duration-300">
                <div className="p-3 pl-5 pr-3 border-b border-rose-100 flex justify-between items-center bg-rose-50">
                    <h3 className="font-bold text-rose-800 flex items-center gap-2"><AlertCircle size={20} /> Reportar Incidencia</h3>
                    <button onClick={onClose} className="text-rose-400 p-3 rounded-full hover:bg-rose-100/50"><X size={20} /></button>
                </div>
                <div className="p-6">
                    <p className="text-sm font-medium text-slate-500 mb-2">Tipo de incidencia:</p>
                    <select value={type} onChange={e => setType(e.target.value as any)} className="w-full bg-slate-50 border border-slate-200 rounded-xl p-3 text-slate-700 font-semibold mb-4 focus:ring-2 focus:ring-rose-200 outline-none appearance-none">
                        {Object.entries(INCIDENT_TYPES).map(([k, v]) => (
                            <option key={k} value={k}>{v.label}</option>
                        ))}
                    </select>

                    <p className="text-sm font-medium text-slate-500 mb-2">Nota (opcional):</p>
                    <textarea
                        value={note}
                        onChange={e => setNote(e.target.value)}
                        maxLength={280}
                        placeholder="Detalles sobre el retraso o situación..."
                        className="w-full bg-slate-50 border border-slate-200 rounded-xl p-3 text-slate-700 font-medium h-24 resize-none mb-6 focus:ring-2 focus:ring-rose-200 outline-none"
                    ></textarea>

                    <div className="flex gap-3">
                        <button onClick={onClose} className="flex-1 py-3.5 bg-white border border-slate-200 text-slate-600 font-bold rounded-xl">Cancelar</button>
                        <button onClick={() => onConfirm(type, note)} className="flex-1 py-3.5 bg-rose-600 text-white font-bold rounded-xl active:bg-rose-700">Enviar Reporte</button>
                    </div>
                </div>
            </div>
        </div>
    );
};

// --- Page Component ---

export default function DriverTrackingPage() {
    const { token } = useParams<{ token: string }>();
    const [status, setStatus] = useState<'loading' | 'success' | 'expired' | 'revoked' | 'not_found'>('loading');
    const [data, setData] = useState<DriverView | null>(null);
    const [actionLoading, setActionLoading] = useState<string | null>(null);

    const [activeModal, setActiveModal] = useState<'confirm' | 'incident' | null>(null);
    const [selectedAction, setSelectedAction] = useState<DriverEventPayload['action'] | null>(null);

    const [isOffline, setIsOffline] = useState(!navigator.onLine);
    const [queueSize, setQueueSize] = useState(0);
    const [showSuccessToast, setShowSuccessToast] = useState(false);

    const loadData = useCallback(async () => {
        if (!navigator.onLine && !data) {
            setStatus('not_found'); // offline with no cached data
            return;
        }
        const result = await fetchDriverView(token || '');
        if (!result.ok) {
            // network / timeout error: keep last loaded data if we have it
            if (!data) setStatus('not_found');
            return;
        }
        const response = result.data;
        setStatus(response.status);
        if (response.data) setData(response.data);
        setQueueSize(getOfflineQueue(token || '').length);
    }, [token, data]);

    const syncQueue = useCallback(async () => {
        if (!navigator.onLine || !token) return;
        let queue = getOfflineQueue(token);
        if (queue.length === 0) return;

        const remaining: typeof queue = [];

        for (const qe of queue) {
            const result = await postDriverEvent(qe.payload);
            if (!result.ok) {
                // network error — keep in queue
                qe.retries += 1;
                if (qe.retries < DRIVER_ANTI_NOISE.offlineMaxRetries) {
                    remaining.push(qe);
                }
            } else {
                const { data } = result;
                if (data.http === 403) {
                    // token revoked/expired — clear entire queue, no more retries
                    saveOfflineQueue(token, []);
                    setQueueSize(0);
                    setStatus('revoked');
                    return;
                }
                // accepted (200/201) or rejected by business rule (422): drop from queue
            }
        }

        saveOfflineQueue(token, remaining);
        setQueueSize(remaining.length);
        if (remaining.length === 0) {
            loadData(); // refresh fully when sync finishes
        }
    }, [token, loadData]);

    useEffect(() => {
        loadData();

        const handleOnline = () => { setIsOffline(false); syncQueue(); };
        const handleOffline = () => setIsOffline(true);

        window.addEventListener('online', handleOnline);
        window.addEventListener('offline', handleOffline);
        return () => {
            window.removeEventListener('online', handleOnline);
            window.removeEventListener('offline', handleOffline);
        };
    }, [loadData, syncQueue]);

    const submitEvent = async (payloadDetails: Partial<DriverEventPayload>) => {
        if (!token) return;
        const payload: DriverEventPayload = {
            ...payloadDetails,
            driverToken: token,
            action: selectedAction || payloadDetails.action!,
            clientTimestamp: new Date().toISOString()
        };

        setActiveModal(null);
        setSelectedAction(null);
        setActionLoading(payload.action);

        if (!navigator.onLine) {
            enqueueEvent(token, payload);
            setQueueSize(getOfflineQueue(token).length);

            // Optimistic Update
            if (data && payload.action !== 'incident') {
                const nextStatus = payload.action === 'departure' ? 'in_transit' : payload.action === 'arrival' ? 'at_destination' : payload.action === 'delivered' ? 'delivered' : data.currentStatus;
                setData({ ...data, currentStatus: nextStatus as any });
            }
            setActionLoading(null);
            setShowSuccessToast(true);
            setTimeout(() => setShowSuccessToast(false), 2500);
            return;
        }

        try {
            const result = await postDriverEvent(payload);
            if (!result.ok) {
                // network / timeout — event already queued offline would have been handled above
                // For online failures, optionally enqueue or alert
                alert('Error de conexión al enviar el evento. Intenta de nuevo.');
                setActionLoading(null);
                return;
            }
            const res = result.data;
            if (res.http === 403) {
                // token was revoked/expired while driver was active
                saveOfflineQueue(token, []);
                setQueueSize(0);
                setStatus('revoked');
                setActionLoading(null);
                return;
            }
            if (!res.accepted && res.reason) {
                alert(`Evento no registrado: ${res.reason === 'same_municipality' ? 'Mismo municipio que el evento anterior.' :
                    res.reason === 'cooldown' ? 'Espera un momento antes de enviar otro evento.' :
                        res.reason
                    }`);
            }
            await loadData();
            setShowSuccessToast(true);
            setTimeout(() => setShowSuccessToast(false), 2500);
        } finally {
            setActionLoading(null);
        }
    };

    if (status === 'loading') {
        return (
            <div className="flex flex-col w-full h-screen bg-slate-50 items-center justify-center font-sans px-4">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-slate-600 mb-4"></div>
                <p className="text-sm font-medium text-slate-500">Cargando...</p>
            </div>
        );
    }

    if (status === 'not_found' || status === 'revoked' || status === 'expired') {
        const errConfig = {
            not_found: { i: <AlertTriangle size={48} className="text-slate-300" />, t: "Enlace no encontrado", d: "El operador no existe o es inválido." },
            revoked: { i: <Shield size={48} className="text-red-400" />, t: "Enlace Desactivado", d: "Fue desactivado por el operador." },
            expired: { i: <Clock size={48} className="text-slate-300" />, t: "Acceso Terminado", d: "Tu acceso ha terminado." }
        }[status];
        return (
            <div className="flex flex-col w-full h-[100dvh] bg-slate-50 items-center justify-center font-sans px-4">
                <div className="mb-4 mx-auto">{errConfig?.i}</div>
                <h2 className="text-xl font-bold text-slate-700 mb-2">{errConfig?.t}</h2>
                <p className="text-sm font-medium text-slate-500 text-center max-w-sm">{errConfig?.d}</p>
            </div>
        );
    }

    if (!data) return null;

    const { currentStatus } = data;

    return (
        <div className="flex flex-col w-full min-h-[100dvh] bg-[#F1F5F9] font-sans pb-10">
            {/* Cabecera PWA */}
            <div className="bg-slate-900 px-5 py-3 flex justify-center items-center relative">
                <p className="text-white font-semibold text-xs tracking-wider uppercase flex items-center gap-2"><Truck size={14} /> Rotero • Operación</p>
            </div>

            {/* Optimistic Toast */}
            {showSuccessToast && (
                <div className="fixed top-4 left-1/2 -translate-x-1/2 z-[100] bg-emerald-600 text-white px-5 py-3 rounded-full shadow-lg font-bold text-sm flex items-center gap-2 animate-in slide-in-from-top-4 fade-in duration-300">
                    <CheckCircle size={18} /> Acción registrada
                </div>
            )}

            {/* Offline Banner */}
            {isOffline && (
                <div className="bg-amber-100 px-4 py-2 flex items-center justify-center gap-2 text-amber-800 text-xs font-bold border-b border-amber-200">
                    <WifiOff size={14} /> Sin conexión. Los cambios se guardarán.
                </div>
            )}
            {!isOffline && queueSize > 0 && (
                <div className="bg-blue-100 px-4 py-2 flex items-center justify-center gap-2 text-blue-800 text-xs font-bold border-b border-blue-200">
                    <UploadCloud size={14} className="animate-pulse" /> Sincronizando {queueSize} pendientes...
                </div>
            )}

            {/* Resumen */}
            <div className="bg-white p-5 rounded-b-3xl shadow-[0_4px_20px_-10px_rgba(0,0,0,0.1)] mb-6 z-10 relative">
                <div className="flex items-center justify-between mb-2">
                    <span className="text-xs font-bold tracking-wider text-slate-400 uppercase">Orden</span>
                    {data.eta && <span className="text-xs font-bold tracking-wider text-slate-500 bg-slate-100 px-2 py-1 rounded-md">ETA: {data.eta}</span>}
                </div>
                <h1 className="text-3xl font-black text-slate-800 tracking-tight leading-none mb-2">{data.orderRef}</h1>
                <p className="text-sm text-slate-500 font-semibold mb-5 flex items-center gap-1.5"><MapPin size={16} className="text-slate-400" /> {data.route}</p>

                <div className="bg-[#F8FAFC] p-4 rounded-2xl border border-slate-100 flex items-center justify-between shadow-inner">
                    <div className="flex-1">
                        <p className="text-[10px] uppercase font-bold tracking-wider text-slate-400 mb-1">Cliente</p>
                        <p className="text-sm font-bold text-slate-700 bg-white inline-block px-2.5 py-1 rounded-lg border border-slate-200">{data.clientName}</p>
                    </div>
                    <div className="w-px h-10 bg-slate-200 mx-3"></div>
                    <div className="flex-1 text-right">
                        <p className="text-[10px] uppercase font-bold tracking-wider text-slate-400 mb-1">Destino</p>
                        <p className="text-sm font-bold text-slate-700 bg-white inline-block px-2.5 py-1 rounded-lg border border-slate-200">{data.destinationCity}</p>
                    </div>
                </div>
            </div>

            {/* Botones */}
            <div className="px-5 flex flex-col gap-3">
                {currentStatus === 'assigned' && (
                    <button
                        onClick={() => { setSelectedAction('departure'); setActiveModal('confirm'); }}
                        disabled={actionLoading !== null}
                        className="w-full bg-blue-600 hover:bg-blue-700 text-white rounded-2xl py-5 flex items-center justify-center gap-3 font-bold text-lg transition-transform active:scale-[0.98] disabled:opacity-50 shadow-lg shadow-blue-600/20"
                    >
                        {actionLoading === 'departure' ? <RefreshCw className="animate-spin" size={24} /> : <Truck size={24} />}
                        INICIAR RUTA
                    </button>
                )}

                {currentStatus === 'in_transit' && (
                    <>
                        <button
                            onClick={() => { setSelectedAction('in_transit'); setActiveModal('confirm'); }}
                            disabled={actionLoading !== null}
                            className="w-full bg-blue-600 hover:bg-blue-700 text-white rounded-2xl py-5 flex items-center justify-center gap-3 font-bold text-lg transition-transform active:scale-[0.98] disabled:opacity-50 shadow-lg shadow-blue-600/20"
                        >
                            {actionLoading === 'in_transit' ? <RefreshCw className="animate-spin" size={24} /> : <Truck size={24} />}
                            EN CAMINO
                        </button>
                        <div className="h-4"></div>
                        <button
                            onClick={() => { setSelectedAction('arrival'); setActiveModal('confirm'); }}
                            disabled={actionLoading !== null}
                            className="w-full bg-slate-100/50 hover:bg-slate-100 text-slate-500 border-2 border-slate-200/60 rounded-2xl py-4 flex items-center justify-center gap-2 font-bold transition-transform active:scale-[0.98] disabled:opacity-50 shadow-sm"
                        >
                            {actionLoading === 'arrival' ? <RefreshCw className="animate-spin" size={20} /> : <MapPin size={20} className="text-slate-400" />}
                            Llegué al Destino
                        </button>
                    </>
                )}

                {currentStatus === 'at_destination' && (
                    <button
                        onClick={() => { setSelectedAction('delivered'); setActiveModal('confirm'); }}
                        disabled={actionLoading !== null}
                        className="w-full bg-emerald-600 hover:bg-emerald-700 text-white rounded-2xl py-5 flex items-center justify-center gap-3 font-bold text-lg transition-transform active:scale-[0.98] disabled:opacity-50 shadow-lg shadow-emerald-600/20"
                    >
                        {actionLoading === 'delivered' ? <RefreshCw className="animate-spin" size={24} /> : <CheckCircle size={24} />}
                        ENTREGADO
                    </button>
                )}

                {currentStatus !== 'delivered' && (
                    <button
                        onClick={() => { setSelectedAction('incident'); setActiveModal('incident'); }}
                        disabled={actionLoading !== null}
                        className="w-full mt-4 bg-[#FFE4E6] text-rose-700 border border-rose-200 rounded-xl py-3.5 flex items-center justify-center gap-2 font-bold transition-transform active:scale-[0.98] disabled:opacity-50"
                    >
                        {actionLoading === 'incident' ? <RefreshCw className="animate-spin" size={18} /> : <AlertCircle size={18} />}
                        Reportar Incidencia
                    </button>
                )}

                {currentStatus === 'delivered' && (
                    <div className="bg-emerald-50 text-emerald-800 p-6 rounded-3xl flex flex-col items-center justify-center gap-3 border border-emerald-200 shadow-sm mt-4 text-center mt-20">
                        <div className="bg-emerald-500 text-white p-3 rounded-full mb-2 shadow-lg shadow-emerald-500/30">
                            <CheckCircle size={40} />
                        </div>
                        <h3 className="font-black text-2xl tracking-tight">Viaje Completado</h3>
                        <p className="text-sm font-semibold opacity-80 leading-snug">La operación fue reportada con éxito.<br />Puedes cerrar esta pantalla.</p>
                    </div>
                )}
            </div>

            {/* Timeline Snapshot */}
            {data.lastEvent && currentStatus !== 'delivered' && (
                <div className="px-5 mt-auto pt-10 pb-4">
                    <p className="text-[10px] font-black text-slate-400 uppercase tracking-widest mb-2 px-1">Último Reporte</p>
                    <div className="bg-white p-4 rounded-2xl border border-slate-200 flex flex-col gap-1 shadow-[0_2px_10px_-5px_rgba(0,0,0,0.05)] border-l-4 border-l-blue-500">
                        <p className="text-sm font-bold text-slate-800 w-full truncate">{data.lastEvent.municipality}</p>
                        <p className="text-xs font-semibold text-slate-400">
                            {new Date(data.lastEvent.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                        </p>
                    </div>
                </div>
            )}

            {/* Modals Mounting */}
            {activeModal === 'confirm' && selectedAction && (
                <ActionConfirmModal
                    action={selectedAction}
                    onClose={() => setActiveModal(null)}
                    onConfirm={(loc) => submitEvent({ action: selectedAction, location: loc })}
                />
            )}

            {activeModal === 'incident' && (
                <IncidentModal
                    onClose={() => setActiveModal(null)}
                    onConfirm={(type, note) => submitEvent({ action: 'incident', incident: { type, note } })}
                />
            )}
        </div>
    );
}
