import type { TrackingEvent, TrackingLink, PublicTrackingView, PublicTimelineEvent } from '@/types/tracking';

export const MOCK_TRACKING_EVENTS: TrackingEvent[] = [
    {
        id: 'TE-001',
        orderId: 'ROT-24-001',
        eventType: 'departure',
        location: { lat: 27.4828, lng: -99.5075 },
        place: { municipality: 'Nuevo Laredo', state: 'Tamaulipas', countryCode: 'MX' },
        timestamp: '2024-10-24T10:00:00Z',
        source: 'system'
    },
    {
        id: 'TE-002',
        orderId: 'ROT-24-001',
        eventType: 'in_transit',
        location: { lat: 26.5015, lng: -100.1764 },
        place: { municipality: 'Sabinas Hidalgo', state: 'Nuevo León', countryCode: 'MX' },
        timestamp: '2024-10-24T11:18:00Z',
        source: 'gps'
    },
    {
        id: 'TE-003',
        orderId: 'ROT-24-001',
        eventType: 'in_transit',
        location: { lat: 25.9556, lng: -100.1705 },
        place: { municipality: 'Ciénega de Flores', state: 'Nuevo León', countryCode: 'MX' },
        timestamp: '2024-10-24T12:47:00Z',
        source: 'gps'
    }
];

export const MOCK_PUBLIC_TIMELINE_EVENTS: PublicTimelineEvent[] = [
    {
        id: 'evt-1',
        title: 'Salida de Almacén',
        subtitle: 'Nuevo Laredo, Tamaulipas · 10:00 AM',
        timestamp: '2024-10-24T10:00:00Z',
        status: 'done',
        icon: 'truck'
    },
    {
        id: 'evt-2',
        title: 'En camino',
        subtitle: 'Sabinas Hidalgo, Nuevo León · 11:18 AM',
        timestamp: '2024-10-24T11:18:00Z',
        status: 'done',
        icon: 'map-pin'
    },
    {
        id: 'evt-3',
        title: 'En camino',
        subtitle: 'Ciénega de Flores, Nuevo León · 12:47 PM',
        timestamp: '2024-10-24T12:47:00Z',
        status: 'current',
        icon: 'map-pin'
    },
    {
        id: 'evt-4',
        title: 'Entrega en destino',
        subtitle: 'Monterrey, Nuevo León · ETA 14:00',
        timestamp: '2024-10-24T14:00:00Z',
        status: 'future',
        icon: 'flag'
    }
];

export const MOCK_PUBLIC_TRACKING_VIEW: PublicTrackingView = {
    orderRef: 'ROT-24-001',
    route: 'Laredo → Monterrey',
    currentStatus: 'En Tránsito',
    events: MOCK_PUBLIC_TIMELINE_EVENTS,
    eta: 'Hoy, 14:00',
    currentLocation: { lat: 25.96, lng: -100.17 }  // GEO-01: rounded to 2 decimals (~1.1km)
};

export const MOCK_TRACKING_LINKS: TrackingLink[] = [
    {
        id: 'TL-101',
        orderId: 'ROT-24-001',
        token: 'test-token', // Aliased for testing active link
        state: 'active',
        expiresAt: '2026-10-31T23:59:59Z',
        createdAt: '2024-10-24T09:00:00Z',
        lastAccessedAt: '2024-10-24T12:50:00Z'
    },
    {
        id: 'TL-101',
        orderId: 'ROT-24-001',
        token: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        state: 'active',
        expiresAt: '2026-10-31T23:59:59Z',
        createdAt: '2024-10-24T09:00:00Z',
        lastAccessedAt: '2024-10-24T12:50:00Z'
    },
    {
        id: 'TL-102',
        orderId: 'OP-8493',
        token: 'b2c3d4e5-f6a7-8901-bcde-f12345678901',
        state: 'soft_expired',
        expiresAt: '2024-10-23T23:59:59Z',
        createdAt: '2024-10-16T09:00:00Z',
    },
    {
        id: 'TL-103',
        orderId: 'OP-8494',
        token: 'c3d4e5f6-a7b8-9012-cdef-123456789012',
        state: 'revoked',
        expiresAt: '2026-10-31T23:59:59Z',
        createdAt: '2024-10-24T09:00:00Z',
        revokedAt: '2024-10-24T10:00:00Z'
    },
    {
        id: 'TL-104',
        orderId: 'OP-8495',
        token: 'hard-expired-token',
        state: 'hard_expired',
        expiresAt: '2024-01-01T23:59:59Z',
        createdAt: '2023-12-01T09:00:00Z',
    }
];

