[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9]{20}$')][string]$ProjectRef,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9._-]{1,80}$')][string]$OperationCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:SUPABASE_ACCESS_TOKEN) {
    throw 'supabase_access_token_unavailable'
}

$sql = @"
select
  count(*) filter (where t.scope = 'public:read')::integer as public_active,
  count(*) filter (where t.scope = 'driver:write')::integer as driver_active
from public.tracking_tokens t
join public.operations o on o.id = t.operation_id
where o.code = '$OperationCode'
  and t.state = 'active'
  and t.revoked_at is null
  and t.expires_at > now();
"@

$headers = @{
    Authorization = "Bearer $($env:SUPABASE_ACCESS_TOKEN)"
    'Content-Type' = 'application/json'
}
$body = @{
    query = $sql
} | ConvertTo-Json -Depth 3 -Compress

$request = @{
    Method = 'Post'
    Uri = "https://api.supabase.com/v1/projects/$ProjectRef/database/query"
    Headers = $headers
    Body = $body
}
$response = Invoke-RestMethod @request
if ($null -eq $response -or @($response).Count -ne 1) {
    throw 'residue_snapshot_contract_failed'
}

[pscustomobject]@{
    public_active = [int]$response[0].public_active
    driver_active = [int]$response[0].driver_active
}
