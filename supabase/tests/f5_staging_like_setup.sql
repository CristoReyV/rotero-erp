\set ON_ERROR_STOP on

-- Reproduce the catalog contract observed on staging immediately before F5.
CREATE TABLE public.internal_notification_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    trigger_type text NOT NULL,
    target_role text NOT NULL,
    area text,
    lead_days integer NOT NULL DEFAULT 0,
    is_enabled boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT internal_notification_rules_role_check CHECK (target_role IN ('admin','operator','finance','viewer')),
    CONSTRAINT internal_notification_rules_area_check CHECK (area IS NULL OR area IN ('operations','commercial','finance','billing','documents','payroll','provider','admin')),
    CONSTRAINT internal_notification_rules_trigger_check CHECK (trigger_type IN ('daily_control_critical','daily_control_high','daily_control_overdue','invoice_due','fiscal_workbench','payroll_pending')),
    CONSTRAINT internal_notification_rules_lead_days_check CHECK (lead_days BETWEEN 0 AND 30)
);
CREATE INDEX internal_notification_rules_tenant_role_idx
    ON public.internal_notification_rules(tenant_id,target_role,is_enabled);
CREATE UNIQUE INDEX internal_notification_rules_unique_idx
    ON public.internal_notification_rules(tenant_id,trigger_type,target_role,COALESCE(area,'*'));

CREATE TABLE public.internal_notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    fingerprint text NOT NULL,
    trigger_type text NOT NULL,
    area text NOT NULL,
    priority text NOT NULL DEFAULT 'medium',
    icon text NOT NULL DEFAULT 'info',
    title text NOT NULL,
    body text NOT NULL DEFAULT '',
    route text,
    related_entity_type text,
    related_entity_id text,
    status text NOT NULL DEFAULT 'unread',
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    read_at timestamptz,
    dismissed_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT internal_notifications_area_check CHECK (area IN ('operations','commercial','finance','billing','documents','payroll','provider','admin')),
    CONSTRAINT internal_notifications_trigger_check CHECK (trigger_type IN ('daily_control_critical','daily_control_high','daily_control_overdue','invoice_due','fiscal_workbench','payroll_pending')),
    CONSTRAINT internal_notifications_priority_check CHECK (priority IN ('critical','high','medium','low')),
    CONSTRAINT internal_notifications_icon_check CHECK (icon IN ('info','warning','success','truck')),
    CONSTRAINT internal_notifications_status_check CHECK (status IN ('unread','read','dismissed')),
    CONSTRAINT internal_notifications_user_fingerprint_unique UNIQUE (tenant_id,user_id,fingerprint)
);
CREATE INDEX internal_notifications_user_feed_idx
    ON public.internal_notifications(tenant_id,user_id,status,last_seen_at DESC);

ALTER TABLE public.internal_notification_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.internal_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.internal_notification_rules,public.internal_notifications FROM PUBLIC,anon,authenticated,service_role;

DO $fixture$
DECLARE
    v_tenant uuid:=gen_random_uuid();
    v_admin uuid:=gen_random_uuid();
    v_finance uuid:=gen_random_uuid();
