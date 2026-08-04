[CmdletBinding()]
param(
    [string]$ContainerName,
    [string]$OutputPath,
    [string]$ExpectedPath
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker is required to read the local Supabase catalog.'
}

if (-not $ContainerName) {
    $matches = @(& docker ps --filter 'name=supabase_db_' --format '{{.Names}}')
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to enumerate local Supabase database containers.'
    }
    if ($matches.Count -ne 1) {
        throw "Expected exactly one running Supabase database container; found $($matches.Count). Pass -ContainerName explicitly."
    }
    $ContainerName = $matches[0]
}

$sql = @'
WITH catalog AS (
    SELECT 'table|' || c.relname || '|kind=' || c.relkind::text || '|rls=' || c.relrowsecurity::text || '|force_rls=' || c.relforcerowsecurity::text AS line
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm')

    UNION ALL
    SELECT 'column|' || c.relname || '|' || a.attnum::text || '|' || a.attname || '|' ||
           pg_catalog.format_type(a.atttypid, a.atttypmod) || '|not_null=' || a.attnotnull::text ||
           '|default=' || COALESCE(pg_catalog.pg_get_expr(d.adbin, d.adrelid), '')
    FROM pg_catalog.pg_attribute AS a
    JOIN pg_catalog.pg_class AS c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    LEFT JOIN pg_catalog.pg_attrdef AS d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm')
      AND a.attnum > 0 AND NOT a.attisdropped

    UNION ALL
    SELECT 'constraint|' || c.relname || '|' || con.conname || '|' || con.contype::text || '|' ||
           pg_catalog.pg_get_constraintdef(con.oid, true)
    FROM pg_catalog.pg_constraint AS con
    JOIN pg_catalog.pg_class AS c ON c.oid = con.conrelid
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'

    UNION ALL
    SELECT 'index|' || t.relname || '|' || i.relname || '|' || pg_catalog.pg_get_indexdef(i.oid)
    FROM pg_catalog.pg_index AS x
    JOIN pg_catalog.pg_class AS i ON i.oid = x.indexrelid
    JOIN pg_catalog.pg_class AS t ON t.oid = x.indrelid
    JOIN pg_catalog.pg_namespace AS n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'

    UNION ALL
    SELECT 'policy|' || p.tablename || '|' || p.policyname || '|cmd=' || p.cmd ||
           '|roles=' || array_to_string(p.roles, ',') || '|qual=' || COALESCE(p.qual, '') ||
           '|check=' || COALESCE(p.with_check, '')
    FROM pg_catalog.pg_policies AS p
    WHERE p.schemaname = 'public'

    UNION ALL
    SELECT 'function|' || p.proname || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')' ||
           '|result=' || pg_catalog.pg_get_function_result(p.oid) ||
           '|language=' || l.lanname || '|security_definer=' || p.prosecdef::text ||
           '|volatility=' || p.provolatile::text || '|config=' || COALESCE(array_to_string(p.proconfig, ','), '')
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
    JOIN pg_catalog.pg_language AS l ON l.oid = p.prolang
    WHERE n.nspname = 'public'

    UNION ALL
    SELECT 'table_grant|' || g.table_name || '|' || g.grantee || '|' || g.privilege_type
    FROM information_schema.role_table_grants AS g
    WHERE g.table_schema = 'public'
      AND g.grantee IN ('anon', 'authenticated', 'service_role')

    UNION ALL
    SELECT 'function_grant|' || p.proname || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')|' ||
           grantee.rolname || '|' || acl.privilege_type
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
    CROSS JOIN LATERAL pg_catalog.aclexplode(
        COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
    ) AS acl
    JOIN pg_catalog.pg_roles AS grantee ON grantee.oid = acl.grantee
    WHERE n.nspname = 'public'
      AND grantee.rolname IN ('anon', 'authenticated', 'service_role')

    UNION ALL
    SELECT 'trigger|' || c.relname || '|' || t.tgname || '|' || pg_catalog.pg_get_triggerdef(t.oid, true)
    FROM pg_catalog.pg_trigger AS t
    JOIN pg_catalog.pg_class AS c ON c.oid = t.tgrelid
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND NOT t.tgisinternal
)
SELECT regexp_replace(line, '[[:space:]]+', ' ', 'g')
FROM catalog
ORDER BY 1;
'@

$lines = @($sql | & docker exec -i $ContainerName psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -At)
if ($LASTEXITCODE -ne 0) {
    throw 'Catalog query failed.'
}

$normalized = ($lines -join "`n") + "`n"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
}
finally {
    $sha.Dispose()
}

if ($OutputPath) {
    $resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
    [System.IO.File]::WriteAllText($resolvedOutput, $normalized, [System.Text.UTF8Encoding]::new($false))
}

$matchesExpected = $null
if ($ExpectedPath) {
    $expected = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath($ExpectedPath))
    $expected = ($expected -replace "`r`n", "`n")
    if (-not $expected.EndsWith("`n")) {
        $expected += "`n"
    }
    $matchesExpected = ($normalized -ceq $expected)
    if (-not $matchesExpected) {
        Write-Error 'Schema fingerprint content differs from the expected sanitized catalog.'
    }
}

[pscustomobject]@{
    Container = $ContainerName
    Entries = $lines.Count
    Sha256 = $hash
    OutputPath = if ($OutputPath) { [System.IO.Path]::GetFullPath($OutputPath) } else { $null }
    MatchesExpected = $matchesExpected
}
