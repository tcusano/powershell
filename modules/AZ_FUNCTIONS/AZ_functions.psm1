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