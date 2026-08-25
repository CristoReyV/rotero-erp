-- BH1 — cross-module integration and runtime reconciliation.
-- This migration intentionally supports both the canonical reset schema and the
-- older staging table shapes. No historical migration or business row is removed.

-- Staging retained the pre-canonical primary_contact_* names while F1/F6 use the
-- canonical contact_* contract. Add a narrow compatibility surface and preserve
-- existing values. Canonical resets already contain these columns, so this is a no-op.
ALTER TABLE public.customers
    ADD COLUMN IF NOT EXISTS contact_name text,
    ADD COLUMN IF NOT EXISTS contact_email text,
    ADD COLUMN IF NOT EXISTS contact_phone text;

ALTER TABLE public.logistics_providers
    ADD COLUMN IF NOT EXISTS contact_name text,
    ADD COLUMN IF NOT EXISTS contact_email text,
    ADD COLUMN IF NOT EXISTS contact_phone text;

DO $migration$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='customers' AND column_name='primary_contact_name'
    ) THEN
        EXECUTE $sql$
            UPDATE public.customers
            SET contact_name=COALESCE(contact_name,primary_contact_name),
                contact_email=COALESCE(contact_email,primary_contact_email),
                contact_phone=COALESCE(contact_phone,primary_contact_phone)
            WHERE (contact_name,contact_email,contact_phone) IS DISTINCT FROM
                  (COALESCE(contact_name,primary_contact_name),COALESCE(contact_email,primary_contact_email),COALESCE(contact_phone,primary_contact_phone))
        $sql$;
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='logistics_providers' AND column_name='primary_contact_name'
    ) THEN
        EXECUTE $sql$
            UPDATE public.logistics_providers
            SET contact_name=COALESCE(contact_name,primary_contact_name),
                contact_email=COALESCE(contact_email,primary_contact_email),
                contact_phone=COALESCE(contact_phone,primary_contact_phone)
            WHERE (contact_name,contact_email,contact_phone) IS DISTINCT FROM
                  (COALESCE(contact_name,primary_contact_name),COALESCE(contact_email,primary_contact_email),COALESCE(contact_phone,primary_contact_phone))
        $sql$;
    END IF;
END
$migration$;

DO $migration$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='customs_descargo_lines' AND column_name='sequence_no') THEN
        ALTER TABLE public.customs_descargo_lines ADD COLUMN sequence_no integer;
        WITH ranked AS (
            SELECT id,row_number() OVER(PARTITION BY pedimento_id ORDER BY created_at,id)::integer AS value
            FROM public.customs_descargo_lines
        )
        UPDATE public.customs_descargo_lines d SET sequence_no=ranked.value FROM ranked WHERE ranked.id=d.id;
        ALTER TABLE public.customs_descargo_lines ALTER COLUMN sequence_no SET NOT NULL;
        ALTER TABLE public.customs_descargo_lines ADD CONSTRAINT customs_descargo_lines_sequence_check CHECK(sequence_no>0);
        CREATE UNIQUE INDEX customs_descargo_lines_pedimento_sequence_uidx ON public.customs_descargo_lines(pedimento_id,sequence_no);
    END IF;
END
$migration$;

CREATE OR REPLACE FUNCTION public.rpc_create_invitation(p_tenant_id uuid, p_email text, p_role text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public, extensions
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_email text := lower(btrim(p_email));
    v_token text;
    v_id uuid;
    v_expires_at timestamptz := now() + interval '7 days';
BEGIN
    IF v_actor IS NULL THEN RETURN jsonb_build_object('accepted',false,'state','authentication_required'); END IF;
    IF p_tenant_id IS NULL OR NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin']) THEN
        RETURN jsonb_build_object('accepted',false,'state','unauthorized');
    END IF;
    IF p_role IS NULL OR p_role NOT IN ('admin','operator','finance','viewer')
       OR v_email IS NULL OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
        RETURN jsonb_build_object('error','invalid_payload');
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant_id::text||':'||v_email,0));
    UPDATE public.invitations SET revoked_at=now(),revoked_by=v_actor
    WHERE tenant_id=p_tenant_id AND email=v_email AND accepted_at IS NULL AND revoked_at IS NULL;
    v_token:=encode(extensions.gen_random_bytes(24),'hex');
    INSERT INTO public.invitations(tenant_id,email,role,token_hash,created_by,expires_at)
    VALUES(p_tenant_id,v_email,p_role,encode(extensions.digest(v_token,'sha256'),'hex'),v_actor,v_expires_at)
    RETURNING id INTO v_id;
    INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata)
    VALUES(p_tenant_id,v_actor,'invitation_created','invitation',v_id,jsonb_build_object('role',p_role));
    RETURN jsonb_build_object('accepted',true,'state','created','invitation_id',v_id,'expires_at',v_expires_at,'token',v_token);
