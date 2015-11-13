######## Script Overview ############################
## > Set up IIS for Application Deployment
##      > IIS bindings
##          > SSL Cert thumbprint
##      > Application Pool
##          > Application Pool Identity
##      > IIS Site
##      > .Net Framework Version
## > Create MSMQ Queues
##      > Set Permissions on queues

trap {
    Write-Host "[TRAP] Error occurred during Deploy: "
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
[Reflection.Assembly]::LoadWithPartialName("System.Messaging") | Out-Null

## Required Variables
$ApplicationName = "ExampleApplication"
if ($DotNetFrameworkVersion -eq $null) { $DotNetFrameworkVersion = "v4.0" }
if ($WebRootPath -eq $null) { $WebRootPath = (Resolve-Path .) }
if ($AppQueueName -eq $null) { $AppQueueName = "ExampleApplicationQueue" }
if ($IisAppPoolName -eq $null) { $IisAppPoolName = "ExampleApplicationPool" }
if ($IisSiteName -eq $null) { $IisSiteName = "ExampleApplicationSite" }
# Local SSL Certificate thumbprint
if ($CertificateThumbprint -eq $null) { $CertificateThumbprint = "307fa3743af109ae18b25494714d62ca7507a3b2" }

## Show our intentions
Write-Host `
  "Application Deployment for ${ApplicationName}: `
     IIS Site Name:              $IisSiteName `
     IIS Application Pool Name:  $IisAppPoolName `
     IIS Host Header:            $IisHostHeader `
     IIS Certificate:            $CertificateThumbprint `
     Physical Path:              $WebRootPath `
     .NET Framework Version:     $DotNetFrameworkVersion `
     MSMQ Private Queue:         $AppQueueName `
     Periodic Restart:           Disabled

"

## Test permissions
if (!(Test-AdministratorPrivileges)) {
    Write-Error "This script must be run with elevated administrator privileges. Run the script again logged in as an Administrator or from an elevated shell."
    exit 1
}

## Test certificate
if (!(Test-Certificate $CertificateThumbprint)) {
    Write-Error "Certificate thumbprint '$CertificateThumbprint' was not found in the Local Machine certificate store."
    exit 1
}

## Microsoft Web Administration
if ((Get-Module | Where-Object { $_.Name -eq "WebAdministration" }) -eq $null) { Import-Module WebAdministration }

if (Test-Path IIS:\Sites\$IisSiteName) {
    Write-Host "Stopping web site '$IisSiteName'"
    Stop-WebSite -Name $IisSiteName -ErrorAction SilentlyContinue
}

Create-IisApplicationPool -Name $IisAppPoolName -DotNetFrameworkVersion $DotNetFrameworkVersion -PeriodicRestartMinutes 0
Create-IisSite -Name $IisSiteName -Path $WebRootPath -AppPool $IisAppPoolName
Set-IisBindings -SiteName $IisSiteName -CertificateThumbprint $CertificateThumbprint -HostHeader $IisHostHeader

## Setup applicstion's machine key
if ((Get-Module | Where-Object { $_.Name -eq "MachineKey" }) -eq $null) { 
    Import-Module (Join-Path -Path (Split-Path -parent $MyInvocation.MyCommand.Definition) `
        -ChildPath "MachineKey.psm1") `
        -DisableNameChecking `
        -ErrorAction Stop
}
if ($AspNetValidationKey -ne $null -or $AspNetDecryptionKey -ne $null) {
        $iisPath = "IIS:\Sites\$IisSiteName"
        Write-Host "Updating machineKey for $iisPath"
        Set-MachineKey $iisPath `
                -ValidationKey $AspNetValidationKey `
                -DecryptionKey $AspNetDecryptionKey `
                -ErrorAction Stop
}

Write-Host "Ensuring web site '$IisSiteName' is running"
Start-Website -Name $IisSiteName
