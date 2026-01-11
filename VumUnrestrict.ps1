# Copyright (c) 2025 Broadcom. All Rights Reserved.
# Broadcom Confidential. The term "Broadcom" refers to Broadcom Inc.
# and/or its subsidiaries.
#
# =============================================================================
#
# SOFTWARE LICENSE AGREEMENT
#
#
# Copyright (c) CA, Inc. All rights reserved.
#
#
# You are hereby granted a non-exclusive, worldwide, royalty-free license
# under CA, Inc.'s copyrights to use, copy, modify, and distribute this
# software in source code or binary form for use in connection with CA, Inc.
# products.
#
#
# This copyright notice shall be included in all copies or substantial
# portions of the software.
#
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.
#
# =============================================================================

<#
    .SYNOPSIS
    Temporarily unrestricts VMware Update Manager (VUM) services on vCenter instances in VMware Cloud Foundation environments or standalone vCenter deployments.

    .DESCRIPTION
    The VumUnrestrict.ps1 script provides a streamlined workflow to temporarily enable VUM operations on
    vCenter Server instances within VMware Cloud Foundation (VCF) deployments or standalone vCenter instances.
    This script is intended to be used to enable heterogeneous hardware clusters to be upgraded to ESX 9.x
    before being transitioned to vLCM baselines.

    The script supports two deployment modes:
    1. VCF Mode: Connects to SDDC Manager and automatically discovers all workload domain vCenter instances.
    2. vCenter Mode: Connects directly to a single vCenter Server instance without requiring SDDC Manager.

    The script performs the following operations:
    1. Determines deployment mode (VCF or vCenter) via parameter or interactive prompt.
    2. Connects to SDDC Manager (VCF mode) or directly to vCenter (vCenter mode) using interactive credential prompts.
    3. Automatically retrieves and connects to all workload domain vCenter instances (VCF mode) or connects to the specified vCenter (vCenter mode).
    4. Validates vCenter version compatibility (vCenter 9.0 or later required).
    5. Executes VUM unrestrict tasks on compatible vCenter instances.
    6. Provides detailed status reporting in both console and log formats.
    7. Automatically disconnects from all connections upon completion.

    Key Features:
    - Interactive credential collection with secure password handling.
    - Support for both VCF deployments and standalone vCenter instances.
    - Support for both management and isolated SSO domains (VCF mode).
    - Comprehensive error handling and logging.
    - JSON-formatted results logging for automation integration.
    - Version compatibility checking and validation.
    - Progress indication during long-running operations.
    - Command-line mode selection to bypass interactive prompts.

    Important Notes:
    - VUM services will be automatically re-restricted after a vCenter LCM service restart.
    - The script requires VCF.PowerCLI 9.0 or later (VCF mode) or VMware.PowerCLI (vCenter mode).
    - PowerShell 7.2 or later is required.
    - The SDDC Manager user must have ADMIN role permissions (VCF mode only).
    - PowerCLI must be configured for multiple server connections.

    .PARAMETER LogLevel
    Specifies the logging verbosity level. Valid values are:
    - DEBUG: Detailed diagnostic information for troubleshooting.
    - INFO: General informational messages (default).
    - ADVISORY: Advisory messages for important notices.
    - WARNING: Warning messages for potential issues.
    - EXCEPTION: Exception details.
    - ERROR: Error messages only.

    Default value: INFO

    .PARAMETER Mode
    Specifies the deployment mode. Valid values are:
    - VCF: Connect via SDDC Manager and discover all workload domain vCenter instances (default behavior).
    - vCenter: Connect directly to a single vCenter Server instance without SDDC Manager.

    If not specified, the script will prompt the user interactively to select the deployment mode.

    .PARAMETER version
    Displays the script version information and exits.

    .EXAMPLE
    ./VumUnrestrict.ps1

    Runs the script with default INFO logging level. Prompts for deployment mode selection, then prompts for
    SDDC Manager credentials (VCF mode) or vCenter credentials (vCenter mode), connects to vCenter instances,
    unrestricts VUM services, and displays a summary table.

    .EXAMPLE
    ./VumUnrestrict.ps1 -Mode VCF

    Runs the script in VCF mode, bypassing the deployment mode prompt. Connects to SDDC Manager and all
    workload domain vCenter instances.

    .EXAMPLE
    ./VumUnrestrict.ps1 -Mode vCenter

    Runs the script in vCenter mode, bypassing the deployment mode prompt. Connects directly to a single
    vCenter Server instance.

    .EXAMPLE
    ./VumUnrestrict.ps1 -LogLevel DEBUG

    Runs the script with verbose DEBUG logging enabled, useful for troubleshooting connection
    or execution issues.

    .EXAMPLE
    ./VumUnrestrict.ps1 -version

    Displays the script version information and exits without performing any operations.

    .INPUTS
    None. The script prompts interactively for all required connection details.

    .OUTPUTS
    The script produces the following outputs:
    - Console: Color-coded status messages and a summary table of vCenter capabilities
    - Log File: Detailed execution log in logs/VumUnrestrict-YYYY-MM-DD.log format
    - JSON Data: Structured vCenter capability data in log file for automation

    .NOTES
    File Name      : VumUnrestrict.ps1
    Author         : Broadcom
    Prerequisite   : VCF.PowerCLI 9.0 or later, PowerShell 7.2 or later
    Version        : 1.0.0.2
    Last Modified  : 2026-01-08

    .LINK
    https://github.com/vmware/powershell-script-for-vmware-cloud-foundation-vum-unrestrict

    .LINK
    https://www.powershellgallery.com/packages/VCF.PowerCLI
