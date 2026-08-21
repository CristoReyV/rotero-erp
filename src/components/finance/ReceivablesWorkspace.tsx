import { AccountsWorkspace } from './AccountsWorkspace';
import type { AccountsWorkspaceProps } from './AccountsWorkspace';
export function ReceivablesWorkspace(props: Omit<AccountsWorkspaceProps, 'direction'>) { return <AccountsWorkspace {...props} direction="ar" />; }
