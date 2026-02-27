import { useState, useEffect } from 'react';
import { useAuthStore } from '@/store/authStore';
import { PageHeader } from '@/components/PageHeader';
import { Badge } from '@/components/Badge';
import { MapPin, ExternalLink, RefreshCw, Send, Settings, Search, CheckCircle, AlertTriangle, Copy, QrCode, MessageCircle, Check, X, ShieldOff } from 'lucide-react';
import { fetchInternalTrackingList } from '@/services/trackingEdge.service';
import { ORDER_STATES, TRACKING_LINK_STATES } from '@/constants/states';
import { reverseGeocode, getGeoCacheStats } from '@/services/trackingGeo.service';
import type { GeoPoint } from '@/types/tracking';

// Simulated GPS coordinates for each order (in production these come from driver app)
const SIMULATED_GPS: Record<string, GeoPoint> = {
    'OP-8492': { lat: 25.6866, lng: -100.3161 },   // Monterrey area
    'OP-8493': { lat: 19.5684, lng: -99.2116 },     // Tepotzotlán area 
    'OP-8494': { lat: 20.6597, lng: -103.3496 },    // Guadalajara area
};

interface GeoResult {
    orderId: string;
    label: string;
    success: boolean;
    fromCache: boolean;
}

export default function TrackingPage() {
    const [isUpdating, setIsUpdating] = useState(false);
    const [trackingList, setTrackingList] = useState<any[]>([]);

    useEffect(() => {
        let mounted = true;
        fetchInternalTrackingList().then(data => {
            if (mounted) setTrackingList(data);
        });
        return () => { mounted = false; };
    }, []);
    const [lastGeoResults, setLastGeoResults] = useState<GeoResult[]>([]);
    const [showResults, setShowResults] = useState(false);
    const [toast, setToast] = useState<{ message: string; visible: boolean }>({ message: '', visible: false });
    const [qrData, setQrData] = useState<{ link: string; orderId: string } | null>(null);

    const role = useAuthStore(state => state.getRole());
    const isViewer = role === 'viewer';

    const handleRevoke = (id: string) => {
        setTrackingList(prev => prev.map(t => t.id === id ? { ...t, linkState: 'revoked' as const } : t));
        showToast('Enlace revocado permanentemente');
    };

    const showToast = (message: string) => {
        setToast({ message, visible: true });
        setTimeout(() => setToast({ message: '', visible: false }), 2500);
    };

    const getFullLink = (token: string) => `${window.location.origin}/t/${token}`;

    const handleCopyLink = (token: string) => {
        navigator.clipboard.writeText(getFullLink(token));
        showToast('Link copiado al portapapeles');
    };

    const handleWhatsApp = (token: string, orderId: string) => {
        const text = encodeURIComponent(`Hola, aquí tienes el link de seguimiento para tu orden ${orderId}: ${getFullLink(token)}`);
        window.open(`https://wa.me/?text=${text}`, '_blank');
    };

    const handleSimulateUpdate = async () => {
        setIsUpdating(true);
        setShowResults(false);
        const results: GeoResult[] = [];

        for (const track of trackingList) {
            const gps = SIMULATED_GPS[track.id];
            if (!gps) continue;

            const { place, fromCache, error } = await reverseGeocode(gps);

            if (place) {
                results.push({
                    orderId: track.id,
                    label: `${place.municipality}, ${place.state}`,
                    success: true,
                    fromCache,
                });
            } else {
                results.push({
                    orderId: track.id,
                    label: error ? `Error: ${error}` : 'Ubicación actualizada',
                    success: false,
                    fromCache,
                });
            }
        }

        const stats = getGeoCacheStats();
        console.log('[TrackingGeo] Cache stats:', stats);

        setLastGeoResults(results);
        setShowResults(true);
        setIsUpdating(false);
    };

    return (
        <div className="flex-1 overflow-y-auto bg-surface font-sans h-full">
            <div className="max-w-[1400px] mx-auto px-6 py-8">
                <PageHeader
                    title="Control de Tracking"
                    subtitle="Monitoreo GPS, geocercas y links de seguimiento"
                    actions={
                        <div className="flex gap-3">
                            {!isViewer && (
                                <button className="flex items-center gap-2 px-4 py-2 bg-white border border-tech-border text-slate-600 rounded-xl hover:bg-slate-50 hover:text-primary transition-colors text-sm font-semibold shadow-sm">
                                    <Settings size={16} /> Configuración
                                </button>
                            )}
                            <button
                                onClick={handleSimulateUpdate}
                                disabled={isUpdating}
                                className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-xl hover:bg-primary/90 transition-all shadow-md shadow-primary/20 text-sm font-semibold disabled:opacity-50"
                            >
                                <RefreshCw size={16} className={isUpdating ? 'animate-spin' : ''} />
                                {isUpdating ? 'Geocodificando…' : 'Forzar Sincronización'}
                            </button>
                        </div>
                    }
                />

                {/* Geocoding results toast */}
                {showResults && lastGeoResults.length > 0 && (
                    <div className="bg-white rounded-xl border border-tech-border shadow-sm mb-6 p-4 animate-in fade-in slide-in-from-top-2">
                        <div className="flex items-center justify-between mb-3">
                            <h4 className="text-xs font-bold text-slate-400 uppercase tracking-wider">Resultado de Geocodificación</h4>
                            <button
                                onClick={() => setShowResults(false)}
                                className="text-xs text-slate-400 hover:text-slate-600 transition-colors font-medium"
                            >
                                Cerrar ✕
                            </button>
                        </div>
                        <div className="space-y-2">
                            {lastGeoResults.map((r) => (
                                <div key={r.orderId} className="flex items-center gap-3 py-1.5">
                                    {r.success ? (
                                        <CheckCircle size={16} className="text-emerald-500 shrink-0" />
                                    ) : (
                                        <AlertTriangle size={16} className="text-amber-500 shrink-0" />
                                    )}
                                    <span className="text-sm font-semibold text-slate-700 w-20">{r.orderId}</span>
                                    <span className={`text-sm font-medium ${r.success ? 'text-emerald-700' : 'text-amber-600'}`}>
                                        {r.label}
                                    </span>
                                    {r.fromCache && (
                                        <span className="text-[10px] font-bold text-slate-400 bg-slate-100 px-2 py-0.5 rounded-full ml-auto">
                                            CACHÉ
                                        </span>
                                    )}
                                </div>
                            ))}
                        </div>
                    </div>
                )}

                {/* Filter bar */}
                <div className="bg-white p-4 rounded-xl border border-tech-border shadow-sm mb-6 flex items-center justify-between">
                    <div className="relative w-full max-w-md">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" size={16} />
                        <input
                            type="text"
                            placeholder="Buscar PO, Cliente o Link..."
                            className="w-full pl-10 pr-4 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-primary/20 transition-all font-medium"
                        />
                    </div>
                </div>

                {/* Tracking List */}
                <div className="bg-white rounded-xl shadow-sm border border-tech-border overflow-hidden">
                    <div className="overflow-x-auto">
                        <table className="w-full text-left border-collapse">
                            <thead>
                                <tr className="bg-slate-50/80 border-b border-tech-border">
                                    <th className="px-5 py-4 text-[10px] font-bold text-slate-400 uppercase tracking-widest whitespace-nowrap">ORDEN</th>
                                    <th className="px-5 py-4 text-[10px] font-bold text-slate-400 uppercase tracking-widest whitespace-nowrap">CLIENTE</th>
                                    <th className="px-5 py-4 text-[10px] font-bold text-slate-400 uppercase tracking-widest whitespace-nowrap">ESTATUS</th>
                                    <th className="px-5 py-4 text-[10px] font-bold text-slate-400 uppercase tracking-widest whitespace-nowrap">ÚLTIMO MUNICIPIO</th>
                                    <th className="px-5 py-4 text-[10px] font-bold text-slate-400 uppercase tracking-widest whitespace-nowrap">LINK PÚBLICO</th>
                                    <th className="px-5 py-4 text-[10px] font-bold text-slate-400 uppercase tracking-widest whitespace-nowrap text-right">ACCIONES</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-tech-border">
                                {trackingList.map((track) => {
                                    const statusSpec = ORDER_STATES[track.status as keyof typeof ORDER_STATES] || ORDER_STATES.draft;
                                    const linkStateSpec = TRACKING_LINK_STATES[track.linkState] || TRACKING_LINK_STATES.active;
                                    const isRevocable = track.linkState === 'active' || track.linkState === 'soft_expired';

                                    return (
                                        <tr key={track.id} className="hover:bg-slate-50/50 transition-colors group">
                                            <td className="px-5 py-4">
                                                <div className="text-sm font-bold text-primary group-hover:text-blue-600 transition-colors cursor-pointer">{track.id}</div>
                                                <div className="text-[11px] font-medium text-slate-400 mt-0.5">{track.route}</div>
                                            </td>
                                            <td className="px-5 py-4">
                                                <div className="flex items-center gap-3">
                                                    <div className="w-8 h-8 rounded-lg bg-slate-100 flex items-center justify-center text-xs font-bold text-slate-500 shrink-0 border border-slate-200">
                                                        {track.client.substring(0, 2).toUpperCase()}
                                                    </div>
                                                    <span className="text-sm font-semibold text-slate-700">{track.client}</span>
                                                </div>
                                            </td>
                                            <td className="px-5 py-4">
                                                <Badge variant={statusSpec.badge}>{statusSpec.label}</Badge>
                                            </td>
                                            <td className="px-5 py-4">
                                                <div className="flex items-center gap-2">
                                                    <div className="p-1.5 bg-blue-50 text-blue-600 rounded-md shrink-0">
                                                        <MapPin size={14} strokeWidth={2.5} />
                                                    </div>
                                                    <div>
                                                        <div className="text-[13px] font-semibold text-slate-700">{track.lastLocation}</div>
                                                        <div className="text-[10px] font-medium text-slate-400 mt-0.5 flex items-center gap-1.5">
                                                            <div className="w-1.5 h-1.5 rounded-full bg-blue-400" />
                                                            Actualizado: {track.lastUpdate}
                                                        </div>
                                                    </div>
                                                </div>
                                            </td>
                                            <td className="px-5 py-4">
                                                <div className="flex flex-col gap-1.5">
                                                    <div className="flex items-center gap-2 group/link cursor-pointer w-fit">
                                                        <div className={`text-[13px] font-medium truncate max-w-[120px] font-mono group-hover/link:underline ${track.linkState === 'revoked' ? 'text-slate-400 line-through' : 'text-blue-600'}`}>
                                                            ...{track.link.substring(track.link.length - 12)}
                                                        </div>
                                                        <a href={`/t/${track.link}`} target="_blank" rel="noreferrer" className="text-slate-400 hover:text-blue-600 transition-colors">
                                                            <ExternalLink size={14} />
                                                        </a>
                                                    </div>
                                                    <div className="flex items-center gap-2">
                                                        <div className="scale-90 origin-left">
                                                            <Badge variant={linkStateSpec.badge}>
                                                                {linkStateSpec.label}
                                                            </Badge>
                                                        </div>
                                                        {track.linkState !== 'revoked' && (
                                                            <span className="text-[10px] font-medium text-slate-400">
                                                                Vence: {new Date(track.expiresAt).toLocaleDateString()}
                                                            </span>
                                                        )}
                                                    </div>
                                                </div>
                                            </td>
                                            <td className="px-5 py-4 text-right">
                                                <div className="flex items-center justify-end gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
                                                    <button
                                                        onClick={() => handleCopyLink(track.link)}
                                                        disabled={track.linkState === 'revoked'}
                                                        className="p-2 text-slate-400 hover:text-blue-600 hover:bg-blue-50 rounded-lg transition-colors border border-transparent hover:border-blue-200 disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:border-transparent disabled:cursor-not-allowed"
                                                        title="Copiar link"
                                                    >
                                                        <Copy size={16} />
                                                    </button>
                                                    <button
                                                        onClick={() => setQrData({ link: getFullLink(track.link), orderId: track.id })}
                                                        disabled={track.linkState === 'revoked'}
                                                        className="p-2 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-lg transition-colors border border-transparent hover:border-slate-300 disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:border-transparent disabled:cursor-not-allowed"
                                                        title="Generar QR"
                                                    >
                                                        <QrCode size={16} />
                                                    </button>
                                                    <button
                                                        onClick={() => handleWhatsApp(track.link, track.id)}
                                                        disabled={track.linkState === 'revoked'}
                                                        className="p-2 text-slate-400 hover:text-emerald-600 hover:bg-emerald-50 rounded-lg transition-colors border border-transparent hover:border-emerald-200 disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:border-transparent disabled:cursor-not-allowed"
                                                        title="Compartir por WhatsApp"
                                                    >
                                                        <MessageCircle size={16} />
                                                    </button>
                                                    {isRevocable && !isViewer && (
                                                        <button
                                                            onClick={() => handleRevoke(track.id)}
                                                            className="p-2 text-red-400 hover:text-red-600 hover:bg-red-50 rounded-lg transition-colors border border-transparent hover:border-red-200"
                                                            title="Revocar link"
                                                        >
                                                            <ShieldOff size={16} />
                                                        </button>
                                                    )}
                                                </div>
                                            </td>
                                        </tr>
                                    );
                                })}
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            {/* Simple Toast */}
            {toast.visible && (
                <div className="fixed bottom-8 left-1/2 -translate-x-1/2 z-50 animate-in fade-in slide-in-from-bottom-4 duration-300">
                    <div className="bg-slate-800 text-white px-6 py-3 rounded-2xl shadow-2xl flex items-center gap-3 border border-slate-700">
                        <Check size={18} className="text-emerald-400" />
                        <span className="text-sm font-semibold">{toast.message}</span>
                    </div>
                </div>
            )}

            {/* QR Modal Overlay */}
            {qrData && (
                <div
                    className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 backdrop-blur-sm p-6 animate-in fade-in duration-200"
                    onClick={() => setQrData(null)}
                >
                    <div
                        className="bg-white rounded-3xl shadow-2xl p-8 max-w-sm w-full animate-in zoom-in-95 duration-200"
                        onClick={e => e.stopPropagation()}
                    >
                        <div className="flex items-center justify-between mb-6">
                            <div>
                                <h3 className="text-lg font-bold text-slate-800">Código QR de Tracking</h3>
                                <p className="text-sm font-medium text-slate-400">Orden: {qrData.orderId}</p>
                            </div>
                            <button onClick={() => setQrData(null)} className="p-2 hover:bg-slate-100 rounded-full transition-colors text-slate-400 hover:text-slate-600">
                                <X size={20} />
                            </button>
                        </div>

                        <div className="bg-slate-50 rounded-2xl p-6 mb-6 flex items-center justify-center border border-slate-100 italic text-slate-400 text-sm">
                            {/* In a real app we'd use a QR library, using an image service here */}
                            <img
                                src={`https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(qrData.link)}`}
                                alt="QR Code"
                                className="w-full h-auto aspect-square rounded-lg"
                                onLoad={(e) => (e.currentTarget.parentElement!.style.opacity = '1')}
                            />
                        </div>

                        <button
                            onClick={() => {
                                navigator.clipboard.writeText(qrData.link);
                                showToast('Link copiado');
                            }}
                            className="w-full py-3 bg-slate-50 hover:bg-slate-100 border border-slate-200 text-slate-600 rounded-xl transition-all font-bold text-sm flex items-center justify-center gap-2"
                        >
                            <Copy size={16} /> Copiar URL
                        </button>
                    </div>
                </div>
            )}
        </div>
    );
}