#>
#
Param (
    [Parameter (Mandatory = $false)] [ValidateSet("DEBUG", "INFO", "ADVISORY", "WARNING", "EXCEPTION", "ERROR")] [String]$LogLevel = "INFO",
    [Parameter (Mandatory = $false)] [ValidateSet("VCF", "vCenter")] [String]$Mode,
    [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$Version
)
# Initialize exit codes early so they're available to all functions.
$Script:ExitCodes = @{
    SUCCESS              = 0
    GENERAL_ERROR        = 1
    PARAMETER_ERROR      = 2
    CONNECTION_ERROR     = 3
    AUTHENTICATION_ERROR = 4
    RESOURCE_NOT_FOUND   = 5
    OPERATION_FAILED     = 6
    TASK_FAILED          = 7
    CONFIGURATION_ERROR  = 8
    PRECONDITION_ERROR   = 9
    USER_CANCELLED       = 10
    VERSION_ERROR        = 11
}

# Initialize log level hierarchy for log filtering.
$Script:logLevelHierarchy = @{
    "DEBUG"     = 0
    "INFO"      = 1
    "ADVISORY"  = 2
    "WARNING"   = 3
    "EXCEPTION" = 4
    "ERROR"     = 5
}

# Set configured log level from parameter (normalize to uppercase).
$Script:configuredLogLevel = $LogLevel.ToUpper()
$Script:logOnly = "disabled"

Function Exit-WithCode {
    <#
        .SYNOPSIS
        Exits the script with a standardized exit code and optional final message.

        .DESCRIPTION
        This function provides a centralized exit point that ensures consistent exit code usage
        and clear logging before script termination. Success messages (exit code 0) are logged
        as INFO, while error messages (non-zero codes) are logged as ERROR.

        .PARAMETER ExitCode
        The exit code to return to the shell. Use values from $Script:ExitCodes hashtable
        for consistency:
        - SUCCESS = 0
        - GENERAL_ERROR = 1
        - PARAMETER_ERROR = 2
        - CONNECTION_ERROR = 3
        - AUTHENTICATION_ERROR = 4
        - RESOURCE_NOT_FOUND = 5
        - OPERATION_FAILED = 6
        - TASK_FAILED = 7
        - CONFIGURATION_ERROR = 8
        - PRECONDITION_ERROR = 9
        - USER_CANCELLED = 10

        .PARAMETER Message
        Optional final message to log before exiting.

        .EXAMPLE
        Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR -Message "Invalid parameters provided"
        Logs an ERROR message and exits with code 2.

        .EXAMPLE
        Exit-WithCode -ExitCode $Script:ExitCodes.SUCCESS -Message "Operation completed successfully"
        Logs an INFO message and exits with code 0.

        .OUTPUTS
        None. This function terminates script execution.
    #>

    Param(
        [Parameter(Mandatory = $true)] [ValidateNotNull()] [Int]$ExitCode,
        [Parameter(Mandatory = $false)] [AllowEmptyString()] [String]$Message
    )

    if ($Message) {
        switch ($ExitCode) {
            0 {
                Write-LogMessage -Type INFO -Message $Message
            }
            Default {
                Write-LogMessage -Type ERROR -Message $Message
            }
        }
    }

    Write-LogMessage -Type DEBUG -Message "Script exiting with code $ExitCode"
    exit $ExitCode
}
Function Test-LogLevel {
    <#
        .SYNOPSIS
        Determines if a message should be displayed based on the configured log level.

        .DESCRIPTION
        Compares the message type against the configured log level threshold to determine
        if the message should be displayed on screen. All messages are always written to
        the log file regardless of level.

        The log level hierarchy from lowest to highest is:
        DEBUG < INFO < ADVISORY < WARNING < EXCEPTION < ERROR

        .PARAMETER ConfiguredLevel
        The configured log level threshold for the script.

        .PARAMETER MessageType
        The type/severity of the message being evaluated.

        .OUTPUTS
        System.Boolean
        Returns $true if the message should be displayed, $false otherwise.

        .EXAMPLE
        Test-LogLevel -ConfiguredLevel "INFO" -MessageType "WARNING"
        Returns $true because WARNING is higher than INFO in the hierarchy.

        .EXAMPLE
        Test-LogLevel -ConfiguredLevel "WARNING" -MessageType "DEBUG"
        Returns $false because DEBUG is lower than WARNING in the hierarchy.
    #>
    Param(
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ConfiguredLevel,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$MessageType
    )

    $messageLevel = $Script:logLevelHierarchy[$MessageType]
    $configuredLevelValue = $Script:logLevelHierarchy[$ConfiguredLevel]

    return ($messageLevel -ge $configuredLevelValue)
}
Function Write-LogMessage {
    <#
        .SYNOPSIS
        Writes a severity-based color-coded message to the console and/or log file.

        .DESCRIPTION
        The Write-LogMessage function provides centralized logging functionality with support for
        different message types (INFO, ERROR, WARNING, EXCEPTION, ADVISORY, DEBUG). Messages are displayed
        on the console with color coding based on severity and written to a log file with timestamps.

        .PARAMETER Message
        The message content to be logged and/or displayed.

        .PARAMETER Type
        The severity level of the message. Valid values are:
        DEBUG, INFO, ADVISORY, WARNING, EXCEPTION, ERROR. Default is INFO.

        .PARAMETER SuppressOutputToScreen
        When specified, prevents the message from being displayed on the console.

        .PARAMETER SuppressOutputToFile
        When specified, prevents the message from being written to the log file.

        .PARAMETER PrependNewLine
        When specified, adds a blank line before displaying the message on the console.

        .PARAMETER AppendNewLine
        When specified, adds a blank line after displaying the message on the console.

        .EXAMPLE
        Write-LogMessage -Type INFO -Message "Operation completed successfully"
        Displays a green INFO message on console and writes to log file.

        .EXAMPLE
        Write-LogMessage -Type ERROR -Message "Connection failed" -PrependNewLine
        Displays a red ERROR message with a blank line before it.

        .EXAMPLE
        Write-LogMessage -Type DEBUG -Message "Variable value: $value" -SuppressOutputToScreen
        Writes message to log file only, not displayed on console.

        .OUTPUTS
        None. This function outputs to console and/or log file.
    #>

    Param(
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$AppendNewLine,
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [String]$Message,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$PrependNewLine,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$SuppressOutputToFile,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$SuppressOutputToScreen,
        [Parameter(Mandatory = $false)] [ValidateSet("ADVISORY", "DEBUG", "ERROR", "EXCEPTION", "INFO", "WARNING")] [String]$Type = "INFO"
    )

    # Define color mapping for different message types.
    $msgTypeToColor = @{
        "INFO"      = "Green";
        "ERROR"     = "Red" ;
        "WARNING"   = "Yellow" ;
        "ADVISORY"  = "Yellow" ;
        "EXCEPTION" = "Cyan";
        "DEBUG"     = "Gray"
    }

    # Get the appropriate color for the message type.
    $messageColor = $msgTypeToColor.$Type

    # Create timestamp for log file entries (MM-dd-yyyy_HH:mm:ss format).
    $timeStamp = Get-Date -Format "MM-dd-yyyy_HH:mm:ss"

    # Determine if message should be displayed based on log level threshold.
    $shouldDisplay = Test-LogLevel -MessageType $Type -ConfiguredLevel $Script:configuredLogLevel

    # Add blank line before message if requested and not in log-only mode and meets log level threshold.
    if ($PrependNewLine -and (-not ($Script:logOnly -eq "enabled")) -and $shouldDisplay) {
        Write-Host ""
    }

    # Display message to console with color coding (unless suppressed, in log-only mode, or below log level threshold).
    if (-not $SuppressOutputToScreen -and $Script:logOnly -ne "enabled" -and $shouldDisplay) {
        Write-Host -ForegroundColor $messageColor "[$Type] $Message"
    }

    # Add blank line after message if requested and not in log-only mode and meets log level threshold.
    if ($AppendNewLine -and (-not ($Script:logOnly -eq "enabled")) -and $shouldDisplay) {
        Write-Host ""
    }

    # Write message to log file (unless suppressed).
    if (-not $SuppressOutputToFile) {
        $logContent = '[' + $timeStamp + '] ' + '(' + $Type + ')' + ' ' + $Message
        try {
            Add-Content -ErrorVariable errorMessage -Path $Script:LogFile $logContent
        } catch {
            # Handle log file write failures gracefully.
            Write-Host "Failed to add content to log file $Script:LogFile."
            Write-Host $errorMessage
        }
    }
}
Function New-LogFile {
    <#
        .SYNOPSIS
        Creates a log file with automatic directory structure and environment logging.

        .DESCRIPTION
        The New-LogFile function establishes the logging infrastructure by creating a timestamped
        log file in a specified directory. The function creates one log file using the format
        yyyy-MM-dd, ensuring logs are organized chronologically. If the log directory doesn't exist,
        it will be created automatically. When a new log file is created, the function automatically
        calls Get-EnvironmentSetup to record system information for troubleshooting purposes.

        .PARAMETER Prefix
        Specifies the prefix for the log file name. Default value is "VumUnrestrict".

        .PARAMETER Directory
        Specifies the directory name where log files will be stored. Default value is "logs".

        .EXAMPLE
        New-LogFile
        Creates a log file with default settings: "logs/VumUnrestrict-2025-12-02.log"

        .EXAMPLE
        New-LogFile -Prefix "MyScript" -Directory "output"
        Creates a log file: "output/MyScript-2025-12-02.log"

        .OUTPUTS
        None. This function sets script-scoped variables $Script:logFolder and $Script:logFile.
    #>

    Param(
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Directory = "logs",
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Prefix = "VumUnrestrict"
    )

    # Generate timestamp for daily log file naming (yyyy-MM-dd format).
    $fileTimeStamp = Get-Date -Format "yyyy-MM-dd"

    # Set script-scoped variables for log directory and file paths.
    $Script:logFolder = Join-Path -Path $PSScriptRoot -ChildPath $Directory
    $Script:logFile = Join-Path -Path $Script:logFolder -ChildPath "$Prefix-$fileTimeStamp.log"

    # Create log directory if it doesn't exist.
    if (-not (Test-Path -Path $Script:logFolder -PathType Container) ) {
        Write-Information "LogFolder not found, creating $Script:logFolder" -InformationAction Continue
        New-Item -ItemType Directory -Path $Script:logFolder | Out-Null
        if (-not $?) {
            Write-Information "Failed to create directory $Script:logFile. Exiting." -InformationAction Continue
            Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR -Message "Failed to create log directory."
        }
    }

    # Create the log file if it doesn't exist for today.
    # When creating a new log file, automatically capture environment details for troubleshooting.
    if (-not (Test-Path $Script:logFile)) {
        New-Item -Type File -Path $Script:logFile | Out-Null
        Get-EnvironmentSetup
    }
}
Function Get-EnvironmentSetup {
    <#
        .SYNOPSIS
        Logs user environment details for troubleshooting purposes.

        .DESCRIPTION
        The Get-EnvironmentSetup function captures and logs comprehensive environment information
        including PowerShell version, PowerCLI versions (VCF.PowerCLI and VMware.PowerCLI), and
        operating system details. This information is automatically logged when a new log file is
        created and helps with troubleshooting and support scenarios.

        The function performs the following checks:
        - Validates PowerCLI installation and logs version information
        - Detects and logs PowerShell version
        - Identifies operating system with enhanced details for macOS and Windows
        - Logs script version information
        - Exits with error if PowerCLI is not installed

        .EXAMPLE
        Get-EnvironmentSetup
        Logs environment details to the current log file.

        .OUTPUTS
        None. This function outputs environment information to the log file only.
    #>

    Write-LogMessage -Type DEBUG -Message "Entered Get-EnvironmentSetup function..."

    # Get PowerShell version information.
    $powerShellRelease = $($PSVersionTable.PSVersion).ToString()

    # Check for installed PowerCLI modules (VCF and VMware versions).
    $vcfPowerCliRelease = (Get-Module -ListAvailable -Name VCF.PowerCLI -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1).Version
    $vmwarePowerCliRelease = (Get-Module -ListAvailable -Name VMware.PowerCLI -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1).Version

    # If the module is not installed, set the release to "N/A".
    if ($null -eq $vcfPowerCliRelease) {
        $vcfPowerCliRelease = "N/A"
    }
    if ($null -eq $vmwarePowerCliRelease) {
        $vmwarePowerCliRelease = "N/A"
    }

    # Start with basic OS information from PowerShell automatic variables.
    $operatingSystem = $($PSVersionTable.OS)

    # Enhanced macOS information - sw_vers provides more user-friendly OS details than Darwin kernel info.
    if ($IsMacOS) {
        try {
            $macOsName = (sw_vers --productName)
            $macOsRelease = (sw_vers --productVersion)
            $macOsVersion = "$macOsName $macOsRelease"
        } catch [Exception] {
            # If sw_vers fails, we'll fall back to the basic OS info from $PSVersionTable.
        }
    }
    if ($macOsVersion) {
        $operatingSystem = $macOsVersion
    }

    # Enhanced Windows information - Get-ComputerInfo provides more detailed OS information.
    if ($IsWindows) {
        try {
            $windowsProductInformation = (Get-ComputerInfo -ProgressAction SilentlyContinue) | Select-Object OSName, OSVersion
            $windowsVersion = "$($windowsProductInformation.OSName) $($windowsProductInformation.OSVersion)"
        } catch [Exception] {
            # If Get-ComputerInfo fails, we'll fall back to the basic OS info from $PSVersionTable.
        }
    }
    if ($windowsVersion) {
        $operatingSystem = $windowsVersion
    }

    Show-Version -Silence

    Write-LogMessage -Type DEBUG -Message "Client PowerShell version is $powerShellRelease"

    if ($vcfPowerCliRelease) {
        Write-LogMessage -Type DEBUG -Message "Client VCF.PowerCLI version is $vcfPowerCliRelease."
    }
    if ($vmwarePowerCliRelease) {
        Write-LogMessage -Type DEBUG -Message "Client VMware.PowerCLI version is $vmwarePowerCliRelease."
    }

    Write-LogMessage -Type DEBUG -Message "Client Operating System is $operatingSystem"
}
Function Show-Version {
    <#
        .SYNOPSIS
        Displays or logs the version of the script.

        .DESCRIPTION
        The Show-Version function displays or logs the current version of the script.
        When called without the -Silence parameter, it displays the version to the console.
        With -Silence, it only logs the version to the log file for audit purposes.

        .PARAMETER Silence
        When specified, suppresses console output and only logs the version to the log file.

        .EXAMPLE
        Show-Version
        Displays the script version to the console and logs it to the file.

        .EXAMPLE
        Show-Version -Silence
        Logs the script version to the file only without console output.

        .OUTPUTS
        None. This function outputs to console and/or log file.
    #>

    Param(
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$Silence
    )

    Write-LogMessage -Type DEBUG -Message "Entered Show-Version function..."

    if (-not $Silence) {
        Write-LogMessage -Type INFO -Message "Script Version: $scriptVersion"
    } else {
        Write-LogMessage -Type DEBUG -Message "Script Version: $scriptVersion"
    }
}
Function Get-Preconditions {
    <#
        .SYNOPSIS
        Validates that all script prerequisites are met before execution.

        .DESCRIPTION
        The Get-Preconditions function performs comprehensive validation of the environment
        to ensure all prerequisites are met for successful script execution. The function
        checks the following conditions:

        - PowerCLI Installation: Verifies VCF.PowerCLI 9.0 or later is installed
        - PowerCLI Configuration: Ensures DefaultVIServerMode is set to "Multiple"
        - PowerShell Version: Validates PowerShell 7.2 or later is installed
        - Operating System: On Windows, requires Windows Server 2016+ or Windows 10+

        The function will exit the script with an appropriate error code if any
        precondition is not met.

        .EXAMPLE
        Get-Preconditions
        Validates all prerequisites and continues if successful, exits if any check fails.

        .OUTPUTS
        None. This function exits the script if preconditions are not met.
    #>

    Write-LogMessage -Type DEBUG -Message "Entered Get-Preconditions function..."

    $vcfPowerCliVersion = (Get-Module -ListAvailable -Name "VCF.PowerCLI" -ErrorAction SilentlyContinue).Version
    $vmwarePowerCliVersion = (Get-Module -ListAvailable -Name "VMware.PowerCLI" -ErrorAction SilentlyContinue).Version

    # Validate PowerCLI module installation and version.
    switch ($true) {
        # Check for lack of VMware PowerCLI and VCF PowerCLI.
        { -not $vcfPowerCliVersion -and -not $vmwarePowerCliVersion } {
            Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR -Message "VMware VCF.PowerCLI was not found. Please install VCF.PowerCLI $minimumVcfPowerCliVersion or later."
        }
        # Check for presence of VMware PowerCLI without VCF PowerCLI.
        { $vmwarePowerCliVersion -and -not $vcfPowerCliVersion } {
            Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR -Message "VMware.PowerCLI version $vmwarePowerCliVersion discovered. This script requires VCF.PowerCLI $minimumVcfPowerCliVersion or later. Please uninstall VMware.PowerCLI and install VCF.PowerCLI $minimumVcfPowerCliVersion or later."
        }
        # Check for presence of both VMware PowerCLI and VCF PowerCLI.
        { $vmwarePowerCliVersion -and $vcfPowerCliVersion } {
            Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR -Message "VMware.PowerCLI version $vmwarePowerCliVersion discovered alongside VCF.PowerCLI version $vcfPowerCliVersion. Please remove VMware.PowerCLI before continuing as the two modules conflict."
        }
        # Check for presence of VCF PowerCLI without VMware PowerCLI.
        { $vcfPowerCliVersion -and -not $vmwarePowerCliVersion } {
            # Validate minimum VCF PowerCLI version.
            if ([version]$vcfPowerCliVersion -lt [version]$minimumVcfPowerCliVersion) {
                Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR -Message "VCF.PowerCLI version $vcfPowerCliVersion discovered. This script requires VCF.PowerCLI $minimumVcfPowerCliVersion or later. Please upgrade VCF.PowerCLI."
            }
        }
    }

    try {
        $response = Get-PowerCLIConfiguration | Where-Object -property DefaultVIServerMode -eq "Single"
    } catch [Exception] {
        switch -Wildcard ($_.Exception.Message) {
            "*is not recognized as a name of a cmdlet*" {
                Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR -Message "Cannot find Get-PowerCLIConfiguration. You may need to reinstall PowerCLI."
            }
            Default {
                Exit-WithCode -ExitCode $Script:ExitCodes.GENERAL_ERROR -Message "ERROR: $($_.Exception.Message)"
            }
        }
    }

    if ($response) {
        Write-LogMessage -Type EXCEPTION -Message "PowerCLI must be configured to connect to multiple vCenters simultaneously."
        Write-Host "Run: Set-PowerCLIConfiguration -DefaultVIServerMode Multiple"
        Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR -Message "PowerCLI must be configured to connect to multiple vCenters simultaneously."
    }

    $currentPSVersion = ($PSVersionTable.PSVersion.Major), ($PSVersionTable.PSVersion.Minor) -join "."

    if ($currentPSVersion -lt $psVersionMinVersion) {
        Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR -Message "PowerShell $psVersionMinVersion or higher is required."
    }

    # Windows 2012 and below do not support the default TLS ciphers required for recent
    # versions of PowerShell.
    if ($IsWindows) {
        if ([Environment]::OSVersion.Version.Major -lt 10) {
            Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR -Message "Windows Server 2016+ or Windows 10+ required."
        }
    }
}
Function Get-VcenterVersion {
    <#
        .SYNOPSIS
        Retrieves the major.minor version number of a vCenter Server instance.

        .DESCRIPTION
        The Get-VcenterVersion function extracts and returns the major.minor version
        (e.g., "8.0", "9.0") from a connected vCenter Server instance. The function
        queries the $Global:DefaultVIServers variable to obtain version information.

        When called with the -Silence parameter, the version is logged to the file only.
        Without the parameter, the version is returned to the caller.

        .PARAMETER Vcenter
        The fully qualified domain name (FQDN) of the vCenter Server instance.
        The vCenter must be connected via Connect-VIServer before calling this function.

        .PARAMETER Silence
        When specified, logs the vCenter version to the log file only and does not
        return a value. Without this parameter, returns the version string to the caller.

        .EXAMPLE
        Get-VcenterVersion -Vcenter "vcenter.example.com"
        Returns the version string (e.g., "9.0") for the specified vCenter.

        .EXAMPLE
        Get-VcenterVersion -Vcenter "vcenter.example.com" -Silence
        Logs the vCenter version to the log file without returning a value.

        .OUTPUTS
        System.String
        Returns the major.minor version string when -Silence is not specified.
        Returns nothing when -Silence is specified.
    #>

    Param(
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$Silence,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Vcenter
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-VcenterVersion function..."

    $vcenterVersionArray = ($Global:DefaultVIServers | Where-Object { $_.name -eq $Vcenter }).Version -split "\."
    $vcenterMajorMinorVersion = "$($vcenterVersionArray[0]).$($vcenterVersionArray[1])"

    if (-not $Silence) {
        return $vcenterMajorMinorVersion
    } else {
        Write-LogMessage -Type DEBUG -Message "vCenter `"$Vcenter`" runs version $vcenterMajorMinorVersion"
    }
}
Function New-ChoiceMenu {
    <#
        .SYNOPSIS
        Presents an interactive yes/no choice menu to the user with a configurable default.

        .DESCRIPTION
        The New-ChoiceMenu function creates a standardized interactive prompt that presents
        the user with a yes/no decision. The function uses PowerShell's built-in choice
        prompt functionality to provide a consistent user experience. The user can select
        options using Y/N keys or simply press Enter to accept the default choice.

        The function returns an integer value (0 for Yes, 1 for No) that can be used in
        conditional logic to determine the user's decision.

        .PARAMETER Question
        The question or prompt text to display to the user. This should be a clear,
        concise question that can be answered with yes or no.

        .PARAMETER DefaultAnswer
        The default answer that will be selected if the user presses Enter without
        making a selection. Valid values are "Yes" or "No" (case-sensitive).

        .OUTPUTS
        System.Int32
        Returns 0 if the user selects Yes, or 1 if the user selects No.

        .EXAMPLE
        $decision = New-ChoiceMenu -Question "Would you like to create the log folder?" -DefaultAnswer "Yes"
        if ($decision -eq 0) {
            Write-Host "User chose Yes"
        } else {
            Write-Host "User chose No"
        }

        .EXAMPLE
        $continue = New-ChoiceMenu -Question "Do you want to proceed with the operation?" -DefaultAnswer "No"
        Creates a prompt with "No" as the default, requiring explicit user confirmation.
    #>

    Param(
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$DefaultAnswer,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Question
    )

    Write-LogMessage -Type DEBUG -Message "Entered New-ChoiceMenu function..."

    # Create a collection to hold the choice options.
    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]

    # Add Yes and No options with keyboard shortcuts (&Y and &N).
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes', "Yes"))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No', "No"))

    # Set the default choice based on the DefaultAnswer parameter.
    # Index 0 = Yes, Index 1 = No.
    # Note: $title is intentionally $null as we use $Question for the prompt text.
    $title = $null
    if ($DefaultAnswer -eq "Yes") {
        $decision = $host.UI.PromptForChoice($title, $Question, $choices, 0)
    } else {
        $decision = $host.UI.PromptForChoice($title, $Question, $choices, 1)
    }

    return $decision
}
Function Get-InteractiveInput {
    <#
        .SYNOPSIS
        Prompts the user for input and returns the value.

        .DESCRIPTION
        The Get-InteractiveInput function provides a standardized way to prompt the user for input and return the value.
        This function is designed to be used for interactive input throughout the VCF PowerShell Toolbox.

        .PARAMETER PromptMessage
        The message to display to the user.

        .PARAMETER AsSecureString
        When specified, the function will prompt the user for input as a secure string.

        .OUTPUTS
        System.String
        Returns the user's input as a string.

        .EXAMPLE
        $username = Get-InteractiveInput -PromptMessage "Enter your username"
        Prompts the user for a username and returns the value.

        .EXAMPLE
        $password = Get-InteractiveInput -PromptMessage "Enter your password" -AsSecureString
        Prompts the user for a password with masked input and returns a SecureString.
    #>

    Param(
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$AsSecureString,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$PromptMessage
    )

    Write-LogMessage -Type DEBUG -Message "Entered Get-InteractiveInput function..."

    do {
        if ($AsSecureString) {
            $value = Read-Host $PromptMessage -AsSecureString
        } else {
            $value = Read-Host $PromptMessage
        }
    } while ($value -eq "")

    return $value
}
Function Write-ConnectionError {
    <#
        .SYNOPSIS
        Writes standardized, user-friendly connection error messages.

        .DESCRIPTION
        The Write-ConnectionError function analyzes connection error messages and provides
        user-friendly, actionable error messages based on the error pattern. The function
        uses regex pattern matching to identify common error scenarios and provides
        appropriate guidance for resolution.

        Supported error patterns include:
        - Authentication failures (IDENTITY_UNAUTHORIZED_ENTITY, incorrect username/password)
        - DNS resolution failures
        - Invalid server responses
        - SSL/TLS connection errors
        - Permission denied errors
        - Missing cmdlets or modules

        .PARAMETER ErrorMessage
        The error message or error object to analyze and display. Can be from $Error[0]
        or an ErrorVariable.

        .PARAMETER ConnectionType
        The type of system being connected to (e.g., "SDDC Manager", "vCenter Server").
        Used for contextual error messages.

        .PARAMETER ServerName
        The server name or FQDN that was being connected to when the error occurred.

        .PARAMETER UserName
        Optional. The username used for the connection attempt. Included in authentication
        error messages when provided.

        .EXAMPLE
        Write-ConnectionError -ErrorMessage $Error[0] -ConnectionType "SDDC Manager" -ServerName "sddc.example.com" -UserName "admin@vsphere.local"
        Analyzes the error and displays an appropriate user-friendly message.

        .EXAMPLE
        Write-ConnectionError -ErrorMessage $errorVar -ConnectionType "vCenter Server" -ServerName "vcenter.example.com"
        Displays connection error without username context.

        .OUTPUTS
        None. This function outputs error messages to the console and log file.
    #>

    Param(
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ConnectionType,
        [Parameter(Mandatory = $true)] [AllowEmptyString()] $ErrorMessage,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ServerName,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$UserName
    )

    Write-LogMessage -Type DEBUG -Message "Entered Write-ConnectionError function..."

    switch -Regex ($ErrorMessage) {
        "IDENTITY_UNAUTHORIZED_ENTITY" {
            if ($UserName) {
                Write-LogMessage -Type ERROR -Message "Failed to connect to $ConnectionType `"$ServerName`" using username `"$UserName`". Please check your credentials."
            } else {
                Write-LogMessage -Type ERROR -Message "Failed to connect to $ConnectionType `"$ServerName`". Authentication failed."
            }
        }
        "incorrect user name or password" {
            if ($UserName) {
                Write-LogMessage -Type ERROR -Message "Incorrect username or password entered for $ConnectionType `"$ServerName`"."
            } else {
                Write-LogMessage -Type ERROR -Message "Incorrect username or password entered for $ConnectionType `"$ServerName`"."
            }
        }
        "Invalid URI|hostname could not be parsed" {
            Write-LogMessage -Type ERROR -Message "Invalid $ConnectionType FQDN `"$ServerName`". Please check that the FQDN is correct and does not contain leading or trailing spaces."
        }
        "nodename nor servname provided, or not known" {
            Write-LogMessage -Type ERROR -Message "Cannot resolve $ConnectionType `"$ServerName`". If this is a valid $ConnectionType FQDN, please check your DNS settings."
        }
        "The requested URL <code>/v1/tokens</code> was not found on this Server" {
            Write-LogMessage -Type ERROR -Message "$ConnectionType `"$ServerName`" did not return a valid response. Please check that `"$ServerName`" is a valid $ConnectionType FQDN and if its services are healthy."
        }
        "The SSL connection could not be established\." {
            Write-LogMessage -Type ERROR -Message "SSL Connection error to $ConnectionType `"$ServerName`". Please check that $ConnectionType has a CA signed certificate or PowerShell trusts insecure certificates."
        }
        "Permission not found" {
            if ($UserName) {
                Write-LogMessage -Type ERROR -Message "Username `"$UserName`" does not have access to $ConnectionType."
            } else {
                Write-LogMessage -Type ERROR -Message "Insufficient permissions to access $ConnectionType `"$ServerName`"."
            }
        }
        "not recognized as a name of a cmdlet" {
            Write-LogMessage -Type ERROR -Message "Could not find required PowerCLI cmdlet. Your PowerCLI installation may be incomplete."
        }
        "but the module could not be loaded" {
            Write-LogMessage -Type ERROR -Message "Required PowerCLI module could not be loaded. Your PowerCLI environment may not be configured correctly. Please investigate before re-running this script."
        }
        Default {
            if ($ErrorMessage) {
                # Filter out cmdlet names and timestamps from error messages for cleaner output.
                $cleanErrorMessage = $ErrorMessage -replace '\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}:\d{2}:\d{2}\s+(AM|PM)\s+', '' -replace 'Connect-VcfSddcManagerServer\s*', '' -replace 'Connect-VIServer\s*', '' -replace '^\s+', '' -replace '\s+$', ''
                if ($cleanErrorMessage -and $cleanErrorMessage -ne $ErrorMessage) {
                    Write-LogMessage -Type ERROR -Message "Failed to connect to $ConnectionType `"$ServerName`": $cleanErrorMessage"
                } elseif ($cleanErrorMessage) {
                    Write-LogMessage -Type ERROR -Message "Failed to connect to $ConnectionType `"$ServerName`". Please check your connection details."
                } else {
                    Write-LogMessage -Type ERROR -Message "Failed to connect to $ConnectionType `"$ServerName`". Please check your connection details."
                }
            }
        }
    }
}
Function Disconnect-Vcenter {
    <#
        .SYNOPSIS
        Safely disconnects from vCenter instances with support for individual or bulk disconnection.

        .DESCRIPTION
        The Disconnect-Vcenter function provides a safe and reliable way to disconnect from
        vCenter instances. It includes comprehensive error handling to ensure that disconnection
        failures are properly logged and handled. The function supports both individual server
        disconnection and bulk disconnection from all active connections, making it flexible for
        various cleanup scenarios.

        .PARAMETER AllVcenters
        Optional switch parameter that disconnects from all active vCenter connections.
        When specified, the function terminates all active PowerCLI sessions. This is useful
        for cleanup scenarios where all connections should be terminated.

        .PARAMETER Vcenter
        Optional. The fully qualified domain name (FQDN) or IP address of a specific vCenter
        to disconnect from. This should match the server name used in the original connection.

        .PARAMETER Silence
        Optional switch parameter that suppresses console output for disconnection success messages.
        When specified, successful disconnections are logged without console output. Error messages
        are still displayed regardless of this parameter.

        .EXAMPLE
        Disconnect-Vcenter -AllVcenters
        Disconnects from all active vCenter connections with verification.

        .EXAMPLE
        Disconnect-Vcenter -AllVcenters -Silence
        Quietly disconnects from all active connections with suppressed console output.

        .EXAMPLE
        Disconnect-Vcenter -Vcenter "vcenter.example.com"
        Disconnects from a specific vCenter with error handling and logging.

        .OUTPUTS
        None. This function outputs status messages to console and log file.
    #>

    Param(
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$AllVcenters,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$Silence,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Vcenter
    )

    Write-LogMessage -Type DEBUG -Message "Entered Disconnect-Vcenter function..."

    # Disconnect specific vCenter.
    if ($Vcenter) {
        try {
            Disconnect-VIServer -Server $Vcenter -Force -Confirm:$false -ErrorAction Stop | Out-Null
            if ($Silence) {
                Write-LogMessage -Type DEBUG -Message "Successfully disconnected from vCenter `"$Vcenter`"."
                Write-Host ""
            } else {
                Write-LogMessage -Type INFO -Message "Successfully disconnected from vCenter `"$Vcenter`"."
                Write-Host ""
            }
        } catch {
            Write-LogMessage -Type ERROR -Message "Failed to disconnect from vCenter `"$Vcenter`": $($_.Exception.Message)"
        }
        return
    }

    # Disconnect from all vCenters.
    if ($AllVcenters) {
        $connectedVcenters = ($Global:DefaultVIServers | Where-Object { $_.IsConnected }).Name

        if ($connectedVcenters) {
            foreach ($vcenterName in $connectedVcenters) {
                try {
                    Disconnect-VIServer -Server $vcenterName -Force -Confirm:$false -ErrorAction Stop | Out-Null
                    if ($Silence) {
                        Write-LogMessage -Type DEBUG -Message "Successfully disconnected from vCenter `"$vcenterName`"."
                    } else {
                        Write-LogMessage -Type INFO -AppendNewLine -Message "Successfully disconnected from vCenter `"$vcenterName`"."
                    }
                } catch {
                    Write-LogMessage -Type ERROR -Message "Failed to disconnect from vCenter `"$vcenterName`": $($_.Exception.Message)"
                }
            }
        } else {
            if (-not $Silence) {
                Write-LogMessage -Type INFO -AppendNewLine -Message "No vCenter connections were detected."
            }
        }
    }
}
Function Get-SddcManagerVersion {

    <#
        .SYNOPSIS
        The function Get-SddcManagerVersion returns a portion of SDDC Manager release.

        .DESCRIPTION
        The first four version components (Major.Minor.Build.Revision) are extracted from
        the SDDC Manager ProductVersion and returned as a System.Version object.

        .EXAMPLE
        $version = Get-SddcManagerVersion
        # Returns [version]"9.0.0.0"

        .EXAMPLE
        if ((Get-SddcManagerVersion) -ge [version]"9.0.0.0") {
            Write-Host "SDDC Manager 9.0 or later"
        }

        .OUTPUTS
        System.Version
        Returns the SDDC Manager version as a System.Version object, or exits the script on failure.
    #>

    Write-LogMessage -Type DEBUG -Message "Entered Get-SddcManagerVersion function..."

    # Verify connection exists.
    if (-not $Global:defaultSddcManagerConnections) {
        Write-LogMessage -Type ERROR -Message "Not connected to SDDC Manager. Use -Connect parameter first."
        Exit-WithCode -ExitCode $Script:ExitCodes.CONNECTION_ERROR -Message "SDDC Manager connection required."
    }

    # Get version from connection.
    $sddcManagerVersion = $Global:defaultSddcManagerConnections.ProductVersion

    if ([string]::IsNullOrEmpty($sddcManagerVersion)) {
        Write-LogMessage -Type ERROR -Message "Unable to retrieve SDDC Manager version from connection."
        Exit-WithCode -ExitCode $Script:ExitCodes.CONNECTION_ERROR -Message "SDDC Manager version unavailable."
    }

    Write-LogMessage -Type DEBUG -Message "Full SDDC Manager version: $sddcManagerVersion"

    # PowerShell [version] type supports 4 components (Major.Minor.Build.Revision).
    # Extract first 4 version segments from SDDC Manager version string.
    if ($sddcManagerVersion -match '^(\d+\.\d+\.\d+\.\d+)') {
        $sanitizedSddcManagerVersion = $Matches[1]
    } else {
        Write-LogMessage -Type ERROR -Message "Unable to parse version from: $sddcManagerVersion"
        Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR -Message "Invalid SDDC Manager version format."
    }

    # Convert to [version] type and return.
    try {
        $versionObject = [version]$sanitizedSddcManagerVersion
        return $versionObject
    } catch {
        Write-LogMessage -Type ERROR -Message "Invalid version format: $sanitizedSddcManagerVersion - $_"
        Exit-WithCode -ExitCode $Script:ExitCodes.CONFIGURATION_ERROR -Message "Cannot convert to System.Version."
    }
}
Function Connect-SddcManager {
    <#
        .SYNOPSIS
        Establishes an authenticated connection to VMware Cloud Foundation SDDC Manager.

        .DESCRIPTION
        The Connect-SddcManager function provides comprehensive connection management for SDDC Manager
        with interactive credential collection and robust error handling. The function performs the
        following operations:

        1. Prompts interactively for SDDC Manager FQDN, username, and password
        2. Securely handles password input using SecureString
        3. Attempts connection using VCF.PowerCLI cmdlets
        4. Analyzes and reports connection errors with user-friendly messages
        5. Offers retry option on connection failure
        6. Logs connection success with version information

        The function uses centralized error handling through Write-ConnectionError to provide
        consistent, actionable error messages for various failure scenarios including authentication
        errors, DNS resolution failures, and network connectivity issues.

        .EXAMPLE
        Connect-SddcManager
        Prompts interactively for SDDC Manager credentials and establishes connection.

        .OUTPUTS
        None. This function sets the global $Global:defaultSddcManagerConnections variable on success.
    #>

    Write-LogMessage -Type DEBUG -Message "Entered Connect-SddcManager function..."

    # Interactive credential collection with validation loops.
    # Ensure all required credentials are provided before proceeding.
    Write-Host ""
    Write-LogMessage -Type INFO -AppendNewLine -Message "Please enter your connection details at the prompt."

    # Collect SDDC Manager FQDN with validation.
    $Script:sddcManagerFqdn = (Get-InteractiveInput -PromptMessage "Enter your SDDC Manager FQDN").Trim()
    $Script:sddcManagerUserName = (Get-InteractiveInput -PromptMessage "Enter your SDDC Manager SSO username").Trim()
    $Script:sddcManagerPassword = Get-InteractiveInput -PromptMessage "Enter your SDDC Manager SSO password" -AsSecureString
    Write-Host ""

    # Log connection attempt (to file only for clean console output).
    Write-LogMessage -Type DEBUG -Message "Attempting to connect to SDDC Manager `"$Script:sddcManagerFqdn`" with user `"$Script:sddcManagerUserName`"..."

    # Attempt connection with error suppression to handle errors gracefully. Write any errors to $errorMessage for parsing.
    $connectedToSddcManager = Connect-VcfSddcManagerServer -Server $Script:sddcManagerFqdn -User $Script:sddcManagerUserName -Password $Script:sddcManagerPassword -ErrorAction SilentlyContinue -ErrorVariable errorMessage

    # Handle connection errors using centralized error handler.
    if ($errorMessage) {
        # ErrorVariable returns an array, extract the error message properly.
        # Check both Exception.Message and Exception.InnerException.Message for connection errors.
        $errorText = if ($errorMessage -is [System.Collections.ArrayList] -or ($errorMessage.Count -gt 1)) {
            if ($errorMessage[0].Exception.InnerException.Message) {
                $errorMessage[0].Exception.InnerException.Message
            } elseif ($errorMessage[0].Exception.Message) {
                $errorMessage[0].Exception.Message
            } elseif ($errorMessage[0].ToString() -notmatch '^\d{1,2}/\d{1,2}/\d{4}') {
                # Only use ToString() if it doesn't look like a timestamp/cmdlet name.
                $errorMessage[0].ToString()
            } else {
                $null
            }
        } elseif ($errorMessage.Exception) {
            if ($errorMessage.Exception.InnerException.Message) {
                $errorMessage.Exception.InnerException.Message
            } elseif ($errorMessage.Exception.Message) {
                $errorMessage.Exception.Message
            } elseif ($errorMessage.Exception.ToString() -notmatch '^\d{1,2}/\d{1,2}/\d{4}') {
                # Only use ToString() if it doesn't look like a timestamp/cmdlet name.
                $errorMessage.Exception.ToString()
            } else {
                $null
            }
        } elseif ($errorMessage.ToString() -notmatch '^\d{1,2}/\d{1,2}/\d{4}') {
            # Only use ToString() if it doesn't look like a timestamp/cmdlet name
            $errorMessage.ToString()
        } else {
            $null
        }
        # Only call Write-ConnectionError if we have a valid error message.
        if ($errorText) {
            Write-ConnectionError -ErrorMessage $errorText -ConnectionType "SDDC Manager" -ServerName $Script:sddcManagerFqdn -UserName $Script:sddcManagerUserName
        } else {
            Write-LogMessage -Type ERROR -Message "Failed to connect to SDDC Manager `"$Script:sddcManagerFqdn`". Please check your connection details."
        }
    }

    # Handle connection failure scenarios and provide recovery options.
    if (-not $connectedToSddcManager) {
        # For interactive mode, offer to retry with new credentials.
        $decision = New-ChoiceMenu -Question "Would you like to re-enter your SDDC Manager FQDN and user credentials?" -DefaultAnswer "Yes"

        # Handle user's decision on retry.
        if ($decision -eq 0) {
            # User chose to retry - recursively call function for new attempt.
            Connect-SddcManager
        } else {
            # User chose not to retry - exit the connection attempt.
            return
        }
    } else {

        $sddcManagerVersion = Get-SddcManagerVersion

        if ([Version]($sddcManagerVersion) -lt [Version]($minimumVcfRelease)) {
            Disconnect-SddcManager -NoPrompt -Silence
            Exit-WithCode -ExitCode $Script:ExitCodes.VERSION_ERROR -Message "SDDC Manager version $sddcManagerVersion detected. Version $minimumVcfRelease or later is required."
        }

        # Connection successful - log success and version information.
        Write-LogMessage -Type INFO -AppendNewLine -Message "Successfully connected to SDDC Manager `"$Script:sddcManagerFqdn`" as `"$Script:sddcManagerUserName`"."
        Write-LogMessage -Type DEBUG -Message "SDDC Manager `"$Script:sddcManagerFqdn`" version is `"$($Global:defaultSddcManagerConnections.ProductVersion)`"."
    }
}
Function Disconnect-SddcManager {
    <#
        .SYNOPSIS
        Safely disconnects from SDDC Manager with optional user confirmation and logging control.

        .DESCRIPTION
        The Disconnect-SddcManager function provides a controlled way to terminate SDDC Manager
        connections with various operation modes: interactive mode with prompts, automatic mode
        without prompts, and silent mode with suppressed console output.

        .PARAMETER NoPrompt
        Bypasses user confirmation and disconnects immediately. Useful for automated cleanup
        operations and error handling scenarios.

        .PARAMETER Silence
        Suppresses console output while maintaining file logging. The disconnect operation
        and results are still logged to file for audit purposes.

        .EXAMPLE
        Disconnect-SddcManager
        Standard interactive disconnect with default confirmation prompt.

        .EXAMPLE
        Disconnect-SddcManager -NoPrompt
        Immediate disconnect without user confirmation, typically used in cleanup.

        .EXAMPLE
        Disconnect-SddcManager -NoPrompt -Silence
        Silent disconnect for automated operations with file-only logging.

        .OUTPUTS
        None. This function outputs status messages to console and/or log file.
    #>

    Param(
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$NoPrompt,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$Silence
    )

    # This ensures all actions are properly logged.
    New-LogFile

    Write-LogMessage -Type DEBUG -Message "Entered Disconnect-SddcManager function..."

    # Check if there's an active SDDC Manager connection.
    if (-not $Global:defaultSddcManagerConnections.IsConnected) {
        # No active connection found.
        if (-not $Silence) {
            Write-LogMessage -Type INFO -Message "No SDDC Manager connection detected."
        }
    } else {
        # Preserve SDDC Manager name for logging after disconnection.
        # This is necessary because the connection object becomes unavailable after disconnect.
        $sddcManagerFqdn = $Global:defaultSddcManagerConnections.name

        # Handle user confirmation unless NoPrompt is specified.
        if (-not $NoPrompt) {
            $decision = New-ChoiceMenu -Question "Would you like to disconnect from `"$sddcManagerFqdn`"?" -DefaultAnswer "No"
        }

        # Execute disconnection if user confirmed or NoPrompt is specified.
        if (($decision -eq 0) -or ($NoPrompt)) {
            # Attempt disconnection using PowerCLI cmdlet.
            $disconnectError = $null
            try {
                Disconnect-VcfSddcManagerServer -Server $Global:defaultSddcManagerConnections.name -ErrorAction Stop
            } catch {
                # Capture disconnection error for later processing.
                $disconnectError = $_
            }

            # Check disconnection result and log appropriately.
            if (-not $disconnectError) {
                # Disconnection successful.
                if ($Silence) {
                    # Silent mode - log to file only.
                    Write-LogMessage -Type DEBUG -Message "Successfully disconnected from SDDC Manager `"$sddcManagerFqdn`"."
                } else {
                    # Normal mode - display success message.
                    Write-LogMessage -Type INFO -AppendNewLine -Message "Successfully disconnected from SDDC Manager `"$sddcManagerFqdn`"."
                }
            } else {
                # Disconnection failed - check for specific error types.
                if ($disconnectError.Exception.Message -match "The request was canceled due to the configured HttpClient.Timeout") {
                    Write-LogMessage -Type ERROR -AppendNewLine -Message "Failed to disconnect from SDDC Manager `"$sddcManagerFqdn`", as it is not reachable from this script execution system."
                } else {
                    Write-LogMessage -Type ERROR -AppendNewLine -Message "Failed to disconnect from SDDC Manager `"$sddcManagerFqdn`": $($disconnectError.Exception.Message)."
                }
            }
        } else {
            # User chose not to disconnect.
            Write-LogMessage -Type DEBUG -Message "User chose not to disconnect from `"$sddcManagerFqdn`"."
        }
    }
}
Function Get-VcfDeploymentMode {
    <#
        .SYNOPSIS
        Prompts the user to determine if this is a VCF deployment or standalone vCenter.

        .DESCRIPTION
        The Get-VcfDeploymentMode function presents an interactive prompt asking the user whether
        this is a VMware Cloud Foundation (VCF) deployment. The default answer is "Yes" (VCF mode).
        The function returns a string value indicating the selected mode: "VCF" or "vCenter".

        .OUTPUTS
        System.String
        Returns "VCF" if the user selects Yes, or "vCenter" if the user selects No.

        .EXAMPLE
        $mode = Get-VcfDeploymentMode
        if ($mode -eq "VCF") {
            Connect-SddcManager
        } else {
            Connect-VcenterDirect
        }
    #>

    Write-LogMessage -Type DEBUG -Message "Entered Get-VcfDeploymentMode function..."
    Write-Host ""
    $decision = New-ChoiceMenu -Question "Is this a VCF Deployment?" -DefaultAnswer "Yes"

    if ($decision -eq 0) {
        return "VCF"
    } else {
        return "vCenter"
    }
}
Function Connect-VcenterDirect {
    <#
        .SYNOPSIS
        Establishes a direct connection to a single vCenter Server instance.

        .DESCRIPTION
        The Connect-VcenterDirect function provides interactive credential collection and connection
        to a standalone vCenter Server instance without requiring SDDC Manager. The function performs
        the following operations:

        1. Prompts interactively for vCenter FQDN, username, and password
        2. Securely handles password input using SecureString
        3. Attempts connection using Connect-VIServer cmdlet
        4. Validates vCenter version compatibility (9.0 or later required)
        5. Analyzes and reports connection errors with user-friendly messages
        6. Offers retry option on connection failure
        7. Logs connection success with version information

        The function uses centralized error handling through Write-ConnectionError to provide
        consistent, actionable error messages for various failure scenarios.

        .EXAMPLE
        Connect-VcenterDirect
        Prompts interactively for vCenter credentials and establishes connection.

        .OUTPUTS
        None. This function sets $Global:DefaultVIServers on success.
    #>

    Write-LogMessage -Type DEBUG -Message "Entered Connect-VcenterDirect function..."

    # Interactive credential collection with validation loops.
    # Ensure all required credentials are provided before proceeding.
    Write-Host ""
    Write-LogMessage -Type INFO -AppendNewLine -Message "Please enter your vCenter connection details at the prompt."

    # Collect vCenter FQDN with validation.
    $vcenterFqdn = (Get-InteractiveInput -PromptMessage "Enter your vCenter FQDN").Trim()
    $vcenterUserName = (Get-InteractiveInput -PromptMessage "Enter your vCenter SSO username").Trim()
    $vcenterPassword = Get-InteractiveInput -PromptMessage "Enter your vCenter SSO password" -AsSecureString

    # Create credential object.
    $vcenterCredential = New-Object System.Management.Automation.PSCredential($vcenterUserName, $vcenterPassword)

    # Log connection attempt (to file only for clean console output).
    Write-LogMessage -Type DEBUG -Message "Attempting to connect to vCenter `"$vcenterFqdn`" with user `"$vcenterUserName`"..."

    # Attempt connection with error suppression to handle errors gracefully. Write any errors to $errorMessage for parsing.
    $connectedToVcenter = Connect-VIServer -Server $vcenterFqdn -Credential $vcenterCredential -ErrorAction SilentlyContinue -ErrorVariable errorMessage

    # Handle connection errors using centralized error handler.
    if ($errorMessage) {
        # ErrorVariable returns an array, extract the error message properly.
        # Check both Exception.Message and Exception.InnerException.Message for vCenter connection errors.
        $errorText = if ($errorMessage -is [System.Collections.ArrayList] -or ($errorMessage.Count -gt 1)) {
            if ($errorMessage[0].Exception.InnerException.Message) {
                $errorMessage[0].Exception.InnerException.Message
            } else {
                $errorMessage[0].Exception.Message
            }
        } elseif ($errorMessage.Exception) {
            if ($errorMessage.Exception.InnerException.Message) {
                $errorMessage.Exception.InnerException.Message
            } else {
                $errorMessage.Exception.Message
            }
        } else {
            $errorMessage.ToString()
        }
        # Only call Write-ConnectionError if we have a valid error message.
        if ($errorText) {
            Write-ConnectionError -ErrorMessage $errorText -ConnectionType "vCenter Server" -ServerName $vcenterFqdn -UserName $vcenterUserName
        } else {
            Write-LogMessage -Type ERROR -Message "Failed to connect to vCenter `"$vcenterFqdn`". Please check your connection details."
        }
    }

    # Handle connection failure scenarios and provide recovery options.
    if (-not $connectedToVcenter) {
        # For interactive mode, offer to retry with new credentials.
        $decision = New-ChoiceMenu -Question "Would you like to re-enter your vCenter FQDN and user credentials?" -DefaultAnswer "Yes"

        # Handle user's decision on retry.
        if ($decision -eq 0) {
            # User chose to retry - recursively call function for new attempt.
            Connect-VcenterDirect
        } else {
            # User chose not to retry - exit the connection attempt.
            return
        }
    } else {
        # Connection successful - validate version and log success.
        $vcenterVersion = Get-VcenterVersion -Vcenter $vcenterFqdn
        if ([Version]$vcenterVersion -lt [Version]$minimumVcenterRelease) {
            Write-LogMessage -Type INFO -PrependNewLine -Message "Disconnecting from incompatible vCenter `"$vcenterFqdn`"."
            Disconnect-Vcenter -Vcenter $vcenterFqdn -Silence
            Exit-WithCode -ExitCode $Script:ExitCodes.VERSION_ERROR -Message "vCenter version $vcenterVersion detected. Version $minimumVcenterRelease or later is required."
        }

        # Initialize vcenterCapabilities array if not already initialized.
        if (-not $Script:vcenterCapabilities) {
            $Script:vcenterCapabilities = @()

            $Script:vcenterCapabilities += [pscustomobject]@{
                'vcenterFqdn'      = "vCenter"
                'unRestrictStatus' = "VUM Services"
                'message'          = "Message"
            }

            $Script:vcenterCapabilities += [pscustomobject]@{
                'vcenterFqdn'      = "-------"
                'unRestrictStatus' = "------------"
                'message'          = "-------"
            }
        }

        # Add entry for this vCenter.
        $Script:vcenterCapabilities += [pscustomobject]@{
            'vcenterFqdn'      = $vcenterFqdn
            'unRestrictStatus' = "STATUS_NOT_UPDATED"
            'message'          = "NO_MESSAGE"
        }

        # Connection successful - log success and version information.
        Write-LogMessage -Type INFO -AppendNewLine -Message "Successfully connected to vCenter `"$vcenterFqdn`" as `"$vcenterUserName`"."
        Write-LogMessage -Type DEBUG -Message "vCenter `"$vcenterFqdn`" version is $vcenterVersion."
        Get-VcenterVersion -Vcenter $vcenterFqdn -Silence
    }
}
Function Connect-Vcenter {
    <#
        .SYNOPSIS
        Establishes connections to all vCenter Server instances in VMware Cloud Foundation workload domains.

        .DESCRIPTION
        The Connect-Vcenter function automatically discovers and connects to all vCenter Server instances
        across all VMware Cloud Foundation workload domains. The function performs the following operations:

        1. Initializes the vCenter capabilities tracking array with header and separator rows
        2. Disconnects any existing vCenter connections to ensure fresh authentication
        3. Queries SDDC Manager for all workload domains
        4. Retrieves appropriate SSO credentials from SDDC Manager for each domain:
           - Management SSO credentials for domains using the management SSO domain
           - Isolated SSO credentials for domains with isolated SSO configurations
        5. Connects to each vCenter using the retrieved credentials
        6. Validates vCenter version compatibility (9.0 or later required)
        7. Disconnects from incompatible vCenter instances
        8. Populates the vcenterCapabilities array for status reporting

        The function requires an active SDDC Manager connection and the authenticated user must
        have ADMIN role permissions to retrieve vCenter credentials from SDDC Manager.

        Credentials are never exposed to the end user and are securely handled as PSCredential objects.

        .EXAMPLE
        Connect-Vcenter
        Connects to all vCenter instances in all workload domains using credentials from SDDC Manager.

        .OUTPUTS
        None. This function populates $Script:vcenterCapabilities array and sets $Global:DefaultVIServers.
    #>

    Write-LogMessage -Type DEBUG -Message "Entered Connect-Vcenter function..."

    $Script:vcenterCapabilities = @()

    $Script:vcenterCapabilities += [pscustomobject]@{
        'vcenterFqdn'      = "vCenter"
        'unRestrictStatus' = "VUM Services"
        'message'          = "Message"
    }

    $Script:vcenterCapabilities += [pscustomobject]@{
        'vcenterFqdn'      = "-------"
        'unRestrictStatus' = "------------"
        'message'          = "-------"
    }

    # List all connected vCenter(s).
    $connectedVcenters = ($Global:DefaultVIServers | Where-Object { $_.IsConnected -eq $true }).Name

    if ($connectedVcenters) {
        foreach ($vcenterName in $connectedVcenters) {
            # As a precaution, disconnect from the system to ensure the correct un/pw and an active token.
            Write-LogMessage -Type DEBUG -Message "Disconnecting existing connection to vCenter `"$vcenterName`" using User $(($Global:DefaultVIServers | Where-Object { $_.IsConnected -eq $true }) | Where-Object name -eq $vcenterName).User"
            Disconnect-Vcenter -Vcenter $vcenterName -Silence
        }
    }

    # Collect details of VCF domains to get vCenter FQDN and WLD name.
    try {
        $response = (Invoke-VcfGetDomains).Elements | Sort-Object
    } catch [Exception] {
        if ($_.Exception.Message -match "TOKEN_NOT_FOUND") {
            Write-LogMessage -Type ERROR -AppendNewLine -Message "Not connected to an SDDC Manager, please reconnect."
        } else {
            Write-LogMessage -Type ERROR -Message $_.Exception.Message
        }
    }
    if (-not $response) {
        Exit-WithCode -ExitCode $Script:ExitCodes.CONNECTION_ERROR -Message "Failed to retrieve workload domains from SDDC Manager."
    }

    # This is very unlikely, but the remaining calls in this function depend on properly-formed VCF WLD output.
    if ([String]::IsNullOrEmpty($response)) {
        Write-LogMessage -Type ERROR -Message "Unable to list VCF Workload Domains."
        Write-LogMessage -Type ERROR -Message "$($Error[0])"
        Exit-WithCode -ExitCode $Script:ExitCodes.CONNECTION_ERROR -Message "Unable to list VCF Workload Domains."
    }

    # Determine the management SSO domain.
    $mgmtDomain = (Invoke-VcfGetDomains -Type MANAGEMENT).Elements

    # Verify the user has sufficient permissions to pull vCenter credentials from SDDC Manager.
    # Operator and Viewer do not have access to SSO credentials.
    try {
        $mgmtSsoDomainElements = (Invoke-VcfGetCredentials -accountType SYSTEM -ResourceType PSC).Elements | Where-Object { $_.Resource.DomainName -eq $($mgmtDomain.Name) -and $_.Username -match "@$($mgmtDomain.SsoName)" }
    } catch {
        if ($_.Exception.Message -match "Forbidden") {
            $accessDenied = $true
        }
    }
    if (-not $mgmtSsoDomainElements) {
        if ($accessDenied -eq $true) {
            Exit-WithCode -ExitCode $Script:ExitCodes.AUTHENTICATION_ERROR -Message "Your SDDC Manager SSO user does not have sufficient access. Please reconnect to SDDC Manager as a user with the ADMIN role."
        } else {
            Exit-WithCode -ExitCode $Script:ExitCodes.RESOURCE_NOT_FOUND -Message "Cannot retrieve vCenter credentials from SDDC Manager `"$($Global:defaultSddcManagerConnections.Name)`"."
        }
    }

    $mgmtSsoDomainUsername = $($mgmtSsoDomainElements).Username
    $mgmtSsoDomainPassword = ConvertTo-SecureString -String $($mgmtSsoDomainElements).Password -AsPlainText -Force
    $mgmtSsoDomainCredentials = New-Object System.Management.Automation.PSCredential($mgmtSsoDomainUsername, $mgmtSsoDomainPassword)
    Clear-Variable -Name mgmtSsoDomainElements

    $workloadDomainNames = (Invoke-VcfGetDomains).Elements

    # Connect to each Workload Domain's vCenter using MGMT or isolated SSO credentials.
    foreach ($workloadDomainName in $workloadDomainNames) {
        # Initialize disconnectedVcenter flag for each iteration.
        $disconnectedVcenter = $false

        $vcenter = $($workloadDomainName.vCenters.fqdn)

        # Validate vCenter FQDN is not empty.
        if ([string]::IsNullOrEmpty($vcenter)) {
            Write-LogMessage -Type WARNING -Message "Skipping workload domain `"$($workloadDomainName.Name)`" - vCenter FQDN not found."
            continue
        }

        if ($workloadDomainName.IsManagementSsoDomain) {
            $vcenterCredential = $mgmtSsoDomainCredentials
        } else {
            $isolatedWldDomain = (Invoke-VcfGetDomains).Elements | Where-Object Name -eq $workloadDomainName.Name
            $isolatedWldSsoDomainElements = (Invoke-VcfGetCredentials -accountType SYSTEM -ResourceType PSC).Elements | Where-Object { $_.Resource.DomainNames -eq $($isolatedWldDomain.Name) -and $_.Username -match "@$($isolatedWldDomain.SsoName)" }
            $isolatedWldSsoDomainUsername = $($isolatedWldSsoDomainElements).Username
            $isolatedWldSsoDomainPassword = ConvertTo-SecureString -String $($isolatedWldSsoDomainElements).Password -AsPlainText -Force
            # Destroy the variable that contains the non-secured password, now that it's no longer needed.
            Clear-Variable -Name isolatedWldSsoDomainElements
            $vcenterCredential = New-Object System.Management.Automation.PSCredential($isolatedWldSsoDomainUsername, $isolatedWldSsoDomainPassword)
        }

        $connectedToVcenter = Connect-VIServer -Server $vcenter -Credential $vcenterCredential -ErrorAction SilentlyContinue -ErrorVariable vcenterConnectError
        if (-not $connectedToVcenter) {
            if ($vcenterConnectError.Exception.InnerException.Message -match "The request channel timed out attempting") {
                Write-LogMessage -Type ERROR -AppendNewLine -Message "Attempted connection to vCenter `"$vcenter`" request timed out. Please verify you have access to `"https://$vcenter`" from this system and vCenter services are healthy."
            } else {
                Write-LogMessage -Type ERROR -AppendNewLine -Message "`"$vcenter`": $($vcenterConnectError.Exception.InnerException.Message)"
            }
        }

        if ($connectedToVcenter) {
            $vcenterVersion = Get-VcenterVersion -Vcenter $vcenter
            if ([Version]$vcenterVersion -lt [Version]$minimumVcenterRelease) {
                Write-Host ""
                Write-LogMessage -Type WARNING -AppendNewLine -Message "vCenter `"$vcenter`" detected running version $vcenterVersion. vCenter $minimumVcenterRelease or later required."
                Write-LogMessage -Type INFO -AppendNewLine -Message "Disconnecting from incompatible vCenter `"$vcenter`"."
                Disconnect-Vcenter -Vcenter $vcenter
                $disconnectedVcenter = $true
                $Script:vcenterCapabilities += [pscustomobject]@{
                    'vcenterFqdn'      = $vcenter
                    'unRestrictStatus' = "N/A"
                    'message'          = "vCenter release unsupported (version $vcenterVersion)."
                }
            } else {
                $Script:vcenterCapabilities += [pscustomobject]@{
                    'vcenterFqdn'      = $vcenter
                    'unRestrictStatus' = "STATUS_NOT_UPDATED"
                    'message'          = "NO_MESSAGE"
                }
            }
        }

        if (($connectedToVcenter) -and (-not $disconnectedVcenter)) {
            Write-LogMessage -Type INFO -Message "Successfully connected to vCenter `"$vcenter`"."
            # Log information on vCenter version.
            Get-VcenterVersion -Vcenter $vcenter -Silence
        }
    }
}
Function Set-VumCapability {
    <#
        .SYNOPSIS
        Temporarily unrestricts VMware Update Manager (VUM) services on connected vCenter instances.

        .DESCRIPTION
        The Set-VumCapability function removes VUM restrictions on all connected vCenter Server instances
        by executing the Invoke-EsxSettingsInventoryUpdateVumCapabilityTask cmdlet. The function performs
        the following operations:

        1. Validates that at least one vCenter is connected (exits if none found)
        2. Initializes the vcenterCapabilities tracking array if not already initialized
        3. For each connected vCenter:
           - Adds a tracking entry to the capabilities array
           - Invokes the VUM unrestrict task
           - Monitors task progress with visual progress indicator
           - Updates the capabilities array with task results:
             * "Unrestricted" if heterogeneous hardware clusters are found
             * "Restricted" if no heterogeneous hardware clusters exist or task fails
        4. Checks workload domain status and warns if ERROR state is detected
        5. Logs vCenter capability data in JSON format to the log file
        6. Displays a formatted summary table of all vCenter VUM statuses

        Important: VUM services will be automatically re-restricted after a vCenter LCM service restart.
        This is a temporary unrestriction intended for immediate patch management operations.

        .EXAMPLE
        Set-VumCapability
        Unrestricts VUM on all connected vCenters and displays results.

        .OUTPUTS
        None. This function displays a summary table and logs results to file.
    #>
    if ($Global:DefaultVIServers.Count -eq 0) {
        Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR -Message "No vCenters are currently connected. Please connect one or more vCenters first."
    }
    Write-LogMessage -Type DEBUG -Message "Entered Set-VumCapability function..."

    # Initialize the array if it doesn't exist or is empty (e.g., when -Enable is run separately from -Connect)
    if (-not $Script:vcenterCapabilities -or $Script:vcenterCapabilities.Count -eq 0) {
        $Script:vcenterCapabilities = @()

        $Script:vcenterCapabilities += [pscustomobject]@{
            'vcenterFqdn'      = "vCenter"
            'unRestrictStatus' = "VUM Services"
            'message'          = "Message"
        }

        $Script:vcenterCapabilities += [pscustomobject]@{
            'vcenterFqdn'      = "-------"
            'unRestrictStatus' = "------------"
            'message'          = "-------"
        }
    }

    Write-LogMessage -Type INFO -AppendNewLine -Message "Looking for heterogeneous-hardware clusters in the connected vCenter(s)..."

    foreach ($vcenter in ($Global:DefaultVIServers | Where-Object { $_.IsConnected -eq $true }).Name) {
        $processTimer = [System.Diagnostics.Stopwatch]::StartNew()

        # Get vCenter server object once to avoid repeated lookups.
        $vcenterServerObject = $Global:DefaultVIServers | Where-Object name -eq $vcenter

        # Add entry for this vCenter if it doesn't already exist in the array.
        $existingEntry = $Script:vcenterCapabilities | Where-Object { $_.vcenterFqdn -eq $vcenter }
        if (-not $existingEntry) {
            $Script:vcenterCapabilities += [pscustomobject]@{
                'vcenterFqdn'      = $vcenter
                'unRestrictStatus' = "STATUS_NOT_UPDATED"
                'message'          = "NO_MESSAGE"
            }
        }

        try {
            $taskId = Invoke-EsxSettingsInventoryUpdateVumCapabilityTask -Server $vcenterServerObject
            if (-not $taskId) {
                Write-LogMessage -Type ERROR -AppendNewLine -Message "Task ID not returned for vCenter `"$vcenter`"."
                $updatedStatus = "Restricted"
                $updatedMessage = "Task creation failed - no task ID returned."
                # Update capabilities array and continue to next vCenter.
                $entry = $Script:vcenterCapabilities | Where-Object { $_.vcenterFqdn -eq $vcenter } | Select-Object -First 1
                if ($entry) {
                    $entry.unRestrictStatus = $updatedStatus
                    $entry.message = $updatedMessage
                }
                continue
            }
        } catch [Exception] {
            if ($_.Exception.Message -match "The term \'Invoke-EsxSettingsInventoryUpdateVumCapabilityTask\' is not recognized as a name of a cmdlet") {
                Exit-WithCode -ExitCode $Script:ExitCodes.PRECONDITION_ERROR -Message "Cannot find the cmdlet Invoke-EsxSettingsInventoryUpdateVumCapabilityTask. Your PowerCLI installation may be incomplete. Please consider reinstalling VCF.PowerCLI."
            } else {
                Write-LogMessage -Type ERROR -AppendNewLine -Message "Encountered error: $($_.Exception.Message)."
                $updatedStatus = "Restricted"
                $updatedMessage = "Task creation failed: $($_.Exception.Message)"
                # Update capabilities array and continue to next vCenter.
                $entry = $Script:vcenterCapabilities | Where-Object { $_.vcenterFqdn -eq $vcenter } | Select-Object -First 1
                if ($entry) {
                    $entry.unRestrictStatus = $updatedStatus
                    $entry.message = $updatedMessage
                }
                continue
            }
        }

        Do {
            Write-Progress -Activity "Processing task on vCenter $vcenter" -Status "$([math]::Round(($processTimer.Elapsed.TotalSeconds),0)) seconds elapsed."
            try {
                $taskState = (Invoke-GetTask -Task $taskId -Server $vcenterServerObject).Status
            } catch {
                Write-LogMessage -Type ERROR -Message "Failed to get task status for task $taskId on vCenter `"$vcenter`": $($_.Exception.Message)"
                $taskState = "FAILED"
                break
            }
            Start-Sleep 1
        }  While (($taskState -eq "Progress") -or ($taskState -eq "RUNNING"))

        Write-LogMessage -Type DEBUG -Message "TaskId for unrestrict VUM on vCenter `"$vcenter`" was `"$taskId`""

        # Get task result once to avoid repeated calls.
        try {
            $taskResult = Invoke-GetTask -Task $taskId -Server $vcenterServerObject
        } catch {
            Write-LogMessage -Type ERROR -Message "Failed to get task result for task $taskId on vCenter `"$vcenter`": $($_.Exception.Message)"
            $updatedStatus = "Restricted"
            $updatedMessage = "Failed to retrieve task result (see logs for details)."
            # Update capabilities array and continue to next vCenter
            $entry = $Script:vcenterCapabilities | Where-Object { $_.vcenterFqdn -eq $vcenter } | Select-Object -First 1
            if ($entry) {
                $entry.unRestrictStatus = $updatedStatus
                $entry.message = $updatedMessage
            }
            continue
        }

        # PowerShell switch statements are case-insensitive by default.
        switch ($taskState) {
            "FAILED" {
                $updatedStatus = "Failed"
                $updatedMessage = "Task failed (see logs for details)."
            }
            "SUCCEEDED" {
                # Result is an array, find the vum_operations_enabled entry.
                $vumEnabledResult = $taskResult.Result | Where-Object { $_.Key -eq 'vum_operations_enabled' }
                if ($vumEnabledResult -and $vumEnabledResult.Value -eq $true) {
                    $updatedStatus = "Unrestricted"
                    $updatedMessage = "Heterogeneous-hardware clusters(s) located."
                    # Check WLD status only if connected to SDDC Manager (VCF mode).
                    if ($Global:defaultSddcManagerConnections.IsConnected) {
                        try {
                            $workloadDomain = ((Invoke-VcfGetDomains).Elements | Where-Object { $_.Vcenters.fqdn -eq $vcenter })
                            if ($workloadDomain.Status -eq "ERROR") {
                                Write-LogMessage -Type WARNING -AppendNewLine -Message "Workload Domain `"$($workloadDomain.Name)`" has an error status. This must be resolved before converting the clusters in vCenter `"$vcenter`" to vLCM management."
                            }
                        } catch {
                            # Silently ignore if Invoke-VcfGetDomains fails (e.g., in vCenter mode).
                            Write-LogMessage -Type DEBUG -Message "Skipping workload domain status check for vCenter `"$vcenter`" (not in VCF mode or SDDC Manager unavailable)."
                        }
                    }
                } else {
                    $updatedStatus = "Restricted"
                    $updatedMessage = "No heterogeneous-hardware clusters(s) located."
                }
            }
            "BLOCKED" {
                $debuggingDetails = $taskResult | ConvertTo-Json -Depth 10
                Write-LogMessage -Type DEBUG -Message "vCenter `"$vcenter`" VUM unrestrict task (Task ID: $taskId) failed with error: $debuggingDetails"
                $updatedStatus = "Failed"
                $updatedMessage = "Task blocked (see logs for details)."
            }
            Default {
                Write-LogMessage -Type WARNING -Message "Unknown task state: $taskState"
                $updatedStatus = "Failed"
                $updatedMessage = "Task in unknown state (see logs for details)."
            }
        }

        # Update capabilities array using more efficient lookup.
        $entry = $Script:vcenterCapabilities | Where-Object { $_.vcenterFqdn -eq $vcenter } | Select-Object -First 1
        if ($entry) {
            $entry.unRestrictStatus = $updatedStatus
            $entry.message = $updatedMessage
        } else {
            # Entry not found, add it.
            $Script:vcenterCapabilities += [pscustomobject]@{
                'vcenterFqdn'      = $vcenter
                'unRestrictStatus' = $updatedStatus
                'message'          = $updatedMessage
            }
        }
        Write-Progress -Completed
        $processingTime = $([math]::Round(($processTimer.Elapsed.TotalSeconds), 0))
        Write-LogMessage -Type INFO -AppendNewLine -Message "vCenter `"$vcenter`" VUM unrestrict task completed in $processingTime seconds."
        Write-LogMessage -Type DEBUG -Message "vCenter `"$vcenter`: Status: $updatedStatus. Message: $updatedMessage"
        $processTimer.Stop()
    }

    # Log the vCenter capabilities data (excluding header and separator rows) to file in JSON format.
    $vcenterData = $Script:vcenterCapabilities | Where-Object { $_.vcenterFqdn -ne "vCenter" -and $_.vcenterFqdn -ne "-------" }
    if ($vcenterData) {
        $jsonOutput = $vcenterData | ConvertTo-Json -Depth 2
        Write-LogMessage -Type DEBUG -Message "vCenter capabilities:`n$jsonOutput"
    }

    Write-Host "Summary:" -ForegroundColor Cyan

    $Script:vcenterCapabilities | Format-Table -Property vcenterFqdn, unRestrictStatus, message -AutoSize -HideTableHeaders

}

