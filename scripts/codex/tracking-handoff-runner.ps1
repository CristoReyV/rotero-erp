[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{32}$')][string]$AttemptId,
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [Parameter(Mandatory = $true)][string]$GuardScript,
    [Parameter(Mandatory = $true)][string]$MatrixScript,
    [Parameter(Mandatory = $true)][string]$RevokeScript,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9]{20}$')][string]$ProjectRef,
    [Parameter(Mandatory = $true)][string]$OperationCode,
    [string]$InputProviderScript,
    [string]$MutexName = 'Local\ROTERO-M44-QA-HANDOFF'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:state = 'PREFLIGHT'
$script:publicPromptCount = 0
$script:driverPromptCount = 0
$script:exitCode = 50
$script:writeCount = 0
$script:resultWritten = $false
$script:mutex = $null
$script:ownsMutex = $false
$script:publicValue = $null
$script:driverValue = $null

$transitions = @{
    PREFLIGHT     = @('PUBLIC_PROMPT', 'FAILED')
    PUBLIC_PROMPT = @('DRIVER_PROMPT', 'FAILED')
    DRIVER_PROMPT = @('VALIDATE', 'FAILED')
    VALIDATE      = @('MATRIX', 'FAILED')
    MATRIX        = @('REVOKE', 'FAILED')
    REVOKE        = @('RESULT', 'FAILED')
    FAILED        = @('RESULT')
    RESULT        = @('EXIT')
    EXIT          = @()
}

function Move-HandoffState {
    param([Parameter(Mandatory = $true)][string]$Next)

    if ($transitions[$script:state] -notcontains $Next) {
        throw "invalid_state_transition:$($script:state):$Next"
    }
    $script:state = $Next
}

function ConvertFrom-SecureValue {
    param([Parameter(Mandatory = $true)][Security.SecureString]$Value)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Read-CapabilityValue {
    param([Parameter(Mandatory = $true)][ValidateSet('PUBLIC', 'DRIVER')][string]$Kind)

    if ($Kind -eq 'PUBLIC') {
        $script:publicPromptCount++
    }
    else {
        $script:driverPromptCount++
    }

    if ($InputProviderScript) {
        $provided = & $InputProviderScript -Kind $Kind -AttemptId $AttemptId
        if ($provided -isnot [Security.SecureString]) {
            throw 'input_provider_contract_failed'
        }
        return $provided
    }

    return Read-Host -Prompt "$Kind capability URL" -AsSecureString
}

function Parse-CapabilityUrl {
    param(
        [Parameter(Mandatory = $true)][Security.SecureString]$Value,
        [Parameter(Mandatory = $true)][ValidateSet('PUBLIC', 'DRIVER')][string]$Kind
    )

    $plain = ConvertFrom-SecureValue -Value $Value
    try {
        $candidate = $plain.Trim()
        if ($candidate.Length -ge 2) {
            $first = $candidate.Substring(0, 1)
            $last = $candidate.Substring($candidate.Length - 1, 1)
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $candidate = $candidate.Substring(1, $candidate.Length - 2).Trim()
            }
        }

        $uri = $null
        if (-not [Uri]::TryCreate($candidate, [UriKind]::Absolute, [ref]$uri)) {
            throw 'invalid_absolute_url'
        }
        if ($uri.Scheme -notin @('http', 'https') -or $uri.UserInfo) {
            throw 'invalid_url_authority'
        }

        $segments = $uri.AbsolutePath.Trim('/') -split '/'
        $expectedPrefix = if ($Kind -eq 'PUBLIC') { 't' } else { 'driver' }
        if ($segments.Count -ne 2 -or $segments[0] -ne $expectedPrefix) {
            throw 'invalid_capability_path'
        }
        if ($segments[1] -notmatch '^[A-Za-z0-9_-]{30,}$') {
            throw 'invalid_capability_literal'
        }

        $builder = New-Object System.UriBuilder($uri)
        $builder.Query = ''
        $builder.Fragment = ''
        return $builder.Uri
    }
    finally {
        $plain = $null
        $candidate = $null
    }
}

