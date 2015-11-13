@echo off
rem ### Description #########################################
rem # This script emulates the Octopus Deploy Tentacle procedure
rem # in order to deploy a web app to the local IIS instance.
rem # Multuple apps running on localhost are supported by using 
rem # Host Headers to setup the URL as http://applicationname.hostname

setlocal ENABLEDELAYEDEXPANSION

if '%1' == '/?' goto PRINT_USAGE
if '%1' == '-?' goto PRINT_USAGE
if '%1' == '?' goto PRINT_USAGE
if '%1' == '/help' goto PRINT_USAGE
if '%1' == '--help' goto PRINT_USAGE
if '%1' == '-help' goto PRINT_USAGE

SET REPOSITORY_ROOT=%~dp0
set APPLICATION=ExampleApplication
set LOCALURLPREFIX=example
set PACKAGESOURCE=%REPOSITORY_ROOT%\artifacts\package
set TARGETDIRECTORY=%SYSTEMDRIVE%\Apps
set NUGET=%REPOSITORY_ROOT%\tools\NuGet.exe
set CTT=%REPOSITORY_ROOT%\tools\xdt\ctt.exe

goto CHECK_ARGS

rem ### Script Usage ##########################################
:PRINT_USAGE
echo.
echo ERROR: Missing arguments.
echo Correct usage: 
echo    %0 [PackageSource] [TargetDir]
echo.
echo    PackageSource:  Path or Uri to the NuGet source containing the %APPLICATION% package. Defaults to .\artifacts\package
echo    TargetDir:      Path to deploy the application to. Defaults to %SYSTEMDRIVE%\Apps
echo.
goto FAILED

:CHECK_ARGS
rem ### Check Arguments #######################################
if not '%1'=='' set PACKAGESOURCE=%1
if not '%2'=='' set TARGETDIRECTORY=%2
if not '%3'=='' goto PRINT_USAGE

:LOCAL_ENVIRONMENT
rem ### Local Environment configuration ######################
FOR /F "usebackq skip=2 tokens=1-3" %%A IN (`REG QUERY HKLM\System\CurrentControlSet\Services\Tcpip\Parameters /v Domain 2^>nul`) DO (
	set LOCALDOMAIN=%%C
)
rem hostname returns the original case sensitive name of the host, %COMPUTERNAME% always returns uppercase
FOR /F "usebackq" %%i IN (`hostname`) DO SET LOCALHOSTNAME=%%i
if not '%LOCALDOMAIN%'=='' set LOCALHOSTNAME=%LOCALHOSTNAME%.%LOCALDOMAIN%

set LOCALTESTURL=%LOCALURLPREFIX%.%LOCALHOSTNAME%
set HOSTHEADER=%LOCALTESTURL%

:RUN
rem ### Run deployment ########################################

rem ## Find version number which will be installed
FOR /F "usebackq tokens=2" %%i IN (`%NUGET% list %APPLICATION% -Source %PACKAGESOURCE%`) DO SET VERSION=%%i
rem ## Application destination directory
set APPLICATIONDIRECTORY=%TARGETDIRECTORY%\%APPLICATION%.%VERSION%

echo.
echo ##############################################################################
echo.
echo Running deployment for:
echo     Application:       %APPLICATION%
echo     Package:           %PACKAGESOURCE%
echo     Target Directory:  %APPLICATIONDIRECTORY%
echo     Host Header:       %HOSTHEADER%
echo     Version:           %VERSION%
echo.
echo ##############################################################################
echo.

:UNINSTALL
rem ## Nuget won't install a package if it finds the package file is already there
rem ## and won't overwrite files that already exist when installing.
if not exist %APPLICATIONDIRECTORY% goto INSTALL
echo Removing existing contents of %APPLICATIONDIRECTORY%
del /f /s /q %APPLICATIONDIRECTORY% 1> nul

:INSTALL
rem ## Install the nuget package to the target directory
echo Installing %APPLICATION% to %APPLICATIONDIRECTORY%
%NUGET% install %APPLICATION% ^
	-Source %PACKAGESOURCE% ^
	-OutputDirectory %TARGETDIRECTORY%
if errorlevel 1 goto FAILED
echo Removing Nupkg file
del /f /q "%APPLICATIONDIRECTORY%\%APPLICATION%.%VERSION%.nupkg" 1> nul

rem ## Octopus Deploy script conventions
set PS_PREDEPLOY=%APPLICATIONDIRECTORY%\PreDeploy.ps1
set PS_DEPLOY=%APPLICATIONDIRECTORY%\Deploy.ps1
set PS_POSTDEPLOY=%APPLICATIONDIRECTORY%\PostDeploy.ps1

rem ## Execute Deploy PS scripts with appropriate environment variables
set ps_variables="$IisHostHeader = '%HOSTHEADER%'; $WebRootPath = '%APPLICATIONDIRECTORY%'; $SmokeTestUrl = '%LOCALTESTURL%';"

:PRE_DEPLOY
rem ## Execute Octopus PreDeploy script
if not exist %PS_PREDEPLOY% goto CFG_TRANSFORM
powershell ^
	-NonInteractive ^
	-NoProfile ^
	-ExecutionPolicy unrestricted ^
	-command "& { %ps_variables% %PS_PREDEPLOY%; exit $LastExitCode }"
if errorlevel 1 goto FAILED

:CFG_TRANSFORM
rem ## Perform Octopus config transforms
set XDT_DEST=%APPLICATIONDIRECTORY%\Web.Config
set XDT_SOURCE=%XDT_DEST%
set XDT_TRANSFORMS=Web.Release.Config,Web.LOCAL.Config
for %%T IN (%XDT_TRANSFORMS%) DO (
	set XDT_TRANSFORM=%APPLICATIONDIRECTORY%\%%T
	echo Looking for web.config transform: !XDT_TRANSFORM!
	echo.
	if exist !XDT_TRANSFORM! %CTT% source:%XDT_SOURCE% destination:%XDT_DEST% transform:!XDT_TRANSFORM! || goto FAILED
)

:DEPLOY
rem ## Execute Octopus Deploy script
if not exist %PS_DEPLOY% goto POST_DEPLOY
powershell ^
	-NonInteractive ^
	-NoProfile ^
	-ExecutionPolicy unrestricted ^
	-command "& { %ps_variables% %PS_DEPLOY%; exit $LastExitCode }"
if errorlevel 1 goto FAILED

:POST_DEPLOY
rem ## Execute Octopus PostDeploy script
if not exist %PS_POSTDEPLOY% goto COMPLETE
powershell ^
	-NonInteractive ^
	-NoProfile ^
	-ExecutionPolicy unrestricted ^
	-command "& { %ps_variables% %PS_POSTDEPLOY%; exit $LastExitCode }"
if errorlevel 1 goto FAILED

:EXIT
endlocal
exit /b 0

:FAILED
echo.
echo Deployment of %APPLICATION% failed.
echo.
endlocal
exit /b 1
