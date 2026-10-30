# Writes synthetic rows only to an explicitly named disposable loopback project.
from pathlib import Path
import os,json,re,subprocess
R=Path(__file__).resolve().parents[3];O=Path(os.environ['LOCAL_QA_OUT'])
assert os.environ.get('LOCAL_QA_ALLOW_DISPOSABLE_FIXTURES')=='1'
project=os.environ['LOCAL_QA_PROJECT'];assert re.fullmatch(r'rotero-[a-z0-9-]*delivery-[a-z0-9-]+',project)
name='supabase_db_'+project
r=subprocess.run(['docker','inspect',name],capture_output=True,check=True)
c=json.loads(r.stdout)[0];assert c['Config']['Labels'].get('com.supabase.cli.project')==project
bindings=c['HostConfig']['PortBindings'];assert bindings and all(b['HostIp']=='127.0.0.1' for values in bindings.values() for b in values or [])
u=os.environ['LOCAL_QA_USER_ID'];assert re.fullmatch(r'[0-9a-f-]{36}',u)
s=(R/'supabase/tests/delivery_company_boundary.sql').read_text()
marker="SELECT pg_temp.actor(current_setting('d.u')";assert s.count(marker)>=1
s=s.split(marker,1)[0];assert "PERFORM set_config('d.file'" in s;assert s.count('u uuid:=gen_random_uuid();ng')==1
s=s.replace('u uuid:=gen_random_uuid();ng',"u uuid:='"+u+"'::uuid;ng")
s+="SELECT json_build_object('tenant',current_setting('d.t'),'company_a',current_setting('d.a'),'company_b',current_setting('d.b'),'operation',current_setting('d.op'),'foreign_operation',current_setting('d.ob'),'invoice',current_setting('d.invoice'),'file',current_setting('d.file'));COMMIT;"
r=subprocess.run(['docker','exec','-i',name,'psql','-XqAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],input=s.encode(),capture_output=True)
assert r.returncode==0,'Disposable synthetic fixture rejected; no automatic retry or cleanup'
rows=r.stdout.decode().splitlines();data=json.loads(next(x for x in rows if x.startswith('{')))
(O/'browser-fixture.json').write_text(json.dumps(data))
