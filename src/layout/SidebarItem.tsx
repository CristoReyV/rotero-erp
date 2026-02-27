import { NavLink } from 'react-router-dom';
import type { LucideIcon } from 'lucide-react';

interface SidebarItemProps {
    key?: string | number;
    icon: LucideIcon;
    label: string;
    to: string;
    collapsed?: boolean;
}

export const SidebarItem = ({ icon: Icon, label, to, collapsed }: SidebarItemProps) => (
    <NavLink
        to={to}
        className={({ isActive }) =>
            `relative flex items-center gap-3 mx-3 px-3 py-2.5 rounded-xl text-[13px] font-medium transition-all duration-250 group
      ${isActive
                ? 'bg-white/12 text-white shadow-lg shadow-black/10'
                : 'text-slate-400 hover:bg-white/6 hover:text-slate-200'
            }`
        }
    >
        {({ isActive }) => (
            <>
                {isActive && (
                    <div className="absolute left-0 top-1/2 -translate-y-1/2 w-[3px] h-5 bg-accent-red rounded-r-full" />
                )}
                <div className={`flex items-center justify-center w-8 h-8 rounded-lg transition-all duration-200
          ${isActive ? 'bg-white/10' : 'group-hover:bg-white/5'}`}>
                    <Icon size={18} strokeWidth={isActive ? 2.2 : 1.8} />
                </div>
                {!collapsed && (
                    <span className="truncate">{label}</span>
                )}
            </>
        )}
    </NavLink>
);
