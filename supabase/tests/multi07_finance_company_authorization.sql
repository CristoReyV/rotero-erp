\set ON_ERROR_STOP on
-- New, disposable local runtime only. Synthetic rows and all test ACL roll back.
CREATE TEMP TABLE m07_before_counts AS SELECT
 (SELECT count(*) FROM public.finance_invoices) invoices,
 (SELECT count(*) FROM public.operations) operations,
 (SELECT count(*) FROM private.finance_invoices_company_evidence) invoice_evidence,
 (SELECT count(*) FROM private.billing_documents_company_evidence) document_evidence,
 (SELECT count(*) FROM private.billing_credit_notes_company_evidence) credit_evidence,
 (SELECT count(*) FROM public.tenants WHERE slug LIKE 'm07-%') synthetic_tenants;
BEGIN;
CREATE FUNCTION pg_temp.m07_check(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'MULTI07 failed: %',label; END IF; END; $$;
CREATE FUNCTION pg_temp.m07_error(q text,code text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN EXECUTE q;
    EXCEPTION WHEN OTHERS THEN IF SQLSTATE<>code THEN RAISE EXCEPTION 'MULTI07 expected %, got %',code,SQLSTATE; END IF; RETURN; END;
    RAISE EXCEPTION 'MULTI07 expected %, succeeded',code;
END; $$;
CREATE FUNCTION pg_temp.m07_actor(u uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claim.sub',COALESCE(u::text,''),true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','iss','https://synthetic-access.invalid/auth/v1',
        'user_metadata',jsonb_build_object('financial_full',true,'consolidated',true))::text,true);
END; $$;
CREATE FUNCTION pg_temp.m07_resolve(root text,target uuid,c uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE e uuid; t uuid; ledger text;
BEGIN
    IF root NOT IN ('operations','finance_invoices','billing_documents','billing_credit_notes') THEN RAISE EXCEPTION 'fixture root'; END IF;
    EXECUTE format('SELECT tenant_id FROM public.%I WHERE id=$1',root) INTO t USING target;
    ledger:=CASE root WHEN 'operations' THEN 'operation_company_classification_events' ELSE root||'_company_evidence' END;
    EXECUTE format('INSERT INTO private.%I(tenant_id,%I,company_id,decision,evidence_kind,evidence_reference,recorded_by)
        VALUES($1,$2,$3,''resolved'',''verified_source_record'',''synthetic-verified-record'',$4) RETURNING id',ledger,
        CASE root WHEN 'operations' THEN 'operation_id' ELSE 'entity_id' END)
        INTO e USING t,target,c,current_setting('m07.reader')::uuid;
    EXECUTE format('UPDATE public.%I SET company_id=$1,company_classification_status=''resolved'',company_classification_event_id=$2 WHERE id=$3',root)
        USING c,e,target;
END; $$;

DO $closed$
DECLARE r text; t text; fn record; role_name text;
BEGIN
    FOR fn IN SELECT p.oid,p.prosecdef,p.proowner,p.proconfig,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname IN ('public','private') AND (p.proname LIKE 'multi07_%' OR p.proname LIKE 'rpc_multi07_%') LOOP
        FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
            PERFORM pg_temp.m07_check(NOT has_function_privilege(r,fn.oid,'EXECUTE'),'no new helper or RPC API execution');
        END LOOP;
        PERFORM pg_temp.m07_check(fn.proconfig @> ARRAY['search_path=""'],'safe qualified path');
    END LOOP;
    FOREACH role_name IN ARRAY ARRAY['rotero_finance_scope_owner','rotero_finance_read_owner'] LOOP
        PERFORM pg_temp.m07_check(EXISTS(SELECT FROM pg_roles WHERE rolname=role_name AND NOT rolcanlogin AND NOT rolinherit
            AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication),'limited owners');
        PERFORM pg_temp.m07_check(NOT has_schema_privilege(role_name,'public','CREATE') AND NOT has_schema_privilege(role_name,'private','CREATE'),
            'no persistent schema creation');
        FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
            PERFORM pg_temp.m07_check(NOT pg_has_role(r,role_name,'MEMBER'),'cannot assume owner');
        END LOOP;
    END LOOP;
    PERFORM pg_temp.m07_check(NOT has_column_privilege('rotero_finance_scope_owner','public.finance_invoices','amount','SELECT')
        AND NOT has_column_privilege('rotero_finance_read_owner','public.finance_invoices','notes','SELECT')
        AND NOT has_column_privilege('rotero_finance_read_owner','public.finance_payments','bank_reference','SELECT'),'metadata/DTO privilege separation');
    FOREACH t IN ARRAY ARRAY['finance_invoices','finance_payments','billing_documents','billing_credit_notes','billing_payment_complements'] LOOP
        FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
            PERFORM pg_temp.m07_check(NOT has_any_column_privilege(r,'public.'||t,'SELECT,INSERT,UPDATE'),'closed direct financial columns');
        END LOOP;
    END LOOP;
END; $closed$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.m07_error('SELECT public.rpc_multi07_list_invoices(NULL,NULL)','42501');
SELECT pg_temp.m07_error('SELECT * FROM public.finance_invoices','42501');
SELECT pg_temp.m07_error('SELECT * FROM private.m07_single_finance_invoices','42501');
SELECT pg_temp.m07_error('SELECT * FROM private.multi07_entity_scope(''invoice'',gen_random_uuid())','42501');
RESET ROLE;
SELECT 'PASS: closed new RPCs, effective raw/column ACL, private views and two limited owners';

SET LOCAL ROLE rotero_company_access_owner;
DO $$ BEGIN EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON public.companies,public.membership_company_access,
    public.membership_company_capabilities,private.financial_principal_bindings,public.membership_consolidation_grants,
    public.consolidation_grant_companies TO %I',SESSION_USER); END; $$;
RESET ROLE;
SET LOCAL ROLE rotero_operations_read_owner;
DO $$ BEGIN EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON private.operation_company_classification_events TO %I',SESSION_USER); END; $$;
RESET ROLE;
SET LOCAL ROLE rotero_finance_scope_owner;
DO $$ BEGIN EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON private.finance_invoices_company_evidence,
    private.billing_documents_company_evidence,private.billing_credit_notes_company_evidence TO %I',SESSION_USER); END; $$;
RESET ROLE;
SET LOCAL ROLE rotero_finance_read_owner;
GRANT EXECUTE ON FUNCTION public.rpc_multi07_list_invoices(uuid,uuid[],text,text,text,uuid,integer,boolean),
    public.rpc_multi07_get_invoice(uuid,uuid,uuid),public.rpc_multi07_finance_summary(uuid,uuid[],boolean),
    public.rpc_multi07_export_invoices_page(uuid,uuid[],text,text,text,uuid,integer,boolean) TO authenticated;
RESET ROLE;

DO $fixtures$
DECLARE t uuid; x uuid; a uuid; b uuid; xc uuid; u uuid:=gen_random_uuid(); ng uuid:=gen_random_uuid();
    adm uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); binding uuid; oa uuid; ob uuid; ox uuid;
    da uuid; db uuid; ia uuid; ap uuid; ib uuid; ix uuid; ip uuid; child uuid; payment uuid; payroll uuid:=gen_random_uuid();
BEGIN
    -- Reconciled audit/creator FKs require real synthetic Auth row IDs. All
    -- actors and effects remain local to this transaction and are rolled back.
    INSERT INTO auth.users(id) VALUES(u),(ng),(adm),(outsider);
    INSERT INTO public.tenants(name,slug) VALUES('M07 synthetic','m07-'||gen_random_uuid()) RETURNING id INTO t;
    INSERT INTO public.tenants(name,slug) VALUES('M07 other','m07-'||gen_random_uuid()) RETURNING id INTO x;
    INSERT INTO public.memberships(user_id,tenant_id,role) VALUES(u,t,'finance'),(ng,t,'finance'),(adm,t,'admin'),(outsider,x,'finance');
    INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status) VALUES(t,'A','Synthetic A','AAA010101AA1','active') RETURNING id INTO a;
    INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status) VALUES(t,'B','Synthetic B','BBB010101BB1','active') RETURNING id INTO b;
    INSERT INTO public.companies(tenant_id,display_name,legal_name,rfc_normalized,status) VALUES(x,'X','Synthetic X','XXX010101XX1','active') RETURNING id INTO xc;
    PERFORM set_config('m07.reader',u::text,true);PERFORM set_config('m07.no_grant',ng::text,true);PERFORM set_config('m07.admin',adm::text,true);
    PERFORM set_config('m07.outsider',outsider::text,true);PERFORM set_config('m07.t',t::text,true);PERFORM set_config('m07.x',x::text,true);
    PERFORM set_config('m07.a',a::text,true);PERFORM set_config('m07.b',b::text,true);PERFORM set_config('m07.xc',xc::text,true);
    INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES(t,u,a,adm),(t,u,b,adm),(t,ng,a,adm),(t,adm,a,adm);
    INSERT INTO private.financial_principal_bindings(tenant_id,user_id,principal_code,identity_kind,identity_issuer,approval_reference,verified_by,verified_at)
    VALUES(t,u,'approved_financial_01','verified_human','https://synthetic-access.invalid/auth/v1','synthetic-approval',adm,now()-interval '1 minute') RETURNING id INTO binding;
    PERFORM set_config('m07.binding',binding::text,true);
    INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,financial_binding_id,approval_reference,granted_by)
    VALUES(t,u,a,'financial.full.read',binding,'synthetic-full-A',adm),(t,u,b,'financial.full.read',binding,'synthetic-full-B',adm);
    INSERT INTO public.operations(tenant_id,reference_code,provider_cost_amount,customer_price_amount) VALUES(t,'OA',60,100) RETURNING id INTO oa;
    INSERT INTO public.operations(tenant_id,reference_code,provider_cost_amount,customer_price_amount) VALUES(t,'OB',120,200) RETURNING id INTO ob;
    INSERT INTO public.operations(tenant_id,reference_code) VALUES(x,'OX') RETURNING id INTO ox;
    PERFORM pg_temp.m07_resolve('operations',oa,a);PERFORM pg_temp.m07_resolve('operations',ob,b);PERFORM pg_temp.m07_resolve('operations',ox,xc);
    INSERT INTO public.billing_documents(tenant_id,operation_id,total) VALUES(t,oa,100) RETURNING id INTO da;
    INSERT INTO public.billing_documents(tenant_id,operation_id,total) VALUES(t,ob,200) RETURNING id INTO db;
    PERFORM pg_temp.m07_resolve('billing_documents',da,a);PERFORM pg_temp.m07_resolve('billing_documents',db,b);
    INSERT INTO public.finance_invoices(tenant_id,operation_id,billing_document_id,direction,counterparty_name,reference,amount,notes,due_date)
        VALUES(t,oa,da,'ar','Needle A','IA',100,'SYNTHETIC_PRIVATE_CANARY',current_date) RETURNING id INTO ia;
    INSERT INTO public.finance_invoices(tenant_id,operation_id,direction,counterparty_name,reference,amount)
        VALUES(t,oa,'ap','Provider A','AP',60) RETURNING id INTO ap;
    INSERT INTO public.finance_invoices(tenant_id,operation_id,billing_document_id,direction,counterparty_name,reference,amount)
        VALUES(t,ob,db,'ar','Needle B','IB',200) RETURNING id INTO ib;
    INSERT INTO public.finance_invoices(tenant_id,operation_id,direction,counterparty_name,reference,amount)
        VALUES(x,ox,'ar','Other X','IX',300) RETURNING id INTO ix;
    PERFORM pg_temp.m07_resolve('finance_invoices',ia,a);PERFORM pg_temp.m07_resolve('finance_invoices',ap,a);
    PERFORM pg_temp.m07_resolve('finance_invoices',ib,b);PERFORM pg_temp.m07_resolve('finance_invoices',ix,xc);
    INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,reference,amount) VALUES(t,'ar','Unknown','PENDING',25) RETURNING id INTO ip;
    INSERT INTO public.finance_invoices(tenant_id,operation_id,direction,counterparty_name,reference,amount) VALUES(t,oa,'ar','Known parent','PARENT',15);
    -- B has the reviewed payroll parent/FK; canonical A only has the nullable
    -- compatibility column. Exercise the same exclusion with a valid B parent.
    IF to_regclass('public.payroll_periods') IS NOT NULL THEN
        EXECUTE 'INSERT INTO public.payroll_periods(id,tenant_id,name,period_start,period_end) VALUES($1,$2,$3,current_date,current_date+14)'
            USING payroll,t,'MULTI07 SYNTHETIC ROLLBACK';
    END IF;
    INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,reference,amount,payroll_period_id)
        VALUES(t,'ap','Synthetic reserved payroll','PAYROLL',1,payroll) RETURNING id INTO child;
    PERFORM pg_temp.m07_resolve('finance_invoices',child,a);PERFORM set_config('m07.payroll',child::text,true);
    INSERT INTO public.finance_payments(tenant_id,invoice_id,amount,paid_at,bank_reference,note) VALUES(t,ia,20,now(),'SYNTHETIC_PRIVATE_CANARY','SYNTHETIC_PRIVATE_CANARY') RETURNING id INTO payment;
    INSERT INTO public.billing_credit_notes(tenant_id,finance_invoice_id,total,status) VALUES(t,ia,10,'applied') RETURNING id INTO child;
    PERFORM pg_temp.m07_resolve('billing_credit_notes',child,a);
    INSERT INTO public.billing_payment_complements(tenant_id,finance_invoice_id,finance_payment_id,invoice_billing_document_id,amount)
        VALUES(t,ia,payment,da,20);
    PERFORM set_config('m07.oa',oa::text,true);PERFORM set_config('m07.ob',ob::text,true);
    PERFORM set_config('m07.da',da::text,true);PERFORM set_config('m07.db',db::text,true);
    PERFORM set_config('m07.ia',ia::text,true);PERFORM set_config('m07.ap',ap::text,true);PERFORM set_config('m07.ib',ib::text,true);
    PERFORM set_config('m07.ix',ix::text,true);PERFORM set_config('m07.ip',ip::text,true);PERFORM set_config('m07.payment',payment::text,true);
