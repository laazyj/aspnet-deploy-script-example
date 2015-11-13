if((Get-Command Get-Website, Get-WebApplication, Get-WebConfiguration, Get-WebConfigFile, Set-WebConfigurationProperty -EA 0).Count -lt 5) {
   throw "The required commands from the 'WebAdministration' module are not available. Import the WebAdministration module and try again.`n
The following commands are required: Get-Website, Get-WebApplication, Get-WebConfiguration, Get-WebConfigFile, Set-WebConfigurationProperty"
}

function New-MachineKeyFile {
#.Synopsis
#  Generate MachineKey File
#.Description
#  Uses RNGCryptoServiceProvider to generate arrays of random bytes into a CSV file
#.Parameter Path
#  The Path to the file where you want to save the key
#.Links
#  http://msdn.microsoft.com/en-us/library/w8h3skw9%28v=VS.100%29.aspx
param(
   [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
   [Alias("PSPath")]
   [string]$Path
,
   [Parameter(ValueFromPipelineByPropertyName=$true)]
   [ValidateSet("3DES","AES","DES")]
   [string]$decryptionType = "3DES" # TODO: AES is better, but 3DES is currently more compatible in our environment.
,   
   [Parameter(ValueFromPipelineByPropertyName=$true)]
   [ValidateSet('AES','MD5','SHA1','3DES','HMACSHA256','HMACSHA384','HMACSHA512')]
   [string]$validationType = "SHA1"
   
)
process {
   $vbytes = $(
      switch($validationType) {
         'AES' { 32 }
         'MD5' { 16 }
         'SHA1' { 64 }
         '3DES' { 24 }
         'HMACSHA256' { 32 }
         'HMACSHA384' { 48 }
         'HMACSHA512'{ 64 }
      }
   )
   $dbytes = $(
      switch($decryptionType) {
         'DES' { 8 }
         '3DES' { 24 }
         'AES' { 32 }
      }
   )
   New-Object PSObject -Property @{
      validationKey=$(Get-CryptoBytes $vbytes -AsString)
      decryptionKey =$(Get-CryptoBytes $dbytes -AsString)
      decryptionType=$decryptionType.ToUpper()
      validationType=$validationType.ToUpper()
   } | Export-CSV -Path $Path
   Get-Item $Path
}
}

function Get-CryptoBytes {
#.Synopsis
#  Generate Cryptographically Random Bytes
#.Description
#  Uses RNGCryptoServiceProvider to generate arrays of random bytes
#.Parameter Count
#  How many bytes to generate
#.Parameter AsString
#  Output hex-formatted strings instead of byte arrays
#.Notes
#  Choosing an appropriate key size:
#  For IIS machineKeys, the following algorithms and key lengths are recommended:
#
#  For Validation, SHA1 is recommended
#     For MD5: the key must be 16 bytes (32 hexadecimal characters).
#     For SHA1: the key must be (at least?) 20 bytes (40 hexadecimal characters).
#     For 3DES: the key must be 24 bytes (48 hexadecimal characters).
#     For AES: the key must be 32 bytes (64 hexadecimal characters).
#     For HMACSHA256: the key must be 32 bytes (64 hexadecimal characters).
#     For HMACSHA384: the key must be 48 bytes (96 hexadecimal characters).
#     For HMACSHA512: the key must be 64 bytes (128 hexadecimal characters).
#  For decryption, AES is recommended, but 3DES is backwards compatible to ASP.Net 2
#     For DES:  the key must be 8 bytes (16 hexadecimal characters).
#     For 3DES: the key must be 24 bytes (48 hexadecimal characters).
#     For AES:  the key should be the maximum: 32 bytes (64 hexadecimal characters).
param(
   [Parameter(ValueFromPipeline=$true)]
   [int[]]$count = 64
,
   [switch]$AsString
)

begin {
   $RNGCrypto = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
   $OFS = ""
}
process {
   foreach($length in $count) {
      $bytes = New-Object Byte[] $length
      $RNGCrypto.GetBytes($bytes)
      if($AsString){
         Write-Output ("{0:X2}" -f $bytes)
      } else {
         Write-Output $bytes
      }
   }
}
end {
   $RNGCrypto = $null
}
}

function Find-WebConfigLocation {
<#
.Synopsis
   Find Web.Config which have a machineKey specified that matches the specified ValidationKey
.Description
   Searches all web.config for the XSM MachineKey and replaces them with a new one (generated at runtime). 
   The default settings will replace all machine keys in IIS which match the current XeroxServicesManager key with keys which must be specified at runtime.
.Parameter ValidationKey
   Specify the validationKey to search for (supports regular expressions).
   Defaults to: ^[0-9A-F]+$ (which matches all validationKeys that are actually specified, but not the default "AutoGenerate,IsolateApps")
#>
[CmdletBinding()]
param (
   [Parameter(Position=1, Mandatory=$false)]
   [string[]]$SiteRoot = "IIS:\Sites"
,
   [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
   [string[]]$ValidationKey = "^[0-9A-F]+$"
,
   [switch]$Force
,
   [switch]$Recurse
)
process {
   if($Recurse) {
      ## This code will get all web.config with machineKey in them, and then warn on web.config that are not apps
      foreach($config in Get-WebConfiguration -Recurse system.web/machineKey -PSPath $SiteRoot) {
         trap { 
            Write-Verbose "Ignoring non-application web.config in $($config.PSPath)"
            continue
         }
         Get-WebConfiguration system.web/machineKey -PSPath $config.PSPath | 
         Where-Object { $Force -or $(foreach($key in $ValidationKey){ $_.validationKey -match $key }) -contains $true } |
         Select-Object -Expand PSPath
      }
   } else {
      ## This code will get the machineKey setting for ALL apps, even those which do not specify it (they inherit it from the machine settings)
      foreach($site in Get-Website *){ 
         foreach($app in Get-WebApplication -Site $site.Name *) {
            $Path = "IIS:\Sites\$($Site.Name)$($App.Path)"
            if($Path -like "$SiteRoot*") {
               Get-WebConfiguration system.web/machinekey -pspath $Path | 
               Where-Object { $Force -or $(foreach($key in $ValidationKey){ $_.validationKey -match $key }) -contains $true } | 
               Select-Object -Expand PSPath
            }
         }
      }
   }
}
}


function Set-FileWriteable {
param(
   [Parameter(Mandatory=$true,ValueFromPipeline=$true)]   
   $File
,
   [switch]$Passthru
)
process {
   foreach($path in @($file)) {
      write-verbose "'$path' is on '$($path.PSComputerName)'"
      if($path.PSComputerName) {
         Invoke-Command $path.PSComputerName {
            param([string[]]$path,[switch]$passthru)
            $files = Get-Item $path
            foreach($f in $files) {
               if($f.Attributes -band [IO.FileAttributes]"ReadOnly") {
                  $f.Attributes = $f.Attributes -bxor [IO.FileAttributes]"ReadOnly"
               }
            }
            write-output $files
         } -Argument $path | Where { $Passthru }
      } else {
         $files = Get-Item $path
         foreach($f in $files) {
            if($f.Attributes -band [IO.FileAttributes]"ReadOnly") {
               $f.Attributes = $f.Attributes -bxor [IO.FileAttributes]"ReadOnly"
            }
         }
         if($Passthru) { write-output $files }
      }
   }
}
}


function Set-MachineKey {
<#
.Synopsis
   Changes the MachineKey for the specified sites.
.Description
   For every specified web.config file, changes the MachineKey setting to the new specified key settings.
.Parameter ValidationKey
   You must specify the validation key as a 128 character hexadecimal string (will be generated randomly, otherwise).
.Parameter DecryptionKey
   You must specify the decryption key as a 48 character hexadecimal string (will be generated randomly, otherwise).
.Parameter ConfigFiles
   You must specify the files to set the machineKey in.
.Example
   New-MachineKeyFile $home\Keys.csv
   C:\PS>Import-Csv $home\Keys.csv | Set-MachineKey $(Find-WebConfigLocation)

   Description
   -----------
   This example shows how to generate a new key pair using New-MachineKeyFile into a csv file and reuse it on multiple machines:
   * Generate the new key into a file by calling New-MachineKeyFile 
   * Import the Key from the CSV file and pipe it to Set-MachineKey
   * Call Find-WebConfigLocation to find all config file swhich currently have hand-coded machineKeys and replace them.
.Example
   $session = New-PSSession $ComputerName
   
   C:\PS>Invoke-Command $session {Import-Module WebAdministration}
   
   C:\PS>Import-PSSession $session -Module WebAdministration

   ModuleType Name                           ExportedCommands                                                                
   ---------- ----                           ----------------                                                                
   Script     tmp_98a1a0b9-eb4d-4a6d-8e8d... {Stop-Website, Get-WebConfiguration, Get-WebAppPoolState, New-WebGlobalModule...
   
   C:\PS>Import-Module MachineKey
   
   C:\PS>New-MachineKeyFile $home\Keys.csv
   
   C:\PS>Import-Csv $home\Keys.csv | Set-MachineKey $(Find-WebConfigLocation)

   Description
   -----------
   Demonstrates how to use this module to set a machine key on a remote server by using Import-PSSession to import the WebAdministration commands from a remote computer.
.Notes
   If you run this script and there are errors (eg: it only sets *some* of the web.configs), you MUST run it again to set those back, or manually correct the web.config.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact="Medium")]
param (
   [Parameter(Position = 0, Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
   [Alias("PSPATH","File")]
   [Array]$ConfigFile
,
   [Parameter(ValueFromPipelineByPropertyName=$true)]
   [ValidateSet("3DES","AES")]
   [string]$DecryptionType = "AES"
,   
   [Parameter(ValueFromPipelineByPropertyName=$true)]
   [ValidateSet("SHA1","MD5")]
   [string]$ValidationType = "SHA1"
,
   [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
   [ValidateLength(16,64)]
   [string]$DecryptionKey #= $(Get-CryptoBytes 24 -AsString)
,  
   [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
   [ValidateLength(32,128)]
   [string]$ValidationKey #= $(Get-CryptoBytes 64 -AsString)
)
process {
   ## Validate the Keys:
   if($ValidationKey -notmatch "^[0-9A-F]+$") {
      throw "The supplied Validation key is not hexadecimal!"
   }
   if($DecryptionKey -notmatch "^[0-9A-F]+$") {
      throw "The supplied Decryption key is not hexadecimal!"
   }
   
   if($PSBoundParameters.ContainsKey("WhatIf")) {
      Write-Host "Setting machineKey to: `n$('<machineKey validationKey="{0}" decryptionKey="{1}" decryption="{2}" validation="{3}" />' -f $ValidationKey, $DecryptionKey, $decryptionType.ToUpper(), $validationType.ToUpper())" -Fore Cyan
   } else {
      Write-Verbose "Setting machineKey to: $('<machineKey validationKey="{0}" decryptionKey="{1}" decryption="{2}" validation="{3}" />' -f $ValidationKey, $DecryptionKey, $decryptionType.ToUpper(), $validationType.ToUpper())"
   }   
   
   foreach($config in $ConfigFile) {
   
      if($PSCmdlet.ShouldProcess("Setting machineKey in $($config) ", "Set Machine Key in '$($config)'?", "Replace MachineKey?")) {

         Get-WebConfigFile -PSPath $config | Set-FileWriteable
      
         ## Finally, set the properties:
         set-webconfigurationproperty system.web/machineKey -PSPath $config -name validationKey -value $ValidationKey
         set-webconfigurationproperty system.web/machineKey -PSPath $config -name decryptionKey -value $DecryptionKey
         ## Just to be sure, set these too:
         set-webconfigurationproperty system.web/machineKey -PSPath $config -name decryption -value $decryptionType
         set-webconfigurationproperty system.web/machineKey -PSPath $config -name validation -value $validationType
      }
   }
}
}