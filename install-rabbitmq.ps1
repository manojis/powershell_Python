param (
	[switch]$skipIntallAdminPlugin = $false,
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
	
	$nameAdminPlugin = "RabbitMQ Admin Plugin"
	$installerPath = "..\rabbitmq-server-3.6.5.exe"
	$installPath = $installDir + "\rabbitmq"
	$installArgs = "/S /D=" + $installPath
	$installerSbinPath = $installPath + '\rabbitmq_server-3.6.5\sbin'
	$installerAdminPluginPath = '.\rabbitmq-plugins.bat'
	$installerServicePath = '.\rabbitmq-service.bat'
	
	# show progress
	Write-InstallProgress $nameRabbitMQ $percentComplete "2 minutes"

	# search registry to check if installation needs to be skipped
	if (!(Skip-Install $nameRabbitMQ $versionRabbitMQ $bitRabbitMQ)) {
		# proceed to installation
		
		#Using Start-Process without Wait and Wait-Process as Install-Software function hangs on RabbitMQ Installation
		#Install-Software $nameRabbitMQ $installerPath $installArgs
		
		$maximumRuntimeSeconds = 120
		$process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -PassThru
		$process | Wait-Process -Timeout $maximumRuntimeSeconds -ErrorAction Stop
		
		if ($process.ExitCode -eq 0) {
			Write-Success "$nameRabbitMQ installed successfully"		
		} else {
			Write-Error "$nameRabbitMQ installation failed" 			
		}
		
		#Install admin plugin
		if (!$skipIntallAdminPlugin) {
			invoke-expression -Command 'Push-Location "$installerSbinPath"'
			$logFilePath = "$scriptRoot" + '\' + $logPath + '\install-rabbitmq-plugins.' + (Get-Date -format yyyyMMddHHmmss) + '.log'
			#Introducing time lag after installation
			Start-Sleep -s 30
			Install-Software $nameAdminPlugin $installerAdminPluginPath "enable rabbitmq_management" $logFilePath $true
			Stop-ServiceIfExist $nameRabbitMQ
			Install-Software $nameAdminPlugin $installerServicePath "install"
			Start-Service $nameRabbitMQ
			invoke-expression -Command 'Pop-Location'
		}
	}
	
} catch {
	invoke-expression -Command 'Pop-Location'
	if ($config) {
		Write-ErrorAsString $error[0]
	} else {
		throw
	}
	
} finally {
	Write-InstallProgress $nameRabbitMQ 100
	if ($config) {
		Reset-Config
	}
}
