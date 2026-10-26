"""Synthetic concurrency on a disposable MULTI-08 loopback DB; no provider I/O.

Fixture rows are committed to observe real independent transactions. Remove the
owned disposable runtime after the suite; never use an existing business stack.
"""
import concurrent.futures
import json
import re
import subprocess
import sys
import threading
import uuid

container = sys.argv[1]
if not re.fullmatch(r"supabase_db_rotero-multi08-[a-z0-9-]+", container):
    raise SystemExit("A disposable MULTI-08 container is required")
state = json.loads(subprocess.check_output(["docker", "inspect", container]))[0]
project = state["Config"]["Labels"].get("com.supabase.cli.project", "")
assert project.startswith("rotero-multi08-")
bindings = state["HostConfig"]["PortBindings"]
assert bindings and all(e["HostIp"] == "127.0.0.1" for entries in bindings.values() for e in entries or [])


def sql(source):
    return subprocess.run(
        ["docker", "exec", "-i", container, "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=sqlstate", "-U", "postgres", "-d", "postgres"],
        input=source.encode(), capture_output=True, timeout=30,
    )


tenant, company, first, second = [str(uuid.uuid4()) for _ in range(4)]
setup = f"""BEGIN;
INSERT INTO public.tenants(id,name,slug) VALUES('{tenant}','M08 concurrency synthetic','m08-concurrency-{tenant}');
SET LOCAL ROLE rotero_company_access_owner;
INSERT INTO public.companies(id,tenant_id,display_name,legal_name,rfc_normalized,status)
 VALUES('{company}','{tenant}','Synthetic','Synthetic','XXX010101XX1','active');
RESET ROLE;
INSERT INTO public.billing_cfdis(id,tenant_id,rfc_emisor,rfc_receptor,total,status)
 VALUES('{first}','{tenant}','XXX010101XX1','AAA010101AA1',1,'draft'),('{second}','{tenant}','XXX010101XX1','AAA010101AA1',1,'draft');
SET LOCAL ROLE rotero_fiscal_policy_owner;
INSERT INTO private.fiscal_document_origins(cfdi_id,tenant_id,company_id,provider_code,environment,credential_profile)
 VALUES('{first}','{tenant}','{company}','facturama','sandbox','facturama_sandbox_lab_v1'),
 ('{second}','{tenant}','{company}','facturama','sandbox','facturama_sandbox_lab_v1');
COMMIT;"""
assert sql(setup).returncode == 0, "synthetic concurrency setup failed"


def race(document, providers):
    barrier = threading.Barrier(2)

    def claim(provider):
        barrier.wait(timeout=10)
        result = sql(f"BEGIN; SELECT private.multi08_begin_stamp('{document}','{provider}','sandbox','{provider}_sandbox_{'lab_v1' if provider == 'facturama' else 'v1'}'); SELECT pg_sleep(0.4); COMMIT;")
        if result.returncode:
            assert b"23514" in result.stderr, "unexpected concurrency error"
            return "denied"
        return "accepted"

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        outcomes = list(pool.map(claim, providers))
    assert outcomes.count("accepted") == 1 and outcomes.count("denied") == 1
    row = sql(f"SET ROLE rotero_fiscal_policy_owner; SELECT count(*),min(state) FROM private.fiscal_stamp_lanes WHERE cfdi_id='{document}';")
    assert row.returncode == 0 and row.stdout.strip() == b"1|uncertain"
    # A timeout/closed process never releases a stamp for another send.
    again = sql(f"SELECT private.multi08_begin_stamp('{document}','facturama','sandbox','facturama_sandbox_lab_v1');")
    assert again.returncode and b"23514" in again.stderr
    return {"accepted": 1, "denied": 1, "lanes": 1, "uncertain_retry_denied": True}


print(json.dumps({
    "same_provider": race(first, ["facturama", "facturama"]),
    "cross_provider": race(second, ["facturama", "soft_management"]),
    "provider_transport_calls": 0,
    "cleanup": "Remove only the owned disposable runtime after all suites",
}, indent=2))
