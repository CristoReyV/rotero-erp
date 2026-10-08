import { Outlet, useLocation } from 'react-router-dom';
import { motion, AnimatePresence } from 'motion/react';
import { Sidebar } from './Sidebar';
import { Topbar } from './Topbar';

export const AppLayout = () => {
    const { pathname } = useLocation();

    return (
        <div className="flex h-dvh min-h-0 min-w-0 max-w-full overflow-hidden bg-surface">
            <Sidebar />
            <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
                <div className="pl-12 lg:pl-0">
                    <Topbar />
                </div>
                <main className="min-w-0 flex-1 overflow-y-auto overflow-x-clip p-3 min-[360px]:p-4 lg:p-8">
                    <AnimatePresence mode="wait">
                        <motion.div
                            key={pathname}
                            initial={{ opacity: 0, y: 12 }}
                            animate={{ opacity: 1, y: 0 }}
                            exit={{ opacity: 0, y: -8 }}
                            transition={{ duration: 0.25, ease: [0.25, 0.46, 0.45, 0.94] }}
                            className="h-full min-w-0 max-w-full"
                        >
                            <Outlet />
                        </motion.div>
                    </AnimatePresence>
                </main>
            </div>
        </div>
    );
};
