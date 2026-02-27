export type BadgeVariant = 'default' | 'success' | 'warning' | 'danger' | 'info';

/**
 * Base entity fields for all Supabase tables.
 * NOT used in mocks — applied when backend is connected.
 * Ref: RT-01, CD-06
 */
export interface BaseEntity {
  id: string;
  tenant_id: string;
  created_at: string;
  updated_at: string;
  created_by: string;
  is_deleted?: boolean;
}
