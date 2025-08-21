<#
.SYNOPSIS
  Remove immutable objects from storage account.

.DESCRIPTION
  Detailed explanation.

.PARAMETER Path
  sa - Storage Account
  cn - Container Name
  rg - Resource Group
  ac - Account (subscription)

.PARAMETER Force
  Forces the operation without confirmation.

.EXAMPLE
  .\MyScript.ps1 -Path "C:\Temp" -Force
#>

[cmdletbinding()] 
Param(                 
        [Parameter(Mandatory=$true)][string]$sa,
        [Parameter(Mandatory=$false)][string]$cn,
        [Parameter(Mandatory=$false)][string]$rg,
        [Parameter(Mandatory=$false)][string]$ac
)

$scriptName = & { $myInvocation.ScriptName }
$scriptName = Get-Item -Path $scriptName
$scriptPath = $scriptName.DirectoryName
$scriptName = $scriptName.BaseName

# Load functions
Import-Module $scriptPath\modules\AZ_FUNCTIONS -Force -ErrorAction Stop

if( -not ${GLOBAL:filename} ){
    $GLOBAL:filename = "${scriptPath}\log\${scriptName}_${servername}.log"
}

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
    $instcred = New-Object pscredential -ArgumentList ([pscustomobject]@{
        UserName = $AZ_ACCESS.client_id
        Password = $cnvpwd[0]
    }) 
    # azlogon -p_client_id $AZ_ACCESS.client_id -p_client_secret $cnvpwd -p_tenant_id $AZ_ACCESS.tenant_id
    Connect-AzAccount -ServicePrincipal -Credential $instcred -Tenant $AZ_ACCESS.tenant_id -Subscription $ac
} catch {
    throw
}

# get a reference to the storage account and the context
$storageAccount = Get-AzStorageAccount `
  -ResourceGroupName $rg `
  -Name $sa
$ctx = $storageAccount.Context 

# list all containers in the storage account 
logger "All containers" 99
Get-AzStorageContainer -Context $ctx | Select-Object Name

$VMNameCheck = 0 
Do {
    logger "####################################################################" 99
    logger "Destroying...." 99
    logger "Blob Contents in container: ${cn}" 99
    logger "Subscription: ${ac}" 99
    logger "Storage Account: ${sa}" 99
    logger "Resource Group: ${rg}" 99   
    logger "####################################################################" 99
    Write-Host ""
    Write-Host "Are you sure you wish to destroy the above please enter 'Delete' or 'Cancel': " -NoNewline -ForegroundColor Red
    $response = Read-Host

    logger "response = ${response}" 99
    if ($response -eq "Delete") {
        $VMNameCheck = 1 
    } else {
        if ($response -eq "Cancel") {
            exit 0
        } else {
            $VMNameCheck = 0 
        }
    }
} Until ($VMNameCheck -eq 1)

Get-AzStorageBlob -Context $ctx -Container $cn | Remove-AzStorageBlob

