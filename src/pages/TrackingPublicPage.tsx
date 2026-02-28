import { useParams } from 'react-router-dom';
import { useState, useEffect } from 'react';
import {
    Truck,
    MapPin,
    Shield,
    ShieldCheck,
    Flag,
    CheckCircle,
    AlertTriangle,
    Clock,
    Share2,
    Info,
    Check,
    RefreshCw,
} from 'lucide-react';
import type { ElementType } from 'react';
import { PublicTrackingMap } from '@/components/PublicTrackingMap';
import type { PublicTrackingResponse } from '@/types/tracking';
import { fetchPublicTracking } from '@/services/trackingEdge.service';

// Mapper to map string names back to Lucide components
const IconMap: Record<string, ElementType> = {
    'truck': Truck,
    'map-pin': MapPin,
    'shield': Shield,
    'shield-check': ShieldCheck,
    'flag': Flag,
    'check-circle': CheckCircle,
    'alert-triangle': AlertTriangle
};

// ── Loading skeleton ──────────────────────────────────────────────────────────

function LoadingState() {
    return (
        <div className="flex flex-col w-full h-screen bg-slate-50 items-center justify-center font-sans px-4">
            <RefreshCw size={32} className="animate-spin text-slate-300 mb-4" />
            <p className="text-sm font-medium text-slate-500">Cargando seguimiento...</p>
        </div>
    );
}

// ── Error states ──────────────────────────────────────────────────────────────

function NotFoundState({ message }: { message?: string }) {
    return (
        <div className="flex flex-col w-full h-screen bg-slate-50 items-center justify-center font-sans px-4">
            <AlertTriangle size={48} className="text-slate-300 mb-4 mx-auto" />
            <h2 className="text-xl font-bold text-slate-700 mb-2">Enlace no encontrado</h2>
            <p className="text-sm font-medium text-slate-500 text-center max-w-sm">
                {message || "Este enlace de seguimiento no existe o es inválido."}
            </p>
        </div>
    );
}

function RevokedState() {
    return (
        <div className="flex flex-col w-full h-screen bg-slate-50 items-center justify-center font-sans px-4">
            <Shield size={48} className="text-red-400 mb-4 mx-auto" />
            <h2 className="text-xl font-bold text-slate-700 mb-2">Acceso Revocado</h2>
            <p className="text-sm font-medium text-slate-500 text-center max-w-sm">
                Este enlace fue desactivado por el operador.
            </p>
        </div>
    );
}

function ExpiredState() {
    return (
        <div className="flex flex-col w-full h-screen bg-slate-50 items-center justify-center font-sans px-4">
            <Clock size={48} className="text-slate-300 mb-4 mx-auto" />
            <h2 className="text-xl font-bold text-slate-700 mb-2">Enlace Expirado</h2>
            <p className="text-sm font-medium text-slate-500 text-center max-w-sm">
                Este enlace de seguimiento ya no está disponible.
            </p>
        </div>
    );
}

