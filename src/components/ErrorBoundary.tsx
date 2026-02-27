import React, { ErrorInfo, ReactNode } from 'react';
import { AlertCircle, RefreshCcw } from 'lucide-react';

interface Props {
    children?: ReactNode;
}

interface State {
    hasError: boolean;
    error: Error | null;
}

export class ErrorBoundary extends React.Component<Props, State> {
    public props: Props;
    public state: State = {
        hasError: false,
        error: null
    };

    public static getDerivedStateFromError(error: Error): State {
        return { hasError: true, error };
    }

    public componentDidCatch(error: Error, errorInfo: ErrorInfo) {
        console.error('Uncaught error:', error, errorInfo);
    }

    private handleReset = () => {
        window.location.reload();
    };

    public render() {
        if (this.state.hasError) {
            return (
                <div className="min-h-screen bg-slate-50 flex flex-col items-center justify-center p-6 text-center">
                    <div className="w-16 h-16 bg-red-100 text-red-600 rounded-2xl flex items-center justify-center mb-6 shadow-sm border border-red-200">
                        <AlertCircle size={32} />
                    </div>
                    <h1 className="text-2xl font-bold text-slate-800 mb-2">Algo salió mal</h1>
                    <p className="text-slate-500 max-w-md mx-auto mb-8 text-sm">
                        Ocurrió un error inesperado al cargar la interfaz. Hemos registrado el problema.
                    </p>
                    <div className="bg-white p-4 rounded-xl border border-slate-200 text-left w-full max-w-lg mb-8 overflow-auto">
                        <code className="text-xs text-slate-600 block">{this.state.error?.toString()}</code>
                    </div>
                    <button
                        onClick={this.handleReset}
                        className="flex items-center gap-2 px-6 py-3 bg-slate-800 text-white font-semibold rounded-xl hover:bg-slate-700 transition-all shadow-md active:scale-95"
                    >
                        <RefreshCcw size={16} />
                        Recargar aplicación
                    </button>
                </div>
            );
        }

        return (this.props as any).children;
    }
}
