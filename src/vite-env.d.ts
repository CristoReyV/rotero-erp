/// <reference types="vite/client" />

// Tracking Edge Function variables
interface ImportMetaEnv {
    readonly VITE_TRACKING_EDGE_BASE_URL: string;
    readonly VITE_USE_MOCKS: string;
    readonly VITE_SUPABASE_URL: string;
    readonly VITE_SUPABASE_ANON_KEY: string;
    readonly VITE_PUBLIC_APP_URL?: string;
    // Add other VITE_ variables here as needed
}

interface ImportMeta {
    readonly env: ImportMetaEnv;
}
