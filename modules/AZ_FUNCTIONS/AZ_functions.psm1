function logger {
    param (
        [string]$p_msg, [int]$p_color
    )
    [string]$color='99'

    if($p_color -eq 0)
    {
        $color = 'Green'
        $type = 'SUCCESS: '
    }
    elseif($p_color -eq 1)
    {
        $color = 'DarkRed'
        $type = 'ERROR: '
    }
    elseif($p_color -eq 2)
    {
        $color = 'Yellow'
        $type = 'WARNING: '
    }
    else {
        $color = 'Magenta'
        $type = 'INFO: '
    }

    [string]$date = Get-Date -Format "dddd dd/MM/yyyy HH:mm"
    $logmsg =  ${date} + ': ' + $type + ${p_msg}
    Write-Host($logmsg) -ForegroundColor $color
    #Write-Verbose -Message (${date} + ': ' + ${p_msg})
    # Write to tmp file for pagerduty
    if($logmsg){
        $logmsg | Out-File -FilePath ${GLOBAL:filename} -Append -NoClobber
    }
}

function azlogon {
    param (
        [Parameter(Mandatory=$true)][String]$p_client_id,
        [Parameter(Mandatory=$true)][SecureString]$p_client_secret,
        [Parameter(Mandatory=$true)][String]$p_tenant_id
      )
    $cnvpwd = ConvertFrom-SecureString -SecureString $p_client_secret -AsPlainText
	logger "Connecting to AZURE" 99
    az login --service-principal -u $p_client_id -p $cnvpwd --tenant $p_tenant_id | out-null
	logger "Connected to AZURE" 0
} 

function execcmd {
    param (
        $cmd
    )
    $res = Invoke-Expression $cmd | Out-String -OutVariable out
    $failure = $res.Contains("False")
    if($failure -eq $true){
        throw
    } else {
        return $out
    }
}

function Fstslog {
	param (
	  [string]$p_txt2
	)
	$dt =  (Get-Date).ToString("yyyyMMddHHmmss")
	$outstr =  $dt + " " + $p_txt2 
	$outstr | out-file -Filepath $logfilepost -Append -Force
}

function create_azure_rg {
    param (
        [string]$rg_name,
        [string]$rg_location,
        [string]$account
    )
    
    logger "Creating terraform files for resource group" 99
    $DIRTFTEMP = $SPATH + "\..\terraform\templates\resource_group\"

    $DIRTFDPL = $SPATH + "\..\terraform\deployment\resource_group\"
    $DIRRGHOME = $DIRTFDPL + $rg_name

    if ( -not (Test-Path -Path $DIRTFDPL)) { New-Item -Path $DIRTFDPL -ItemType Container }
    if ( -not (Test-Path -Path $DIRRGHOME)) { New-Item -Path $DIRRGHOME -ItemType Container }

    try {
        # Copy template to deployment folder
        copy-Item -Path $DIRTFTEMP\* -Destination $DIRRGHOME\. -ErrorAction Stop

        logger "INFO: Updating Terraform configuration" 99
        $filecont = Get-Content -Path $DIRRGHOME\az_vars.json |ConvertFrom-Json

        $filecont.resource_group_name = $rg_name
        $filecont.resource_group_location = $rg_location
        $filecont | ConvertTo-Json | Out-File -FilePath $DIRRGHOME/az_vars.json -Encoding ASCII -ErrorAction stop

        & ./az_deploy.ps1 -resource $rg_name -account $account -region $rg_location

    } catch {
        logger "failed to create resource group" 1
        throw 
    }
}