END
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_descargo_lines(p_pedimento_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM public.customs_pedimentos WHERE id=p_pedimento_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator','viewer']) THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    RETURN COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.created_at,d.id)
                     FROM public.customs_descargo_lines d WHERE d.pedimento_id=p_pedimento_id),'[]'::jsonb);
END
$function$;

CREATE OR REPLACE FUNCTION public.rpc_add_descargo_line(p_pedimento_id uuid,p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;v_id uuid;v_sequence integer;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM public.customs_pedimentos WHERE id=p_pedimento_id FOR UPDATE;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT COALESCE(max(d.sequence_no),0)+1 INTO v_sequence FROM public.customs_descargo_lines d WHERE d.pedimento_id=p_pedimento_id;
    INSERT INTO public.customs_descargo_lines(tenant_id,pedimento_id,sequence_no,sku,lot_code,qty,unit,inventory_lot_id)
    VALUES(v_tenant_id,p_pedimento_id,v_sequence,p_payload->>'sku',NULLIF(p_payload->>'lot_code',''),(p_payload->>'qty')::numeric,COALESCE(NULLIF(p_payload->>'unit',''),'Piezas'),NULLIF(p_payload->>'inventory_lot_id','')::uuid)
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('id',v_id);
EXCEPTION WHEN invalid_text_representation OR not_null_violation OR check_violation OR foreign_key_violation THEN
    RETURN jsonb_build_object('error','invalid_payload');
END
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_deal_notes(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM public.crm_deals WHERE id=p_deal_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator','viewer']) THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object('id',n.id,'note',n.note,
            'author_name',u.raw_user_meta_data->>'full_name','created_at',n.created_at) ORDER BY n.created_at DESC)
        FROM public.crm_deal_notes n
        LEFT JOIN auth.users u ON u.id=COALESCE(NULLIF(to_jsonb(n)->>'author_id',''),NULLIF(to_jsonb(n)->>'author_user_id',''))::uuid
        WHERE n.deal_id=p_deal_id
    ),'[]'::jsonb);
END
$function$;

CREATE OR REPLACE FUNCTION public.rpc_list_deal_checklist(p_deal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM public.crm_deals WHERE id=p_deal_id;
    IF v_tenant_id IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
    IF NOT public.tanda1_user_has_role(v_tenant_id,ARRAY['admin','operator','viewer']) THEN
        RETURN jsonb_build_object('error','unauthorized');
    END IF;
    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object('id',c.id,'stage',c.stage,'label',c.label,'is_done',c.is_done,
            'updated_at',COALESCE(to_jsonb(c)->>'updated_at',to_jsonb(c)->>'created_at'))
            ORDER BY COALESCE(to_jsonb(c)->>'created_at',to_jsonb(c)->>'updated_at'),c.id)
        FROM public.crm_deal_checklist_items c WHERE c.deal_id=p_deal_id
    ),'[]'::jsonb);
END
$function$;

