######## Script Overview ############################
## Smoke test the HTTP & HTTPS url for the 
## deployed web application.
##

if ($SmokeTestUrl -eq $null) { $SmokeTestUrl = "localhost/" }
if ($SmokeTestTimeoutSeconds -eq $null) { $SmokeTestTimeoutSeconds = 20 }

trap {
    Write-Host "[TRAP] Error occurred during PostDeploy: "
    Write-Host $_
    exit 1
}

# Import shared modules
if ((Get-Module | Where-Object { $_.Name -eq "Shared-Deployment-Tasks" }) -eq $null) { 
    Import-Module (Join-Path -Path (Split-Path -parent $MyInvocation.MyCommand.Definition) `
        -ChildPath "Shared-Deployment-Tasks") `
        -DisableNameChecking `
        -ErrorAction Stop
}

@( "http://$SmokeTestUrl", "https://$SmokeTestUrl" ) | Test-Uri -TimeoutSeconds $SmokeTestTimeoutSeconds -IgnoreCertificateValidation
