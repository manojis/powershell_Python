param (
	[switch]$debug = $false,
	# flag to determine if script should take responsibility of installer configuration & exception handling
	# set to $false if script called from parent script to let parent responsible for installer configuration & exception handling
	[switch]$config = $true,
	# set percentage completion for installer
	$percentComplete = 0,
	# force installing and configuring RabbitMQ user even if user guest does not exist
	[switch]$force = $false
)

try {	
	if ($config) {
		Import-Module -Name .\Functions.psm1 -Force
		New-Config $debug
	}	
	
	$nameAddUser = "RabbitMQ User"
	$installerControlPath = '.\rabbitmqctl.bat'
	$installerSbinPath = Find-RabbitMQSbinPath
	$logFilePath = "$scriptRoot" + '\' + $logPath + '\install-rabbitmq-user.' + (Get-Date -format yyyyMMddHHmmss) + '.log'
	$guestcred = "guest"
	
	Write-InstallProgress $nameAddUser $percentComplete "1 minute" $null $true
	
	# verify WFM installation
	$objInstalled = Search-Registry $nameWFM
	if(!$objInstalled) {
		$objInstalled = Search-Registry $nameRadDesktop
	}
	if ($objInstalled) {
		$objInstalledWFM = Get-ItemProperty $keyWFM | select InstallPath
		if ($objInstalledWFM.InstallPath) {
			$installPathWFM = ($objInstalledWFM.InstallPath).Substring(0, ($objInstalledWFM.InstallPath).length - 1)
		}
	} else {
		Write-Error "$nameWFM installation not found. Please install $nameWFM and rerun the script to install RabbitMQ service."
	}

    # verify PREDIX installation
	$ID_DSP_HOME = [environment]::GetEnvironmentVariable("ID_DSP_HOME","Machine")
	if (!($ID_DSP_HOME -And (Test-Path $ID_DSP_HOME\etc\users.properties))) {
		Write-Error "Skipping $name installation as Predix installation not found. Please install Predix and rerun the script."
	}	
	
	
	$backuperlangcookieFile = [environment]::GetEnvironmentVariable("windir","Machine")        
    $windowserlangcookiepath=$backuperlangcookieFile+ "\.erlang.cookie"
	$usererlangcookiepath = $env:USERPROFILE+"\.erlang.cookie"	
	Copy-File "$windowserlangcookiepath" "$usererlangcookiepath"
	
	# get list of existing users within RabbitMQ
	invoke-expression -Command 'Push-Location "$installerSbinPath"'	
	$installerListUsersCmd = $installerControlPath + ' list_users'
	$userlist = invoke-expression -Command "$installerListUsersCmd"

	# check if user guest exist
	

    Foreach ($user in $userlist) {
		$userName = $user.Split("[")[0].Trim()
		if ($userName -ceq $guestcred) {
			$isguestpresent = $true
			break;
		}
	}	

	$skipInstall = $false
	
	if (!$force -And !$isguestpresent) {
		Write-Warning "Skipping $nameAddUser installation as user $guestcred does not exist in RabbitMQ."
		$skipInstall = $true
	}
	
	Write-InstallProgress $nameAddUser 100
	
	if (!$skipInstall) {
	
		# prompt new user name
		do{
			$isValidUser = $true
			$minchars = "5"
			$inputName = "RabbitMQ Username"
			$adminusername = Write-Prompt "Please provide $inputName without any special characters (e.g. user123)" "$inputName" $false $false $minchars
			
			if($adminusername -match '[^a-zA-Z0-9]'){
				$isValidUser = $false
				Write-Warning "$inputName is invalid. It must not contain SPACE or any other special character"			
			}
			If($isValidUser -And ($adminusername.length -gt 15)){
				$isValidUser = $false
				Write-Warning "$inputName is invalid. It must be less than 15 characters in length"			
			}
			If($isValidUser -And ($adminusername -ceq $guestcred)) {
				$isValidUser = $false
				Write-Warning "$inputName must be other than $guestcred."
			}			
			$adminusername = $adminusername + ''	

			Foreach ($user in $userlist) {
				$userName = $user.Split("[")[0].Trim()
				if ($isValidUser -And ($userName -ceq $adminusername)) {
					$isValidUser = $false
					Write-Warning "Provided $inputName already exists!!"
					break;
				}
			}	
		} while(!$isValidUser)
		
		# prompt new user password
		do {
			$isValidPwd = $true
			
			$inputName = 'RabbitMQ Password'
			$adminpassword = Write-Prompt "Please provide $inputName (e.g. *****)" "$inputName" $true
			$adminpasswordConfirm = Write-Prompt "Please confirm $inputName (e.g. *****)" "$inputName" $true $true
			if ($adminpassword -ne $adminpasswordConfirm) {
				Write-Warning "RabbitMQ Confirm Password did not match with $inputName. Please try again."
				$isValidPwd = $false
			}
			
		} while (!$isValidPwd)
		
		# show progress
		Write-InstallProgress $nameAddUser $percentComplete "1 minute"

		# start installation
		$isInstallStarted = $true

		# Add & Configure user to RabbitMQ
		Install-Software 'New Admin User' $installerControlPath "add_user $adminusername $adminpassword" $logFilePath $true $true
		Start-Sleep 5
		Install-Software 'Tags administrator' $installerControlPath "set_user_tags $adminusername administrator" $logFilePath $true $true
		Start-Sleep 5
		Install-Software 'New Admin Permissions' $installerControlPath "set_permissions -p / $adminusername `".*`" `".*`" `".*`"" $logFilePath $true $true
		Start-Sleep 5
		if ($isguestpresent){
			Install-Software 'Delete guest user' $installerControlPath "delete_user $guestcred" $logFilePath $true $true
			Start-Sleep 5
		}
		
		invoke-expression -Command 'Pop-Location'
		Write-Success "RabbitMQ user $adminusername added successfully"
			
		# Configure user to Predix
		$name = "Config RabbitMQ Credentials"
		$installerPath = "python"
		$installerConfigRabbitMQ="rabbitmq-update-config.py"
		$eventspath = $ID_DSP_HOME + "\dsp\config\com.ge.hcit.id.events.conf"
		$cryptoconfpath = $installPathWFM +"\conf\cryptoApp.conf"
		$adminuserkey_predix = '"id.messaging.broker.ConnectionUserName="'
		$adminpwdkey_predix = '"id.messaging.broker.ConnectionPassword="'
		$adminpwdencryptkey_predix='"id.messaging.broker.ConnectionPassword.encrypted="'
		$adminuserkey_crypto = '"rabbitmq.username ="'
		$adminpwdkey_crypto='"rabbitmq.password ="'
		$adminpwdkeyencrypt_crypto='"rabbitmq.password.encrypted ="'
		$empty_val = '""'
		
		# backup Predix eventspath
		$backupeventspath = $installPathWFM + '\conf\ConfBackups\com.ge.hcit.id.events_' + (Get-Date -format MMddyyyyHHmmss) + '.conf'
		Copy-File "$eventspath" "$backupeventspath"
		
		# backup WFM cryptoconfpath	
		$backupcryptoconfpath = $installPathWFM + '\conf\ConfBackups\cryptoApp_' + (Get-Date -format MMddyyyyHHmmss) + '.conf'
		Copy-File "$cryptoconfpath" "$backupcryptoconfpath"

		# proceed to installation
		$isPredixConfUpdateStarted = $true
		
		# configure predix RabbitMQ Admin user and password
		Install-Software $name $installerPath "$installerConfigRabbitMQ $eventspath $adminuserkey_predix $adminusername" $null $true $true
		Install-Software $name $installerPath "$installerConfigRabbitMQ $eventspath $adminpwdkey_predix $adminpassword" $null $true	$true
		Install-Software $name $installerPath "$installerConfigRabbitMQ $eventspath $adminpwdencryptkey_predix $empty_val" $null $true $true		

		$isPlayConfUpdateStarted = $true
		Install-Software $name $installerPath "$installerConfigRabbitMQ `"$cryptoconfpath`" $adminuserkey_crypto $adminusername" $null $true $true
		Install-Software $name $installerPath "$installerConfigRabbitMQ `"$cryptoconfpath`" $adminpwdkey_crypto $adminpassword" $null $true $true
		Install-Software $name $installerPath "$installerConfigRabbitMQ `"$cryptoconfpath`" $adminpwdkeyencrypt_crypto $empty_val" $null $true $true
		Write-Success "RabbitMQ user $adminusername configured successfully"

		invoke-expression -Command 'Pop-Location'
	}
	
} catch {
	
	invoke-expression -Command 'Pop-Location'
	
	Write-Warning "Rolling back $name installation due to error in $name installation."

	if ($isInstallStarted) {
		# revert backup
		invoke-expression -Command 'Push-Location "$installerSbinPath"'
		Install-Software $name $installerControlPath "add_user $guestcred $guestcred" $false $true $true
		Start-Sleep 5
		Install-Software $name $installerControlPath "set_user_tags $guestcred administrator" $false $true $true
		Start-Sleep 5
		Install-Software $name $installerControlPath "set_permissions -p / $guestcred `".*`" `".*`" `".*`"" $false $true $true
		Start-Sleep 5
		Install-Software $name $installerControlPath "delete_user $adminusername" $false $true $true		
	}
	
	if ($isPredixConfUpdateStarted) {
		# revert backup
		Copy-File "$backupeventspath" "$eventspath"
		# remove backup
		Remove-File "$backupeventspath"
		if ($isPlayConfUpdateStarted) {
			# revert backup
			Copy-File "$backupcryptoconfpath" "$cryptoconfpath"
			# remove backup
			Remove-File "$backupcryptoconfpath"
		}
	}
	
	if ($config) {
		Write-ErrorAsString $error[0]
	} else {
		throw
	}
	
} finally {
	invoke-expression -Command 'Pop-Location'
	Write-InstallProgress $nameAddUser 100
	if ($config) {
		Reset-Config
	}
}
