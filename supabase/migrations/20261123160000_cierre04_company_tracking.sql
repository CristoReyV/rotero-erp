BEGIN;

SET LOCAL ROLE rotero_company_access_owner;
GRANT REFERENCES(tenant_id,id) ON public.companies TO postgres;
RESET ROLE;

-- An issued link belongs to the classified operation and, for a driver, to
-- the assignment in effect at issuance. Existing links are never backfilled.
ALTER TABLE public.tracking_tokens
    ADD COLUMN company_id uuid,
    ADD COLUMN assignment_id uuid REFERENCES public.operation_assignment_history(id),
    ADD CONSTRAINT tracking_tokens_company_fk FOREIGN KEY (tenant_id,company_id)
        REFERENCES public.companies(tenant_id,id),
    ADD CONSTRAINT tracking_tokens_company_assignment_check CHECK (
        assignment_id IS NULL OR (company_id IS NOT NULL AND scope='driver:write')
    );

CREATE POLICY tracking_tokens_manage_via_rpc ON public.tracking_tokens AS RESTRICTIVE
    FOR ALL TO anon,authenticated USING (company_id IS NULL) WITH CHECK (company_id IS NULL);

SET LOCAL ROLE rotero_company_access_owner;
REVOKE REFERENCES(tenant_id,id) ON public.companies FROM postgres;
DO $$
DECLARE d text;
BEGIN
    SELECT pg_get_constraintdef(oid) INTO STRICT d FROM pg_constraint
    WHERE conrelid='public.membership_company_capabilities'::regclass
      AND conname='membership_company_capabilities_capability_code_check';
    IF position('automations.manage' IN d)=0 OR position('tracking.manage' IN d)>0
    THEN RAISE EXCEPTION 'tracking_capability_source_drift'; END IF;
    ALTER TABLE public.membership_company_capabilities
      DROP CONSTRAINT membership_company_capabilities_capability_code_check;
    EXECUTE 'ALTER TABLE public.membership_company_capabilities ADD CONSTRAINT '
      ||'membership_company_capabilities_capability_code_check '
      ||replace(d,'''automations.manage''','''automations.manage'', ''tracking.manage''');
END $$;
RESET ROLE;

DO $$
DECLARE d text:=pg_get_functiondef('public.rpc_delivery_context(uuid)'::regprocedure);
BEGIN
    IF position('''automations.manage''' IN d)=0 THEN RAISE EXCEPTION 'tracking_context_source_drift'; END IF;
    EXECUTE replace(d,'''automations.manage''','''automations.manage'',''tracking.manage''');
END $$;

CREATE FUNCTION private.c04_current_assignment(t uuid, op uuid) RETURNS uuid
LANGUAGE sql STABLE SET search_path='' AS $$
    SELECT h.id FROM public.operation_assignment_history h
    WHERE h.tenant_id=t AND h.operation_id=op
    ORDER BY h.changed_at DESC,h.id DESC LIMIT 1;
$$;

CREATE FUNCTION private.c04_tracking_manager(t uuid, op uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
    SELECT private.delivery_headers()->>'x-rotero-scope'='company'
        AND cardinality(private.delivery_company_ids())=1
        AND private.delivery_cap(t,'operations.read')
        AND private.delivery_cap(t,'tracking.manage')
        AND private.delivery_entity_allowed(t,'operation',op)
        AND public.tanda1_user_has_role(t,ARRAY['admin','operator']);
$$;

CREATE FUNCTION public.rpc_delivery_tracking_links(p_tenant_id uuid,p_operation_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF NOT COALESCE(private.c04_tracking_manager(p_tenant_id,p_operation_id),false)
    THEN RETURN jsonb_build_object('error','unauthorized'); END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'id',t.id,'operation_id',t.operation_id,'scope',t.scope,
            'state',CASE
              WHEN t.state='active' AND t.scope='driver:write'
                AND t.assignment_id IS DISTINCT FROM private.c04_current_assignment(t.tenant_id,t.operation_id)
              THEN 'hard_expired' ELSE t.state END,
            'created_at',t.created_at,'expires_at',t.expires_at,'last_used_at',t.last_used_at
        ) ORDER BY t.created_at DESC,t.id DESC)
        FROM (
            SELECT id,operation_id,tenant_id,scope,state,created_at,expires_at,last_used_at,assignment_id
            FROM public.tracking_tokens
            WHERE tenant_id=p_tenant_id AND operation_id=p_operation_id
              AND company_id=(private.delivery_company_ids())[1]
            ORDER BY created_at DESC,id DESC LIMIT 100
        ) t
    ),'[]'::jsonb);
