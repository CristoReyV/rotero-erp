import { useSyncExternalStore } from 'react';

interface MediaQueryEntry {
    mediaQuery: MediaQueryList;
    subscribers: Set<() => void>;
    listener: () => void;
}

const entries = new Map<string, MediaQueryEntry>();

function getEntry(query: string): MediaQueryEntry | null {
    if (typeof window === 'undefined') return null;
    const existing = entries.get(query);
    if (existing) return existing;

    const mediaQuery = window.matchMedia(query);
    const subscribers = new Set<() => void>();
    const entry: MediaQueryEntry = {
        mediaQuery,
        subscribers,
        listener: () => subscribers.forEach((subscriber) => subscriber()),
    };
    entries.set(query, entry);
    return entry;
}

export function useMediaQuery(query: string): boolean {
    return useSyncExternalStore(
        (subscriber) => {
            const entry = getEntry(query);
            if (!entry) return () => undefined;
            if (entry.subscribers.size === 0) entry.mediaQuery.addEventListener('change', entry.listener);
            entry.subscribers.add(subscriber);
            return () => {
                entry.subscribers.delete(subscriber);
                if (entry.subscribers.size === 0) entry.mediaQuery.removeEventListener('change', entry.listener);
            };
        },
        () => getEntry(query)?.mediaQuery.matches ?? false,
        () => false,
    );
}

export const MOBILE_MEDIA_QUERY = '(max-width: 767px)';
