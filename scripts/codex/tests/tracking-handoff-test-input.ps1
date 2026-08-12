param(
    [Parameter(Mandatory = $true)][ValidateSet('PUBLIC', 'DRIVER')][string]$Kind,
    [Parameter(Mandatory = $true)][string]$AttemptId
)

$value = if ($Kind -eq 'PUBLIC') { $env:ROTERO_TEST_PUBLIC_URL } else { $env:ROTERO_TEST_DRIVER_URL }
if ($null -eq $value) {
    $value = ''
}
ConvertTo-SecureString -String $value -AsPlainText -Force
