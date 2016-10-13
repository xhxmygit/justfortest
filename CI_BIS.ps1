
echo "------------------------------------"

# SetExecutionPolicyToRemoteSigned.ps1
# Need to run this after every server reboot.
Write-Output "Setting local Powershell policy to RemoteSigned"
Write-Output ""

Set-ExecutionPolicy -scope CurrentUser Undefined -Force
#Set-ExecutionPolicy -scope Process Undefined -Force
Set-ExecutionPolicy -scope LocalMachine Undefined -Force

Set-ExecutionPolicy -scope CurrentUser RemoteSigned -Force
#Set-ExecutionPolicy -scope Process RemoteSigned -Force
Set-ExecutionPolicy -scope LocalMachine RemoteSigned -Force

Write-Output "Finished."

Get-ExecutionPolicy -list
Start-Sleep -s 10

echo "------------------------------------"



$vmName = "FreeBSD11"
$hvServer = "localhost"

# $v = Get-VM  -Name $vmName -ComputerName $hvServer
$VMs =  Get-VM 
if ($VMs -eq $null)
{
	"Error: VM cannot find the VMs"
	return 1
} 


"The VMs are: $VMs"
echo "------------------------------------"