export const MOCK_INTERNAL_TRACKING_LIST = [
    { id: 'OP-8492', client: 'Autopartes de México', route: 'Laredo → MTY', link: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', status: 'in_transit', lastLocation: 'Ciénega de Flores, N.L.', lastUpdate: '12:47', linkState: 'active' as const, expiresAt: '2026-10-31T23:59:59Z' },
    { id: 'OP-8493', client: 'ElectroTech R', route: 'Querétaro → CDMX', link: 'b2c3d4e5-f6a7-8901-bcde-f12345678901', status: 'in_transit', lastLocation: 'Tepotzotlán, Méx.', lastUpdate: '11:20', linkState: 'soft_expired' as const, expiresAt: '2024-10-23T23:59:59Z' },
    { id: 'OP-8494', client: 'Global Logistics', route: 'Manzanillo → GDL', link: 'c3d4e5f6-a7b8-9012-cdef-123456789012', status: 'delivered', lastLocation: 'Guadalajara, Jal.', lastUpdate: 'Ayer', linkState: 'revoked' as const, expiresAt: '2026-10-31T23:59:59Z' },
];

import type { PublicTrackingResponse } from '@/types/tracking';

export function getMockPublicTracking(token: string): PublicTrackingResponse {
    const link = MOCK_TRACKING_LINKS.find(l => l.token === token);

    if (!link) {
        return { status: 'not_found' };
    }

    // Server-side enforcement equivalent
    if (link.state === 'revoked') {
        return { status: 'revoked' };
    }

    if (link.state === 'hard_expired') {
        return { status: 'hard_expired' };
    }

    // For soft_expired or active, we return the view
    // GEO-01: In a real app, coordinates are rounded here before sending to frontend.
    // We simulate this by directly using the already rounded MOCK_PUBLIC_TRACKING_VIEW.
    const isSoftExpired = link.state === 'soft_expired';

    return {
        status: isSoftExpired ? 'soft_expired' : 'success',
        data: {
            ...MOCK_PUBLIC_TRACKING_VIEW,
            orderRef: link.orderId
        }
    };
}

import type { DriverTrackingResponse, DriverEventPayload } from '@/types/tracking';

const mockDriverState = {
    currentStatus: 'assigned' as 'assigned' | 'in_transit' | 'at_destination' | 'delivered',
    lastEvent: undefined as { municipality: string; timestamp: string } | undefined
};

export async function getMockDriverView(token: string): Promise<DriverTrackingResponse> {
    await new Promise(resolve => setTimeout(resolve, 800));

    if (token !== 'driver-test-auth' && token !== 'test-token') {
        return { status: 'not_found' };
    }

    return {
        status: 'success',
        data: {
            orderRef: 'ROT-24-001',
            route: 'Laredo → Monterrey',
            currentStatus: mockDriverState.currentStatus,
            eta: mockDriverState.currentStatus === 'delivered' ? undefined : 'Hoy, 14:00',
            clientName: 'Juan P.',
            destinationCity: 'Monterrey, Centro',
            lastEvent: mockDriverState.lastEvent
        }
    };
}

export async function postMockDriverEvent(payload: DriverEventPayload): Promise<{ accepted: boolean; reason?: string }> {
    await new Promise(resolve => setTimeout(resolve, 800));

    const timestamp = payload.clientTimestamp || new Date().toISOString();
    let municipality = '';
    let state = '';

    if (payload.location?.source === 'manual' && payload.manualPlace) {
        municipality = payload.manualPlace.municipality;
        state = payload.manualPlace.state;
    } else if (payload.location?.source === 'none') {
        municipality = 'Ubicación Desconocida';
        state = '---';
    } else if (payload.location) {
        // mock geocoding logic
        if (payload.action === 'departure') {
            municipality = 'Nuevo Laredo'; state = 'Tamaulipas';
        } else if (payload.action === 'arrival' || payload.action === 'delivered') {
            municipality = 'Monterrey'; state = 'Nuevo León';
        } else {
            // Simulate moving
            const steps = ['Ciénega de Flores', 'General Zuazua', 'San Nicolás'];
            municipality = steps[Math.floor(Math.random() * steps.length)];
            state = 'Nuevo León';
        }
    }

    const placeStr = `${municipality}, ${state}`;

    // anti-ruido (DEDUP-01) - allow manual selection to repeat according to spec V2
    if (payload.action === 'in_transit' && payload.location?.source !== 'manual') {
        if (mockDriverState.lastEvent?.municipality === placeStr) {
            return { accepted: false, reason: 'same_municipality' };
        }
    }

    if (payload.action === 'departure') {
        mockDriverState.currentStatus = 'in_transit';
    } else if (payload.action === 'arrival') {
        mockDriverState.currentStatus = 'at_destination';
    } else if (payload.action === 'delivered') {
        mockDriverState.currentStatus = 'delivered';
    }

    let title = '';
    let statusText = '';
    let icon = 'map-pin';

    if (payload.action === 'departure') {
        title = 'Salida de Almacén';
        statusText = 'En Tránsito';
        icon = 'truck';
    } else if (payload.action === 'in_transit') {
        title = 'En camino';
        statusText = 'En Tránsito';
    } else if (payload.action === 'arrival') {
        title = 'En punto de entrega';
        statusText = 'En Destino';
        icon = 'map-pin';
    } else if (payload.action === 'delivered') {
        title = 'Entregado';
        statusText = 'Entregado';
        icon = 'check-circle';
    } else if (payload.action === 'incident') {
        title = 'Retraso reportado';
        statusText = mockDriverState.currentStatus === 'assigned' ? 'Asignado' : mockDriverState.currentStatus === 'in_transit' ? 'En Tránsito' : 'En Destino';
        icon = 'alert-triangle';
    }

    if (municipality && municipality !== 'Ubicación Desconocida' && payload.action !== 'incident') {
        mockDriverState.lastEvent = {
            municipality: placeStr,
            timestamp: timestamp
        };
    }

    // append to timeline public mock
    const timeStr = new Date(timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    let subtitle = `Reportado a las ${timeStr}`;
    if (municipality && municipality !== 'Ubicación Desconocida' && state !== '---') {
        subtitle = `${municipality}, ${state} · ${timeStr}`;
    }

    MOCK_PUBLIC_TIMELINE_EVENTS.forEach(e => {
        if (e.status === 'current') e.status = 'done';
    });

    MOCK_PUBLIC_TIMELINE_EVENTS.push({
        id: 'evt-mock-' + Date.now(),
        title,
        subtitle,
        timestamp,
        status: payload.action === 'delivered' ? 'done' : 'current',
        icon
    });

    if (payload.action !== 'incident') {
        MOCK_PUBLIC_TRACKING_VIEW.currentStatus = statusText;
    }

    return { accepted: true };
}
