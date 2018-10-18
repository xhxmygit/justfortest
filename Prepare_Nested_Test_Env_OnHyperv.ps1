

param([string]$server_host, [string]$server_vm, [string]$client_host, [string]$client_vm, [switch]$enable_Network)

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



if($enable_Network) {
	# The client and server vm maybe created randomly on server and client host
	RemoveVM -computerName $client_host -vmName $client_vm
	RemoveVM -computerName $client_host -vmName $server_vm
	RemoveVM -computerName $server_host -vmName $server_vm
	RemoveVM -computerName $server_host -vmName $client_vm
}


# .\Prepare_Nested_Test_Env_OnHyperv.ps1 -server_host "sh-ostc-perf-03" -server_vm "server-vm"   -client_host "sh-ostc-perf-04" -client_vm "client-vm" -enable_Network


