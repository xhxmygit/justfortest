. .\CI\CI_Utils_2008R2.ps1  | out-null

$sts = get-module | select-string -pattern HyperV -quiet
if (! $sts)
{
	"Import the module of HyperV.psd1"
    Import-module .\BIS\WS2008R2\lisa\HyperVLibV2Sp1\Hyperv.psd1
}

$TestParameterEnable = $False
if( $TestParameterEnable -eq $True )
{
	$env:VMName = "FreeBSD11"
	$env:TestSuite = "Debug"
}




<#
$xml: xml file path
$scriptFile: The file will be executed on VM
$remoteDir: This directory on VM is stored the files from the local
$toolsParentDir: This directory on local is the parent directory of tools subdirectory
$scriptFilePara: The parameters for script file 
$logFileOnVM: The log name generated by the script on VM
$logFileDirOnLocal: This directory is stored the log copied from VM 
$timeout: The script file must be done in this time

Example:
$remoteDir = "/tmp"
$logFile = "autobuild.log"
ExecuteScriptFromLocalToVmAndCheckResult  "$pwd\BIS\$os_on_host\lisa\run.xml" "./CI/autobuildtest.sh" $remoteDir  "CI" " --buildworld --srcURL https://svn.FreeBSD.org/base/ --log $remoteDir/$logFile " "$remoteDir/$logFile"  $pwd  "3600"
#>
Function ExecuteScriptFromLocalToVmAndCheckResult ( [String]$xml,[String]$scriptFile,[String]$remoteDir,[String]$toolsParentDir,[String]$scriptFilePara,[String]$logFileOnVM,[String]$logFileDirOnLocal,[String]$timeout)
{

	$xmlFilenameForVM = [xml] (Get-Content -Path  $xml)  2>null
	$vm = $xmlFilenameForVM.config.VMs.vm

	cd .\$toolsParentDir
	WaitSSHLoginPrepare $vm.sshKey  $vm.ipv4 
	cd ..
	
	#Send the script from local to VM
	$sts = SendFileToVMUntilTimeout  $vm $scriptFile $remoteDir $toolsParentDir 
	if( $sts -ne 0 )
	{
		Write-Error  "Error: $($vm.vmName) send $scriptFile to $($vm.vmName) failed"
		return 1
	}
	Write-Output "Log: $($vm.vmName) send $scriptFile to $($vm.vmName) successfully"

	#Send command from local host to VM 
	#Make sure the format of script on VM is unix 
	$fileName = [io.path]::GetFileName("$scriptFile")
	$FreeBSDFileName = "$remoteDir/$fileName"
	Write-Output "Info: To set the format of script $FreeBSDFileName on $($vm.vmName) being unix"
	if (-not (SendCommandToVMUntilTimeout $vm "dos2unix  $FreeBSDFileName" $toolsParentDir "120") )
	{
		Write-Error "Error: Unable to set the format of script $FreeBSDFileName on $($vm.vmName) being unix"
		return 1
	}
	Write-Output "Log: Set the format of script $FreeBSDFileName on $($vm.vmName) being unix successfully"

	#To set x bit of the script on VM
	Write-Output  "Info: To set x bit of the script $FreeBSDFileName on $($vm.vmName)"
	if (-not (SendCommandToVMUntilTimeout $vm "chmod 755 $FreeBSDFileName"  $toolsParentDir "120") )
	{
		Write-Error "Error: $($vm.vmName) unable to set x bit on test $FreeBSDFileName script"
		return 1
	}


	#Send command to run script on VM 
	#Note: This script will reboot the VM !!!
	Write-Output "Info: To run the script $FreeBSDFileName on $($vm.vmName) for Syncing, building and installing kernel/world"
	Write-Output "Info: This step will take a very long time ..."
	if (-not (SendCommandToVMUntilTimeout $vm "$FreeBSDFileName  $scriptFilePara"  $toolsParentDir $timeout) )
	{
		Write-Error  "Error: $($vm.vmName) unable to run $FreeBSDFileName script"
		return 1
	} 

	Write-Output  "Info: The former step will reboot the VM, so please wait VM boot completely"
	Write-Output  "Info: It will takes more than one minute, please wait with patience"
	$sts = WaitVMBootFinish $vm 
	if( $sts -ne 0 )
	{
		return 1
	}

	#Get log file from VM to local host		
	Write-Output  "Info: Get log file $logFileOnVM from VM to local host"
	$sts = GetFileFromVMUntilTimeout  $vm $logFileOnVM $logFileDirOnLocal  $toolsParentDir   
	if( $sts -ne 0 )
	{
		Write-Error "Error: $($vm.vmName) get $logFileOnVM from $($vm.vmName) failed"
		return 1
	}
	
	$name = [io.path]::GetFileName("$logFileOnVM")
	$sts = CheckErrorLogInFile "$logFileDirOnLocal\$name"
	if( $sts -ne 0 )
	{
		Write-Error "Error: There is some errors in $logFileDirOnLocal\$name"
		return 1
	}

	return 0

}


