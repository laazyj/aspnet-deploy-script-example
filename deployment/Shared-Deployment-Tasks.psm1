######## Script Overview ############################
## Reusable functions supporting application deployment scripts (PreDeploy.ps1, Deploy.ps1, PostDeploy.ps1)
##
## Code-snippet to import:
##
## if ((Get-Module | Where-Object { $_.Name -eq "Shared-Deployment-Tasks" }) -eq $null) { 
##     Import-Module (Join-Path -Path (Split-Path -parent $MyInvocation.MyCommand.Definition) `
##         -ChildPath "Shared-Deployment-Tasks") `
##         -DisableNameChecking `
##         -ErrorAction Stop
## }
##
##

## Functions
function Test-AdministratorPrivileges {
    $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal( $identity )
    $principal.IsInRole( [System.Security.Principal.WindowsBuiltInRole]::Administrator )
}

# Alternative Way to Set bindings, wipe, then re-add
function Set-IisBindings {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string] $SiteName,
        [Parameter(Mandatory = $false)]
        [string] $CertificateThumbprint,
        [Parameter(Mandatory = $false)]
        [string] $HostHeader)
        
    begin {
		if ((Get-Module | Where-Object { $_.Name -eq "WebAdministration" }) -eq $null) { Import-Module WebAdministration }
		
        $path = "IIS:\Sites\$SiteName"
        Write-Host -foregroundcolor green "Clearing IIS Site Bindings on '$path'"
        Clear-ItemProperty $path -name Bindings
    }
    
    process {
        Write-Host -foregroundcolor green "Creating HTTP binding on port 80"
        New-WebBinding -Name "$SiteName" -IP "*" -Port 80 -Protocol http -HostHeader $HostHeader
        
        if ($CertificateThumbprint) {
            Write-Host -foregroundcolor green "Creating HTTPS binding on port 443"
            New-WebBinding -Name "$SiteName" -IP "*" -Port 443 -Protocol https -HostHeader $HostHeader

            pushd IIS:\SslBindings
            Write-Host "Updating HTTPS certificate"
            if (Test-Path IIS:\SslBindings\0.0.0.0!443) {
                Write-Host -foregroundcolor green "Removing existing certificate binding"
                Remove-Item .\0.0.0.0!443
            }
            Write-Host "Binding SSL certificate with thumbprint '$CertificateThumbprint'"
            Get-ChildItem cert:\LocalMachine\My | Where { $_.Thumbprint -eq "$CertificateThumbprint" } | select -First 1 | New-Item IIS:\SslBindings\0.0.0.0!443 | Out-Null
            popd
        }
    }
}

function Create-IisApplicationPool {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string] $Name,
        [Parameter(Position = 1, Mandatory = $false)]
        [ValidateSet($null, "v4.0", "v2.0")]
        [string] $DotNetFrameworkVersion,
        [Parameter(Position = 2, Mandatory = $false)]
        [int] $PeriodicRestartMinutes = 1740)
    
    begin { 
		if ((Get-Module | Where-Object { $_.Name -eq "WebAdministration" }) -eq $null) { Import-Module WebAdministration }
		pushd IIS:\ 
	}
    
    process {
        $path = "IIS:\AppPools\$Name"
        $pool = Get-Item $path -ErrorAction SilentlyContinue
        if (!$pool) {
            Write-Host -foregroundcolor green "Creating IIS Application Pool: '$Name'"
            $pool = New-Item $path            
        }
        if ($PeriodicRestartMinutes -eq 1740) {
            Write-Host "Setting application pool periodic restart to default value"
        } elseif ($PeriodicRestartMinutes -gt 0) {
            Write-Host "Setting application pool periodic restart every $PeriodicRestartMinutes minutes"
        } elseif ($PeriodicRestartMinutes -eq 0) {
            Write-Host "Disabling application pool periodic restarts"
        }
        $pool.Recycling.PeriodicRestart.Time = [TimeSpan]::FromMinutes($PeriodicRestartMinutes)            
        $pool | Set-Item

        Write-Host "Setting .NET Framework Version '$DotNetFrameworkVersion' on '$path'"
        Set-ItemProperty $path managedRuntimeVersion $DotNetFrameworkVersion
        
        Write-Host "Setting Application Pool Identity on '$path'"
        Set-ItemProperty $path -name processModel -value @{ identitytype="ApplicationPoolIdentity" }
    }
    
    end { popd }
}

