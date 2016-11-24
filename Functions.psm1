# -------------------------------------------------------------------------------------
# PUBLIC METHODS
# -------------------------------------------------------------------------------------

# installer configuration
function New-Config ($debug) {
	# set preferences
	$Global:ErrorActionPreference = "Stop"
	if ($debug) {
		$Global:DebugPreference = "Continue"
	}
	$($host.PrivateData).DebugForegroundColor = "Cyan"

	# check if PowerShell is running in Administrator mode
	Confirm-AdminMode

	# set current script directory location
	New-Variable -Name scriptRoot -Value $(Get-Location) -Scope Global -Force
	
	# import properties from config file
	Import-Config '..\config\install.config'

	# create log path directory
	New-Variable -Name logPath -Value ..\logs -Scope Global -Force
	New-Item -ItemType Directory -Path $logPath -Force | Out-Null

	# create log file
	$time = Get-Date -format yyyyMMddHHmmss

	Start-Transcript -path $logPath\install.$time.log -noclobber

	# validate install path configured into config file
	Test-InstallDir
}

# check if OS is Windows Server 2012 R2
function Confirm-OSWin2012R2 {
	if ((Get-WmiObject -class Win32_OperatingSystem).Caption -match "Microsoft Windows Server 2012 R2") {
		$true
	}
	$false
}

# check if install should be skipped
function Skip-Install ($name, $version, $bit) {
	$skipInstall = $false
	
	# search registry for software entry
	$objInstalled = Search-Registry $name
	if ($objInstalled) {
		Write-Host "Found $($objInstalled.bit) bit $($objInstalled.name) of version $($objInstalled.version)"
		# check if same version of software installed
		if (($ObjInstalled.version -eq $version) -And ($ObjInstalled.bit -eq $bit)) {
			Write-Warning "Skipping $name installation as same version of software found."
		} else {
			Write-Warning "Skipping $name installation as other version of software found. Please uninstall software and rerun the script."
		}
		$skipInstall = $true
	}
	
	$skipInstall
}

# check if install should be skipped due to same software is installed
function Skip-InstallSameSW ($name, $version, $bit) {
	$skipInstall = $false
	
	# search registry for software entry
	$objInstalled = Search-Registry $name
	if ($objInstalled) {
		Write-Host "Found $($objInstalled.bit) bit $($objInstalled.name) of version $($objInstalled.version)"
		# check if same version of software installed
		if (($ObjInstalled.version -eq $version) -And ($ObjInstalled.bit -eq $bit)) {
			Write-Warning "Skipping $name installation as same version of software found."
			$skipInstall = $true
		}
	}
	
	$skipInstall
}

# get file name using open file dialog
function Get-FileName($initialDirectory, $title) {
	Add-Type -AssemblyName System.Windows.Forms
	$fDialog = New-Object System.Windows.Forms.OpenFileDialog
	$fDialog.initialDirectory = $initialDirectory
	if ($title) {
		$fDialog.title = "Please select certificate file"
	}
	$fDialog.filter = "PFX (*.pfx)|*.pfx"
	$fDialog.ShowHelp = $true
	$fDialog.ShowDialog() | Out-Null
	$fDialog.filename
}

# copy file if exist
function Copy-File ($fileSrc, $fileDest) {
	if (Test-Path $fileSrc) {
		Copy-Item $fileSrc $fileDest -force
	}	
}

# remove file if exist
function Remove-File ($filePath) {
	if (Test-Path $filePath) {
		Remove-Item $filePath -force
	}	
}

# find Erlang install path
function Find-ErlangInstallPath {
	$erlangInstallPath = $null
	
	# search registry for software entry
	$objInstalled = Search-Registry "Erlang"
	if ($objInstalled) {
		Write-Debug "Found $($objInstalled.bit) bit $($objInstalled.name) of version $($objInstalled.version)"
		Write-Debug "Found uninstall string :: $($ObjInstalled.uninstallString)"
		$positionStringUninstall = ($objInstalled.uninstallString).IndexOf("\Uninstall.exe")
		$erlangInstallPath = ($objInstalled.uninstallString).Substring(0, $positionStringUninstall)
	}
	
	$erlangInstallPath 
}