function azure_recovery_plan {
    param (
        [string]$vault_name,
        [string]$vault_rg,
        [string]$fabric_primary_name,
        [string]$fabric_secondary_name,
        [string]$recovery_plan_name,
        [string]$vm_replication_id,
        [string]$account,
        [string]$rg_location,
        [string]$create
    )
    
    logger "Creating terraform files for resource group" 99
    $DIRTFTEMP = $SPATH + "\..\terraform\templates\site_recovery\s2s_plans\"

    $DIRTFDPL = $SPATH + "\..\terraform\deployment\site_recovery\s2s_plans\"
    $DIRRGHOME = $DIRTFDPL + $recovery_plan_name

    if ( -not (Test-Path -Path $DIRTFDPL)) { New-Item -Path $DIRTFDPL -ItemType Container }
    if ( -not (Test-Path -Path $DIRRGHOME)) { New-Item -Path $DIRRGHOME -ItemType Container }

    try {
        if( $create -eq "true" ){
            # Copy template to deployment folder
            copy-Item -Path $DIRTFTEMP\* -Destination $DIRRGHOME\. -ErrorAction Stop
        }

        logger "INFO: Updating Terraform configuration" 99
        $filecont = Get-Content -Path $DIRRGHOME\az_vars.json |ConvertFrom-Json

        $vm_list = [Collections.ArrayList]@()
        if($create -eq "true"){
            $filecont.recovery_plan_name = $recovery_plan_name
            $filecont.s2s_vault_name = $vault_name
            $filecont.s2s_vault_rg = $vault_rg
            $filecont.s2s_fabric_primary_name = $fabric_primary_name
            $filecont.s2s_fabric_secondary_name = $fabric_primary_name
            $vm_list.add($vm_replication_id)
        } else {
            foreach( $x1 in $filecont.replication_ids) {
                $vm_list.Add($x1)
            }
            $vm_list.add($vm_replication_id)
        }
        $filecont.replication_ids = $vm_list
        $filecont | ConvertTo-Json | Out-File -FilePath $DIRRGHOME/az_vars.json -Encoding ASCII -ErrorAction stop

        & ./az_deploy.ps1 -resource $recovery_plan_name -account $account -region $rg_location

    } catch {
        logger "Failed to recovery plan." 1
        throw 
    }
}

function validatevmname {
    param (
        [string]$vmname,
        [string]$region,
        [string]$account
    )

    $scriptcfg = $SPATH + '\naming_std.json'
    if(Test-Path -Path $scriptcfg){
        $naming = Get-Content -Path $scriptcfg -ErrorAction Stop | ConvertFrom-Json
    } else {
        logger "Script naming std file ${scriptcfg} not found." 1
        throw
    }
    
    if($vmname.Length -ne 13){
        logger "Invalid server name length must be 13 characters" 1
        throw
    }

    $vmprovider = $vmname.Substring(0,1)
    $vmlocation = $vmname.Substring(1,3)
    $vmfunction = $vmname.Substring(4,2)
    $vmrole = $vmname.Substring(6,3)
    $vmplatform = $vmname.Substring(9,1)
    $sequence = $vmname.Substring(10,2)
    $vmenvironment = $vmname.Substring(12,1)

    #Build list
    $roles = $($naming.roles|Get-Member |Where-Object {$_.membertype -eq 'NoteProperty'}|Select-Object Name).Name
    foreach ($role in $roles ){
        $list = $($naming.roles.${role}|Get-Member |Where-Object {$_.membertype -eq 'NoteProperty'}|Select-Object Name)
        $rlist = $list + $rlist
    }

    $functions = $($naming.functions|Get-Member |Where-Object {$_.membertype -eq 'NoteProperty'}|Select-Object Name).Name
    foreach ($function in $functions ){
        $list = $($naming.functions.${function}|Get-Member |Where-Object {$_.membertype -eq 'NoteProperty'}|Select-Object Name)
        $flist = $list + $flist
    }

    try {
        if($vmprovider -ne 'M'){
            logger "Name must start with M --> Microsoft" 1
            throw
        }
        if( -not $naming.location.$vmlocation){
            logger "Invalid location ${vmlocation} Valid list:" 1
            $naming.location
            throw
        }
        if($naming.location.$vmlocation -ne $region){
            logger "${region} does not match location in server name." 1
            throw
        }
        if( $flist.name -notcontains $vmfunction){
            logger "Invalid function ${vmfunction} Valid list:" 1
            foreach ($function in $functions ){
                $naming.functions.${function}
            }
            throw
        }
        if($rlist.Name -notcontains $vmrole){
            logger "Invalid role ${vmrole} Valid list:" 1
            foreach ($role in $roles ){
                $naming.roles.${role}
            }
            throw
        }
        if($vmplatform -ne 'L' -and $vmplatform -ne 'W'){
            logger "Please enter valid platform L or W" 1
            throw
        }
        $sequence
        if($sequence -notmatch '^\d+$'){
            logger "Sequence can only be between 00-99" 1
            throw
        }
        if($vmenvironment -ne 'P' -and $vmenvironment -ne 'T' -and $vmenvironment -ne 'D'){
            logger "Please enter valid environment P, T or D" 1
            throw
        }
        $envin = $account.Substring(4,3)
        $ae = $naming.accenv.$envin
        if( $ae -ne ${vmenvironment} ){
            logger "Incorrect environment in VM name." 1
            logger "${envin} --> ${ae} and not ${vmenvironment}" 1
            throw
        }
    }
    catch {
        logger "" 1
        logger "Example: MSGBADWDCW01P" 1
        logger "Position 1 --> provider valid value M" 1
        logger "Position 2-4 --> location SGB = uksouth" 1
        logger "Position 5-6 --> function AD = Active Directory" 1
        logger "Position 7-9 --> application WDC = Writable Domain Controller" 1
        logger "Position 10 --> platform W = Windows or L = Linux" 1
        logger "Position 11-12 --> vm number next availble number" 1
        logger "Position 13 --> environment P = PROD, T = TEST, D = DEV" 1
        throw
    }
}

