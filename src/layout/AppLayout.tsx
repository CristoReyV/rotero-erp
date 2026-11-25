import { Outlet, useLocation } from 'react-router-dom';
import { AnimatePresence, motion } from 'motion/react';
import { Sidebar } from './Sidebar';
import { Topbar } from './Topbar';
import { CompanyBoundary } from '@/components/company/CompanyBoundary';
import { useCompanyStore } from '@/store/companyStore';

export const AppLayout = () => {
    const { pathname } = useLocation();
    const epoch = useCompanyStore((state) => state.epoch);

    return (
        <div className='flex h-screen bg-surface overflow-hidden'>
            <Sidebar />
            <div className='flex-1 flex flex-col min-w-0 overflow-hidden'>
                <div className='pl-12 lg:pl-0'>
                    <Topbar key={epoch} />
                </div>
                <main className='flex-1 overflow-y-auto p-6 lg:p-8'>
                    <CompanyBoundary>
                        <AnimatePresence mode='wait'>
                            <motion.div
                                key={pathname}
                                initial={{ opacity: 0, y: 12 }}
                                animate={{ opacity: 1, y: 0 }}
                                exit={{ opacity: 0, y: -8 }}
                                transition={{ duration: 0.25, ease: [0.25, 0.46, 0.45, 0.94] }}
                                className='h-full'
                            >
                                <Outlet />
                            </motion.div>
                        </AnimatePresence>
                    </CompanyBoundary>
                </main>
            </div>
        </div>
    );
};