# find RabbitMQ sbin path
function Find-RabbitMQSbinPath {
	$rabbitmqSbinPath = $null
	
	# search registry for software entry
	$objInstalled = Search-Registry "RabbitMQ"
	if ($objInstalled) {
		Write-Debug "Found $($objInstalled.bit) bit $($objInstalled.name) of version $($objInstalled.version)"
		Write-Debug "Found uninstall string :: $($ObjInstalled.uninstallString)"
		$positionStringUninstall = ($objInstalled.uninstallString).IndexOf("uninstall.exe")
		$rabbitmqSbinPath = ($objInstalled.uninstallString).Substring(0, $positionStringUninstall) + "rabbitmq_server-" + $objInstalled.version + "\sbin"
	}
	
	$rabbitmqSbinPath 
}

# install software using msi/exe
function Install-Software ($name, $filePath, $argumentList, $logFilePath, $skipSuccessMsg, $noNewWindow) {
	if ($logFilePath) {
		$setup = Start-Process -FilePath $filePath -ArgumentList $argumentList -NoNewWindow -Wait -Passthru -RedirectStandardOutput $logFilePath
	} else {
		if ($noNewWindow) {
			$setup = Start-Process -FilePath $filePath -ArgumentList $argumentList -NoNewWindow -Wait -Passthru
		} else {
			$setup = Start-Process -FilePath $filePath -ArgumentList $argumentList -Wait -Passthru
		}
	}
	if ($setup.ExitCode -eq 0) {
		if (!$skipSuccessMsg) {
			Write-Success "$name installed successfully"		
		}
	} else {
		Write-Error "$name installation failed" 			
	}
}

# uninstall software using msi/exe
function Uninstall-Software ($name, $filePath, $argumentList, $skipSuccessMsg) {
	$setup = Start-Process -FilePath $filePath -ArgumentList $argumentList -Wait -Passthru
	if ($setup.ExitCode -eq 0) {
		if (!$skipSuccessMsg) {
			Write-Success "$name uninstalled successfully"		
		}
	} else {
		Write-Error "$name uninstallation failed" 			
	}
}

# write error message
# used for logging as Write-Error throws Exception and stops execution when ErrorActionPreference set to True
function Write-ErrorAsString ($err) {
	Write-Host "ERROR:" ($err | Out-String) -ForegroundColor Red -BackgroundColor Black -NoNewline
}

# set console color for success message
function Write-Success ($msg) {
	Write-Host $msg -ForegroundColor Green -BackgroundColor Black
}

# show progress
function Write-InstallProgress ($currentOperationComponent, $percentComplete, $approxOperationTime, $currentOperationActivity, $skipMessage) {
	if (!$currentOperationActivity) {
		$currentOperationActivity = 'Installing'
	}
	$activity = $currentOperationActivity + ' Workflow Manager (' + $percentComplete + '% completed)'
	$currentOperation = $currentOperationActivity + ' ' + $currentOperationComponent + ' (started at ' + (Get-Date).ToLongTimeString() + ') ...'
	$status = 'Please wait ...'
	if ($approxOperationTime) {
		$status = $status + ' ' + $currentOperationActivity + ' ' + $currentOperationComponent + ' may take up to ' + $approxOperationTime + ' ...'
	}
	if ($percentComplete -eq 100) {
		Write-Progress -Activity $activity -Status 'Completed' -Completed
	} else {
		if (!$skipMessage) {
			Write-Host "$currentOperation"
		}
		#Write-Progress -Activity $activity -Status $status -CurrentOperation $currentOperation -PercentComplete $percentComplete
		Write-Progress -Activity $activity -Status $status -CurrentOperation $currentOperation
	}
}

# Read-Host with validation
function Write-Prompt ($msg, $inputName, $secure, $skipValidation, $minChars, $minIntValue) {
	do {
		$isValidInput = $true
		Write-Host $msg":" -ForegroundColor Magenta -BackgroundColor Black -NoNewline
		
		if ($secure) {
			$inputEncrypted = Read-Host -AsSecureString
			$input = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($inputEncrypted))
		} else {
			$input = Read-Host
		}
		
		if(!$skipValidation -And !$minIntValue -And ((($input).trim() -eq [string]::empty) -Or ($input -match '\s+'))) {
			$isValidInput = $false
			Write-Warning "$inputName is invalid. It must not contain SPACE or TAB. Please try again."
		}
		
		if (!$skipValidation -And $isValidInput -And $minChars -And ($input.Length -lt $minChars)) {
			$isValidInput = $false
			Write-Warning "$inputName is invalid. It must be atleast $minChars characters."
		}
		
		if (!$skipValidation -And $isValidInput -And $minIntValue) {
			$inputNum = ""
			if(![int32]::TryParse($input,[ref]$inputNum)) {
				$isValidInput = $false
				Write-Warning "$inputName is invalid. It must be numeric."
			} elseIf ($inputNum -lt $minIntValue) {
				$isValidInput = $false
				Write-Warning "$inputName is invalid. Value must be atleast $minIntValue."
			}
		}
		
	} while (!$isValidInput)
	$input
}