function validatergname {
    param (
        [string]$rgname,
        [string]$account
    )

    $envin = $account.Substring(4,3)
    $ae = $rgname.Substring(9,3)
    if( $ae -ne ${envin} ){
        logger "Incorrect environment in Resource Group Name." 1
        logger "${ae} --> ${envin} and not ${rgname}" 1
        throw
    }
}

function chkdsksiz {
    param (
        [int]$item
    )
    
    if( $item -le 4 ){ $disksize = 4 }
    if( $item -gt 4 -and $item -le 8 ){ $disksize = 8 }
    if( $item -gt 8 -and $item -le 16 ){ $disksize = 16 }
    if( $item -gt 16 -and $item -le 32 ){ $disksize = 32 }
    if( $item -gt 32 -and $item -le 64 ){ $disksize = 64 }
    if( $item -gt 64 -and $item -le 128 ){ $disksize = 128 }
    if( $item -gt 128 -and $item -le 256 ){ $disksize = 256 }
    if( $item -gt 256 -and $item -le 512 ){ $disksize = 512 }
    if( $item -gt 512 -and $item -le 1024 ){ $disksize = 1024 }
    if( $item -gt 1024 -and $item -le 2048 ){ $disksize = 2048 }
    if( $item -gt 2048 -and $item -le 4096 ){ $disksize = 4096 }
    if( $item -gt 4096 -and $item -le 8192 ){ $disksize = 8192 }
    if( $item -gt 8192 -and $item -le 16384 ){ $disksize = 16384 }
    if( $item -gt 16384 -and $item -le 32767){ $disksize = 32767 } 

    return $disksize
}