CREATE OR REPLACE FUNCTION public.rpc_demo_configure_module(p_tenant_id uuid,p_module_name text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE v_demo boolean;
BEGIN
    IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    SELECT allow_demo_mode INTO v_demo FROM public.tenant_settings WHERE tenant_id=p_tenant_id;
    IF v_demo IS NOT TRUE THEN RETURN jsonb_build_object('error','demo_mode_disabled'); END IF;
    IF p_module_name NOT IN ('inventory','customs','billing') THEN RETURN jsonb_build_object('error','invalid_module'); END IF;
    INSERT INTO public.tenant_setup_status(tenant_id,module_name,is_configured,config_data)
    VALUES(p_tenant_id,p_module_name,true,jsonb_build_object('mode','demo'))
    ON CONFLICT(tenant_id,module_name) DO UPDATE SET is_configured=true,config_data=EXCLUDED.config_data,updated_at=now();
    RETURN jsonb_build_object('success',true);
END
$function$;

-- Older staging-only overloads are not part of the canonical reset. Keep their
-- identities and OIDs, but remove stale schema references and raw SQL errors.
DO $migration$
BEGIN
    IF to_regprocedure('public.rpc_dashboard_overview(uuid)') IS NOT NULL THEN
        EXECUTE $sql$
        CREATE OR REPLACE FUNCTION public.rpc_dashboard_overview(p_tenant_id uuid)
        RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
        AS $body$
        BEGIN
          IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
          RETURN jsonb_build_object('kpis',jsonb_build_object(
            'ops_total',(SELECT count(*) FROM public.operations WHERE tenant_id=p_tenant_id),
            'ops_in_transit',(SELECT count(*) FROM public.operations WHERE tenant_id=p_tenant_id AND status='in_transit'),
            'billing_total',COALESCE((SELECT sum(total) FROM public.billing_cfdis WHERE tenant_id=p_tenant_id AND lower(status)='timbrado'),0),
            'inventory_value',COALESCE((SELECT sum(qty_on_hand*COALESCE(unit_cost,0)) FROM public.inventory_lots WHERE tenant_id=p_tenant_id),0)),
            'chart',jsonb_build_object('data','[]'::jsonb,'labels','[]'::jsonb));
        END $body$
        $sql$;
    END IF;
    IF to_regprocedure('public.rpc_dashboard_recent_activity(uuid,integer)') IS NOT NULL THEN
        EXECUTE $sql$
        CREATE OR REPLACE FUNCTION public.rpc_dashboard_recent_activity(p_tenant_id uuid,p_limit integer DEFAULT 4)
        RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog, public
        AS $body$
        BEGIN
          IF NOT public.tanda1_user_is_member(p_tenant_id) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
          RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id',x.reference_code,'client',COALESCE(x.client_display_name,'N/A'),'status',x.status,'route',COALESCE(x.route_summary,x.destination_city,'N/A'),'eta',COALESCE(x.eta_display,'')) ORDER BY x.updated_at DESC)
            FROM (SELECT * FROM public.operations WHERE tenant_id=p_tenant_id ORDER BY updated_at DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,4),1),50)) x),'[]'::jsonb);
        END $body$
        $sql$;
    END IF;
    IF to_regprocedure('public.rpc_assign_operation(uuid,uuid,uuid,uuid,timestamptz,text,text,text)') IS NOT NULL THEN
        EXECUTE $sql$
        CREATE OR REPLACE FUNCTION public.rpc_assign_operation(p_tenant_id uuid,p_operation_id uuid,p_driver_id uuid,p_vehicle_id uuid,p_planned_departure timestamptz,p_priority text DEFAULT 'normal',p_driver_name text DEFAULT NULL,p_vehicle_ref text DEFAULT NULL)
        RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
        AS $body$
        DECLARE v_tenant uuid;v_status text;
        BEGIN
          IF NOT public.tanda1_user_has_role(p_tenant_id,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
          SELECT tenant_id,status INTO v_tenant,v_status FROM public.operations WHERE id=p_operation_id FOR UPDATE;
          IF v_tenant IS NULL OR v_tenant<>p_tenant_id THEN RETURN jsonb_build_object('error','not_found_or_unauthorized'); END IF;
          IF v_status NOT IN ('draft','planned','assigned') THEN RETURN jsonb_build_object('error','invalid_status_for_assignment'); END IF;
          UPDATE public.operations SET driver_id=p_driver_id,vehicle_id=p_vehicle_id,driver_name=p_driver_name,vehicle_ref=p_vehicle_ref,
            planned_departure=p_planned_departure,priority=p_priority,status='assigned',assigned_at=now(),updated_at=now() WHERE id=p_operation_id;
          INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata)
          VALUES(p_tenant_id,auth.uid(),'operation_assigned_legacy','operation',p_operation_id,jsonb_build_object('old_status',v_status));
          RETURN jsonb_build_object('success',true);
        EXCEPTION WHEN check_violation OR foreign_key_violation OR invalid_text_representation THEN RETURN jsonb_build_object('error','invalid_payload');
          WHEN OTHERS THEN RETURN jsonb_build_object('error','internal_error');
        END $body$
        $sql$;
    END IF;
END
$migration$;

