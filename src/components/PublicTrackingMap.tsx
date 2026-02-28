import { useEffect, useMemo } from 'react';
import { MapContainer, TileLayer, Marker, useMap, Circle, Polyline } from 'react-leaflet';
import L from 'leaflet';
import { MapPin } from 'lucide-react';
import 'leaflet/dist/leaflet.css';
import type { GeoPoint } from '@/types/tracking';

// Fix for default Leaflet icon paths in React
delete (L.Icon.Default.prototype as any)._getIconUrl;
L.Icon.Default.mergeOptions({
    iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon-2x.png',
    iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon.png',
    shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
});

// Custom Premium Marker using divIcon
const createCustomMarker = (lastUpdateText: string = 'Reciente') => {
    return L.divIcon({
        className: 'custom-leaflet-marker',
        html: `
            <div class="relative flex flex-col items-center justify-end h-[80px] w-[140px] -ml-[70px] -mt-[60px]">
                <div class="bg-slate-900 text-white text-[10px] font-bold px-3 py-1.5 rounded-xl shadow-lg whitespace-nowrap mb-1 flex flex-col items-center leading-tight">
                    <span class="text-[9px] text-slate-400 uppercase tracking-wider">Última actualización</span>
                    <span class="text-white font-medium">${lastUpdateText}</span>
                    <div class="absolute bottom-[2px] left-1/2 -translate-x-1/2 w-0 h-0 border-l-4 border-r-4 border-t-4 border-transparent border-t-slate-900"></div>
                </div>
                <div class="relative flex items-center justify-center w-8 h-8">
                    <div class="absolute inset-0 bg-blue-500/20 rounded-full animate-ping"></div>
                    <div class="relative bg-white rounded-full p-1.5 shadow-lg border-2 border-blue-500 z-10">
                        <div class="w-3 h-3 bg-blue-500 rounded-full"></div>
                    </div>
                </div>
            </div>
        `,
        iconSize: [0, 0], // The offset is handled by the wrapper div margins
        iconAnchor: [0, 0],
    });
};

interface PublicTrackingMapProps {
    currentLocation?: GeoPoint;
    lastUpdateText?: string;
    /** Route v1: GEO-01 ofuscated route points (rounded ~1.1km) */
    routePoints?: GeoPoint[];
}

// Component to dynamically re-center map when location changes
function MapUpdater({ center }: { center: [number, number] }) {
    const map = useMap();
    useEffect(() => {
        if (center) {
            map.setView(center, map.getZoom());
        }
    }, [center, map]);
    return null;
}

export function PublicTrackingMap({ currentLocation, lastUpdateText, routePoints }: PublicTrackingMapProps) {
    if (!currentLocation) {
        return (
            <div className="absolute inset-0 bg-slate-50 flex flex-col items-center justify-center overflow-hidden">
                <div className="absolute inset-0 opacity-[0.03] bg-[radial-gradient(#000_1px,transparent_1px)] [background-size:16px_16px]"></div>
                <div className="w-16 h-16 bg-slate-100 rounded-full flex items-center justify-center mb-4 border border-slate-200 shadow-sm relative z-10">
                    <MapPin size={24} className="text-slate-400" />
                </div>
                <h3 className="text-lg font-bold text-slate-600 tracking-tight z-10">Esperando Ubicación</h3>
                <p className="text-sm font-medium text-slate-400 text-center max-w-[250px] mt-2 z-10">
                    La ubicación GPS estará disponible pronto en esta vista interactiva.
                </p>
            </div>
        );
    }

    const position: [number, number] = [currentLocation.lat, currentLocation.lng];
    const markerIcon = useMemo(() => createCustomMarker(lastUpdateText), [lastUpdateText]);

    return (
        <div className="absolute inset-0 z-0">
            <MapContainer
                center={position}
                zoom={13}
                scrollWheelZoom={false} // Prevents stealing scroll from page
                className="w-full h-full"
                zoomControl={false} // Hiding default zoom for cleaner look, we can add it custom if needed
            >
                <TileLayer
                    url="https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png"
                    attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OSM</a>'
                />

                {/* GEO-01: Approximate 1.1km area radius */}
                <Circle
                    center={position}
                    radius={1100}
                    pathOptions={{ color: '#3b82f6', fillColor: '#3b82f6', fillOpacity: 0.1, weight: 1.5, dashArray: '4 4' }}
                />

                {/* Route v1: GEO-01 ofuscated polyline */}
                {routePoints && routePoints.length >= 2 && (
                    <Polyline
                        positions={routePoints.map(p => [p.lat, p.lng] as [number, number])}
                        pathOptions={{
                            color: '#6366f1',
                            weight: 3,
                            opacity: 0.5,
                            dashArray: '8 6',
                            lineCap: 'round',
                            lineJoin: 'round',
                        }}
                    />
                )}

                <Marker position={position} icon={markerIcon} />
                <MapUpdater center={position} />
            </MapContainer>

            {/* Adding the Leaflet CSS locally if the global import doesn't work perfectly in Vite */}
            <style>{`
                .leaflet-container {
                    font-family: inherit;
                }
                .custom-leaflet-marker {
                    background: transparent;
                    border: none;
                }
                .leaflet-control-attribution {
                    background: rgba(255, 255, 255, 0.7) !important;
                    font-size: 10px !important;
                    color: #94a3b8 !important;
                    padding: 2px 6px !important;
                    border-top-left-radius: 6px !important;
                }
                .leaflet-control-attribution a {
                    color: #64748b !important;
                }
            `}</style>
        </div>
    );
}
