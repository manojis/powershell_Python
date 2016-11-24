param (
	[switch]$debug = $false,
	# flag to determine if script should take responsibility of installer configuration & exception handling
	# set to $false if script called from parent script to let parent responsible for installer configuration & exception handling
	[switch]$config = $true,
	# set percentage completion for installer
	$percentComplete = 0
)

try {
	if ($config) {
		Import-Module -Name .\Functions.psm1 -Force
		New-Config $debug
	}
	
	$name = 'RabbitMQ Queues'
	$msiRabbitmqSbinPath = 'C:\Program Files (x86)\RabbitMQ Server\rabbitmq_server-3.6.5\sbin'
	$addQueueFileName = 'rabbitmq-addqueue.bat'
	$adminPluginFileName = 'rabbitmqadmin'
	$installerPath = '.\' + $addQueueFileName

	# show progress
	Write-InstallProgress $name $percentComplete "45 seconds"

	if (!((Test-Path "$msiRabbitmqSbinPath\$addQueueFileName") -And (Test-Path "$msiRabbitmqSbinPath\$adminPluginFileName"))) {
		Write-Error "Files not found to configure epp queue. Run RadDesktop MSI and rerun the script to add epp queue."
	}
	
	$rabbitmqSbinPath = Find-RabbitMQSbinPath
	Write-Debug "rabbitmqSbinPath :: $rabbitmqSbinPath"
	
	if (!$rabbitmqSbinPath) {
		Write-Error "RabbitMQ installation not found. Please install RabbitMQ and rerun the script to add epp queue."
	}
	
	if ($rabbitmqSbinPath -ne $msiRabbitmqSbinPath) {
		Copy-Item -Path $msiRabbitmqSbinPath\$addQueueFileName -Destination $rabbitmqSbinPath -force
		Copy-Item -Path $msiRabbitmqSbinPath\$adminPluginFileName -Destination $rabbitmqSbinPath -force
	}

	$logFilePath = "$scriptRoot" + '\' + $logPath + '\install-rabbitmq-queue.' + (Get-Date -format yyyyMMddHHmmss) + '.log'

	invoke-expression -Command 'Push-Location "$rabbitmqSbinPath"'
	Install-Software $name $installerPath SKIP_PAUSE $logFilePath
	invoke-expression -Command 'Pop-Location'
	
} catch {
	invoke-expression -Command 'Pop-Location'
	if ($config) {
		Write-ErrorAsString $error[0]
	} else {
		throw
	}
	
} finally {
	Write-InstallProgress $name 100
	if ($config) {
		Reset-Config
	}
}