# Variables and Constants.
$ConfirmPreference = "None"
$Global:ProgressPreference = 'Continue'
$PSStyle.Progress.Style = "`e[93;1m"
$scriptVersion = '1.0.0.2'
$psVersionMinVersion = '7.2'
$minimumVcenterRelease = '9.0'
$minimumVcfRelease = '9.0'
$minimumVcfPowerCliVersion = '9.0'
New-LogFile

# Added for debugging.
if (-not $env:SkipChecks) {
    Get-Preconditions
}

if ($Version) {
    Show-Version
    break
}

# Determine deployment mode if not provided via parameter.
if (-not $Mode) {
    $Mode = Get-VcfDeploymentMode
}

# Normalize mode to uppercase for comparison.
if ($Mode) {
    $Mode = $Mode.ToUpper()
}

# Disconnect from existing connections if they exist.
if ($Global:defaultSddcManagerConnections.IsConnected) {
    Write-LogMessage -Type INFO -Message "Detected existing SDDC Manager connection. Disconnecting..."
    Disconnect-SddcManager -NoPrompt
}

# Disconnect from existing vCenter connections if they exist.
if ($Global:DefaultVIServers.Count -ne 0) {
    Write-LogMessage -Type INFO -Message "Detected existing vCenter connections. Disconnecting..."
    Disconnect-Vcenter -AllVcenters
}

# Connect based on deployment mode, then set VUM capability, and disconnect.
switch ($Mode) {
    "VCF" {
        # Disconnect from existing SDDC Manager and vCenter connections if they exist.
        Disconnect-SddcManager -NoPrompt -Silence
        # Disconnect from all vCenter connections if they exist.
        Disconnect-Vcenter -AllVcenters -Silence
        Connect-SddcManager
        Connect-Vcenter
        Set-VumCapability
        Disconnect-SddcManager -NoPrompt
        Disconnect-Vcenter -AllVcenters
    }
    "VCENTER" {
        # Disconnect from all vCenter connections if they exist.
        Disconnect-Vcenter -AllVcenters -Silence
        Connect-VcenterDirect
        Set-VumCapability
        Disconnect-Vcenter -AllVcenters
    }
    Default {
        Exit-WithCode -ExitCode $Script:ExitCodes.PARAMETER_ERROR -Message "Invalid mode specified: $Mode. Valid values are 'VCF' or 'vCenter'."
    }
}
