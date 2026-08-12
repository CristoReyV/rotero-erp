[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9]{20}$')][string]$ProjectRef,
    [Parameter(Mandatory = $true)][string]$OperationCode,
    [string]$GuardScript = (Join-Path $PSScriptRoot 'tracking-handoff-residue-guard.ps1'),
    [Parameter(Mandatory = $true)][string]$MatrixScript,
    [Parameter(Mandatory = $true)][string]$RevokeScript,
    [string]$InputProviderScript,
    [string]$MutexName = 'Local\ROTERO-M44-QA-HANDOFF',
    [string]$ArtifactRoot = (Join-Path ([IO.Path]::GetTempPath()) 'rotero-m44-handoff')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Quote-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

$attemptId = [Guid]::NewGuid().ToString('N')
$attemptDirectory = Join-Path $ArtifactRoot $attemptId
$resultPath = Join-Path $attemptDirectory 'result.json'
$runnerPath = Join-Path $PSScriptRoot 'tracking-handoff-runner.ps1'
$consumed = $false

try {
    New-Item -ItemType Directory -Path $attemptDirectory -Force | Out-Null

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Quote-ProcessArgument $runnerPath),
        '-AttemptId', $attemptId,
        '-ResultPath', (Quote-ProcessArgument $resultPath),
        '-GuardScript', (Quote-ProcessArgument $GuardScript),
        '-MatrixScript', (Quote-ProcessArgument $MatrixScript),
        '-RevokeScript', (Quote-ProcessArgument $RevokeScript),
        '-ProjectRef', $ProjectRef,
        '-OperationCode', (Quote-ProcessArgument $OperationCode),
        '-MutexName', (Quote-ProcessArgument $MutexName)
    )
    if ($InputProviderScript) {
        $arguments += @('-InputProviderScript', (Quote-ProcessArgument $InputProviderScript))
    }

    $startParameters = @{
        FilePath = 'powershell.exe'
        ArgumentList = ($arguments -join ' ')
        PassThru = $true
        Wait = $true
    }
    if ($InputProviderScript) {
        $startParameters.WindowStyle = 'Hidden'
    }

    # One immutable attempt launches one child, waits once, and never retries.
    $child = Start-Process @startParameters
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw 'terminal_result_missing'
    }

    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $properties = @($result.PSObject.Properties.Name | Sort-Object)
    $expectedProperties = @('exit_code', 'prompt_counts', 'state', 'write_count')
    if (Compare-Object $properties $expectedProperties) {
        throw 'terminal_result_contract_failed'
    }
    if ($result.state -ne 'EXIT' -or [int]$result.exit_code -ne $child.ExitCode) {
        throw 'terminal_result_exit_mismatch'
    }
    if ([int]$result.prompt_counts.public -gt 1 -or [int]$result.prompt_counts.driver -gt 1) {
        throw 'terminal_result_prompt_count_invalid'
    }

    $consumed = $true
    $result | ConvertTo-Json -Depth 3 -Compress
    exit $child.ExitCode
}
finally {
    # Cleanup occurs only after the terminal result and child exit code were consumed.
    if ($consumed -and (Test-Path -LiteralPath $attemptDirectory)) {
        Remove-Item -LiteralPath $attemptDirectory -Recurse -Force
    }
}
