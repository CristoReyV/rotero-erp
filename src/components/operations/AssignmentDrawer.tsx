import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Calendar as CalendarIcon, Truck, UserCircle, Loader2, AlertCircle } from 'lucide-react';
import type { Operation } from '@/types/operations';
import { assignOperation } from '@/services/operations.service';
import { useAuthStore } from '@/store/authStore';

interface AssignmentDrawerProps {
    isOpen: boolean;
    onClose: () => void;
    operation: Operation | null;
    onAssigned: () => void;
}

export const AssignmentDrawer: React.FC<AssignmentDrawerProps> = ({
    isOpen,
    onClose,
    operation,
    onAssigned
}) => {
    const activeTenant = useAuthStore((s) => s.activeTenant);

    // Form state
    const [driverId, setDriverId] = useState('');
    const [vehicleId, setVehicleId] = useState('');
    const [plannedDeparture, setPlannedDeparture] = useState('');
    const [priority, setPriority] = useState('normal');

    const [isSubmitting, setIsSubmitting] = useState(false);
    const [error, setError] = useState('');

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');

        if (!activeTenant || !operation?.db_id) {
            setError('Falta ID de operación o tenant');
            return;
        }

        if (!driverId || !vehicleId || !plannedDeparture) {
            setError('Por favor completa todos los campos obligatorios');
            return;
        }

        setIsSubmitting(true);
        try {
            // Find names from select options or use fallback
            const driverName = document.querySelector(`select[name="driver_id"] option[value="${driverId}"]`)?.textContent?.split(' (')[0] || 'Conductor Asignado';
            const vehicleRef = document.querySelector(`select[name="vehicle_id"] option[value="${vehicleId}"]`)?.textContent?.split(' (')[0] || 'Unidad Asignada';

            await assignOperation(activeTenant, operation.db_id, {
                driver_id: driverId,
                vehicle_id: vehicleId,
                driver_name: driverName,
                vehicle_ref: vehicleRef,
                planned_departure: new Date(plannedDeparture).toISOString(),
                priority
            });
            onAssigned();
        } catch (err: any) {
            setError(err.message || 'Error al asignar operación');
        } finally {
            setIsSubmitting(false);
        }
    };

    // Reset when operation changes
    React.useEffect(() => {
        if (operation) {
            setDriverId(operation.driver_id || '');
            setVehicleId(operation.vehicle_id || '');

            // Format datetime logic mapping
            if (operation.planned_departure) {
                // If the DB has ISO string, chop off the Z and seconds for datetime-local
                try {
                    const d = new Date(operation.planned_departure);
                    const formatted = new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
                    setPlannedDeparture(formatted);
                } catch {
                    setPlannedDeparture('');
                }
            } else {
                setPlannedDeparture('');
            }

            setPriority(operation.priority || 'normal');
            setError('');
        }
    }, [operation, isOpen]);

    return (
        <AnimatePresence>
            {isOpen && operation && (
                <div className="fixed inset-y-0 right-0 z-50 flex items-center justify-center bg-slate-900/20 backdrop-blur-sm p-4 w-full">
                    {/* Backdrop */}
                    <motion.div
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        exit={{ opacity: 0 }}
                        className="fixed inset-0"
                        onClick={onClose}
                    />

                    <motion.div
                        initial={{ opacity: 0, x: 100 }}
                        animate={{ opacity: 1, x: 0 }}
                        exit={{ opacity: 0, x: 100 }}
                        transition={{ type: 'spring', damping: 25, stiffness: 200 }}
                        className="bg-white h-full shadow-2xl overflow-y-auto w-full max-w-sm absolute right-0 flex flex-col"
                    >
                        {/* Header */}
                        <div className="sticky top-0 bg-white/90 backdrop-blur-md px-6 py-4 border-b border-slate-100 flex items-center justify-between z-10">
                            <div>
                                <h2 className="text-lg font-bold text-slate-800">Asignar Operación</h2>
                                <p className="text-xs text-slate-500 font-mono mt-0.5">{operation.id}</p>
                            </div>
                            <button onClick={onClose} className="text-slate-400 hover:text-slate-600 bg-slate-50 p-2 rounded-lg transition-colors">
                                <X size={16} />
                            </button>
                        </div>

                        {/* Content */}
                        <form onSubmit={handleSubmit} className="p-6 space-y-6 flex-1 flex flex-col">
                            {error && (
                                <div className="p-3 bg-red-50 text-red-600 border border-red-200 rounded-xl text-xs font-semibold flex items-center gap-2">
                                    <AlertCircle size={14} className="shrink-0" />
                                    <span>{error}</span>
                                </div>
                            )}

                            {/* Informative text depending on status */}
                            {operation.status === 'assigned' && (
                                <div className="p-3 bg-amber-50 border border-amber-200 rounded-xl mb-2">
                                    <p className="text-xs font-semibold text-amber-800">
                                        Esta operación ya está asignada. Editar cambiará al responsable en campo.
                                    </p>
                                </div>
                            )}

                            <div className="space-y-4 flex-1">
                                {/* Driver Selection */}
                                <div>
                                    <label className="flex items-center gap-2 text-xs font-bold text-slate-500 uppercase tracking-wider mb-2">
                                        <UserCircle size={14} /> Conductor
                                    </label>
                                    <select
                                        name="driver_id"
                                        required
                                        value={driverId}
                                        onChange={(e) => setDriverId(e.target.value)}
                                        className="w-full px-3 py-2.5 bg-slate-50 border border-slate-200 rounded-lg text-sm text-slate-700 focus:outline-none focus:ring-2 focus:ring-primary/20 appearance-none font-medium"
                                    >
                                        <option value="" disabled>Seleccionar Conductor...</option>
                                        <option value="b1f50123-1111-4444-a1a1-999999990001">Miguel Hernández (Disponible)</option>
                                        <option value="b1f50123-1111-4444-a1a1-999999990002">Juan Carlos Pérez (En Tránsito)</option>
                                        <option value="b1f50123-1111-4444-a1a1-999999990003">Roberto Gómez (Descanso)</option>
                                    </select>
                                </div>

                                {/* Vehicle Selection */}
                                <div>
                                    <label className="flex items-center gap-2 text-xs font-bold text-slate-500 uppercase tracking-wider mb-2">
                                        <Truck size={14} /> Unidad / Tracto
                                    </label>
                                    <select
                                        name="vehicle_id"
                                        required
                                        value={vehicleId}
                                        onChange={(e) => setVehicleId(e.target.value)}
                                        className="w-full px-3 py-2.5 bg-slate-50 border border-slate-200 rounded-lg text-sm text-slate-700 focus:outline-none focus:ring-2 focus:ring-primary/20 appearance-none font-medium"
                                    >
                                        <option value="" disabled>Seleccionar Unidad...</option>
                                        <option value="c2a60123-2222-5555-b2b2-888888880001">Volvo VNL (Eco-01) - 53ft</option>
                                        <option value="c2a60123-2222-5555-b2b2-888888880002">Kenworth T680 (Eco-02) - Caja Seca</option>
                                        <option value="c2a60123-2222-5555-b2b2-888888880003">Freightliner Cascadia (Eco-03) - Plana</option>
                                    </select>
                                </div>

                                {/* Departure Date */}
                                <div>
                                    <label className="flex items-center gap-2 text-xs font-bold text-slate-500 uppercase tracking-wider mb-2">
                                        <CalendarIcon size={14} /> Salida Planeada
                                    </label>
                                    <input
                                        required
                                        type="datetime-local"
                                        value={plannedDeparture}
                                        onChange={(e) => setPlannedDeparture(e.target.value)}
                                        className="w-full px-3 py-2.5 bg-slate-50 border border-slate-200 rounded-lg text-sm text-slate-700 focus:outline-none focus:ring-2 focus:ring-primary/20 font-medium"
                                    />
                                </div>

                                {/* Priority */}
                                <div>
                                    <label className="flex items-center gap-2 text-xs font-bold text-slate-500 uppercase tracking-wider mb-2">
                                        Prioridad
                                    </label>
                                    <div className="grid grid-cols-3 gap-2">
                                        <button
                                            type="button"
                                            onClick={() => setPriority('low')}
                                            className={`py-2 rounded-lg text-xs font-bold border transition-colors ${priority === 'low' ? 'bg-blue-50 border-blue-200 text-blue-700' : 'bg-white border-slate-200 text-slate-500 hover:bg-slate-50'}`}
                                        >
                                            Baja
                                        </button>
                                        <button
                                            type="button"
                                            onClick={() => setPriority('normal')}
                                            className={`py-2 rounded-lg text-xs font-bold border transition-colors ${priority === 'normal' ? 'bg-primary/5 border-primary/20 text-primary' : 'bg-white border-slate-200 text-slate-500 hover:bg-slate-50'}`}
                                        >
                                            Normal
                                        </button>
                                        <button
                                            type="button"
                                            onClick={() => setPriority('high')}
                                            className={`py-2 rounded-lg text-xs font-bold border transition-colors ${priority === 'high' ? 'bg-red-50 border-red-200 text-red-700' : 'bg-white border-slate-200 text-slate-500 hover:bg-slate-50'}`}
                                        >
                                            Alta
                                        </button>
                                    </div>
                                </div>
                            </div>

                            {/* Footer Actions */}
                            <div className="pt-4 border-t border-slate-100 mt-6 flex gap-3">
                                <button
                                    type="button"
                                    onClick={onClose}
                                    className="flex-1 py-2.5 bg-slate-100 hover:bg-slate-200 text-slate-600 text-sm font-semibold rounded-xl transition-colors"
                                >
                                    Cancelar
                                </button>
                                <button
                                    type="submit"
                                    disabled={isSubmitting}
                                    className="flex-[2] py-2.5 bg-primary hover:bg-primary-dark text-white text-sm font-semibold rounded-xl shadow-md shadow-primary/20 transition-all flex items-center justify-center gap-2 disabled:opacity-50"
                                >
                                    {isSubmitting && <Loader2 size={16} className="animate-spin" />}
                                    Confirmar Asignación
                                </button>
                            </div>
                        </form>
                    </motion.div>
                </div>
            )}
        </AnimatePresence>
    );
};
