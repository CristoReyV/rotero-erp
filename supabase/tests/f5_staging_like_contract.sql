\set ON_ERROR_STOP on

DO $catalog$
DECLARE v_tenant uuid; v_rules integer; v_notifications integer;
BEGIN
    SELECT id INTO v_tenant FROM public.tenants WHERE slug='f5-staging-like';
    SELECT count(*) INTO v_rules FROM public.internal_notification_rules WHERE tenant_id=v_tenant;
    SELECT count(*) INTO v_notifications FROM public.internal_notifications WHERE tenant_id=v_tenant AND fingerprint LIKE 'legacy:%';
    IF v_rules<>58 THEN RAISE EXCEPTION 'staging-like rule count changed: %',v_rules; END IF;
    IF v_notifications<>21 THEN RAISE EXCEPTION 'legacy notifications changed: %',v_notifications; END IF;
    IF (SELECT count(*) FROM public.internal_notification_rules WHERE tenant_id=v_tenant AND trigger_type IN ('daily_control_critical','daily_control_high','daily_control_overdue','invoice_due','fiscal_workbench','payroll_pending'))<>40 THEN
        RAISE EXCEPTION 'legacy rules were not preserved';
    END IF;
    IF (SELECT count(*) FROM public.internal_notification_rules WHERE tenant_id=v_tenant AND trigger_type NOT IN ('daily_control_critical','daily_control_high','daily_control_overdue','invoice_due','fiscal_workbench','payroll_pending'))<>18 THEN
        RAISE EXCEPTION 'F5 rule seed is not idempotent';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.internal_notification_rules WHERE tenant_id=v_tenant AND target_role='operator')
       OR NOT EXISTS (SELECT 1 FROM public.internal_notification_rules WHERE tenant_id=v_tenant AND target_role='viewer')
       OR NOT EXISTS (SELECT 1 FROM public.internal_notification_rules WHERE tenant_id=v_tenant AND area IS NULL) THEN
        RAISE EXCEPTION 'historical role/area coverage was reduced';
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='internal_notification_rules' AND column_name IN ('role','module','kind','enabled')
    ) OR EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='internal_notifications' AND column_name IN ('module','kind','entity_type','entity_id','occurred_at','created_at','updated_at')
    ) THEN RAISE EXCEPTION 'parallel F5 notification schema remains'; END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='internal_notification_rules' AND column_name='priority')
       OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='internal_notifications' AND column_name='due_at') THEN
        RAISE EXCEPTION 'minimal F5 extensions missing';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.internal_notification_rules
        GROUP BY tenant_id,trigger_type,target_role,COALESCE(area,'*') HAVING count(*)>1
    ) THEN RAISE EXCEPTION 'duplicate canonical rule identity'; END IF;
END;
$catalog$;

BEGIN;
DO $context$
DECLARE v_tenant uuid; v_admin uuid; v_legacy uuid;
BEGIN
    SELECT id INTO v_tenant FROM public.tenants WHERE slug='f5-staging-like';
    SELECT user_id INTO v_admin FROM public.memberships WHERE tenant_id=v_tenant AND role='admin' LIMIT 1;
    SELECT id INTO v_legacy FROM public.internal_notifications
    WHERE tenant_id=v_tenant AND user_id=v_admin AND status='unread' AND fingerprint LIKE 'legacy:%' LIMIT 1;
    PERFORM set_config('f5_stage.tenant',v_tenant::text,true);
    PERFORM set_config('f5_stage.admin',v_admin::text,true);
    PERFORM set_config('f5_stage.legacy_notification',v_legacy::text,true);
END;
$context$;
SET LOCAL ROLE authenticated;
DO $compatibility$
DECLARE v_tenant uuid; v_admin uuid; v_legacy uuid; v_result jsonb;
BEGIN
    v_tenant:=current_setting('f5_stage.tenant')::uuid;
    v_admin:=current_setting('f5_stage.admin')::uuid;
    v_legacy:=current_setting('f5_stage.legacy_notification')::uuid;
    PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
    v_result:=public.rpc_list_internal_notifications(v_tenant,'{}'::jsonb);
    IF jsonb_array_length(v_result->'items')<>21 THEN RAISE EXCEPTION 'legacy list signature changed: %',v_result; END IF;
    IF public.rpc_mark_internal_notifications_read(v_tenant,ARRAY[v_legacy])->>'success'<>'true' THEN RAISE EXCEPTION 'legacy mark-read signature failed'; END IF;
    IF public.rpc_dismiss_internal_notification(v_legacy)->>'success'<>'true' THEN RAISE EXCEPTION 'legacy dismiss signature failed'; END IF;
    v_result:=public.rpc_list_internal_notifications(v_tenant,100,false);
    IF v_result?'error' OR NOT v_result?'items' OR EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_result->'items') x
        WHERE NOT (x?'module' AND x?'kind' AND x?'entity_type' AND x?'entity_id' AND x?'created_at')
    ) THEN RAISE EXCEPTION 'normalized F5 list contract failed: %',v_result; END IF;
END;
$compatibility$;
ROLLBACK;