-- Staging-only author/checklist shapes. Dynamic DDL prevents canonical resets
-- from compiling a body against columns that intentionally differ there.
DO $migration$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='crm_deal_notes' AND column_name='author_user_id') THEN
      EXECUTE $sql$
      CREATE OR REPLACE FUNCTION public.rpc_add_deal_note(p_deal_id uuid,p_note text)
      RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
      AS $body$
      DECLARE v_tenant uuid;v_id uuid;
      BEGIN
        SELECT tenant_id INTO v_tenant FROM public.crm_deals WHERE id=p_deal_id;
        IF v_tenant IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
        IF NOT public.tanda1_user_has_role(v_tenant,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
        IF NULLIF(btrim(p_note),'') IS NULL THEN RETURN jsonb_build_object('error','invalid_payload'); END IF;
        INSERT INTO public.crm_deal_notes(tenant_id,deal_id,author_user_id,note) VALUES(v_tenant,p_deal_id,auth.uid(),p_note) RETURNING id INTO v_id;
        INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata)
        VALUES(v_tenant,auth.uid(),'note_added','deal',p_deal_id,jsonb_build_object('note_preview',left(p_note,50)));
        RETURN jsonb_build_object('id',v_id);
      END $body$
      $sql$;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='crm_deal_checklist_items' AND column_name='updated_at')
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='crm_deal_checklist_items' AND column_name='completed_at') THEN
      EXECUTE $sql$
      CREATE OR REPLACE FUNCTION public.rpc_toggle_deal_checklist_item(p_item_id uuid,p_is_done boolean)
      RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog, public
      AS $body$
      DECLARE v_tenant uuid;v_deal uuid;
      BEGIN
        SELECT tenant_id,deal_id INTO v_tenant,v_deal FROM public.crm_deal_checklist_items WHERE id=p_item_id;
        IF v_tenant IS NULL THEN RETURN jsonb_build_object('error','not_found'); END IF;
        IF NOT public.tanda1_user_has_role(v_tenant,ARRAY['admin','operator']) THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
        UPDATE public.crm_deal_checklist_items SET is_done=p_is_done,updated_at=now() WHERE id=p_item_id;
        INSERT INTO public.audit_log(tenant_id,actor_user_id,action,entity_type,entity_id,metadata)
        VALUES(v_tenant,auth.uid(),'checklist_updated','deal',v_deal,jsonb_build_object('item_id',p_item_id,'is_done',p_is_done));
        RETURN jsonb_build_object('success',true);
      END $body$
      $sql$;
    END IF;
END
$migration$;

-- Reassert normal ERP ACLs after reconciliation. CREATE OR REPLACE preserves
-- existing OIDs and ACLs, but these statements make the release contract explicit.
REVOKE EXECUTE ON FUNCTION public.rpc_create_invitation(uuid,text,text),
    public.rpc_list_descargo_lines(uuid),public.rpc_add_descargo_line(uuid,jsonb),public.rpc_list_deal_notes(uuid),
    public.rpc_list_deal_checklist(uuid),public.rpc_demo_configure_module(uuid,text),
    public.rpc_add_deal_note(uuid,text),public.rpc_toggle_deal_checklist_item(uuid,boolean)
FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_create_invitation(uuid,text,text),
    public.rpc_list_descargo_lines(uuid),public.rpc_add_descargo_line(uuid,jsonb),public.rpc_list_deal_notes(uuid),
    public.rpc_list_deal_checklist(uuid),public.rpc_demo_configure_module(uuid,text),
    public.rpc_add_deal_note(uuid,text),public.rpc_toggle_deal_checklist_item(uuid,boolean)
TO authenticated;

DO $migration$
BEGIN
    IF to_regprocedure('public.rpc_dashboard_overview(uuid)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.rpc_dashboard_overview(uuid) FROM PUBLIC,anon,authenticated,service_role';
    END IF;
    IF to_regprocedure('public.rpc_dashboard_recent_activity(uuid,integer)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.rpc_dashboard_recent_activity(uuid,integer) FROM PUBLIC,anon,authenticated,service_role';
    END IF;
    IF to_regprocedure('public.rpc_assign_operation(uuid,uuid,uuid,uuid,timestamptz,text,text,text)') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.rpc_assign_operation(uuid,uuid,uuid,uuid,timestamptz,text,text,text) FROM PUBLIC,anon,authenticated,service_role';
    END IF;
END
$migration$;
