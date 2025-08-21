<#
.SYNOPSIS
  Stop or Start VM

.DESCRIPTION
  Detailed explanation.

.PARAMETER Path
   Optional choice:
        stop
        start
        pwroff

    vmname -  host name

.PARAMETER Force
  Forces the operation without confirmation.

.EXAMPLE
  .\MyScript.ps1 -Path "C:\Temp" -Force
#>

[cmdletbinding()] 
Param
(               
        [Parameter(Mandatory=$false)][switch]$stop,
        [Parameter(Mandatory=$false)][switch]$start,
        [Parameter(Mandatory=$false)][switch]$pwroff,
		[Parameter(Mandatory=$true)][string]$vmname
)   

if ($psISE)
{
    $GLOBAL:SPATH = Split-Path -Path $psISE.CurrentFile.FullPath        
}
else
{
    if(-not $Global:SPATH)
    {
        $GLOBAL:SPATH = $PSScriptRoot
    }
} 

# Load configuration file
$scriptName = & { $myInvocation.ScriptName }
$scriptName = Get-Item -Path $scriptName

if($stop.IsPresent -and $start.IsPresent){
    logger "Please specify either -stop or -start or -pwroff" 1
    throw 
}

if($stop.IsPresent -and $pwroff.IsPresent){
    logger "Please specify either -stop or -start or -pwroff" 1
    throw 
}

if($pwroff.IsPresent -and $start.IsPresent){
    logger "Please specify either -stop or -start or -pwroff" 1
    throw 
}

# Load functions
Import-Module $SPATH\Modules\AZ_FUNCTIONS -Force -ErrorAction Stop

if( -not ${GLOBAL:filename} ){
    $GLOBAL:filename = "${SPATH}\log\$($scriptName.Basename)_${vmname}.log"
}

logger "SPATH is $SPATH" 99
logger "Log file: ${GLOBAL:filename}" 99

#// Check PowerShell Version
logger "INFO: Checking PowerShell version is 7 or above" 99
If(($PSVersionTable.PSVersion.Major) -lt 7)
{
	Write-Host "ERROR: Upgrade to minumum PowerShell (WMF) 7. Try 'pwsh <scriptname>'" -Foregroundcolor Red
    logger "ERROR: Upgrade to minumum PowerShell (WMF) 7" 1
	throw
}

# Connect to Azure
try {
    $scriptacc = $HOME + '\az_access.json'
    $AZ_ACCESS = Get-Content -Path $scriptacc -ErrorAction Stop | ConvertFrom-Json
    $cnvpwd = Convertto-SecureString -String $AZ_ACCESS.client_secret
    azlogon -p_client_id $AZ_ACCESS.client_id -p_client_secret $cnvpwd -p_tenant_id $AZ_ACCESS.tenant_id
} catch {
    throw
}

$AZ_ACCLIST = $(az account list|convertfrom-json)

$vmname = $vmname.ToUpper()
logger "Getting resource group" 99
if($vmname){
    foreach( $x in $AZ_ACCLIST){
        $AZ_VMDETLIST = $(az vm list --subscription $x.id)|convertfrom-json
        $AZ_VMLIST = $(az vm list --subscription $x.id|convertfrom-json).name
        foreach( $y in $AZ_VMLIST){
            if($vmname -eq $y){
                logger "Getting metadata." 0
                $rg =  $($AZ_VMDETLIST |where-object { $_.name -eq $vmname }).resourcegroup
                logger $rg 99
                $sub = $x.id
                logger $sub 99
                break
            } 
        }
    }
} else {
    logger "Value required for -vmname" 1
    throw
}

if($stop.IsPresent -or $pwroff.IsPresent){
    try {
        $msg = "Stopping ${vmname}"
        logger $msg 99
        if($pwroff.IsPresent){
            az vm stop --resource-group $rg --name $vmname --subscription $sub --skip-shutdown
        } else {
            az vm stop --resource-group $rg --name $vmname --subscription $sub 
        }
        $msg = "Deallocate ${vmname}"
        logger $msg 99
        az vm deallocate --resource-group $rg --name $vmname --subscription $sub
    }
    catch {
        logger $msg 1
        logger $res 1
        throw 1
    }
}

if($start.IsPresent){
    try {
        $msg = "Starting ${vmname}"
        logger $msg 99
        az vm start -g $rg -n $vmname --subscription $sub
    }
    catch {
        logger $msg 1
        throw 1
    }
}

exit 0