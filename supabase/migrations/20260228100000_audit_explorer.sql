-- ============================================================
-- Sprint 3.1: Audit Explorer — Server-side filters + index
-- ============================================================

-- 1) Index for fast tenant+date queries
CREATE INDEX IF NOT EXISTS idx_audit_log_tenant_created
ON audit_log (tenant_id, created_at DESC);

-- 2) Patch rpc_list_audit_log with filter support + pagination
CREATE OR REPLACE FUNCTION public.rpc_list_audit_log(
    p_tenant_id uuid,
    p_limit int DEFAULT 50,
    p_offset int DEFAULT 0,
    p_entity_type text DEFAULT NULL,
    p_action text DEFAULT NULL,
    p_start timestamptz DEFAULT NULL,
    p_end timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM memberships m
        WHERE m.user_id = auth.uid() AND m.tenant_id = p_tenant_id
    ) THEN
        RETURN jsonb_build_object('error', 'unauthorized');
    END IF;

    RETURN (
        SELECT jsonb_build_object(
            'items', COALESCE((
                SELECT jsonb_agg(row_obj ORDER BY created_at DESC)
                FROM (
                    SELECT
                        jsonb_build_object(
                            'id', a.id,
                            'action', a.action,
                            'entity_type', a.entity_type,
                            'entity_id', a.entity_id,
                            'created_at', a.created_at,
                            'metadata', a.metadata,
                            'actor_id', a.actor_user_id,
                            'actor_email', u.email,
                            'actor_name', (u.raw_user_meta_data->>'full_name')
                        ) AS row_obj,
                        a.created_at
                    FROM audit_log a
                    LEFT JOIN auth.users u ON u.id = a.actor_user_id
                    WHERE a.tenant_id = p_tenant_id
                      AND (p_entity_type IS NULL OR a.entity_type = p_entity_type)
                      AND (p_action IS NULL OR a.action = p_action)
                      AND (p_start IS NULL OR a.created_at >= p_start)
                      AND (p_end IS NULL OR a.created_at <= p_end)
                    ORDER BY a.created_at DESC
                    LIMIT p_limit
                    OFFSET p_offset
                ) sub
            ), '[]'::jsonb),
            'total', (
                SELECT count(*)::int
                FROM audit_log a
                WHERE a.tenant_id = p_tenant_id
                  AND (p_entity_type IS NULL OR a.entity_type = p_entity_type)
                  AND (p_action IS NULL OR a.action = p_action)
                  AND (p_start IS NULL OR a.created_at >= p_start)
                  AND (p_end IS NULL OR a.created_at <= p_end)
            ),
            'distinct_entities', (
                SELECT COALESCE(jsonb_agg(DISTINCT a.entity_type), '[]'::jsonb)
                FROM audit_log a WHERE a.tenant_id = p_tenant_id
            ),
            'distinct_actions', (
                SELECT COALESCE(jsonb_agg(DISTINCT a.action), '[]'::jsonb)
                FROM audit_log a WHERE a.tenant_id = p_tenant_id
            )
        )
    );
END;
$$;

NOTIFY pgrst, 'reload schema';