function tfinit {
    logger "Initilising terraform" 99
    $cmd = "terraform init -backend=true -backend-config=`"" + $dirtfcommon + "az_config.hcl`" -compact-warnings"
    $cmd +=';$?'
    try {
        $res = execcmd $cmd
    } catch {
        logger "Terraform failed to initialise" 1
        throw
    }
    return $res
}

function tfoutput {
    param (
        [string]$parmname
    )
    $cmd = "terraform output " + $parmname
    # $cmd +=';$?'
    try {
        $res = execcmd $cmd
    } catch {
        logger "Terraform failed to find ${parmname}" 1
        throw
    }
    return $res
}

function tfwrkspc {
    logger "Selecting terraform workspace environment" 99
    $cmd = "terraform workspace new " + $wrkspc
    $cmd +=';$?'
    try {
    $res = Invoke-Expression $cmd
    if ( $res -eq $False ){
        $cmd = "terraform workspace select " + $wrkspc
        $cmd +=';$?'
        try {
            $res = execcmd $cmd
            }
        catch {
                logger "Terraform failed to select workspace ${wrkspc}" 1
        } 
    }
    $success = $res | Select-Object -Last 1
    if($success -eq $False){
        logger "Terraform failed to select workspace" 1
        throw
    }
    $cmd = "terraform workspace list | Select-String -Pattern '\*'"
    Invoke-Expression $cmd
    } catch {
    logger "Terraform failed create new workspace" 1
    $res
    throw
    }
}

function tfplan {
    logger "Preparing terraform plan" 99
    $cmd = "terraform plan -var='json_common=${fpjsoncommon}' -var='json_input=${fpjsoninput}' -out ${wrkspc}_plan.out -input=false"
    $cmd +=';$?'
    try {
    logger $cmd 99
    $res = execcmd $cmd    
    if($res|select-string -Pattern 'No changes.'){
        logger "No changes" 99
        exit 0
    } else {
        $content = (($res|select-string -Pattern 'Plan:').line)
        $content = $content.Split(',')
        [string]$destroy = $content[2]
        if($destroy.split(' ')[3].Substring(0,7) -eq 'destroy'){
        if($destroy.split(' ')[1] -gt 0){
            $cnt = $destroy.split(' ')[1]
            logger "DO NOT RUN APPLY AS ${cnt} RESOURCE WILL BE DESTROYED" 1
            throw 
        }
        } else {
            logger "plan destroy verify failed" 1
            throw
        }
    }
    $res
    } catch {
        logger "Terraform failed to produce plan" 1
        $res
        throw 
    }
}

function tfapply {
    logger "Applying terraform plan to create VM" 99
    $cmd = "terraform apply -input=false ${wrkspc}_plan.out"
    $cmd +=';$?'
    logger "${cmd}" 99
    try {
        $res = execcmd $cmd
    } catch {
        logger "Terraform failed to apply" 1
        $res
        throw 
    }
}

function Get-MenuAnswer2 {
	PARAM(
		[string]$Banner="",
		[string[]]$DisplayOptions=@(),
        [array]$DisplayOptions2=@(),
        [string]$header=""
	)
	If ($DisplayOptions.Count -gt 0) {
		$ValidSelection=$False
		do
	{
		$FormattedBanner=Get-HeaderFormattedArray -HeaderString $Banner
		$FormattedBanner | Write-Host -ForegroundColor Yellow
		$OptionCount=0
		$ItemHash = @{}
    write-host($header)
		ForEach($Option in $DisplayOptions) {
			$OptionCount+=1
			$ItemHash.Add($OptionCount,$Option)
      [int]$dp2 = $OptionCount - 1
			[String]$out = $OptionCount.ToString() + ")   " + $Option + '      ' + $DisplayOptions2[$dp2]
      Write-Host($out)
		}
		Write-Host "Enter an option : " -NoNewline -ForegroundColor Yellow
		$Answer=Read-Host
		$IntAnswer=$Answer -as [int32]
		if ($Null -ne $IntAnswer) {
			if (($IntAnswer -gt 0) -and ($IntAnswer -le $OptionCount)) {
				$ValidSelection=$True
			}
		}
        }
	Until ($ValidSelection)
        [int]$dp2 = $Answer - 1
		return $ItemHash.[int]$Answer, $DisplayOptions2[$dp2]
	}
}

Function Get-HeaderFormattedArray {
	param (
		[string]$HeaderString=""
	)
	$TitleBar = ""
	#// Builds a line for use in a banner
	for ($i = 0; $i -lt ($HeaderString.Length) + 2; $i++) {
		$TitleBar += $TitleChar
	}
	Return @($TitleBar, "INPUT: $TitleChar$HeaderString$TitleChar", $TitleBar)
}
