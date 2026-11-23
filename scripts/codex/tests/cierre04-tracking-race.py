"""Run only after a disposable C04 replay, with no network or published ports."""
import concurrent.futures
import json
import pathlib
import subprocess
import uuid

CONTAINER = 'rotero-c04-20261123-db'
TASK_LABEL = 'c04-20261123'
ROOT = pathlib.Path(__file__).resolve().parents[3]

def docker(*args, data=None):
    return subprocess.run(
        ['docker', *args], input=data, capture_output=True, check=True, timeout=45
    ).stdout.decode('utf-8').strip()

def query(sql):
    return docker(
        'exec', '-i', CONTAINER, 'psql', '-X', '-qAt',
        '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1',
        data=sql.encode('utf-8'),
    ).splitlines()

inspection = json.loads(docker('inspect', CONTAINER))[0]
assert inspection['Config']['Labels'].get('rotero.task') == TASK_LABEL
assert inspection['HostConfig']['NetworkMode'] == 'none'
assert not inspection['HostConfig']['PortBindings']

fixture = (ROOT / 'supabase/tests/cierre04_tracking_workflow.sql').read_text(encoding='utf-8')
setup, separator, _ = fixture.partition('-- All bearer literals stay in the transaction')
assert separator
row = query(setup + """
SELECT jsonb_build_object('tenant',current_setting('d.t'),'actor',current_setting('d.u'),
    'company',current_setting('d.a'),'operation',current_setting('d.flow'));
COMMIT;
""")[-1]
ids = {key: str(uuid.UUID(value)) for key, value in json.loads(row).items()}
tenant, actor, company, operation = (ids[x] for x in ('tenant', 'actor', 'company', 'operation'))
claims = json.dumps({'sub': actor, 'role': 'authenticated', 'iss': 'https://synthetic-access.invalid/auth/v1'})
headers = json.dumps({'x-rotero-scope': 'company', 'x-rotero-company-id': company})

def request(action, expected):
    expect = f"'{uuid.UUID(expected)}'::uuid" if expected else 'NULL::uuid'
    return json.loads(query(rf"""
    BEGIN;
    SET LOCAL ROLE authenticated;
    SELECT set_config('request.jwt.claim.sub','{actor}',true) AS actor_claim \gset
    SELECT set_config('request.jwt.claims','{claims}',true) AS claims \gset
    SELECT set_config('request.headers','{headers}',true) AS selected_scope \gset
    SELECT (public.rpc_delivery_tracking_action('{tenant}','{operation}','public:read',1,'{action}',{expect})-'token')
       || jsonb_build_object('backend_pid',pg_backend_pid());
    COMMIT;
    """)[-1])

expected = request('issue', None)['token_id']
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(lambda _: request('rotate', expected), range(2)))

assert len({result['backend_pid'] for result in results}) == 2
assert sum(result.get('error') == 'conflict' for result in results) == 1
assert sum('token_id' in result for result in results) == 1
assert query(f"""
    SELECT count(*) FROM public.tracking_tokens
    WHERE operation_id='{operation}' AND scope='public:read' AND state='active';
""") == ['1']
print(json.dumps({'race': 'two concurrent rotations of one token', 'passed': True,
                  'successes': 1, 'stale_conflicts': 1, 'active_links': 1}))