END $$;

-- CAS rotation and revoke serialize on the operation row. An uncertain issue
-- returns metadata on retry, never a second literal. Rotate only the listed ID.
CREATE FUNCTION public.rpc_delivery_tracking_action(
    p_tenant_id uuid,p_operation_id uuid,p_scope text,p_ttl_hours integer,
    p_action text,p_expected_token_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
    op public.operations%ROWTYPE;
    active_link public.tracking_tokens%ROWTYPE;
    actor uuid;
    assigned uuid;
    literal text;
    new_id uuid;
    expiry timestamptz;
BEGIN
    actor:=auth.uid();
    IF actor IS NULL OR NOT COALESCE(private.c04_tracking_manager(p_tenant_id,p_operation_id),false)
    THEN RETURN jsonb_build_object('error','unauthorized'); END IF;
    IF p_scope IS NULL OR p_scope NOT IN ('public:read','driver:write')
    THEN RETURN jsonb_build_object('error','invalid_scope'); END IF;
    IF p_action IS NULL OR p_action NOT IN ('issue','rotate','revoke')
       OR ((p_action='issue') <> (p_expected_token_id IS NULL))
    THEN RETURN jsonb_build_object('error','conflict'); END IF;

    SELECT * INTO op FROM public.operations WHERE tenant_id=p_tenant_id AND id=p_operation_id FOR UPDATE;
    IF NOT FOUND OR NOT COALESCE(private.c04_tracking_manager(p_tenant_id,p_operation_id),false)
    THEN RETURN jsonb_build_object('error','unauthorized'); END IF;

    IF p_action='revoke' THEN
        SELECT * INTO active_link FROM public.tracking_tokens
        WHERE id=p_expected_token_id AND operation_id=op.id AND tenant_id=op.tenant_id
          AND company_id=op.company_id AND scope=p_scope;
        IF NOT FOUND THEN RETURN jsonb_build_object('error','conflict'); END IF;
        IF active_link.state='revoked' THEN RETURN jsonb_build_object('success',true,'status','already_revoked'); END IF;
        IF active_link.state='rotated' THEN RETURN jsonb_build_object('error','conflict'); END IF;
        UPDATE public.tracking_tokens SET state='revoked',revoked_at=clock_timestamp(),revoked_by=actor
          WHERE id=active_link.id;
        RETURN jsonb_build_object('success',true,'status','revoked');
    END IF;

    IF op.status IN ('delivered','closed','cancelled')
    THEN RETURN jsonb_build_object('error','operation_inactive'); END IF;
    IF p_ttl_hours IS NULL OR p_ttl_hours<1 THEN RETURN jsonb_build_object('error','invalid_ttl'); END IF;
    IF p_ttl_hours>(CASE p_scope WHEN 'driver:write' THEN 72 ELSE 720 END)
    THEN RETURN jsonb_build_object('error','ttl_exceeds_max'); END IF;
    IF p_scope='driver:write' THEN
        assigned:=private.c04_current_assignment(op.tenant_id,op.id);
        IF assigned IS NULL OR op.status NOT IN ('assigned','in_transit')
        THEN RETURN jsonb_build_object('error','assignment_required'); END IF;
    END IF;

    SELECT * INTO active_link FROM public.tracking_tokens
      WHERE tenant_id=op.tenant_id AND operation_id=op.id AND scope=p_scope AND state='active';
    IF p_action='rotate' AND (active_link.id IS DISTINCT FROM p_expected_token_id
                             OR active_link.company_id IS DISTINCT FROM op.company_id)
    THEN RETURN jsonb_build_object('error','conflict'); END IF;
    IF p_action='issue' AND active_link.company_id=op.company_id
       AND active_link.expires_at>clock_timestamp()
       AND active_link.assignment_id IS NOT DISTINCT FROM assigned THEN
        RETURN jsonb_build_object('token_id',active_link.id,'scope',p_scope,
            'expires_at',active_link.expires_at,'already_existed',true);
    END IF;

    -- An active legacy/stale link cannot block adoption or remain usable.
    IF active_link.id IS NOT NULL THEN
        UPDATE public.tracking_tokens SET state='rotated',revoked_at=clock_timestamp(),revoked_by=actor
        WHERE id=active_link.id;
    END IF;
    literal:=gen_random_uuid()::text;
    expiry:=clock_timestamp()+make_interval(hours=>p_ttl_hours);
    INSERT INTO public.tracking_tokens(tenant_id,operation_id,company_id,assignment_id,
        scope,token_hash,created_by,expires_at)
    VALUES(op.tenant_id,op.id,op.company_id,assigned,p_scope,public.tracking_hash_token(literal),actor,expiry)
    RETURNING id INTO new_id;
    IF active_link.id IS NOT NULL THEN
        UPDATE public.tracking_tokens SET rotated_into=new_id WHERE id=active_link.id;
    END IF;
    RETURN jsonb_build_object('token_id',new_id,'token',literal,'scope',p_scope,
        'expires_at',expiry,'rotated_previous',active_link.id IS NOT NULL,'already_existed',false);
END $$;

CREATE FUNCTION private.c04_tracking_is_enterprise(link public.tracking_tokens) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
    SELECT link.company_id IS NOT NULL OR EXISTS (
        SELECT FROM private.delivery_tenant_cutovers d WHERE d.tenant_id=link.tenant_id AND d.enabled
    );
$$;

CREATE FUNCTION private.c04_tracking_live(link public.tracking_tokens) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
    SELECT link.company_id IS NOT NULL AND link.state='active'
      AND link.expires_at>statement_timestamp()
      AND EXISTS (SELECT FROM private.delivery_tenant_cutovers d WHERE d.tenant_id=link.tenant_id AND d.enabled)
      AND EXISTS (
        SELECT FROM public.operations o JOIN public.companies c
          ON c.tenant_id=o.tenant_id AND c.id=o.company_id
        WHERE o.id=link.operation_id AND o.tenant_id=link.tenant_id AND o.company_id=link.company_id
          AND o.company_classification_status='resolved' AND c.status='active'
          AND o.status<>'cancelled' AND (link.scope<>'driver:write' OR (
            o.status IN ('assigned','in_transit','delivered') AND link.assignment_id IS NOT NULL
            AND link.assignment_id=private.c04_current_assignment(o.tenant_id,o.id)
          ))
      );
$$;

-- Scope the existing readiness calculation to live enterprise links. The
-- company's operations workflow continues to use the original state machine.
CREATE FUNCTION private.c04_tracking_readiness(t uuid, op uuid, checks jsonb) RETURNS jsonb
LANGUAGE sql STABLE SET search_path='' AS $$
    WITH live AS (
        SELECT count(*) FILTER(WHERE l.scope='driver:write')>0 AS driver,
               count(*) FILTER(WHERE l.scope='public:read')>0 AS shared
        FROM public.tracking_tokens l
        WHERE l.operation_id=op AND l.tenant_id=t AND l.state='active' AND private.c04_tracking_live(l)
    )
    SELECT checks || jsonb_build_object(
        'has_driver_token',driver,'has_public_token',shared,
        'is_tracking_ready',COALESCE((checks->>'is_tracking_ready')::boolean,false) AND driver AND shared,
        'can_transition_to_in_transit',COALESCE((checks->>'can_transition_to_in_transit')::boolean,false) AND driver AND shared
    ) FROM live;
$$;

DO $$
DECLARE f record; d text;
BEGIN
    SELECT * INTO STRICT f FROM pg_proc WHERE oid='public.rpc_get_operation_dispatch_readiness(uuid)'::regprocedure;
    IF md5(replace(f.prosrc,E'\r\n',E'\n'))<>'e6b90c5797c64c4d906058abf8138a2d'
      OR f.proowner<>'postgres'::regrole OR NOT f.prosecdef
    THEN RAISE EXCEPTION 'tracking_readiness_source_drift'; END IF;
    d:=pg_get_functiondef(f.oid);
    EXECUTE replace(d,'RETURN private.delivery_pick_dto(result,',
      'RETURN private.delivery_pick_dto(private.c04_tracking_readiness(v_tenant,p_operation_id,result),');

    SELECT * INTO STRICT f FROM pg_proc WHERE oid='private.c03_core_transition(uuid,text)'::regprocedure;
    IF md5(replace(f.prosrc,E'\r\n',E'\n'))<>'bc317002949eedc3bc262b0fa40db61a'
      OR f.proowner<>'postgres'::regrole OR NOT f.prosecdef
    THEN RAISE EXCEPTION 'tracking_transition_source_drift'; END IF;
    d:=pg_get_functiondef(f.oid);
    EXECUTE replace(d,
      'SELECT 1 FROM public.tracking_events e WHERE e.operation_id = p_operation_id AND e.event_type = ''delivered''',
      'SELECT 1 FROM public.tracking_events e JOIN public.tracking_tokens l ON l.id=e.token_id
       WHERE e.operation_id=p_operation_id AND e.tenant_id=v_operation.tenant_id
         AND NOT e.is_suspicious AND e.event_type=''delivered''
         AND l.operation_id=e.operation_id AND l.tenant_id=e.tenant_id AND l.company_id=v_operation.company_id
         AND l.assignment_id=private.c04_current_assignment(e.tenant_id,e.operation_id)');
END $$;

-- Keep the two reviewed writer variants and their event validation. Only the
-- legacy route can ask the writer to update the operational state.
DO $$
DECLARE r record; f record; definition text; source_hash text;
        writer text; writer_args text;
        writer_tail constant text:='p_offline_queued boolean DEFAULT false)';
        status_guard constant text:='IF v_new_status IS NOT NULL THEN';
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('rpc_get_public_tracking','text','87fb3ca90047236d3445faa46da10d6e','02f079e276b1c44e3d3f7e0756dd2d23'),
        ('rpc_get_driver_view','text','0a3c9db177c29de28a2402c7b938831c','08a04f481ca61667710c3953e1fd7298'),
        ('rpc_post_driver_event','text, text, text, numeric, numeric, numeric, text, text, character, text, text, timestamp with time zone, boolean',
         '9345385d44db5d49cc6831ff197fca74','e580c2a786480e51b6a6048a2fd39f2c')
    ) v(name,args,a_hash,b_hash) LOOP
        SELECT * INTO STRICT f FROM pg_proc
          WHERE oid=to_regprocedure(format('public.%I(%s)',r.name,r.args));
        source_hash:=md5(replace(f.prosrc,E'\r\n',E'\n'));
        IF source_hash NOT IN (r.a_hash,r.b_hash)
           OR f.proowner<>'postgres'::regrole OR NOT f.prosecdef
        THEN RAISE EXCEPTION 'tracking_service_source_drift: %',r.name; END IF;

        writer:='c04_legacy_'||r.name;
        writer_args:=r.args;
        definition:=pg_get_functiondef(f.oid);
        IF r.name='rpc_post_driver_event' THEN
            writer:='c04_write_driver_event';
            writer_args:=r.args||', boolean';
            IF length(definition)-length(replace(definition,writer_tail,''))<>length(writer_tail)
            THEN RAISE EXCEPTION 'tracking_writer_signature_drift'; END IF;
            definition:=replace(definition,writer_tail,
                'p_offline_queued boolean DEFAULT false, p_tracking_only boolean DEFAULT true)');
            IF source_hash=r.b_hash THEN
                IF length(definition)-length(replace(definition,status_guard,''))<>length(status_guard)
                THEN RAISE EXCEPTION 'tracking_writer_status_guard_drift'; END IF;
                definition:=replace(definition,status_guard,
                    'IF NOT p_tracking_only AND v_new_status IS NOT NULL THEN');
            END IF;
        END IF;
        EXECUTE replace(definition,'FUNCTION public.'||r.name||'(','FUNCTION private.'||writer||'(');
        EXECUTE format('REVOKE ALL ON FUNCTION private.%I(%s) FROM PUBLIC,anon,authenticated,service_role',
            writer,writer_args);
    END LOOP;
END $$;

-- Enterprise views restrict the output to fixed labels, an opaque shipment
-- reference and ordered milestones. No route free text, location, party data,
-- raw snapshots, driver notes, financial fields or files are projected.
CREATE OR REPLACE FUNCTION public.rpc_get_public_tracking(p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE link public.tracking_tokens%ROWTYPE; op_status text; milestones jsonb; has_arrived boolean;
BEGIN
    SELECT * INTO link FROM public.tracking_tokens
      WHERE token_hash=public.tracking_hash_token(p_token) AND scope='public:read';
    IF NOT FOUND THEN RETURN jsonb_build_object('status','not_found'); END IF;
    IF NOT private.c04_tracking_is_enterprise(link) THEN RETURN private.c04_legacy_rpc_get_public_tracking(p_token); END IF;
    IF link.state IN ('revoked','rotated') THEN RETURN jsonb_build_object('status','revoked'); END IF;
    IF link.expires_at<=statement_timestamp() THEN RETURN jsonb_build_object('status','hard_expired'); END IF;
    IF NOT private.c04_tracking_live(link) THEN RETURN jsonb_build_object('status','not_found'); END IF;
    SELECT status INTO op_status FROM public.operations WHERE id=link.operation_id AND tenant_id=link.tenant_id;
    SELECT EXISTS (
        SELECT FROM public.tracking_events
        WHERE tenant_id=link.tenant_id AND operation_id=link.operation_id
          AND event_type='arrival' AND NOT is_suspicious
    ) INTO has_arrived;
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id','evt-'||n,'title',
        CASE event_type WHEN 'departure' THEN 'Salida' WHEN 'arrival' THEN 'En destino'
             WHEN 'delivered' THEN 'Entregado' ELSE 'En tránsito' END,
        'subtitle','Actualización logística','timestamp',server_timestamp,
        'status','done','icon','map-pin') ORDER BY n),'[]'::jsonb)
    INTO milestones FROM (
        SELECT event_type,server_timestamp,row_number() OVER (ORDER BY server_timestamp,id) n
        FROM public.tracking_events
        WHERE tenant_id=link.tenant_id AND operation_id=link.operation_id
          AND (event_type IN ('departure','in_transit','arrival')
               OR (event_type='delivered' AND op_status IN ('delivered','closed')))
          AND NOT is_suspicious
        ORDER BY server_timestamp,id LIMIT 20
    ) events;
    RETURN jsonb_build_object('status','success','managedCompanyLink',true,'data',
        jsonb_build_object('orderRef',upper(left(link.operation_id::text,8)),
        'route','Seguimiento de entrega','currentStatus',
        CASE WHEN op_status IN ('delivered','closed') THEN 'Entregado'
            WHEN op_status='in_transit' AND has_arrived THEN 'En destino'
            WHEN op_status='in_transit' THEN 'En Tránsito'
            ELSE 'En Espera' END,'events',milestones));
