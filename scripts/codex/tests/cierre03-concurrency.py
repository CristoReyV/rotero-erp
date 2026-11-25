"""Real concurrent SQL sessions, only in an explicitly disposable loopback DB."""
from pathlib import Path
import concurrent.futures,datetime,json,os,re,subprocess,threading,uuid

assert os.environ.get('LOCAL_QA_ALLOW_DISPOSABLE_FIXTURES')=='1'
project=os.environ['LOCAL_QA_PROJECT'];database=os.environ['LOCAL_QA_DB'];out=Path(os.environ['LOCAL_QA_OUT'])
assert re.fullmatch(r'rotero-[a-z0-9-]+-delivery-[a-z0-9]+',project)
assert re.fullmatch(r'c03_races_[a-f0-9]{8}',database)
container='supabase_db_'+project
info=json.loads(subprocess.check_output(['docker','inspect',container]))[0]
assert info['Config']['Labels'].get('com.supabase.cli.project')==project
assert all(v['HostIp']=='127.0.0.1' for values in info['HostConfig']['PortBindings'].values() for v in values or [])
run=uuid.uuid4().hex
ids={k:str(uuid.uuid4()) for k in ['tenant','a','b','actor','driver1','vehicle1','driver2','vehicle2','edit','assign_a','assign_b','transition_a','transition_b']}
fixture=out/('c03-concurrency-fixtures-'+run+'.json')
with fixture.open('x',encoding='utf8') as f:json.dump({'project':project,'database':database,'ids':ids,'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat()},f,indent=2)
cmd=['docker','exec','-i',container,'psql','-XqAt','-v','ON_ERROR_STOP=1','-U','postgres','-d',database]
def sql(value):
 p=subprocess.run(cmd,input=value.encode(),capture_output=True,timeout=90)
 if p.returncode:raise RuntimeError('Local SQL rejected; '+p.stderr.decode(errors='replace')[-1600:])
 return p.stdout.decode()
def lit(value):return "'"+str(value).replace("'","''")+"'"
t=ids['tenant'];u=ids['actor']
seed=f"BEGIN;INSERT INTO auth.users(id,email) VALUES('{u}','race-{run}@example.test');INSERT INTO public.tenants(id,name,slug) VALUES('{t}','SYNTHETIC C03 RACE','c03-race-{run}');INSERT INTO public.memberships(user_id,tenant_id,role) VALUES('{u}','{t}','operator');INSERT INTO private.delivery_tenant_cutovers(tenant_id,enabled,approval_reference,approved_by) VALUES('{t}',true,'LOCAL_SYNTHETIC_RACE','{u}');UPDATE public.automation_rules SET is_enabled=false WHERE tenant_id='{t}';SET LOCAL ROLE rotero_company_access_owner;"
for key,rfc in [('a','QCA010101ZZ1'),('b','QCB010101ZZ2')]:
 c=ids[key];seed+=f"INSERT INTO public.companies(id,tenant_id,display_name,legal_name,rfc_normalized,status) VALUES('{c}','{t}','Synthetic {key}','SYNTHETIC RACE {key}','{rfc}','active');INSERT INTO public.membership_company_access(tenant_id,user_id,company_id,granted_by) VALUES('{t}','{u}','{c}','{u}');"
 for cap in ['operations.read','operations.capture','operations.edit','operations.assign','operations.transition']:
  seed+=f"INSERT INTO public.membership_company_capabilities(tenant_id,user_id,company_id,capability_code,approval_reference,granted_by) VALUES('{t}','{u}','{c}','{cap}','LOCAL_SYNTHETIC_RACE','{u}');"
seed+='RESET ROLE;'
for n in [1,2]:
 seed+=f"INSERT INTO public.drivers(id,tenant_id,display_name) VALUES('{ids['driver'+str(n)]}','{t}','Synthetic driver {n}');INSERT INTO public.vehicles(id,tenant_id,unit_code) VALUES('{ids['vehicle'+str(n)]}','{t}','SYNTHETIC-{run}-{n}');"
for key,company in [('edit','a'),('assign_a','a'),('assign_b','b'),('transition_a','a'),('transition_b','b')]:
 op=ids[key];e=str(uuid.uuid5(uuid.UUID(op),'classification'));assigned=key.startswith('transition')
 driver=lit(ids['driver2']) if assigned else 'NULL';vehicle=lit(ids['vehicle2']) if assigned else 'NULL'
 seed+=f"INSERT INTO public.operations(id,tenant_id,reference_code,status,execution_type,service_type,route_summary,destination_city,origin_place,destination_place,operational_window_start,operational_window_end,planned_departure,driver_id,vehicle_id,cargo_summary) VALUES('{op}','{t}','C03-{key}-{run}','planned','own_fleet','Synthetic','QA A to QA B','QA B','{{\"countryCode\":\"MX\",\"state\":\"QA\",\"municipality\":\"A\"}}','{{\"countryCode\":\"MX\",\"state\":\"QA\",\"municipality\":\"B\"}}',now()+interval '1 hour',now()+interval '3 hours',now()+interval '1 hour',{driver},{vehicle},'{{\"description\":\"Synthetic\"}}');SET LOCAL ROLE rotero_operations_read_owner;INSERT INTO private.operation_company_classification_events(id,tenant_id,operation_id,company_id,decision,evidence_kind,evidence_reference,recorded_by) VALUES('{e}','{t}','{op}','{ids[company]}','resolved','verified_source_record','LOCAL_SYNTHETIC_RACE','{u}');RESET ROLE;UPDATE public.operations SET company_id='{ids[company]}',company_classification_status='resolved',company_classification_event_id='{e}' WHERE id='{op}';"
seed+='COMMIT;';sql(seed)
def call(action,op,company,payload,key,revision,barrier):
 settings={'request.jwt.claim.sub':u,'request.jwt.claims':json.dumps({'sub':u,'role':'authenticated','iss':'https://synthetic-access.invalid/auth/v1'}),'request.headers':json.dumps({'x-rotero-scope':'company','x-rotero-company-id':ids[company]})}
 q='BEGIN;SET LOCAL ROLE authenticated;'+''.join('SET LOCAL '+lit(k).replace("'",'"')+'='+lit(v)+';' for k,v in settings.items())
 if action=='create':q+=f"SELECT public.rpc_delivery_create_operation_once('{t}','{key}',{lit(payload['reference'])});"
 else:q+=f"SELECT public.rpc_delivery_operation_action('{t}','{ids[op]}',{lit(action)},{lit(json.dumps(payload))}::jsonb,'{key}',{revision});"
 q+='SELECT pg_sleep(0.25);COMMIT;'
 barrier.wait(timeout=10);raw=sql(q);return json.loads(next(line for line in raw.splitlines() if line.startswith('{')))
results=[]
def race(label,calls):
 barrier=threading.Barrier(2)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
  futures=[pool.submit(call,*args,barrier) for args in calls]
  rows=[f.result(timeout=100) for f in futures]
 result={'case':label,'results':rows}
 results.append(result)
 with (out/('c03-race-'+run+'-'+str(len(results))+'.json')).open('x',encoding='utf8') as f:json.dump(result,f,indent=2)
 print(json.dumps(result),flush=True)
 return rows
key=str(uuid.uuid4());payload={'route_summary':'SYNTHETIC SAME REQUEST'}
creation=race('concurrent capture creates one root', [('create','edit','a',{'reference':'C03-CREATE-'+run},str(uuid.uuid5(uuid.UUID(run),'capture')),0)]*2)
assert creation[0]==creation[1] and creation[0].get('workflow_revision')==0
assert sql(f"SELECT count(*) FROM public.operations WHERE tenant_id='{t}' AND reference_code='C03-CREATE-{run}';").strip()=='1'
same=race('same request commits once', [('edit','edit','a',payload,key,0)]*2)
assert same[0]==same[1] and same[0].get('workflow_revision')==1
different=race('different requests with stale version', [('edit','edit','a',{'route_summary':v},str(uuid.uuid4()),1) for v in ['LEFT','RIGHT']])
assert sum(r.get('success') is True for r in different)==1 and sum(r.get('error')=='stale_operation' for r in different)==1
assignment={'execution_type':'own_fleet','driver_id':ids['driver1'],'vehicle_id':ids['vehicle1'],'reason':'Synthetic resource concurrency verification','planned_departure':(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(hours=1)).isoformat()}
assigned=race('shared resources across companies', [('assign',op,co,assignment,str(uuid.uuid4()),0) for op,co in [('assign_a','a'),('assign_b','b')]])
assert sum(r.get('success') is True for r in assigned)==1 and sum('error' in r for r in assigned)==1
transition=race('shared resources on transition', [('transition',op,co,{'to_status':'assigned'},str(uuid.uuid4()),0) for op,co in [('transition_a','a'),('transition_b','b')]])
assert sum(r.get('success') is True for r in transition)==1 and sum('error' in r for r in transition)==1
state=json.loads(sql(f"SELECT jsonb_build_object('revision',(SELECT workflow_revision FROM public.operations WHERE id='{ids['edit']}'),'successful_edit_receipts',(SELECT count(*) FROM private.c03_operation_commands WHERE operation_id='{ids['edit']}' AND outcome->>'success'='true'),'active_shared_assignments',(SELECT count(*) FROM public.operations WHERE tenant_id='{t}' AND driver_id='{ids['driver1']}' AND status IN('assigned','in_transit')),'active_shared_transitions',(SELECT count(*) FROM public.operations WHERE tenant_id='{t}' AND driver_id='{ids['driver2']}' AND status IN('assigned','in_transit')));").strip())
assert state=={'revision':2,'successful_edit_receipts':2,'active_shared_assignments':1,'active_shared_transitions':1}
report={'passed':True,'project':project,'database':database,'fixture_manifest':fixture.name,'results':results,'persisted_state':state,'scope':'real independent local SQL sessions; no remote execution, passwords or mock handlers','cleanup':'owned database removed with disposable project; no immutable audit deleted'}
with (out/('c03-concurrency-results-'+run+'.json')).open('x',encoding='utf8') as f:json.dump(report,f,indent=2)
print(json.dumps({'passed':True,'races':len(results),'persisted_state':state,'manifest':fixture.name}))
