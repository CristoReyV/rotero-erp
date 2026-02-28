export const APP_MODE = import.meta.env.VITE_APP_MODE ?? "prod";
export const isDemo = APP_MODE === "demo";
export const isProd = APP_MODE === "prod";