function Write-TerminalResult {
    $resultDirectory = Split-Path -Parent $ResultPath
    if (-not (Test-Path -LiteralPath $resultDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
    }

    $payload = [ordered]@{
        state = 'EXIT'
        prompt_counts = [ordered]@{
            public = $script:publicPromptCount
            driver = $script:driverPromptCount
        }
        exit_code = $script:exitCode
        write_count = $script:writeCount
    }
    $temporaryPath = "$ResultPath.tmp"
    $payload | ConvertTo-Json -Depth 3 -Compress | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $ResultPath -Force
    $script:resultWritten = $true
}

try {
    $createdNew = $false
    $script:mutex = New-Object Threading.Mutex($false, $MutexName, [ref]$createdNew)
    try {
        $script:ownsMutex = $script:mutex.WaitOne(0, $false)
    }
    catch [Threading.AbandonedMutexException] {
        $script:ownsMutex = $true
    }
    if (-not $script:ownsMutex) {
        $script:exitCode = 12
        throw 'single_instance_lock_unavailable'
    }

    $guard = & $GuardScript -ProjectRef $ProjectRef -OperationCode $OperationCode
    if ($null -eq $guard -or $guard.public_active -ne 0 -or $guard.driver_active -ne 0) {
        $script:exitCode = 10
        throw 'active_capability_residue'
    }

    Move-HandoffState -Next 'PUBLIC_PROMPT'
    $script:publicValue = Read-CapabilityValue -Kind 'PUBLIC'

    Move-HandoffState -Next 'DRIVER_PROMPT'
    $script:driverValue = Read-CapabilityValue -Kind 'DRIVER'

    Move-HandoffState -Next 'VALIDATE'
    try {
        $publicUri = Parse-CapabilityUrl -Value $script:publicValue -Kind 'PUBLIC'
    }
    catch {
        $script:exitCode = 21
        throw 'public_capability_parse_failed'
    }
    try {
        $driverUri = Parse-CapabilityUrl -Value $script:driverValue -Kind 'DRIVER'
    }
    catch {
        $script:exitCode = 22
        throw 'driver_capability_parse_failed'
    }

    Move-HandoffState -Next 'MATRIX'
    $matrix = & $MatrixScript -PublicUri $publicUri -DriverUri $driverUri -OperationCode $OperationCode
    if ($null -eq $matrix -or -not $matrix.success) {
        $script:exitCode = 31
        throw 'matrix_failed'
    }
    $script:writeCount = [int]$matrix.write_count
    if ($script:writeCount -ne 1) {
        $script:exitCode = 32
        throw 'matrix_write_count_invalid'
    }

    Move-HandoffState -Next 'REVOKE'
    $revoke = & $RevokeScript -PublicUri $publicUri -DriverUri $driverUri -OperationCode $OperationCode
    if ($null -eq $revoke -or -not $revoke.success) {
        $script:exitCode = 41
        throw 'revoke_failed'
    }

    $script:exitCode = 0
    Move-HandoffState -Next 'RESULT'
}
catch {
    if ($script:state -ne 'FAILED' -and $script:state -ne 'RESULT' -and $script:state -ne 'EXIT') {
        Move-HandoffState -Next 'FAILED'
    }
    if ($script:state -eq 'FAILED') {
        Move-HandoffState -Next 'RESULT'
    }
}
finally {
    $script:publicValue = $null
    $script:driverValue = $null
    $publicUri = $null
    $driverUri = $null

    if ($script:state -ne 'RESULT') {
        if ($script:state -ne 'FAILED') {
            $script:state = 'FAILED'
        }
        $script:state = 'RESULT'
    }
    Write-TerminalResult
    Move-HandoffState -Next 'EXIT'

    if ($script:ownsMutex -and $script:mutex) {
        $script:mutex.ReleaseMutex()
    }
    if ($script:mutex) {
        $script:mutex.Dispose()
    }
}

exit $script:exitCode
