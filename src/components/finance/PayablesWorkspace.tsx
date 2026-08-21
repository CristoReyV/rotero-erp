import { AccountsWorkspace } from './AccountsWorkspace';
import type { AccountsWorkspaceProps } from './AccountsWorkspace';
export function PayablesWorkspace(props: Omit<AccountsWorkspaceProps, 'direction'>) { return <AccountsWorkspace {...props} direction="ap" />; }
