\set ON_ERROR_STOP on
-- Local synthetic transaction only; compatible with A45 or the restored B45.
BEGIN;
CREATE FUNCTION pg_temp.c02_assert(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'CIERRE02 assertion: %',label;END IF;END $$;
CREATE TEMP TABLE c02_test_results(signature text,test text,result text);

DO $$ DECLARE c record;p record;BEGIN
 PERFORM pg_temp.c02_assert((SELECT count(*) FROM private.c02_contracts)=169,'169 reviewed observed contracts');
 PERFORM pg_temp.c02_assert(NOT pg_has_role('authenticated','rotero_c02_gate_owner','MEMBER')
  AND NOT pg_has_role('anon','rotero_c02_gate_owner','MEMBER')
  AND NOT pg_has_role('service_role','rotero_c02_gate_owner','MEMBER'),'gate owner cannot be assumed');
 PERFORM pg_temp.c02_assert(NOT EXISTS(SELECT FROM pg_roles WHERE rolname='rotero_c02_gate_owner'
  AND (rolcanlogin OR rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb OR rolinherit)),'limited owner');
 PERFORM pg_temp.c02_assert(NOT has_table_privilege('authenticated','private.c02_contracts','SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege('anon','private.c02_contracts','SELECT,INSERT,UPDATE,DELETE'),'registry closed');
 PERFORM pg_temp.c02_assert(NOT has_table_privilege('rotero_c02_gate_owner','public.operations','INSERT,UPDATE,DELETE')
  AND NOT has_column_privilege('rotero_c02_gate_owner','public.operations','provider_cost_amount','SELECT'),'metadata owner has no costs or writes');
 FOR c IN SELECT * FROM private.c02_contracts LOOP
  SELECT x.* INTO p FROM pg_proc x WHERE x.oid=to_regprocedure(c.signature);
  IF NOT FOUND THEN
   PERFORM pg_temp.c02_assert(c.category='canonical_default_redirect' OR (c.source_variant='A' AND c.signature IN
    ('public.rpc_accept_invitation(text, text, text)','public.rpc_revoke_invitation(uuid, uuid)')), 'only reviewed redirected/inert overloads absent');
  ELSE
   IF c.category IN('closed_legacy_rpc','server_only_helper','internal_trigger') THEN
    PERFORM pg_temp.c02_assert(NOT has_function_privilege('anon',p.oid,'EXECUTE')
     AND (c.category='closed_legacy_rpc' OR NOT has_function_privilege('authenticated',p.oid,'EXECUTE')),'individual helper/API ACL: '||c.signature);
   END IF;
   IF c.category IN('closed_legacy_rpc','server_only_helper','internal_trigger','pure_input_helper','own_membership_metadata','keep_token_service_variant') THEN
    PERFORM pg_temp.c02_assert(private.c02_is_reviewed_api(p.oid),'exact admitted contract: '||c.signature);
   END IF;
  END IF;
  INSERT INTO c02_test_results VALUES(c.signature,'reviewed_acl_and_owner','pass');
 END LOOP;
END $$;

-- A shorter overload must resolve normally through the canonical defaults.
SET LOCAL ROLE authenticated;
SELECT pg_temp.c02_assert(public.rpc_dashboard_alerts(NULL::uuid)->>'error' IN('unauthorized','company_adoption_pending'),'dashboard alerts default resolution');
SELECT pg_temp.c02_assert(public.rpc_dashboard_overview(NULL::uuid)->>'error' IN('unauthorized','company_adoption_pending'),'dashboard overview default resolution');
SELECT pg_temp.c02_assert(public.rpc_list_audit_log(NULL::uuid,10)->>'error' IN('unauthorized','company_adoption_pending'),'audit default resolution');
RESET ROLE;

-- Execute every legacy extra RPC with a protected context, including TABLE ABI.
-- No authenticated identity or business rows are required: denial precedes work.
DO $$ DECLARE c record;q text;args text;r jsonb;was_denied boolean;BEGIN
 PERFORM set_config('request.headers','{"x-rotero-scope":"company","x-rotero-company-id":"00000000-0000-4000-8000-000000000001"}',true);
 FOR c IN SELECT reg.*,p.oid,p.proretset,p.prorettype FROM private.c02_contracts reg
 JOIN pg_proc p ON p.oid=to_regprocedure(reg.signature)
 WHERE reg.category='closed_legacy_rpc' OR (reg.category='keep_token_service_variant' AND p.proname='rpc_list_route_points') LOOP
  SELECT string_agg('NULL::'||format_type(t,NULL),',' ORDER BY ord) INTO args FROM unnest((SELECT proargtypes FROM pg_proc WHERE oid=c.oid)) WITH ORDINALITY u(t,ord);
  q:='SELECT '||split_part(c.signature,'(',1)||'('||COALESCE(args,'')||')';r:=NULL;was_denied:=false;
  BEGIN
   SET LOCAL ROLE authenticated;
   IF c.proretset THEN EXECUTE q;ELSE EXECUTE q INTO r;END IF;
  EXCEPTION WHEN insufficient_privilege THEN was_denied:=true;
  END;
  RESET ROLE;
  PERFORM pg_temp.c02_assert(was_denied OR r->>'error'='company_adoption_pending','protected legacy denial: '||c.signature);
  INSERT INTO c02_test_results VALUES(c.signature,'executed_company_denial','pass');
 END LOOP;
 PERFORM set_config('request.headers','{}',true);
END $$;

-- Input-only functions retain their observed behavior, not arbitrary data access.
DO $$ DECLARE c record;args text;live jsonb;archived jsonb;BEGIN
 FOR c IN SELECT reg.*,p.oid FROM private.c02_contracts reg JOIN pg_proc p ON p.oid=to_regprocedure(reg.signature)
 WHERE reg.category='pure_input_helper' AND reg.source_variant='B' LOOP
  SELECT string_agg('NULL::'||format_type(t,NULL),',' ORDER BY ord) INTO args FROM unnest((SELECT proargtypes FROM pg_proc WHERE oid=c.oid)) WITH ORDINALITY u(t,ord);
  EXECUTE 'SELECT to_jsonb('||split_part(c.signature,'(',1)||'('||args||'))' INTO live;
  EXECUTE 'SELECT to_jsonb('||split_part(c.archive_signature,'(',1)||'('||args||'))' INTO archived;
  PERFORM pg_temp.c02_assert(live IS NOT DISTINCT FROM archived,'input helper behavior: '||c.signature);
  INSERT INTO c02_test_results VALUES(c.signature,'executed_input_equivalence','pass');
 END LOOP;
END $$;

-- Mutating a registered wrapper cannot become a new accepted source implicitly.
DO $$ DECLARE f oid:='public.rpc_approve_payroll_period(uuid,uuid)'::regprocedure;BEGIN
 PERFORM pg_temp.c02_assert(private.c02_is_reviewed_api(f),'registered before mutation');
 SET LOCAL ROLE rotero_c02_gate_owner;
 REVOKE EXECUTE ON FUNCTION public.rpc_approve_payroll_period(uuid,uuid) FROM authenticated;
 RESET ROLE;
 PERFORM pg_temp.c02_assert(NOT private.c02_is_reviewed_api(f),'ACL drift rejected');
 SET LOCAL ROLE rotero_c02_gate_owner;
 GRANT EXECUTE ON FUNCTION public.rpc_approve_payroll_period(uuid,uuid) TO authenticated;
 RESET ROLE;
 PERFORM pg_temp.c02_assert(private.c02_is_reviewed_api(f),'restored exact reviewed ACL');
END $$;

SELECT test,count(*) AS contracts FROM c02_test_results GROUP BY test ORDER BY test;
ROLLBACK;