function Create-IisSite {
    param(
        [Alias("Name")]
        [Parameter(Position = 0, Mandatory = $true)]
        [string] $SiteName,
        [Alias("Path")]
        [Parameter(Position = 1, Mandatory = $true)]
        [string] $RootPath,
        [Alias("AppPool")]
        [Parameter(Position = 2, Mandatory = $true)]
        [string] $ApplicationPool)
        
    begin { 
		if ((Get-Module | Where-Object { $_.Name -eq "WebAdministration" }) -eq $null) { Import-Module WebAdministration }
		pushd IIS:\ 
	}
    
    process {
        $sitePath = "IIS:\Sites\$SiteName"
        $site = Get-Item $sitePath -ErrorAction SilentlyContinue
        if (!$site) {
            Write-Host -foregroundcolor green "Creating IIS Site '$SiteName' at '$RootPath'"
            $id = (dir IIS:\Sites | foreach { $_.id } | sort -Descending | select -first 1) + 1
            $site = New-Item $sitePath `
                -bindings (@{ 
                    protocol = "http"; 
                    bindingInformation = "*:80:" }) `
                -id $id `
                -physicalPath $RootPath
        } else {
            Write-Host -foregroundcolor green "Updating IIS site's physical path to '$RootPath'"
            Set-ItemProperty $sitePath -name physicalPath -value $RootPath
        }
        
        Write-Host "Updating Application Pool on '$sitePath' to '$ApplicationPool'"
        Set-ItemProperty $sitePath -name applicationPool -value $ApplicationPool
    }
    
    end { popd }
}

function Install-Features($RolesToInstall) {
    $args = @("/Online")
    $args +=    "/Enable-Feature"
    foreach ($role in $RolesToInstall) {
        $args += "/FeatureName:$role"
    }

	$os = (gwmi win32_operatingsystem)
	if ($os.Version -gt 6.2) {
		# Option not supported on Win7/2008R2
    	$args += "/all"
	}
	
    & $env:windir\system32\dism $args
	if ($LastExitCode -gt 0) {
		throw "DISM command failed [$LastExitCode]: '$env:windir\system32\dism $args'"
	}
}

function Test-Folder (
    [string] $Path = $(throw "Path is required.")) {
    Test-Path $Path
}

function Create-Folder (
    [string] $Path = $(throw "Path is required.")) {
    New-Item -Path $Path -Type Directory | Out-Null
}

function Test-FolderPermissionsForEveryone([string] $path) {
    $acl = Get-Acl $path
    ($acl.Access | Where-Object { $_.IdentityReference -eq "Everyone" -and $_.AccessControlType -eq "Allow" }) -ne $null
}

function Set-FolderPermissionsForEveryone([string] $path) {
    $acl = Get-Acl $path
    $ace = New-Object System.Security.AccessControl.FileSystemAccessRule "everyone", "ReadAndExecute", 3, "None", "Allow" 
    $acl.AddAccessRule($ace)
    Set-Acl $path $acl | Out-Null
}

function Enable-Firewall-Rule ($RuleName) {
    Write-Host "Enabling firewall rule: $RuleName"
    netsh advfirewall firewall set rule name="$RuleName" new enable=Yes
}

function Enable-Remote-MSDTC () {
	Write-Host "Enabling firewall rules for MSDTC"

    # Detect the name of the firewall rules for DTC..
    $rulePrefix = "Distributed Transaction Coordinator"
    netsh advfirewall firewall show rule name="$rulePrefix (TCP-In)" | out-null

    if($LastExitCode -eq 1) {
        $rulePrefix = "Distributed Transaction Co-ordinator"
        $global:LastExitCode = 0
    }

    Enable-Firewall-Rule "$rulePrefix (TCP-In)"
    Enable-Firewall-Rule "$rulePrefix (TCP-Out)"

	Write-Host "Configuring registry settings for MSDTC"
	$msdtcKey = "HKLM:\Software\Microsoft\MSDTC\Security"
	$settingsUpdated = $false
	$settingsUpdated = (Set-ItemPropertyIfNotEqualTo $msdtcKey "NetworkDtcAccess" 1) -bor $settingsUpdated
	$settingsUpdated = (Set-ItemPropertyIfNotEqualTo $msdtcKey "NetworkDtcAccessClients" 1) -bor $settingsUpdated
	$settingsUpdated = (Set-ItemPropertyIfNotEqualTo $msdtcKey "NetworkDtcAccessInbound" 1) -bor $settingsUpdated
	$settingsUpdated = (Set-ItemPropertyIfNotEqualTo $msdtcKey "NetworkDtcAccessOutbound" 1) -bor $settingsUpdated
	$settingsUpdated = (Set-ItemPropertyIfNotEqualTo $msdtcKey "NetworkDtcAccessTransactions" 1) -bor $settingsUpdated
	$settingsUpdated = (Set-ItemPropertyIfNotEqualTo $msdtcKey "XaTransactions" 1) -bor $settingsUpdated
	# Only restart service if any settings were changed
	if ($settingsUpdated) {
		Restart-Service "MSDTC"
	}
}

function Restart-Service([string] $ServiceName) {
    $service = Get-Service -Name $serviceName
    if ($service.Status -eq "Running") {
        Write-Host "Stopping service [$serviceName]"
        $service | Stop-Service
    }
    Write-Host "Starting service [$serviceName]"
    $service | Start-Service
}

function Test-RegistryValue {
    param(
        [Alias("PSPath")]
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]    $Path,
        [Parameter(Position = 1, Mandatory = $true)]
        [string]    $Name,
        [Parameter(Position = 2, Mandatory = $false)]
        [object]    $TestValue)
       
    process {
        if (Test-Path $Path) {
            Write-Debug "Loading key '$Path'"
            $key = Get-Item -LiteralPath $Path
            Write-Debug "Getting value '$Path\$Name'"
            $value = $key.GetValue($Name, $null)
            if ($value -ne $null) {
                if ($TestValue -ne $null) {
                    Write-Debug "Comparing values for '$Path\$Value', current: '$value', expected: '$TestValue'"
                    $value -eq $TestValue
                } else {
                    Write-Debug "Value exists: '$Path\$Value'"
                    $true
                }
            } else {
                Write-Debug "Value does not exist: '$Path\$Value'"
                $false
            }
        } else {
            Write-Debug "Path does not exist: '$Path'"
            $false
        }
    }
}

function Set-ItemPropertyIfNotEqualTo {
    param(
        [string] $Path,
        [string] $Name,
        [object] $Value)
    
    process {
        if (Test-RegistryValue $Path $Name $Value) {
            # Value does not require updating
            Write-Debug "'$Path\$Name' already has value '$Value'"
            $false
        } else {
            # Update value
            Write-Debug "Updating '$Path\$Name' to '$Value'"
            Set-ItemProperty -path $Path -name $Name -value $Value
            $true
        }
    }
}

## Test if a certificate exists in the local machine certificate store
function Test-Certificate {
    param(
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $Thumbprint)
    
    begin {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My","LocalMachine")
        $store.Open("ReadOnly")
    }
    
    process {
        return ($store.Certificates.Find("FindByThumbprint", $Thumbprint, $false).Count -gt 0)
    }
    
    end { $store.Close() }
}

## Test if the Uri is responding ok
function Test-Uri {
    param(
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $Uri,
        [int] $TimeoutSeconds = 90,
        [int] $ExpectedStatusCode = 200,
        [switch] $IgnoreCertificateValidation)
    
    begin {
        $hasInvokeWebRequest = (Get-Command "Invoke-WebRequest" -errorAction SilentlyContinue)
        if (!$hasInvokeWebRequest) {
            Write-Warning "PowerShell Version does not support 'Invoke-WebRequest'. TimeoutSeconds parameter will be ignored. Install PowerShell version 3 or greater."
        } 

        # Ignore SSL certificate validity errors
        if ($IgnoreCertificateValidation) {
            if (!$hasInvokeWebRequest) {
                # Certificate validation for System.Net.WebClient
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
            } else {
                # Certificate validation for Invoke-WebRequest
                add-type "
                    using System.Net;
                    using System.Security.Cryptography.X509Certificates;
                    public class TrustAllCertsPolicy : ICertificatePolicy {
                        public bool CheckValidationResult(
                            ServicePoint srvPoint, X509Certificate certificate,
                            WebRequest request, int certificateProblem) {
                            return true;
                        }
                    }
                "
                [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy            
            }
        }

        # Temp file for PowerShell < 3 method
        $guid = [Guid]::NewGuid()
        $tempFile = Join-Path (gc Env:\TEMP) -ChildPath "\$guid.html"
    }
    
    process {
        try {
            Write-Host "Running smoke test on '$Uri'... "
            if (!$hasInvokeWebRequest) {
                $time = Measure-Command { (New-Object System.Net.WebClient).DownloadFile($Uri, $tempFile) }
            } else {
                $time = Measure-Command { $response = (Invoke-WebRequest -Uri $Uri -TimeoutSec $TimeoutSeconds -UseBasicParsing) }
                if ($response.StatusCode -ne $ExpectedStatusCode) { throw "Request failed. Expected status code '$ExpectedStatusCode' but got: " + $response.StatusCode }
            }

            if ($time.TotalSeconds -gt 5) {
                $timeTaken = ($time.TotalSeconds -as [string]) + "s"
            } else {
                $timeTaken = ($time.TotalMilliseconds -as [string]) + "ms"
            }
            Write-Host -foregroundcolor green "  OK ($timeTaken)!"
        }
        finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -ErrorAction SilentlyContinue }            
        }
    }
}

function Download-File {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string] $Url,
        [Parameter(Position = 1, Mandatory = $true)]
        [string] $TargetFile,
        [Parameter(Position = 2, Mandatory = $false)]
        [int] $TimeoutSeconds = 15)

    process {
        Write-Host "Downloading $Url..."
        $uri = New-Object "System.Uri" "$Url"
        $request = [System.Net.HttpWebRequest]::Create($uri)
        $request.set_Timeout($TimeoutSeconds * 1000)
        $response = $request.GetResponse()
        $totalLength = [System.Math]::Floor($response.get_ContentLength()/1024)
        try {
            $responseStream = $response.GetResponseStream()
            $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $TargetFile, Create
            $buffer = New-Object byte[] 10KB
            $count = $responseStream.Read($buffer, 0, $buffer.length)
            $downloadedBytes = $count
            while ($count -gt 0) {
                $percentComplete = [System.Math]::Floor($downloadedBytes/1024) / $totalLength * 100
                Write-Progress -Activity "Downloading..." -Status $Url -PercentComplete $percentComplete
                $targetStream.Write($buffer, 0, $count)
                $count = $responseStream.Read($buffer, 0, $buffer.length)
                $downloadedBytes = $downloadedBytes + $count
            }
            Write-Host "Finished download."
        }
        finally {
            $targetStream.Flush()
            $targetStream.Close()
            $targetStream.Dispose()
            $responseStream.Dispose()
        }
    }
}

function Unzip-File {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string] $ZipFile,
        [Parameter(Position = 1, Mandatory = $true)]
        [string] $Target)
        
    process {
        Write-Host "Unzipping $ZipFile to $Target..."
        $shell = New-Object -com shell.application
        $zip = $shell.NameSpace($ZipFile)
        $targetFolder = $shell.NameSpace($Target)
        $copyHereOptions = 4 + 16 # Show no dialogs and respond "Yes to All"
        $targetFolder.CopyHere($zip.Items(), $copyHereOptions)
    }
}
