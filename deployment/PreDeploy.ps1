######## Script Overview ############################
## Install features required by application:
## * MSMQ
## * MSDTC
##

trap {
    Write-Host "[TRAP] Error occurred during PreDeploy: "
    Write-Host $_
    exit 1
}

# Import dem modules
if ((Get-Module | Where-Object { $_.Name -eq "Shared-Deployment-Tasks" }) -eq $null) { 
    Import-Module (Join-Path -Path (Split-Path -parent $MyInvocation.MyCommand.Definition) `
        -ChildPath "Shared-Deployment-Tasks") `
        -DisableNameChecking `
        -ErrorAction Stop
}

## Main
if (!(Test-AdministratorPrivileges)) {
    Write-Error "This script must be run with elevated administrator privileges. Run the script again logged in as an Administrator or from an elevated shell."
    exit 1
}

# MSMQ
$MSMQ = @()
if (!(Test-RegistryValue -Path HKLM:\SOFTWARE\Microsoft\MSMQ\Setup -Name "msmq_Core")) { $MSMQ += "MSMQ-Server" }

if ($MSMQ.Count -gt 0) {
    Write-Host -foregroundcolor green "Installing MSMQ Support..."
    Install-Features $MSMQ
} else {
    Write-Host "Required MSMQ components already installed."
}

# MSDTC
Enable-Remote-MSDTC