# stop service
function Stop-ServiceIfExist ($serviceName) {
	if ((Get-Service | Where-Object {$_.Name -eq $serviceName}).Name -eq $serviceName) {
		if ((Get-Service -Name $ServiceName).Status -eq "Running") {
			Stop-Service $ServiceName | Out-Null
			Write-Success "$ServiceName service stopped successfully"
		} else {
			Write-Warning "Skipping stopping $ServiceName service as it is already stopped."
		}
	} else {
		Write-Warning "$ServiceName service not found"
	}
}

# remove service if exist
function Remove-Service ($serviceName) {
	if ((Get-Service | Where-Object {$_.Name -eq $serviceName}).Name -eq $serviceName) {
		if ((Get-Service -Name $ServiceName).Status -eq "Running") {
			Write-Debug "$ServiceName service is in running state"
			Stop-Service $ServiceName | Out-Null
			Write-Debug "$ServiceName service stopped successfully"
		}
		$service = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
		$service.delete() | Out-Null
		Write-Debug "$ServiceName service deleted successfully"
	}
}

# uninstall predix
function Uninstall-Predix ($serviceName, $installPath) {
	Remove-Service $serviceName
	if (Test-Path $installPath) {
		Remove-Item $installPath -Recurse -Force
	}
	if([environment]::GetEnvironmentVariable("ID_DSP_HOME","Machine")) {
		[Environment]::SetEnvironmentVariable("ID_DSP_HOME", $null, "Machine")
	}
	if ($env:ID_DSP_HOME) {
		Remove-Item Env:\ID_DSP_HOME
	}
}

# reset installer configuration
function Reset-Config {
	# stop transcribing if started
	Stop-Transcribing
	
	# reset preference to default
	$Global:ErrorActionPreference = "Continue"
	$Global:DebugPreference = "SilentlyContinue"
	$($host.PrivateData).DebugForegroundColor = "Yellow"

	# reset global variables to default
	$Global:cpacsIp = $null
	$Global:cpacsNgiPwd = $null
	$Global:custStorePwd = $null
}

# -------------------------------------------------------------------------------------
# PRIVATE METHODS
# -------------------------------------------------------------------------------------

