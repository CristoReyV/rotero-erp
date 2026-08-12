[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$codexRoot = Split-Path -Parent $PSScriptRoot
$orchestrator = Join-Path $codexRoot 'tracking-handoff-orchestrator.ps1'
$runner = Join-Path $codexRoot 'tracking-handoff-runner.ps1'
$guard = Join-Path $PSScriptRoot 'tracking-handoff-test-guard.ps1'
$inputProvider = Join-Path $PSScriptRoot 'tracking-handoff-test-input.ps1'
$matrix = Join-Path $PSScriptRoot 'tracking-handoff-test-matrix.ps1'
$revoke = Join-Path $PSScriptRoot 'tracking-handoff-test-revoke.ps1'
$artifactRoot = Join-Path ([IO.Path]::GetTempPath()) ("rotero-m44-handoff-tests-" + [Guid]::NewGuid().ToString('N'))
$mutexName = 'Local\ROTERO-M44-QA-HANDOFF-TEST-' + [Guid]::NewGuid().ToString('N')
$projectRef = 'abcdefghijklmnopqrst'
$operationCode = 'SYNTHETIC-OPS-001'
$script:assertions = 0

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    $script:assertions++
    if ($Actual -ne $Expected) {
        throw "$Message (expected=$Expected actual=$Actual)"
    }
}

function Invoke-OrchestratorCase {
    param(
        [Parameter(Mandatory = $true)][string]$PublicUrl,
        [Parameter(Mandatory = $true)][string]$DriverUrl,
        [int]$ExpectedExit = 0,
        [int]$ExpectedPublicPrompts = 1,
        [int]$ExpectedDriverPrompts = 1,
        [int]$PublicActive = 0,
        [int]$DriverActive = 0,
        [int]$WriteCount = 1,
        [switch]$MatrixFailure
    )

    $env:ROTERO_TEST_PUBLIC_URL = $PublicUrl
    $env:ROTERO_TEST_DRIVER_URL = $DriverUrl
    $env:ROTERO_TEST_PUBLIC_ACTIVE = [string]$PublicActive
    $env:ROTERO_TEST_DRIVER_ACTIVE = [string]$DriverActive
    $env:ROTERO_TEST_WRITE_COUNT = [string]$WriteCount
    $env:ROTERO_TEST_MATRIX_FAIL = if ($MatrixFailure) { '1' } else { '0' }
    $env:ROTERO_TEST_REVOKE_FAIL = '0'

    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $orchestrator,
        '-ProjectRef', $projectRef, '-OperationCode', $operationCode,
        '-GuardScript', $guard, '-MatrixScript', $matrix, '-RevokeScript', $revoke,
        '-InputProviderScript', $inputProvider, '-MutexName', $mutexName,
        '-ArtifactRoot', $artifactRoot
    )
    $output = & powershell.exe @arguments
    $actualExit = $LASTEXITCODE
    Assert-Equal $actualExit $ExpectedExit 'orchestrator exit code'
    $result = $output | Select-Object -Last 1 | ConvertFrom-Json
    Assert-Equal ([int]$result.prompt_counts.public) $ExpectedPublicPrompts 'PUBLIC prompt count'
    Assert-Equal ([int]$result.prompt_counts.driver) $ExpectedDriverPrompts 'DRIVER prompt count'
    if ($result.prompt_counts.public -gt 1 -or $result.prompt_counts.driver -gt 1) {
        throw 'prompt counts exceeded 1/1'
    }
    return $result
}

$public = 'https://staging.invalid/t/pppppppppppppppppppppppppppppppp'
$driver = 'https://staging.invalid/driver/dddddddddddddddddddddddddddddddd'