function NetworkErrorState({ onRetry }: { onRetry: () => void }) {
    return (
        <div className="flex flex-col w-full h-screen bg-slate-50 items-center justify-center font-sans px-4">
            <AlertTriangle size={48} className="text-amber-400 mb-4 mx-auto" />
            <h2 className="text-xl font-bold text-slate-700 mb-2">Sin conexión</h2>
            <p className="text-sm font-medium text-slate-500 text-center max-w-sm mb-6">
                No se pudo cargar el seguimiento. Verifica tu conexión e intenta nuevamente.
            </p>
            <button
                onClick={onRetry}
                className="flex items-center gap-2 px-5 py-2.5 bg-slate-800 text-white rounded-xl text-sm font-bold hover:bg-slate-700 transition"
            >
                <RefreshCw size={16} />
                Reintentar
            </button>
        </div>
    );
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function TrackingPublicPage() {
    const { token } = useParams<{ token: string }>();

    const [uiState, setUiState] = useState<
        'loading' | 'success' | 'soft_expired' | 'not_found' | 'revoked' | 'hard_expired' | 'network_error'
    >('loading');
    const [response, setResponse] = useState<PublicTrackingResponse | null>(null);
    const [retryCount, setRetryCount] = useState(0);

    useEffect(() => {
        if (!token) {
            setUiState('not_found');
            return;
        }

        let cancelled = false;
        setUiState('loading');

        fetchPublicTracking(token).then((result) => {
            if (cancelled) return;

            if (!result.ok) {
                setUiState('network_error');
                return;
            }

            const { data } = result;
            setResponse(data);

            switch (data.status) {
                case 'success': setUiState('success'); break;
                case 'soft_expired': setUiState('soft_expired'); break;
                case 'not_found': setUiState('not_found'); break;
                case 'revoked': setUiState('revoked'); break;
                case 'hard_expired': setUiState('hard_expired'); break;
                default: setUiState('not_found');
            }
        });

        return () => { cancelled = true; };
    }, [token, retryCount]);

    const handleRetry = () => setRetryCount(c => c + 1);

    // ── Production Gate ───────────────────────────────────────────────────────
    // In strict production, we don't allow test tokens.
    const isTestToken = token === 'test-token';
    const isProdMode = import.meta.env.VITE_APP_MODE === 'prod';

    if (isProdMode && isTestToken && uiState !== 'loading') {
        return <NotFoundState />;
    }

    // ── Status gates ──────────────────────────────────────────────────────────

    if (!token) return <NotFoundState message="El token es requerido para ver el seguimiento." />;
    if (uiState === 'loading') return <LoadingState />;
    if (uiState === 'not_found') return <NotFoundState />;
    if (uiState === 'revoked') return <RevokedState />;
    if (uiState === 'hard_expired') return <ExpiredState />;
    if (uiState === 'network_error') return <NetworkErrorState onRetry={handleRetry} />;

    // success | soft_expired: render full tracking UI
    const trackingData = response?.data;
    if (!trackingData) return <NotFoundState />;

    const isSoftExpired = uiState === 'soft_expired';

    const lastValidEvent = [...trackingData.events]
        .reverse()
        .find(e => e.status !== 'future');

    const lastUpdateText = lastValidEvent
        ? `${lastValidEvent.subtitle.split(' · ')[0]}`
        : 'Ubicación actualizada';

    return (
        <div className="flex flex-col md:flex-row w-full h-screen bg-slate-50 overflow-hidden font-sans">
            {/* Left Panel: Map */}
            <div className="relative flex-1 h-[40vh] md:h-screen z-10 border-b md:border-b-0 md:border-r border-tech-border">
                {/*
                  GEO-01/GEO-04: Location rounding and omitting if null is handled in backend.
                  This component blindly renders what it gets safely.
                */}
                <PublicTrackingMap
                    currentLocation={trackingData.currentLocation}
                    lastUpdateText={lastUpdateText}
                    routePoints={trackingData.routePoints}
                />

                {/* CB-02: Soft-expiry banner discretamente sobre el mapa */}
                {isSoftExpired && (
                    <div className="absolute top-20 left-6 right-6 md:right-auto md:w-[400px] bg-amber-50/95 backdrop-blur-md border border-amber-200 p-3 rounded-xl shadow-lg z-50 flex items-start gap-3 animate-in fade-in slide-in-from-top-4">
                        <AlertTriangle className="text-amber-500 shrink-0 mt-0.5" size={18} />
                        <div>
                            <p className="text-xs font-bold text-amber-800 uppercase tracking-wider mb-0.5">Seguimiento Vencido</p>
                            <p className="text-xs font-medium text-amber-700/80 leading-relaxed">
                                Este enlace ha expirado recientemente. Los datos pueden no estar actualizados.
                            </p>
                        </div>
                    </div>
                )}

                {/* Branding overlay */}
                <div className="absolute top-6 left-6 bg-white/90 backdrop-blur px-5 py-3 rounded-2xl shadow-lg border border-white/50 flex items-center gap-4 z-40">
                    <div className="w-10 h-10 gradient-accent rounded-xl flex items-center justify-center text-white font-black text-xl shadow-md">
                        R
                    </div>
                    <div>
                        <h1 className="text-sm font-extrabold text-primary mb-0.5 tracking-tight">ROTERO ERP</h1>
                        <p className="text-[10px] text-slate-500 font-bold uppercase tracking-widest">Tracking Seguro</p>
                    </div>
                </div>

                {/* Simple ETA overlay on map */}
                {trackingData.eta && (
                    <div className="absolute top-6 right-6 md:right-10 bg-slate-900/90 text-white backdrop-blur px-4 py-2.5 rounded-xl shadow-xl flex items-center gap-3 z-40 animate-in fade-in slide-in-from-right-4">
                        <div className="bg-emerald-500/20 p-1.5 rounded-lg text-emerald-400">
                            <Clock size={18} />
                        </div>
                        <div className="flex flex-col pr-1">
                            <span className="text-[9px] uppercase font-bold tracking-widest text-slate-300 mb-0.5">ETA • Llegada Est.</span>
                            <span className="text-sm font-bold tracking-tight">{trackingData.eta}</span>
                        </div>
                    </div>
                )}

                {/* Status overlay */}
                <div className="absolute bottom-6 left-1/2 -translate-x-1/2 bg-white/95 backdrop-blur px-6 py-4 rounded-2xl shadow-xl border border-white/50 w-[90%] max-w-sm">
                    <div className="flex items-center justify-between mb-2">
                        <span className="text-xs font-bold text-slate-400 uppercase tracking-wider">Estatus Actual</span>
                        <div className="flex items-center gap-1.5 px-2.5 py-1 bg-emerald-50 text-emerald-700 rounded-md text-xs font-bold">
                            <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse-dot" />
                            {trackingData.currentStatus}
                        </div>
                    </div>
                    <div className="text-lg font-black text-slate-800 tracking-tight">
                        A tiempo en ruta
                    </div>
                    <div className="flex items-center gap-2 text-xs font-medium text-slate-500 mt-3 pt-3 border-t border-slate-100">
                        <Clock size={14} className="text-emerald-500" />
                        Última actualización: {lastValidEvent?.timestamp || 'Reciente'} · {lastUpdateText}
                    </div>
                </div>
            </div>

            {/* Right Panel: Detail & Timeline */}
            <div className="w-full md:w-[480px] h-[60vh] md:h-screen bg-white flex flex-col shadow-2xl z-20 overflow-y-auto">
                <div className="p-8 border-b border-tech-border shrink-0 bg-slate-50/50">
                    <div className="flex justify-between items-start mb-6">
                        <div>
                            <h2 className="text-2xl font-black tracking-tight text-primary mb-1">{trackingData.orderRef}</h2>
                            <p className="text-sm text-slate-500 font-medium">Operación Logística</p>
                        </div>
                        <button className="w-10 h-10 rounded-xl bg-white border border-tech-border flex items-center justify-center text-slate-400 hover:text-primary hover:border-primary/30 transition-all shadow-sm">
                            <Share2 size={18} />
                        </button>
                    </div>

                    <div className="bg-white rounded-xl p-5 border border-tech-border shadow-sm flex items-start gap-4 mb-2">
                        <div className="p-2.5 bg-blue-50 text-blue-600 rounded-lg shrink-0">
                            <Info size={20} strokeWidth={2} />
                        </div>
                        <div>
                            <p className="text-[11px] font-bold text-slate-400 uppercase tracking-wider mb-0.5">Ruta Asignada</p>
                            <p className="font-semibold text-slate-700 text-sm mb-2">{trackingData.route}</p>
                            <div className="flex items-center gap-2 text-xs">
                                <span className="px-2 py-0.5 bg-slate-100 text-slate-600 rounded font-medium">
                                    ETA: {trackingData.eta}
                                </span>
                            </div>
                        </div>
                    </div>
                </div>

                <div className="p-8 flex-1">
                    <h3 className="text-sm font-bold text-slate-400 uppercase tracking-wider mb-8">Bitácora de Viaje</h3>

                    <div className="relative border-l-2 border-slate-100 ml-4 space-y-8">
                        {trackingData.events.map((evt, idx) => {
                            const IconCmp = IconMap[evt.icon] || Info;
                            const isDone = evt.status === 'done';
                            const isCurrent = evt.status === 'current';
                            const isFuture = evt.status === 'future';

                            return (
                                <div key={idx} className="relative pl-8 group">
                                    {/* Line connector */}
                                    {(isDone || isCurrent) && idx < trackingData.events.length - 1 && (
                                        <div className="absolute top-8 bottom-[-2rem] -left-[2px] w-[2px] bg-emerald-500/30" />
                                    )}

                                    {/* Marker */}
                                    <div className={`absolute top-0 -left-[14px] w-7 h-7 rounded-full flex items-center justify-center ring-4 ring-white shadow-sm transition-all
                                        ${isDone ? 'bg-emerald-50 text-emerald-500 border border-emerald-200' : ''}
                                        ${isCurrent ? 'bg-emerald-500 text-white shadow-emerald-500/30 shadow-lg' : ''}
                                        ${isFuture ? 'bg-white text-slate-300 border-[1.5px] border-slate-200' : ''}
                                    `}>
                                        {isDone && !isCurrent ? (
                                            <Check size={14} strokeWidth={3} />
                                        ) : (
                                            <IconCmp size={14} strokeWidth={isCurrent ? 2.5 : 2} />
                                        )}
                                        {isCurrent && (
                                            <span className="absolute inset-0 rounded-full ring-2 ring-emerald-500 animate-ping opacity-30" />
                                        )}
                                    </div>

                                    {/* Content */}
                                    <div className="flex flex-col">
                                        <div className="flex items-center justify-between gap-4 mb-0.5">
                                            <h4 className={`text-sm font-bold tracking-tight
                                                ${isDone || isCurrent ? 'text-slate-800' : 'text-slate-400'}
                                            `}>
                                                {evt.title}
                                            </h4>
                                            {isCurrent && (
                                                <span className="text-[10px] font-bold uppercase tracking-wider text-emerald-600 bg-emerald-50 px-2.5 py-0.5 rounded-full whitespace-nowrap">
                                                    Ahora
                                                </span>
                                            )}
                                        </div>
                                        <p className={`text-xs font-medium leading-relaxed
                                            ${isDone || isCurrent ? 'text-slate-500' : 'text-slate-400'}
                                        `}>
                                            {evt.subtitle}
                                        </p>
                                    </div>
                                </div>
                            );
                        })}
                    </div>
                </div>
            </div>
        </div>
    );
}
