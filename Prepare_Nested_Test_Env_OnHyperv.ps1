

param([string]$server_host, 
[string]$server_vm, 
[string]$client_host, 
[string]$client_vm, 
[string]$srcPath="", 
[string]$dstPath="", 
$user, 
$password, 
[switch]$enable_Network)


Function Get-Cred($user, $password)
{
	$secstr = New-Object -TypeName System.Security.SecureString
	$password.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
	$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $user, $secstr
	Set-Item WSMan:\localhost\Client\TrustedHosts * -Force
	return $cred
}


Function RemoveVM ($computerName, $vmName) {
	Write-Output "Delete the $vmName on $computerName if it exits."
	# Get-VM  -ComputerName $computerName | Where-Object {$_.Name -eq $vmName} | Stop-VM -ComputerName  $computerName -Force | Remove-VM -ComputerName $computerName -Force
	$vm = Get-VM  -ComputerName $computerName | Where-Object {$_.Name -eq $vmName}
	if($vm) {
		Stop-VM -ComputerName  $computerName   -Name $vmName   -Force
		Start-Sleep 3
		Remove-VM -ComputerName $computerName  -Name $vmName   -Force 
		Start-Sleep 3
		Write-Output "Delete the $vmName on $computerName done."
	}
}

Function Get-OSvhd ([string]$computerName, [string]$srcPath, [string]$dstPath, $session) {
	Write-Output "Copy $srcPath to $dstPath on $computerName ..."
	Invoke-Command  -session $session -ScriptBlock {
		param($dstPath)
		$target = ( [io.fileinfo] $dstPath ).DirectoryName
		if( -not (Test-Path $target) ) {
			Write-Output "Create the directory: $target"
			New-Item -Path $target -ItemType "directory" -Force
		}
	} -ArgumentList $dstPath
	
	if( $srcPath.Trim().StartsWith("http") ){
		Invoke-Command  -session $session -ScriptBlock {
			param($srcPath, $dstPath)

			Import-Module BitsTransfer
			$displayName = "MyBitsTransfer" + (Get-Date)
			Start-BitsTransfer `
				-Source $srcPath `
				-Destination $dstPath `
				-DisplayName $displayName `
				-Asynchronous
			$btjob = Get-BitsTransfer $displayName
			$lastStatus = $btjob.JobState
			do{
				if($lastStatus -ne $btjob.JobState) {
					$lastStatus = $btjob.JobState
				}

				if($lastStatus -like "*Error*") {
					Remove-BitsTransfer $btjob
					Write-Output "Error connecting $srcPath to download."
					return 1
				}
			} while ($lastStatus -ne "Transferring")

			do{
				Write-Output (Get-Date) $btjob.BytesTransferred $btjob.BytesTotal ($btjob.BytesTransferred/$btjob.BytesTotal*100)
				Start-Sleep -s 10
			} while ($btjob.BytesTransferred -lt $btjob.BytesTotal)

			Write-Output (Get-Date) $btjob.BytesTransferred $btjob.BytesTotal ($btjob.BytesTransferred/$btjob.BytesTotal*100)
			Complete-BitsTransfer $btjob
		}  -ArgumentList $srcPath, $dstPath
	}
	else {
		Copy-Item $srcPath -Destination $dstPath -ToSession $session
	}

	Write-Output "Copy $srcPath to $dstPath on $computerName Done."
}


function Main()
{
	$cred = Get-Cred -user $user -password $password

	if($enable_Network) {
		# The client and server vm maybe created randomly on server and client host
		RemoveVM -computerName $client_host -vmName $client_vm
		RemoveVM -computerName $client_host -vmName $server_vm
		RemoveVM -computerName $server_host -vmName $server_vm
		RemoveVM -computerName $server_host -vmName $client_vm
	}

	# For network test, copy/download the vhd
	if($enable_Network -and $srcPath -and $dstPath) {
		$session = New-PsSession  -ComputerName  $server_host -Credential $cred
		Get-OSvhd -computerName $server_host -srcPath $srcPath -dstPath $dstPath -session $session
		$session = New-PsSession  -ComputerName  $client_host -Credential $cred
		Get-OSvhd -computerName $client_host -srcPath $srcPath -dstPath $dstPath -session $session
	} else {
		# For storage test, copy/download the vhd
		if($srcPath -and $dstPath) {
			$session = New-PsSession  -ComputerName  $server_host -Credential $cred
			Get-OSvhd -computerName $server_host -srcPath $srcPath -dstPath $dstPath -session $session
		}
	}
}


Main


# .\Prepare_Nested_Test_Env_OnHyperv.ps1 -server_host "sh-ostc-perf-03" -server_vm "server-vm"   -client_host "sh-ostc-perf-04" -client_vm "client-vm" -enable_Network

# .\Prepare_Nested_Test_Env_OnHyperv.ps1 -server_host "sh-ostc-perf-03"  -server_vm "server-vm"   `
										# -client_host "sh-ostc-perf-04" -client_vm "client-vm"   `
										# -srcPath "\\SH-OSTC-PERF-03\share\xhxTestFile.txt"      `
										# -dstPath "D:\\lili\\vhd\\xhxTestFile_LOCAL.txt"         `
										# -user '**********'  -password '******'   -enable_Network