try {
    Invoke-OrchestratorCase -PublicUrl $public -DriverUrl $driver | Out-Null
    Invoke-OrchestratorCase -PublicUrl "  $public  " -DriverUrl "  $driver  " | Out-Null
    Invoke-OrchestratorCase -PublicUrl "'$public'" -DriverUrl "`"$driver`"" | Out-Null
    Invoke-OrchestratorCase -PublicUrl "${public}?utm_source=dummy" -DriverUrl "${driver}?x=1" | Out-Null
    Invoke-OrchestratorCase -PublicUrl "${public}#dummy" -DriverUrl "${driver}#dummy" | Out-Null

    Invoke-OrchestratorCase -PublicUrl 'https://staging.invalid/t/bad' -DriverUrl $driver -ExpectedExit 21 | Out-Null
    Invoke-OrchestratorCase -PublicUrl $public -DriverUrl 'https://staging.invalid/driver/bad' -ExpectedExit 22 | Out-Null
    Invoke-OrchestratorCase -PublicUrl $public -DriverUrl $driver -PublicActive 1 -ExpectedExit 10 -ExpectedPublicPrompts 0 -ExpectedDriverPrompts 0 | Out-Null
    Invoke-OrchestratorCase -PublicUrl $public -DriverUrl $driver -DriverActive 1 -ExpectedExit 10 -ExpectedPublicPrompts 0 -ExpectedDriverPrompts 0 | Out-Null
    Invoke-OrchestratorCase -PublicUrl $public -DriverUrl $driver -MatrixFailure -ExpectedExit 31 | Out-Null

    $heldMutex = New-Object Threading.Mutex($false, $mutexName)
    $held = $heldMutex.WaitOne(0, $false)
    Assert-Equal $held $true 'test mutex acquisition'
    try {
        $directAttempt = [Guid]::NewGuid().ToString('N')
        $directDirectory = Join-Path $artifactRoot $directAttempt
        New-Item -ItemType Directory -Path $directDirectory -Force | Out-Null
        $directResult = Join-Path $directDirectory 'result.json'
        $directArguments = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner,
            '-AttemptId', $directAttempt, '-ResultPath', $directResult,
            '-GuardScript', $guard, '-MatrixScript', $matrix, '-RevokeScript', $revoke,
            '-ProjectRef', $projectRef, '-OperationCode', $operationCode,
            '-InputProviderScript', $inputProvider, '-MutexName', $mutexName
        )
        & powershell.exe @directArguments | Out-Null
        Assert-Equal $LASTEXITCODE 12 'second-instance lock exit code'
        $lockedResult = Get-Content -LiteralPath $directResult -Raw | ConvertFrom-Json
        Assert-Equal ([int]$lockedResult.prompt_counts.public) 0 'locked PUBLIC prompt count'
        Assert-Equal ([int]$lockedResult.prompt_counts.driver) 0 'locked DRIVER prompt count'
        Remove-Item -LiteralPath $directDirectory -Recurse -Force
    }
    finally {
        if ($held) { $heldMutex.ReleaseMutex() }
        $heldMutex.Dispose()
    }

    $orchestratorSource = Get-Content -LiteralPath $orchestrator -Raw
    Assert-Equal ([regex]::Matches($orchestratorSource, 'Start-Process').Count) 1 'single child launch statement'
    Assert-Equal ([regex]::Matches($orchestratorSource, '(?i)-NoExit').Count) 0 'NoExit absence'
    Assert-Equal ([regex]::Matches($orchestratorSource, '(?i)retry|relaunch').Count) 0 'retry/relaunch loop absence'

    $guardSource = Get-Content -LiteralPath (Join-Path $codexRoot 'tracking-handoff-residue-guard.ps1') -Raw
    Assert-Equal ([regex]::Matches($guardSource, '(?im)^\s*(insert|update|delete|merge|alter|drop|create|truncate|grant|revoke)\b').Count) 0 'guard mutating SQL absence'

    Start-Sleep -Milliseconds 150
    $surviving = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'powershell.exe' -and $_.CommandLine -like "*tracking-handoff-runner.ps1*" -and $_.CommandLine -like "*$mutexName*"
    })
    Assert-Equal $surviving.Count 0 'successful/failed attempts exit permanently'

    $remainingArtifacts = if (Test-Path -LiteralPath $artifactRoot) { @(Get-ChildItem -LiteralPath $artifactRoot -Force).Count } else { 0 }
    Assert-Equal $remainingArtifacts 0 'per-attempt artifacts cleaned after consume'

    [pscustomobject]@{
        status = 'PASS'
        assertions = $script:assertions
        synthetic_cases = 10
        secret_artifacts = 0
    } | ConvertTo-Json -Compress
}
finally {
    Remove-Item Env:ROTERO_TEST_PUBLIC_URL -ErrorAction SilentlyContinue
    Remove-Item Env:ROTERO_TEST_DRIVER_URL -ErrorAction SilentlyContinue
    Remove-Item Env:ROTERO_TEST_PUBLIC_ACTIVE -ErrorAction SilentlyContinue
    Remove-Item Env:ROTERO_TEST_DRIVER_ACTIVE -ErrorAction SilentlyContinue
    Remove-Item Env:ROTERO_TEST_WRITE_COUNT -ErrorAction SilentlyContinue
    Remove-Item Env:ROTERO_TEST_MATRIX_FAIL -ErrorAction SilentlyContinue
    Remove-Item Env:ROTERO_TEST_REVOKE_FAIL -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $artifactRoot) {
        Remove-Item -LiteralPath $artifactRoot -Recurse -Force
    }
}
