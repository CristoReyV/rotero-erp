param([Uri]$PublicUri, [Uri]$DriverUri, [string]$OperationCode)

[pscustomobject]@{
    success = $env:ROTERO_TEST_REVOKE_FAIL -ne '1'
}