END; $fixtures$;
SELECT 'PASS: synthetic roots and evidence, AR/AP, parent-inherited payments/credit/complement graph';

DO $integrity$
DECLARE t uuid:=current_setting('m07.t')::uuid; ia uuid:=current_setting('m07.ia')::uuid; db uuid:=current_setting('m07.db')::uuid;
BEGIN
    PERFORM pg_temp.m07_error(format('UPDATE public.finance_invoices SET billing_document_id=%L WHERE id=%L',db,ia),'23503');
    PERFORM pg_temp.m07_error(format('UPDATE public.finance_invoices SET operation_id=%L WHERE id=%L',current_setting('m07.ob'),ia),'23503');
    PERFORM pg_temp.m07_error(format('SELECT pg_temp.m07_resolve(''finance_invoices'',%L,%L)',current_setting('m07.ip'),current_setting('m07.xc')),'23503');
    PERFORM pg_temp.m07_error(format('INSERT INTO public.finance_payments(tenant_id,invoice_id,amount,paid_at) VALUES(%L,%L,1,now())',current_setting('m07.x'),ia),'23503');
    PERFORM pg_temp.m07_error(format('INSERT INTO public.billing_payment_complements(tenant_id,finance_invoice_id,finance_payment_id,amount,status) VALUES(%L,%L,%L,1,''cancelled'')',
        t,current_setting('m07.ib'),current_setting('m07.payment')),'23503');
    -- Even unresolved roots cannot bridge two already-known incompatible parents.
    PERFORM pg_temp.m07_error(format('INSERT INTO public.finance_invoices(tenant_id,operation_id,billing_document_id,direction,counterparty_name,amount)
        VALUES(%L,%L,%L,''ar'',''synthetic'',1)',t,current_setting('m07.oa'),db),'23503');
    PERFORM pg_temp.m07_error(format('INSERT INTO public.billing_credit_notes(tenant_id,finance_invoice_id,source_billing_document_id,total)
        VALUES(%L,%L,%L,1)',t,ia,db),'23503');
    PERFORM pg_temp.m07_error(format('INSERT INTO public.billing_credit_notes(tenant_id,finance_invoice_id,source_billing_document_id,total,status)
        VALUES(%L,%L,%L,1,''applied'')',t,current_setting('m07.ip'),db),'23503');
    PERFORM pg_temp.m07_check((SELECT company_id IS NULL AND company_classification_status='pending_classification'
        FROM public.finance_invoices WHERE id=current_setting('m07.ip')::uuid),'unknown is not assigned by default');
END; $integrity$;
SELECT 'PASS: cross-tenant/company/document/payment/invoice relations rejected, unresolved remains explicit';

SET LOCAL ROLE authenticated;
DO $denials$
DECLARE who uuid; t uuid:=current_setting('m07.t')::uuid; a uuid:=current_setting('m07.a')::uuid; r jsonb;
BEGIN
    FOREACH who IN ARRAY ARRAY[current_setting('m07.no_grant')::uuid,current_setting('m07.admin')::uuid,current_setting('m07.outsider')::uuid] LOOP
        PERFORM pg_temp.m07_actor(who);
        r:=public.rpc_multi07_list_invoices(t,ARRAY[a]);
        PERFORM pg_temp.m07_check(r=jsonb_build_object('error','unauthorized'),'role/access/metadata does not expose financial payload or count');
        PERFORM pg_temp.m07_check(public.rpc_multi07_get_invoice(t,a,current_setting('m07.ia')::uuid)=r
            AND public.rpc_multi07_finance_summary(t,ARRAY[a])=r AND public.rpc_multi07_export_invoices_page(t,ARRAY[a])=r,
            'all new paths deny without full permission');
    END LOOP;
    PERFORM pg_temp.m07_actor(current_setting('m07.no_grant')::uuid);
    r:=public.rpc_get_finance_invoice_detail(t,current_setting('m07.ia')::uuid);
    PERFORM pg_temp.m07_check(r->>'error'='not_found','legacy direct detail no classified data by finance role');
    r:=public.rpc_list_finance_invoices(t,'{}'::jsonb);
    PERFORM pg_temp.m07_check(jsonb_array_length(r->'items')=1 AND r->'items'->0->>'reference'='PENDING',
        'genuinely unclassified legacy preserved; known-parent unresolved is guarded');
    r:=public.rpc_finance_overview(t,'{}'::jsonb);
    PERFORM pg_temp.m07_check((r->>'total_ar_open')::numeric=25,'legacy aggregate excludes classified data before sum');
    PERFORM pg_temp.m07_check(r=public.rpc_finance_overview(t) AND r=public.rpc_finance_overview(t,NULL::text,NULL::text),
        'both overview wrappers preserve guarded result');
    PERFORM pg_temp.m07_check(public.rpc_list_finance_invoices(t,50,NULL::text,NULL::text)=public.rpc_list_finance_invoices(t,'{}'::jsonb)->'items'
        AND public.rpc_list_finance_invoices(t,50,NULL::text,NULL::text,NULL::text,NULL::text)=public.rpc_list_finance_invoices(t,'{}'::jsonb)->'items',
        'both invoice list wrappers preserve guarded result');
    PERFORM pg_temp.m07_check(jsonb_array_length(public.rpc_list_finance_payments(t,'{}'::jsonb)->'items')=0
        AND jsonb_array_length(public.rpc_list_finance_due_alerts(t,'{}'::jsonb)->'items')=0
        AND jsonb_array_length(public.rpc_list_finance_due_alerts(t,7))=0,'payments and due-alert overloads exclude classified invoices');
    PERFORM pg_temp.m07_check(jsonb_array_length(public.rpc_finance_profitability(t)->'operations')=0
        AND public.rpc_get_operation_finance_summary(t,current_setting('m07.oa')::uuid)->>'error'='not_found'
        AND jsonb_array_length(public.rpc_list_payment_complements(t)->'items')=0,
        'profitability, operation financial summary and complements do not bypass full-read grants');
    PERFORM pg_temp.m07_check(public.rpc_export_finance_ledger(t,'{}'::jsonb)=public.rpc_export_finance_ledger(t,NULL::text,NULL::text),
        'both export overloads route through guarded source');
    r:=public.rpc_export_data_page(t,'finance_ar');
    PERFORM pg_temp.m07_check(jsonb_array_length(r->'items')=1 AND r->'items'->0->>'reference'='PENDING','generic AR export guarded before projection');
END; $denials$;
RESET ROLE;
SELECT 'PASS: no role-based full read, legacy detail/aggregate/exports guarded, unknown legacy still available';

SET LOCAL ROLE authenticated;
SELECT pg_temp.m07_actor(current_setting('m07.reader')::uuid);
DO $positive$
DECLARE t uuid:=current_setting('m07.t')::uuid; a uuid:=current_setting('m07.a')::uuid; b uuid:=current_setting('m07.b')::uuid;
    r jsonb; cursor uuid; ids uuid[]:='{}'; item jsonb; actual text[]; expected text[];
BEGIN
    r:=public.rpc_multi07_list_invoices(t,ARRAY[a]);
    PERFORM pg_temp.m07_check((r->>'total')::int=2 AND r->>'classification_notice' LIKE 'resolved_only%','only two resolved A invoices, explicit notice');
    r:=public.rpc_multi07_get_invoice(t,a,current_setting('m07.ia')::uuid);item:=r->'item';
    PERFORM pg_temp.m07_check((item->>'amount')::numeric=100 AND (item->>'paid_amount')::numeric=20
        AND (item->>'credit_amount')::numeric=10 AND (item->>'balance_amount')::numeric=70,'unchanged paid/credit/balance formula');
    PERFORM pg_temp.m07_check(jsonb_array_length(r->'payments')=1 AND jsonb_array_length(r->'credit_notes')=1
        AND jsonb_array_length(r->'complements')=1 AND r::text NOT LIKE '%SYNTHETIC_PRIVATE_CANARY%','minimal detail graph without private fields');
    SELECT array_agg(k ORDER BY k) INTO actual FROM jsonb_object_keys(item) k;
    SELECT array_agg(k ORDER BY k) INTO expected FROM unnest(ARRAY['id','company_id','operation_id','direction','reference','counterparty_name',
        'currency','status','due_date','amount','paid_amount','credit_amount','balance_amount','created_at']) k;
    PERFORM pg_temp.m07_check(actual=expected,'exact invoice DTO, not whole-row JSON');
    PERFORM pg_temp.m07_check(public.rpc_multi07_get_invoice(t,a,current_setting('m07.ib')::uuid)->>'error'='not_found'
        AND public.rpc_multi07_get_invoice(t,a,current_setting('m07.ix')::uuid)->>'error'='not_found'
        AND public.rpc_multi07_get_invoice(t,a,current_setting('m07.ip')::uuid)->>'error'='not_found'
        AND public.rpc_multi07_get_invoice(t,a,current_setting('m07.payroll')::uuid)->>'error'='not_found',
        'direct ID foreign/pending/payroll denied even with financial.full.read');
    PERFORM pg_temp.m07_check(public.rpc_multi07_list_invoices(current_setting('m07.x')::uuid,ARRAY[a])->>'error'='unauthorized'
        AND public.rpc_multi07_list_invoices(t,ARRAY[current_setting('m07.xc')::uuid])->>'error'='unauthorized','tenant/company manipulation');
    r:=public.rpc_multi07_list_invoices(t,ARRAY[a],'needle','ar','MXN');
    PERFORM pg_temp.m07_check((r->>'total')::int=1 AND r->'items'->0->>'reference'='IA','search/direction/currency scoped before count');
    LOOP
        r:=public.rpc_multi07_list_invoices(t,ARRAY[a],'','','',cursor,1);
        ids:=array_append(ids,(r->'items'->0->>'id')::uuid);cursor:=(r->>'next_cursor')::uuid;
        EXIT WHEN cursor IS NULL;
        PERFORM pg_temp.m07_check(cardinality(ids)<=2,'bounded cursor');
    END LOOP;
    PERFORM pg_temp.m07_check(cardinality(ids)=2 AND ids[1]<>ids[2],'pagination without repeats or cross-company rows');
    PERFORM pg_temp.m07_check(public.rpc_multi07_list_invoices(t,ARRAY[a],'','','',current_setting('m07.ib')::uuid)->>'error'='invalid_cursor','foreign cursor');
    PERFORM pg_temp.m07_check(public.rpc_multi07_list_invoices(t,ARRAY[a],'','bad')->>'error'='invalid_filters','invalid filters');
    PERFORM pg_temp.m07_check(public.rpc_multi07_finance_summary(t,ARRAY[a,b],true)->>'error'='unauthorized'
        AND public.rpc_multi07_finance_summary(t,ARRAY[a,b],false)->>'error'='unauthorized','full read per company does not consolidate');
    PERFORM pg_temp.m07_check(public.rpc_multi07_finance_summary(t,ARRAY[a,a])->>'error'='unauthorized'
        AND public.rpc_multi07_finance_summary(t,ARRAY[a,NULL])->>'error'='unauthorized'
        AND public.rpc_multi07_finance_summary(t,ARRAY[]::uuid[])->>'error'='unauthorized'
        AND public.rpc_multi07_finance_summary(t,array_fill(a,ARRAY[1],ARRAY[0]))->>'error'='unauthorized','invalid scopes fail without data');
    r:=public.rpc_multi07_finance_summary(t,ARRAY[a]);
    PERFORM pg_temp.m07_check(EXISTS(SELECT FROM jsonb_array_elements(r->'groups') q WHERE q->>'direction'='ar' AND (q->>'balance_amount')::numeric=70),
        'summary groups company/currency/direction without pending amounts');
    PERFORM pg_temp.m07_check(public.rpc_multi07_export_invoices_page(t,ARRAY[a])->>'error'='unauthorized','export is separate');
    PERFORM pg_temp.m07_check(public.rpc_get_finance_invoice_detail(t,current_setting('m07.ia')::uuid)->'invoice'->>'reference'='IA',
        'legacy single-ID uses individual full read without consolidation');
    r:=public.rpc_list_finance_invoices(t,'{}'::jsonb);
    PERFORM pg_temp.m07_check(jsonb_array_length(r->'items')=1,'legacy set cannot combine classified companies without consolidation');
END; $positive$;
RESET ROLE;
SELECT 'PASS: explicit financial read, exact DTO/detail, scope/filter/count/cursor and separate consolidation/export';

DO $grant_consolidation$
DECLARE g uuid; t uuid:=current_setting('m07.t')::uuid; u uuid:=current_setting('m07.reader')::uuid;
BEGIN
    INSERT INTO public.membership_consolidation_grants(tenant_id,user_id,financial_binding_id,approval_reference,granted_by)
        VALUES(t,u,current_setting('m07.binding')::uuid,'synthetic-consolidation',u) RETURNING id INTO g;
    INSERT INTO public.consolidation_grant_companies(tenant_id,user_id,consolidation_grant_id,company_id)
        VALUES(t,u,g,current_setting('m07.a')::uuid),(t,u,g,current_setting('m07.b')::uuid);
    INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,financial_binding_id,approval_reference,granted_by)
        VALUES(t,u,current_setting('m07.a')::uuid,'export.financial',current_setting('m07.binding')::uuid,'synthetic-export-A',u);
END; $grant_consolidation$;
SET LOCAL ROLE authenticated;
DO $consolidation$
DECLARE t uuid:=current_setting('m07.t')::uuid; a uuid:=current_setting('m07.a')::uuid; b uuid:=current_setting('m07.b')::uuid; r jsonb;
BEGIN
    r:=public.rpc_multi07_finance_summary(t,ARRAY[a,b],true);
    PERFORM pg_temp.m07_check(EXISTS(SELECT FROM jsonb_array_elements(r->'groups') q WHERE q->>'direction'='ar'
        AND q->'company_id'='null'::jsonb AND (q->>'amount')::numeric=300 AND (q->>'balance_amount')::numeric=270),'explicit consolidated total');
    PERFORM pg_temp.m07_check(public.rpc_multi07_export_invoices_page(t,ARRAY[a,b],'','','',NULL,50,true)->>'error'='unauthorized',
        'missing B export rejects entire requested set');
    PERFORM pg_temp.m07_check(public.rpc_multi07_export_invoices_page(t,ARRAY[a])=public.rpc_multi07_list_invoices(t,ARRAY[a]),'screen/export exact same A rows/columns');
    PERFORM pg_temp.m07_check(public.rpc_multi07_finance_summary(t,ARRAY[a,b,current_setting('m07.xc')::uuid],true)->>'error'='unauthorized','consolidation cannot expand scope');
END; $consolidation$;
RESET ROLE;
INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,financial_binding_id,approval_reference,granted_by)
VALUES(current_setting('m07.t')::uuid,current_setting('m07.reader')::uuid,current_setting('m07.b')::uuid,'export.financial',
    current_setting('m07.binding')::uuid,'synthetic-export-B',current_setting('m07.reader')::uuid);
SET LOCAL ROLE authenticated;
SELECT pg_temp.m07_check((public.rpc_multi07_export_invoices_page(current_setting('m07.t')::uuid,
    ARRAY[current_setting('m07.a')::uuid,current_setting('m07.b')::uuid],'','','',NULL,50,true)->>'total')::int=3,'authorized A+B export only three resolved rows');
RESET ROLE;
SELECT 'PASS: explicit consolidation set and per-company financial export grants';

DO $revoke$
DECLARE t uuid:=current_setting('m07.t')::uuid; a uuid:=current_setting('m07.a')::uuid; b uuid:=current_setting('m07.b')::uuid;
    u uuid:=current_setting('m07.reader')::uuid;
BEGIN
    UPDATE public.membership_company_capabilities SET status='revoked',revoked_at=now(),revoked_by=u
        WHERE user_id=u AND company_id=b AND capability_code='export.financial';
    PERFORM pg_temp.m07_check(public.rpc_multi07_export_invoices_page(t,ARRAY[a,b],'','','',NULL,50,true)->>'error'='unauthorized','export revoked before next page');
    UPDATE public.membership_company_access SET status='revoked',revoked_at=now(),revoked_by=u WHERE user_id=u AND company_id=b;
    PERFORM pg_temp.m07_check(public.rpc_multi07_finance_summary(t,ARRAY[a,b],true)->>'error'='unauthorized'
        AND public.rpc_multi07_finance_summary(t,ARRAY[a])->>'error' IS NULL,'access revocation denies whole consolidated scope, preserves independent A');
    UPDATE public.membership_company_access SET status='active',revoked_at=NULL,revoked_by=NULL WHERE user_id=u AND company_id=b;
    UPDATE private.financial_principal_bindings SET status='revoked',revoked_at=now(),revoked_by=u WHERE user_id=u;
    PERFORM pg_temp.m07_check(public.rpc_multi07_list_invoices(t,ARRAY[a])->>'error'='unauthorized','binding revocation without refreshing claims');
    UPDATE private.financial_principal_bindings SET status='active',revoked_at=NULL,revoked_by=NULL WHERE user_id=u;
    UPDATE public.companies SET status='inactive' WHERE id=a;
    PERFORM pg_temp.m07_check(public.rpc_multi07_get_invoice(t,a,current_setting('m07.ia')::uuid)->>'error'='unauthorized','inactive company');
    UPDATE public.companies SET status='active' WHERE id=a;
END; $revoke$;
SELECT 'PASS: export/access/binding revocation and inactive company deny following requests';

-- Verify actual restrictive RLS even if a raw-table grant is accidentally added.
GRANT SELECT,INSERT,UPDATE,DELETE ON public.finance_invoices,public.finance_payments,public.billing_documents,
    public.billing_credit_notes,public.billing_payment_complements TO authenticated;
-- Isolate RLS from the legacy policy helper's separate EXECUTE denial.
GRANT EXECUTE ON FUNCTION private.f4_user_can_manage_finance(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.f4_amount_mxn(numeric,text,numeric) TO authenticated;
-- Also satisfy the direct metadata dependency of restored legacy policies;
-- the assertion must exercise RLS, not stop on that separate ACL denial.
GRANT SELECT(user_id,tenant_id,role) ON public.memberships TO authenticated;
SET LOCAL ROLE authenticated;
DO $raw_rls$ DECLARE t text; n int;
BEGIN
    FOREACH t IN ARRAY ARRAY['finance_invoices','finance_payments','billing_documents','billing_credit_notes','billing_payment_complements'] LOOP
        EXECUTE 'SELECT count(*) FROM public.'||t INTO n;PERFORM pg_temp.m07_check(n=0,'restrictive raw RLS, even verified full reader');
    END LOOP;
    UPDATE public.finance_invoices SET company_id=current_setting('m07.b')::uuid;GET DIAGNOSTICS n=ROW_COUNT;
    PERFORM pg_temp.m07_check(n=0,'no self-reclassification under accidental grant');
    PERFORM pg_temp.m07_error('INSERT INTO public.finance_invoices(tenant_id,direction,counterparty_name,amount)
        VALUES(current_setting(''m07.t'')::uuid,''ar'',''synthetic'',1)','42501');
END; $raw_rls$;
RESET ROLE;
REVOKE ALL ON public.finance_invoices,public.finance_payments,public.billing_documents,public.billing_credit_notes,public.billing_payment_complements FROM authenticated;
REVOKE EXECUTE ON FUNCTION private.f4_user_can_manage_finance(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION private.f4_amount_mxn(numeric,text,numeric) FROM authenticated;
SET LOCAL ROLE rotero_finance_scope_owner;
SELECT pg_temp.m07_error('SELECT amount FROM public.finance_invoices','42501');
RESET ROLE;
SET LOCAL ROLE rotero_finance_read_owner;
SELECT pg_temp.m07_check((SELECT count(*)=3 FROM public.finance_invoices),'dedicated reader sees only resolved authorized A/B');
SELECT pg_temp.m07_error('SELECT bank_reference FROM public.finance_payments','42501');
RESET ROLE;
SELECT 'PASS: effective restrictive RLS and metadata/financial reader column boundaries';

-- Emulate pre-existing drift only in this disposable transaction. The guard
-- must reject its payload without blocking an unrelated graph or repairing it.
ALTER TABLE public.finance_invoices DISABLE TRIGGER finance_invoices_m07_coherence;
INSERT INTO public.finance_invoices(tenant_id,operation_id,billing_document_id,direction,counterparty_name,amount)
VALUES(current_setting('m07.t')::uuid,current_setting('m07.oa')::uuid,current_setting('m07.db')::uuid,'ar','Synthetic historical conflict',1);
ALTER TABLE public.finance_invoices ENABLE TRIGGER finance_invoices_m07_coherence;
ALTER TABLE public.billing_credit_notes DISABLE TRIGGER billing_credit_notes_m07_coherence;
INSERT INTO public.billing_credit_notes(tenant_id,finance_invoice_id,source_billing_document_id,total,status)
VALUES(current_setting('m07.t')::uuid,current_setting('m07.ip')::uuid,current_setting('m07.db')::uuid,1,'applied');
ALTER TABLE public.billing_credit_notes ENABLE TRIGGER billing_credit_notes_m07_coherence;
INSERT INTO public.operations(tenant_id,reference_code) VALUES(current_setting('m07.t')::uuid,'UNRELATED');
SELECT pg_temp.m07_check(NOT private.multi07_legacy_visible('invoice',(SELECT id FROM public.finance_invoices WHERE counterparty_name='Synthetic historical conflict'),'single'),
    'old incompatible graph fails closed; unrelated operation remains usable');
SELECT pg_temp.m07_check(NOT private.multi07_legacy_visible('invoice',current_setting('m07.ip')::uuid,'single'),
    'known-company child cannot leak through an unclassified legacy invoice total');
SELECT 'PASS: historical conflict does not globally block unrelated operational writes';
ROLLBACK;

DO $clean$
BEGIN
    IF (SELECT count(*) FROM public.finance_invoices)<>(SELECT invoices FROM m07_before_counts)
        OR (SELECT count(*) FROM public.operations)<>(SELECT operations FROM m07_before_counts)
        OR (SELECT count(*) FROM private.finance_invoices_company_evidence)<>(SELECT invoice_evidence FROM m07_before_counts)
        OR (SELECT count(*) FROM private.billing_documents_company_evidence)<>(SELECT document_evidence FROM m07_before_counts)
        OR (SELECT count(*) FROM private.billing_credit_notes_company_evidence)<>(SELECT credit_evidence FROM m07_before_counts)
        OR (SELECT count(*) FROM public.tenants WHERE slug LIKE 'm07-%')<>(SELECT synthetic_tenants FROM m07_before_counts)
        OR has_function_privilege('authenticated','public.rpc_multi07_list_invoices(uuid,uuid[],text,text,text,uuid,integer,boolean)','EXECUTE') THEN
        RAISE EXCEPTION 'MULTI07 fixture or activation residue';
    END IF;
END; $clean$;
SELECT 'PASS: fixture/evidence/activation/raw grants all rolled back';
