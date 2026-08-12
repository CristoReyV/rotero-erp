[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https?://')]
    [string]$BaseUrl,

    [Parameter(Mandatory = $true)]
    [string[]]$Path
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$results = foreach ($item in $Path) {
    $normalizedPath = if ($item.StartsWith('/')) { $item } else { "/$item" }
    $uri = "$($BaseUrl.TrimEnd('/'))$normalizedPath"

    try {
        $response = Invoke-WebRequest -Uri $uri -Method Get -MaximumRedirection 5 -UseBasicParsing
        $statusCode = [int]$response.StatusCode
    }
    catch {
        if ($null -eq $_.Exception.Response) {
            throw
        }
        $statusCode = [int]$_.Exception.Response.StatusCode
    }

    [pscustomobject]@{
        Method = 'GET'
        Url = $uri
        Status = $statusCode
        Passed = $statusCode -ge 200 -and $statusCode -lt 400
    }
}

$results
if ($results.Passed -contains $false) {
    exit 1
}
