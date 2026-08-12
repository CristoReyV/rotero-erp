param([Uri]$PublicUri, [Uri]$DriverUri, [string]$OperationCode)

if ($env:ROTERO_TEST_REVOKE_COUNTER_PATH) {
    $count = if (Test-Path -LiteralPath $env:ROTERO_TEST_REVOKE_COUNTER_PATH) {
        [int](Get-Content -LiteralPath $env:ROTERO_TEST_REVOKE_COUNTER_PATH -Raw)
    }
    else {
        0
    }
    Set-Content -LiteralPath $env:ROTERO_TEST_REVOKE_COUNTER_PATH -Value ($count + 1) -Encoding ASCII
}

[pscustomobject]@{
    success = $env:ROTERO_TEST_REVOKE_FAIL -ne '1'
}