# check if PowerShell is running in Administrator mode
function Confirm-AdminMode {
	if (!([bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544"))) {
		Write-Error "The current Windows PowerShell session is not running as Administrator. Start Windows PowerShell by using the Run as Administrator option, and then try running the script again."
	}
}

# convert configuration properties into variables
# skipping empty lines and commented lines
function Import-Config ($filePath) {
	Get-Content $filePath | Foreach-Object{
	    $var = $_.Split('=')
		if ($var -And ($var[0].StartsWith("#") -ne $True))  {
			New-Variable -Name $var[0] -Value $var[1] -Scope Global -Force
		}
	}
}

# test if install path is valid and doesn't contain SPACE or any other special characters
function Test-InstallDir {
	$regexInstallDir = "^[a-zA-Z]:\\[a-zA-Z0-9\\]*$"
	if(!$installDir) {
		Write-Error "Please configure valid install path into config file and rerun the installer."
	}
	if (!(($installDir -match $regexInstallDir) -And (Test-Path $installDir -isValid))) {
		Write-Error "Install path is not valid. It must not contain SPACE or any other special character. Please configure valid install path into config file and rerun the installer."
	}
}

# search registry to check if software is already installed
function Search-Registry ($name) {
	$objInstalled = $null
	$install = $null
	$bit = 64
	$registryUninstall64BitPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"

	# search in 64 bit uninstall directory within registry
	$install = Get-ItemProperty $registryUninstall64BitPath | select DisplayName, DisplayVersion, UninstallString | Where-Object {$_.DisplayName -like "$name*"}
	
	# take first installation if more than one 64-bit installation found as Java allows multiple installation of different version
	if ($install -And ($install.length -gt 1)) {
		$install = $install[0]
	}
	
	if (!($install.DisplayName)) {
		# search in 32 bit uninstall directory within registry
		$bit = 32
		# search in 32 bit uninstall directory within registry		
		if (Confirm-OSWin2012R2) {
			$registryUninstall32BitPath = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
			$install = Get-ItemProperty $registryUninstall32BitPath | select DisplayName, DisplayVersion, UninstallString | Where-Object {$_.DisplayName -like "$name*"}
		} else {
			$install = Search-RegistryBit32NonWin2012R2 $name
		}
	}
	
	if ($install.DisplayName) {
		# Erlang do not have separate version entry in registry so set version from name
		if ($name -eq "Erlang") {
			$position = ($install.DisplayName).IndexOf("(") + 1
			$length = ($install.DisplayName).IndexOf(")") - $position
			$install.DisplayVersion = ($install.DisplayName).Substring($position, $length)
		}
		$objInstalled = [PSCustomObject]@{
			name = $install.DisplayName
			version = $install.DisplayVersion
			uninstallString = $install.UninstallString
			bit = $bit
		}
	}
	
	$objInstalled
}

# search 32 bit registry for Windows7 to check if software is already installed
function Search-RegistryBit32NonWin2012R2 ($name) {
	# for Windows7, 32 bit registry access not allowed by * from 64 bit PowerShell
	$registryUninstall32BitPath = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\"
	$registryUninstal32BitSWPath = $registryUninstall32BitPath + $name
	if ($name -eq "Erlang") {
		# check if Erlang 5.7.4 is installed
		$registryUninstal32BitSWPath = $registryUninstall32BitPath + 'Erlang OTP R13B03 (5.7.4)'
		$install = Search-Registry32Bit $name $registryUninstal32BitSWPath
		# check if Erlang 5.10.4 is installed
		if (!($install.DisplayName)) {
			$registryUninstal32BitSWPath = $registryUninstall32BitPath + 'Erlang OTP R16B03 (5.10.4)'
			$install = Search-Registry32Bit $name $registryUninstal32BitSWPath
		}
		# check if Erlang 18.3 is installed
		if (!($install.DisplayName)) {
			$registryUninstal32BitSWPath = $registryUninstall32BitPath + 'Erlang OTP 18 (7.3)'
			$install = Search-Registry32Bit $name $registryUninstal32BitSWPath
		}
		# check if Erlang 19.0 is installed
		if (!($install.DisplayName)) {
			$registryUninstal32BitSWPath = $registryUninstall32BitPath + 'Erlang OTP 19 (8.0)'
			$install = Search-Registry32Bit $name $registryUninstal32BitSWPath
		}
	} elseif ($name -eq $nameWFM) {
		$registryUninstal32BitSWPath = $keyWFM
		$install = $null
		if (Test-Path $registryUninstal32BitSWPath) {
			$install = Get-ItemProperty $registryUninstal32BitSWPath | select CurrentVersion, InstallPath, DisplayName, DisplayVersion, UninstallString
		}
		if (!($install.CurrentVersion)) {
			$install = $null
		} else {
			$install.DisplayName = $name
			$position = ($install.CurrentVersion).LastIndexOf(".")
			$install.DisplayVersion = ($install.CurrentVersion).Substring(0, $position)
		}
	
	} else {
		$registryUninstall32BitPath = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\"
		$registryUninstal32BitSWPath = $registryUninstall32BitPath + $name
		$install = Search-Registry32Bit $name $registryUninstal32BitSWPath
	}
	
	$install
}

# search registry to check if 32 bit software is already installed for 64 bit Windows-7
function Search-Registry32Bit ($name, $registryUninstall32BitPath) {
	$install = $null
	if (Test-Path $registryUninstall32BitPath) {
		$install = Get-ItemProperty $registryUninstall32BitPath | select DisplayName, DisplayVersion, UninstallString | Where-Object {$_.DisplayName -like "$name*"}
	}
	$install
}

# test if transcribing started
function Test-Transcribing {
	$externalHost = $host.gettype().getproperty("ExternalHost", [reflection.bindingflags]"NonPublic,Instance").getvalue($host, @())
	try {
		$externalHost.gettype().getproperty("IsTranscribing", [reflection.bindingflags]"NonPublic,Instance").getvalue($externalHost, @())
	} catch {
        # this host does not support transcription
		# do nothing as same error thrown already while starting transcription
    }
}

# stop transcribing if started
function Stop-Transcribing {
	if(Test-Transcribing) {
		Stop-Transcript
	}
}