BEGIN
    INSERT INTO auth.users(instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
      ('00000000-0000-0000-0000-000000000000',v_admin,'authenticated','authenticated','f5-stage-admin@example.invalid',now(),'{}','{}',now(),now()),
      ('00000000-0000-0000-0000-000000000000',v_finance,'authenticated','authenticated','f5-stage-finance@example.invalid',now(),'{}','{}',now(),now());
    INSERT INTO public.tenants(id,name,slug) VALUES(v_tenant,'F5 staging-like','f5-staging-like');
    INSERT INTO public.memberships(tenant_id,user_id,role) VALUES(v_tenant,v_admin,'admin'),(v_tenant,v_finance,'finance');

    INSERT INTO public.internal_notification_rules(tenant_id,trigger_type,target_role,area,lead_days,is_enabled)
    SELECT v_tenant,
           (ARRAY['daily_control_critical','daily_control_high','daily_control_overdue','invoice_due','fiscal_workbench','payroll_pending'])[1+((i-1)%6)],
           (ARRAY['admin','operator','finance','viewer'])[1+((i-1)%4)],
           (ARRAY[NULL,'operations','commercial','finance','billing','documents','payroll','provider','admin']::text[])[1+((i-1)%9)],
           (i-1)%31,true
    FROM generate_series(1,36) AS s(i);
    INSERT INTO public.internal_notification_rules(tenant_id,trigger_type,target_role,area,lead_days,is_enabled) VALUES
      (v_tenant,'daily_control_high','admin',NULL,1,true),
      (v_tenant,'daily_control_critical','operator','operations',2,true),
      (v_tenant,'daily_control_critical','finance','commercial',3,true),
      (v_tenant,'daily_control_critical','viewer','finance',4,false);

    INSERT INTO public.internal_notifications(
        tenant_id,user_id,fingerprint,trigger_type,area,priority,icon,title,body,route,
        related_entity_type,related_entity_id,status,first_seen_at,last_seen_at,read_at,dismissed_at,metadata
    )
    SELECT v_tenant,v_admin,'legacy:'||i,
           (ARRAY['daily_control_critical','daily_control_high','daily_control_overdue','invoice_due','fiscal_workbench','payroll_pending'])[1+((i-1)%6)],
           (ARRAY['operations','commercial','finance','billing','documents','payroll','provider','admin'])[1+((i-1)%8)],
           (ARRAY['critical','high','medium','low'])[1+((i-1)%4)],
           (ARRAY['info','warning','success','truck'])[1+((i-1)%4)],
           'Legacy notification '||i,'Preserved body '||i,'/legacy/'||i,'legacy_entity','legacy-'||i,
           (ARRAY['unread','read','dismissed'])[1+((i-1)%3)],
           now()-make_interval(hours=>i),now()-make_interval(mins=>i),
           CASE WHEN i%3=2 THEN now()-make_interval(mins=>i) END,
           CASE WHEN i%3=0 THEN now()-make_interval(mins=>i) END,
           jsonb_build_object('legacy',true,'ordinal',i)
    FROM generate_series(1,21) AS s(i);
END;
$fixture$;

CREATE OR REPLACE FUNCTION public.rpc_list_internal_notifications(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
    SELECT jsonb_build_object('items',COALESCE(jsonb_agg(to_jsonb(n) ORDER BY n.last_seen_at DESC),'[]'::jsonb))
    FROM (
        SELECT id,trigger_type,area,priority,title,status,first_seen_at,last_seen_at
        FROM public.internal_notifications
        WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid())
          AND (COALESCE(p_filters->>'status','')='' OR status=p_filters->>'status')
    ) n;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_mark_internal_notifications_read(p_tenant_id uuid,p_notification_ids uuid[] DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE v_count integer;
BEGIN
    UPDATE public.internal_notifications SET status='read',read_at=COALESCE(read_at,now())
    WHERE tenant_id=p_tenant_id AND user_id=(SELECT auth.uid()) AND (p_notification_ids IS NULL OR id=ANY(p_notification_ids));
    GET DIAGNOSTICS v_count=ROW_COUNT;
    RETURN jsonb_build_object('success',true,'updated',v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_get_executive_dashboard(p_tenant_id uuid,p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public
AS $function$
    SELECT jsonb_build_object('tenant_id',p_tenant_id,'filters',COALESCE(p_filters,'{}'::jsonb));
$function$;

CREATE OR REPLACE FUNCTION public.rpc_dismiss_internal_notification(p_notification_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $function$
DECLARE v_count integer;
BEGIN
    UPDATE public.internal_notifications SET status='dismissed',dismissed_at=COALESCE(dismissed_at,now())
    WHERE id=p_notification_id AND user_id=(SELECT auth.uid());
    GET DIAGNOSTICS v_count=ROW_COUNT;
    RETURN CASE WHEN v_count=1 THEN jsonb_build_object('success',true) ELSE jsonb_build_object('error','not_found') END;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.rpc_list_internal_notifications(uuid,jsonb) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_mark_internal_notifications_read(uuid,uuid[]) FROM PUBLIC,anon,service_role;
REVOKE EXECUTE ON FUNCTION public.rpc_dismiss_internal_notification(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_list_internal_notifications(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_mark_internal_notifications_read(uuid,uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_dismiss_internal_notification(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_get_executive_dashboard(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_executive_dashboard(uuid,jsonb) TO authenticated,service_role;

-- Capture the exact pre-F5 identities and signature metadata. CREATE OR REPLACE
-- must preserve these OIDs and may not rename parameters or alter defaults.
CREATE TABLE private.f5_staging_like_rpc_snapshot (
    identity text PRIMARY KEY,
    function_oid oid NOT NULL,
    signature jsonb NOT NULL
);

INSERT INTO private.f5_staging_like_rpc_snapshot(identity,function_oid,signature)
SELECT format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)),
       p.oid,
       jsonb_build_object(
           'arg_names',to_jsonb(p.proargnames),
           'input_types',to_jsonb(p.proargtypes::regtype[]::text[]),
           'all_arg_types',CASE WHEN p.proallargtypes IS NULL THEN NULL ELSE
               (SELECT jsonb_agg(t::regtype::text ORDER BY ordinal)
                FROM unnest(p.proallargtypes) WITH ORDINALITY AS args(t,ordinal)) END,
           'arg_modes',to_jsonb(p.proargmodes),
           'default_count',p.pronargdefaults,
           'identity_arguments',pg_get_function_identity_arguments(p.oid),
           'arguments',pg_get_function_arguments(p.oid),
           'result',pg_get_function_result(p.oid)
       )
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.oid=ANY(ARRAY[
    'public.rpc_list_internal_notifications(uuid,jsonb)'::regprocedure::oid,
    'public.rpc_mark_internal_notifications_read(uuid,uuid[])'::regprocedure::oid,
    'public.rpc_dismiss_internal_notification(uuid)'::regprocedure::oid,
    'public.rpc_get_executive_dashboard(uuid,jsonb)'::regprocedure::oid,
    'public.rpc_get_operation_dispatch_readiness(uuid)'::regprocedure::oid
]);

REVOKE ALL ON TABLE private.f5_staging_like_rpc_snapshot FROM PUBLIC,anon,authenticated,service_role;
