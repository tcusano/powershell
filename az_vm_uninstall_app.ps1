[cmdletbinding()] 
Param(  
    [Parameter(Mandatory=$true)][string]$application,
    [Parameter(Mandatory=$true)][string]$vm,
    [Parameter(Mandatory=$true)][string][Validateset('Linux','Windows')]$platform,
    [Parameter(Mandatory=$true)][string][Validateset('MGT01','PRD01','HUB01','TST01','DEV01')]$vm_account,
    [Parameter(Mandatory=$false)][switch]$list
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
$appgallery = "ACGMSGBMGT01SRVDEPLOY01"
$appgalleryrg = "RGP-MSGB-MGT01-SRVDEPLOY01"
$management = "GAM-MGT01"

# Load functions
Import-Module $SPATH\Modules\AZ_UTILS_FUNCTIONS -Force

if( -not ${GLOBAL:filename} ){
    $GLOBAL:filename = "${SPATH}\log\$($scriptName.Basename)_${application}_${platform}.log"
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

###########################################
# Main  
###########################################
# Connect to Azure
try {
    $scriptacc = $HOME + '\az_access.json'
    $AZ_ACCESS = Get-Content -Path $scriptacc -ErrorAction Stop | ConvertFrom-Json
    $cnvpwd = Convertto-SecureString -String $AZ_ACCESS.client_secret
    azlogon -p_client_id $AZ_ACCESS.client_id -p_client_secret $cnvpwd -p_tenant_id $AZ_ACCESS.tenant_id
} catch {
    throw
}

try {
    # Check application exists
    Set-AzContext -Subscription $management
    $applist = Get-AzGalleryApplication -GalleryName $appgallery -ResourceGroupName $appgalleryrg
    if (-not ($applist.name -contains $application)){
        logger "Application name not found" 1
        logger "Valid applications are: " 1
        logger $applist 1
        throw
    } else {
        $appid = $(Get-AzGalleryApplication -GalleryName $appgallery -ResourceGroupName $appgalleryrg | where-object {$_.Name -eq "${application}"}).Id
    }
 
    Set-AzContext -Subscription $vm_account
    # Check is single VM or ALL 
    If($vm -eq 'all'){
        $vmlist = get-azvm | where-object {$_.StorageProfile.OsDisk.OsType -eq "${platform}"}
    } else {
        $vmlist = get-azvm | where-object {$_.name -eq "${vm}"}
    }

    if ( -not $vmlist){
        logger "vm/vms not found" 1
        throw
    }
   
    # Uninstall application
    foreach($vmdet in $vmlist){
        try {
            $refId = $($vmdet.ApplicationProfile.GalleryApplications|where-object { $_.PackageReferenceId -like "${appid}*"}).PackageReferenceId
            if( $refId ){    
                if($list.IsPresent){
                    logger "Installed on: $($vmdet.Name)" 99
                } else {
                    logger "Uninstalling application ${application} from $($vmdet.Name)" 99
                    logger "Get-AzVM -ResourceGroupName $($vmdet.ResourceGroupName) -VMName $($vmdet.Name)" 99
                    Remove-AzVmGalleryApplication -VM $vmdet -GalleryApplicationsReferenceId $refid -Verbose -Debug
                    Update-AzVM -ResourceGroupName  $($vmdet.ResourceGroupName) -VM $vmdet -ErrorAction Stop
                    logger "Uninstalling application ${application} from $($vmdet.Name) Successful." 99
                }
            } else {
                logger "App not found on $($vmdet.Name)" 99
            }
            # $(Get-AzVM -ResourceGroupName $vmdet.ResourceGroupName -VMName $vmdet.Name).ApplicationProfile.GalleryApplications
        } catch {
            logger "Failed to uninstall application ${application} from $($vmdet.Name)" 1
        }
    }
} catch {
    throw
}