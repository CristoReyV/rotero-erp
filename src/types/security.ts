export interface UserRecord {
    name: string;
    role: string;
    status: string;
    last: string;
}

export interface AuditLog {
    time: string;
    user: string;
    event: string;
    color: string;
}
