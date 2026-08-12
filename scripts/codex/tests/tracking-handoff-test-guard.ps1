param([string]$ProjectRef, [string]$OperationCode)

$publicValue = if ($env:ROTERO_TEST_PUBLIC_ACTIVE) { $env:ROTERO_TEST_PUBLIC_ACTIVE } else { '0' }
$driverValue = if ($env:ROTERO_TEST_DRIVER_ACTIVE) { $env:ROTERO_TEST_DRIVER_ACTIVE } else { '0' }
[pscustomobject]@{
    public_active = [int]$publicValue
    driver_active = [int]$driverValue
}
