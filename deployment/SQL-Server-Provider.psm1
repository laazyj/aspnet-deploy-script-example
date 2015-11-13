#
# Add the SQL Server Provider.
#

# Look for SQL 2012 first...
if (Get-Module -ListAvailable | Where-Object { $_.Name -eq "SQLPS" }) {
	Write-Host "Loading SQL2012 PoweShell Module..."
	Import-Module SQLPS -DisableNameChecking
	
} else {
	# Look for older SQL versions...
	$ErrorActionPreference = "Stop"
	$sqlpsreg="HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.SqlServer.Management.PowerShell.sqlps"

	if (Get-ChildItem $sqlpsreg -ErrorAction SilentlyContinue) {
    	throw "SQL Server Provider for Windows PowerShell is not installed."
	} else {
    	$item = Get-ItemProperty $sqlpsreg
    	$sqlpsPath = [System.IO.Path]::GetDirectoryName($item.Path)
	}

	Write-Host "Loading SQL2008R2 PowerShell Snap-in..."
	#
	# Set mandatory variables for the SQL Server provider
	#
	Set-Variable -scope Global -name SqlServerMaximumChildItems -Value 0
	Set-Variable -scope Global -name SqlServerConnectionTimeout -Value 30
	Set-Variable -scope Global -name SqlServerIncludeSystemObjects -Value $false
	Set-Variable -scope Global -name SqlServerMaximumTabCompletion -Value 1000

	#
	# Load the snapins, type data, format data
	#
	Push-Location
	cd $sqlpsPath
	Add-PSSnapin SqlServerCmdletSnapin100
	Add-PSSnapin SqlServerProviderSnapin100
	Update-TypeData -PrependPath SQLProvider.Types.ps1xml 
	update-FormatData -prependpath SQLProvider.Format.ps1xml 
	Pop-Location
}