END $$;

CREATE OR REPLACE FUNCTION public.rpc_get_driver_view(p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE link public.tracking_tokens%ROWTYPE; latest text;
BEGIN
    SELECT * INTO link FROM public.tracking_tokens
      WHERE token_hash=public.tracking_hash_token(p_token) AND scope='driver:write';
    IF NOT FOUND THEN RETURN jsonb_build_object('status','not_found'); END IF;
    IF NOT private.c04_tracking_is_enterprise(link) THEN RETURN private.c04_legacy_rpc_get_driver_view(p_token); END IF;
    IF link.state IN ('revoked','rotated') THEN RETURN jsonb_build_object('status','revoked'); END IF;
    IF NOT private.c04_tracking_live(link) THEN RETURN jsonb_build_object('status','expired'); END IF;
    SELECT event_type INTO latest FROM public.tracking_events
      WHERE tenant_id=link.tenant_id AND operation_id=link.operation_id
        AND event_type IN ('departure','in_transit','arrival','delivered') AND NOT is_suspicious
      ORDER BY CASE event_type WHEN 'delivered' THEN 4 WHEN 'arrival' THEN 3
        WHEN 'in_transit' THEN 2 ELSE 1 END DESC,server_timestamp DESC,id DESC LIMIT 1;
    RETURN jsonb_build_object('status','success','data',jsonb_build_object(
        'orderRef',upper(left(link.operation_id::text,8)),'route','Seguimiento de entrega',
        'clientName','','destinationCity','',
        'currentStatus',CASE latest WHEN 'delivered' THEN 'delivered' WHEN 'arrival' THEN 'at_destination'
           WHEN 'departure' THEN 'in_transit' WHEN 'in_transit' THEN 'in_transit' ELSE 'assigned' END));
END $$;

CREATE OR REPLACE FUNCTION public.rpc_post_driver_event(
    p_token text,p_action text,p_source text DEFAULT 'gps',
    p_lat numeric DEFAULT NULL,p_lng numeric DEFAULT NULL,p_accuracy numeric DEFAULT NULL,
    p_municipality text DEFAULT NULL,p_state_name text DEFAULT NULL,p_country_code char DEFAULT 'MX',
    p_incident_type text DEFAULT NULL,p_incident_note text DEFAULT NULL,
    p_client_timestamp timestamptz DEFAULT now(),p_offline_queued boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE link public.tracking_tokens%ROWTYPE; op_status text; prior text; result jsonb;
BEGIN
    SELECT * INTO link FROM public.tracking_tokens
      WHERE token_hash=public.tracking_hash_token(p_token) AND scope='driver:write';
    IF NOT FOUND THEN RETURN jsonb_build_object('http',404,'accepted',false,'reason','not_found'); END IF;
    SELECT status INTO op_status FROM public.operations WHERE id=link.operation_id AND tenant_id=link.tenant_id FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('http',404,'accepted',false,'reason','not_found'); END IF;
    SELECT * INTO STRICT link FROM public.tracking_tokens WHERE id=link.id;
    IF NOT private.c04_tracking_is_enterprise(link) THEN
        RETURN private.c04_write_driver_event(p_token,p_action,p_source,p_lat,p_lng,p_accuracy,
            p_municipality,p_state_name,p_country_code,p_incident_type,p_incident_note,p_client_timestamp,p_offline_queued,false);
    END IF;
    IF NOT private.c04_tracking_live(link) OR link.expires_at<=clock_timestamp()
    THEN RETURN jsonb_build_object('http',403,'accepted',false,'reason','expired'); END IF;
    IF p_action IS NULL OR p_action NOT IN ('departure','in_transit','arrival','delivered','incident')
       OR p_client_timestamp IS NULL
    THEN RETURN jsonb_build_object('http',400,'accepted',false,'reason','invalid_action'); END IF;
    -- A retry of the same event is acknowledged without calling the writer.
    IF EXISTS (SELECT FROM public.tracking_events e WHERE e.token_id=link.id AND e.event_type=p_action
              AND e.client_timestamp=p_client_timestamp AND NOT e.is_suspicious)
    THEN RETURN jsonb_build_object('http',200,'accepted',true,'reason','already_recorded'); END IF;
    SELECT event_type INTO prior FROM public.tracking_events
      WHERE operation_id=link.operation_id AND tenant_id=link.tenant_id
      AND event_type IN ('departure','in_transit','arrival','delivered') AND NOT is_suspicious
      ORDER BY CASE event_type WHEN 'delivered' THEN 4 WHEN 'arrival' THEN 3
        WHEN 'in_transit' THEN 2 ELSE 1 END DESC,server_timestamp DESC,id DESC LIMIT 1;
    IF NOT COALESCE(CASE p_action
        WHEN 'departure' THEN op_status IN ('assigned','in_transit') AND prior IS NULL
        WHEN 'in_transit' THEN op_status='in_transit' AND prior IN ('departure','in_transit')
        WHEN 'arrival' THEN op_status='in_transit' AND prior IN ('departure','in_transit')
        WHEN 'delivered' THEN op_status='in_transit' AND prior='arrival'
        WHEN 'incident' THEN op_status IN ('assigned','in_transit') AND prior IS DISTINCT FROM 'delivered' END,false)
    THEN RETURN jsonb_build_object('http',409,'accepted',false,'reason','invalid_transition'); END IF;
    result:=private.c04_write_driver_event(p_token,p_action,p_source,p_lat,p_lng,p_accuracy,
        p_municipality,p_state_name,p_country_code,p_incident_type,p_incident_note,p_client_timestamp,p_offline_queued,true);
    RETURN jsonb_strip_nulls(jsonb_build_object('http',result->'http','accepted',result->'accepted',
        'eventId',result->'eventId','reason',CASE
            WHEN result->>'reason' ~ '^[a-z_]{1,40}$' THEN result->>'reason' END));
END $$;

REVOKE ALL ON FUNCTION private.c04_current_assignment(uuid,uuid),private.c04_tracking_manager(uuid,uuid),
    private.c04_tracking_is_enterprise(public.tracking_tokens),private.c04_tracking_live(public.tracking_tokens),
    private.c04_tracking_readiness(uuid,uuid,jsonb)
    FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.rpc_delivery_tracking_links(uuid,uuid),
    public.rpc_delivery_tracking_action(uuid,uuid,text,integer,text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.rpc_delivery_tracking_links(uuid,uuid),
    public.rpc_delivery_tracking_action(uuid,uuid,text,integer,text,uuid) TO authenticated;

COMMIT;