Function CIUpdateConfig([string]$originalConfigFile, [string]$CIFolder, [string]$newConfigFileName)
{
	<#
	Usage:
		CIUpdateConfig $originalConfigFile $CIFolder $newConfigFileName
	Description:
		This is a function to update cloud configuration for CI job.
	#>
	
	$newConfigFile = "$CIFolder\$newConfigFileName"
    
    # The $newConfigFileName is a copy of $originalConfigFile. All changes will be written into the $newConfigFileName
	"Copy $originalConfigFile to $newConfigFile"
    Copy-Item $originalConfigFile $newConfigFile
    
    #For FreeBSD 10.3, the VM bus protocol version is not supported
    if( $env:VMName -eq "FreeBSD10.3")
    {
        $content = get-content $newConfigFile
        clear-content $newConfigFile
        foreach ($line in $content)
        {
            $liner = $line.Replace("<suiteTest>VmbusProtocolVersion</suiteTest>","")
            Add-content $newConfigFile -Value $liner
        }
        sleep 1
    }

	"Begin to update the parameters of vm name, test suite, ip address and so on."
	[xml]$xml = Get-Content "$newConfigFile"
	
	# Update parameter of OnGuestReadHostKvpData test case
	# TODO
	
	# Update vmName
	$xml.config.VMs.vm.vmName = $env:VMName
	
	# Update test suite
	$xml.config.VMs.vm.suite = $env:TestSuite
	
	# Update test hvServer
	$server = "localhost"
	$xml.config.VMs.vm.hvServer = $server
	
	# Update ipv4 address
	$ipv4_addr = GetIPv4 $env:VMName $server
	$xml.config.VMs.vm.ipv4 = [string]$ipv4_addr

	if($env:DebugCases -and $env:DebugCases.Trim() -ne "")
	{
		$debugCycle = $xml.SelectSingleNode("/config/testSuites/suite[suiteName=`"debug`"]")
		if($debugCycle)
		{
			foreach($testcase in $debugCycle.suiteTests)
			{
				$testcase = $debugCycle.RemoveChild($testcase)
			}
		}
		else
		{
			$debugCycle = $xml.CreateElement("suite")
			$name = $xml.CreateElement("suiteName")
			$name.InnerText = "DEBUG"
			$name = $debugCycle.AppendChild($name)
			$debugCycle = $xml.DocumentElement.testSuites.AppendChild($debugCycle)
		}
		
		$debugCase = $xml.CreateElement("suiteTests")
		foreach($cn in ($env:DebugCases).Trim().Split(","))
		{
			$debugCaseName = $xml.CreateElement("suiteTest")
			$debugCaseName.InnerText = $cn.Trim()
			$debugCaseName = $debugCase.AppendChild($debugCaseName)
			$debugCase = $debugCycle.AppendChild($debugCase)
		}
	}

	$xml.Save("$newConfigFile")
}




"-------------------------------------------------"
"Begin to prepare the xml for test"

# Copy certificate
$os_on_host = "WS2008R2"
$sshDir = "$pwd" +"\BIS\$os_on_host\lisa\ssh"
$global:testReport = "$pwd\CI\report.xml"
$global:reportCompressFile = "$pwd\CI\logs.zip"
$status = Test-Path $sshDir  
if( $status -ne "True" )
{
	New-Item  -ItemType "Directory" $sshDir
}
Copy-Item CI\ssh\*   $sshDir

# Copy tools
$binDir = "$pwd" + "\BIS\$os_on_host\lisa\bin"
$status = Test-Path $binDir 
if( $status -ne "True" )
{
	New-Item  -ItemType "Directory" $binDir
}
Copy-Item CI\tools\*   $binDir


"The vm name is:  $env:VMName"
#Delete the snapshort
$sts = DeleteSnapshot $env:VMName "localhost"
if($sts -eq 1)
{
	"The expected return value  is 0, but it's $sts."
	return 1
}

"Now, it begins to start the $env:VMName vm and please wait for a moment..."
$sts = DoStartVM $env:VMName "localhost"
if($sts -eq 1)
{
	"The expected return value  is 0, but it's $sts."
	return 1
}

"Begin to update the xml config for CI test"
$XmlConfigFile = "FreeBSD_WS2008R2.xml"
if ($XmlConfigFile -and (Test-Path "$pwd\BIS\$os_on_host\lisa\xml\freebsd\$XmlConfigFile"))
{
	CIUpdateConfig "$pwd\BIS\$os_on_host\lisa\xml\freebsd\$XmlConfigFile" "$pwd\BIS\$os_on_host\lisa" run.xml 
}
else
{
	#TODO
	return 1
}


"Update the xml config for CI test done."
"-------------------------------------------------"


#Begin to build and install kernel/world if necessary
$remoteDir = "/usr"
$logFile = "autobuild.log"
$branch = $env:GitBranch
$bisCodeDir = "BIS"
$ciCodeDir = "CI"
$env:BuildWorld = $False
$env:BuildKernel = $True

if( $env:SoureCodeURL -eq $null -or $env:SoureCodeURL -eq "" -or $env:SoureCodeURL -eq " " )
{
	$env:BuildKernel = $False
}

if( $env:BuildWorld -eq $True )
{
    "Begin to build and install world&kernel and it will take a very long time ..."
	$sts=ExecuteScriptFromLocalToVmAndCheckResult  ".\$bisCodeDir\$os_on_host\lisa\run.xml" ".\$ciCodeDir\autobuild.sh" $remoteDir  $ciCodeDir " --buildworld  -b $branch  --srcURL $env:SoureCodeURL --log $remoteDir/$logFile " "$remoteDir/$logFile"  $pwd  "36000"
	if($sts -eq 1)
	{
		"The expected return value  is 0, but it's $sts."
		"Build & install world&kernel failed"
		"----------------------- Log from vm -----------------------"
		Get-Content $logFile
		return 1
	}
}
elseif( $env:BuildKernel -eq $True )
{
    "Begin to build and install kernel and it will take a long time ..."
	$sts=ExecuteScriptFromLocalToVmAndCheckResult  ".\$bisCodeDir\$os_on_host\lisa\run.xml" ".\$ciCodeDir\autobuild.sh" $remoteDir  $ciCodeDir " -b $branch --srcURL $env:SoureCodeURL --log $remoteDir/$logFile " "$remoteDir/$logFile"  $pwd  "108000"
	if($sts -eq 1)
	{
		"The expected return value  is 0, but it's $sts."
		"Build & install kernel failed"
		"----------------------- Log from vm -----------------------"
		Get-Content $logFile
		return 1
	}
}



#To stop the vm before creating a snapshort
$sts = DoStopVM $env:VMName "localhost"
if($sts -eq 1)
{
	"The expected return value  is 0, but it's $sts."
	return 1
}

#Create a snapshort named "ICABase" before test cases
$sts=CreateSnapshot $env:VMName "localhost"  "ICABase"
if($sts -eq 1)
{
	"The expected return value  is 0, but it's $sts."
	return 1
}

#Now, everything is OK and begins to run the test cases
"Ready to run test cases"
cd .\BIS\$os_on_host\lisa
.\lisa run run.xml
"Run test cases done"


