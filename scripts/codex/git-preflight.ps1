[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExpectedBranch,

    [string]$ExpectedSha,

    [string]$Remote = 'origin'
)

$ErrorActionPreference = 'Stop'

function Invoke-GitRead {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $output = & git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join ' ')"
    }

    return ($output -join "`n").Trim()
}

$repoRoot = Invoke-GitRead -Arguments @('rev-parse', '--show-toplevel')
$branch = Invoke-GitRead -Arguments @('branch', '--show-current')
if ($branch -ne $ExpectedBranch) {
    throw "Expected branch '$ExpectedBranch'; found '$branch'."
}

$status = Invoke-GitRead -Arguments @('status', '--porcelain')
if (-not [string]::IsNullOrWhiteSpace($status)) {
    throw 'Worktree is not clean.'
}

$head = Invoke-GitRead -Arguments @('rev-parse', 'HEAD')
$remoteRef = "$Remote/$ExpectedBranch"
$remoteHead = Invoke-GitRead -Arguments @('rev-parse', '--verify', $remoteRef)
if ($head -ne $remoteHead) {
    throw "HEAD '$head' is not aligned with $remoteRef '$remoteHead'."
}

if ($ExpectedSha -and $head -ne $ExpectedSha) {
    throw "Expected SHA '$ExpectedSha'; found '$head'."
}

[pscustomobject]@{
    Repository = $repoRoot
    Branch = $branch
    Head = $head
    RemoteRef = $remoteRef
    Clean = $true
    Aligned = $true
}
