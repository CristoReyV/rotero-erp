param([Uri]$PublicUri, [Uri]$DriverUri, [string]$OperationCode)

$normalized = (
    $PublicUri.AbsolutePath -match '^/t/[A-Za-z0-9_-]{30,}/?$' -and
    $DriverUri.AbsolutePath -match '^/driver/[A-Za-z0-9_-]{30,}/?$' -and
    -not $PublicUri.Query -and -not $PublicUri.Fragment -and
    -not $DriverUri.Query -and -not $DriverUri.Fragment
)

[pscustomobject]@{
    success = $env:ROTERO_TEST_MATRIX_FAIL -ne '1' -and $normalized
    write_count = if ($env:ROTERO_TEST_WRITE_COUNT) { [int]$env:ROTERO_TEST_WRITE_COUNT } else { 1 }
}
