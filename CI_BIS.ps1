
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

