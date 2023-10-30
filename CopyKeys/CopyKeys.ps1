### ---------------------------------------------------------------
### <script name=CopyKeys>
### <summary>
### This script copies the disk encryption keys and key encryption
### keys for Azure Disk Encryption (ADE) enabled VMs from the source
### region to disaster recovery (DR) region. Azure Site Recovery requires
### the keys to enable replication for these VMs to another region.
### </summary>
###
### <param name="AllowResourceMoverAccess">Switch parameter indicating if the MSI created by
### Azure Resource Mover for moving the selected VM resources need to be given access to the
### target BEK/KEK key vaults.</param>
### <param name="FilePath">Optional parameter defining the location of the output file.</param>
### ---------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter(
        Mandatory = $false,
        HelpMessage="Switch parameter indicating if the MSI created by Azure Resource Mover" + `
            "for moving the selected VM resources need to be given access to the target " + `
            "BEK/KEK key vaults.")]
    [switch]$AllowResourceMoverAccess = $false,
    [Parameter(
        Mandatory = $false,
        HelpMessage="Location of the output file.")]
    [string]$FilePath = $null)

### Checking for module versions and assemblies.
#Requires -Modules "Az.Compute"
#Requires -Modules @{ ModuleName="Az.KeyVault"; ModuleVersion="3.0.0" }
#Requires -Modules @{ ModuleName="Az.Accounts"; ModuleVersion="2.2.3" }
Set-StrictMode -Version 1.0
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

#region Logger

### <summary>
###  Types of logs available.
### </summary>
Enum LogType
{
    ### <summary>
    ###  Log type is error.
    ### </summary>
    ERROR = 1

    ### <summary>
    ###  Log type is warning.
    ### </summary>
    WARNING = 2

    ### <summary>
    ###  Log type is debug.
    ### </summary>
    DEBUG = 3

    ### <summary>
    ###  Log type is information.
    ### </summary>
    INFO = 4

    ### <summary>
    ###  Log type is output.
    ### </summary>
    OUTPUT = 5
}

### <summary>
###  Class to log results.
### </summary>
class Logger
{
    ### <summary>
    ###  Gets the output file name.
    ### </summary>
    [string]$fileName

    ### <summary>
    ###  Gets the output file location.
    ### </summary>
    [string]$filePath

    ### <summary>
    ###  Gets the output line width.
    ### </summary>
    [int]$lineWidth

    ### <summary>
    ###  Gets the debug segment status.
    ### </summary>
    [bool]$isDebugSegmentOpen

    ### <summary>
    ###  Gets the debug output.
    ### </summary>
    [System.Object[]]$debugOutput

    ### <summary>
    ###  Initializes an instance of class OutLogger.
    ### </summary>
    ### <param name="name">Name of the file.</param>
    ### <param name="path">Local or absolute path to the file.</param>
    Logger(
        [String]$name,
        [string]$path)
    {
        $this.fileName = $name
        $this.filePath = $path
        $this.isDebugSegmentOpen = $false
        $this.lineWidth = 80
    }

    ### <summary>
    ###  Gets the full file path.
    ### </summary>
    [String] GetFullPath()
    {
        $path = $this.fileName + '.log'

        if($this.filePath)
        {
            if (-not (Test-Path $this.filePath))
            {
                Write-Warning "Invalid file path: $($this.filePath)"
                return $path
            }

            if ($this.filePath[-1] -ne "\")
            {
                $this.filePath = $this.filePath + "\"
            }

            $path = $this.filePath + $path
        }

        return $path
    }


    ### <summary>
    ###  Gets the full file path.
    ### </summary>
    ### <param name="invocationInfo">Gets the invocation information.</param>
    ### <param name="message">Gets the message to be logged.</param>
    ### <param name="type">Gets the type of log.</param>
    ### <return>String containing the formatted message -
    ### Type: DateTime ScriptName Line [Method]: Message.</return>
    [String] GetFormattedMessage(
        [System.Management.Automation.InvocationInfo] $invocationInfo,
        [string]$message,
        [LogType] $type)
    {
        $dateTime = Get-Date -uFormat "%d/%m/%Y %r"
        $line = $type.ToString() + "`t`t: $dateTime "
        $line +=
            "$($invocationInfo.scriptName.split('\')[-1]):$($invocationInfo.scriptLineNumber) " + `
            "[$($invocationInfo.invocationName)]: "
        $line += $message

        return $line
    }

    ### <summary>
    ###  Starts the debug segment.
    ### </summary>
    [Void] StartDebugLog()
    {
        $script:DebugPreference = "Continue"
        $this.isDebugSegmentOpen = $true
    }

    ### <summary>
    ###  Stops the debug segment.
    ### </summary>
    [Void] StopDebugLog()
    {
        $script:DebugPreference = "SilentlyContinue"
        $this.isDebugSegmentOpen = $false
    }

    ### <summary>
    ###  Gets the debug output and stores it in $DebugOutput.
    ### </summary>
    ### <param name="command">Command whose debug output needs to be redirected.</param>
    ### <return>Command modified to get the debug output to the success stream to be stored in
    ### a variable.</return>
    [string] GetDebugOutput([string]$command)
    {
        if ($this.isDebugSegmentOpen)
        {
            return '$(' + $command + ') 5>&1'
        }

        return $command
    }

    ### <summary>
    ###  Redirects the debug output to the output file.
    ### </summary>
    ### <param name="invocationInfo">Gets the invocation information.</param>
    ### <param name="command">Gets the command whose debug output needs to be redirected.</param>
    ### <return>Command modified to redirect debug stream to the log file.</return>
    [string] RedirectDebugOutput(
        [System.Management.Automation.InvocationInfo] $invocationInfo,
        [string]$command)
    {
        if ($this.isDebugSegmentOpen)
        {
            $this.Log(
                $InvocationInfo,
                "Debug output for command: $command`n",
                [LogType]::DEBUG)
            return $command + " 5>> $($this.GetFullPath())"
        }

        return $command
    }

    ### <summary>
    ###  Appends a message to the output file.
    ### </summary>
    ### <param name="invocationInfo">Gets the invocation information.</param>
    ### <param name="message">Gets the message to be logged.</param>
    ### <param name="type">Gets the type of log.</param>
    [Void] Log(
        [System.Management.Automation.InvocationInfo] $invocationInfo,
        [string] $message,
        [LogType] $type)
    {
        if ([LogType]::OUTPUT -eq $type)
        {
            Write-Host -ForegroundColor Green $message
        }

        Out-File -FilePath $($this.GetFullPath()) -InputObject $this.GetFormattedMessage(
            $invocationInfo,
            $message,
            $type) -Append -NoClobber -Width $this.lineWidth
    }

    ### <summary>
    ###  Appends an object to the output file.
    ### </summary>
    ### <param name="invocationInfo">Gets the invocation information.</param>
    ### <param name="object">Gets the object to be logged.</param>
    ### <param name="message">Gets the message to be logged.</param>
    ### <param name="type">Gets the type of log.</param>
    [Void] LogObject(
        [System.Management.Automation.InvocationInfo] $invocationInfo,
        $object,
        [string] $message,
        [LogType] $type)
    {
        Out-File -FilePath $($this.GetFullPath()) -InputObject $this.GetFormattedMessage(
            $invocationInfo,
            "`n",
            $type) -Append -NoClobber -Width $this.lineWidth

        if (-not [string]::IsNullOrEmpty($message))
        {
            $this.Log($invocationInfo, $message, $type)
        }

        Out-File -FilePath $($this.GetFullPath()) -InputObject `
            $(ConvertTo-Json -InputObject $object) -Append -NoClobber
    }
}
#endRegion

#region Source

### <summary>
###  Class for the source machines.
### </summary>
class Source
{
    ### <summary>
    ###  Gets VM source name.
    ### </summary>
    [string]$Name

    ### <summary>
    ###  Gets name of disks.
    ### </summary>
    [string]$DiskName

    ### <summary>
    ###  Gets disk encryption key information.
    ### </summary>
    [Microsoft.Azure.Management.Compute.Models.KeyVaultSecretReference]$Bek

    ### <summary>
    ###  Gets key encryption key information.
    ### </summary>
    [Microsoft.Azure.Management.Compute.Models.KeyVaultKeyReference]$Kek

    ### <summary>
    ###  Initializes an instance of Source.
    ### </summary>
    ### <param name="Name">Gets the source name.</param>
    Source([String]$Name, [String]$DiskName)
    {
        $this.Name = $Name
        $this.DiskName = $DiskName
    }
}
#endregion

#region Constants

class ConstantStrings
{
    static [string] $adeExtensionPrefix = "azurediskencryption"
    static [string] $apiVersion = "api-version"
    static [string] $asrSuffix = "-asr"
    static [string] $authHeader = "authorization"
    static [string] $contentType = "application/json"
    static [string] $httpGet = "GET"
    static [string] $httpPost = "POST"
    static [int] $keyVaultNameMaxLength = 24
    static [string] $loadingBEK = "Loading target BEK vault"
    static [string] $loadingKEK = "Loading target KEK vault"
    static [string] $loadingRG = "Loading resource groups"
    static [string] $moveResourceType = "moveresources"
    static [string] $newPrefix = "(new)"
    static [string] $noAdeVmInResourceGroup = "Selected resource group does `nnot contain any " + `
        "encrypted VMs."
    static [string] $notApplicable = "Not Applicable"
    static [string] $providers = "providers"
    static [string] $resourceGroups = "resourceGroups"
    static [string] $resourceLinks = "links"
    static [string] $resourceLinksApiVersion = "2016-09-01"
    static [string] $resourcesProvider = "Microsoft.Resources"
    static [string] $scopes = "scopes"
    static [string] $subscriptions = "subscriptions"
    static [string] $tokenType = "Bearer"
    static [string] $vmType = "virtualmachines"
}
#endregion


#Region Errors

### <summary>
### Class to maintain all the errors.
### </summary>
class Errors
{
    ### <summary>
    ###  Encryption information missing.
    ### </summary>
    ### <param name="vmName">Virtual machine name.</param>
    ### <return>Error string.</return>
    static [string] EncryptionInfoMissing([string] $vmName)
    {
        return "Virtual machine $vmName encrypted but encryption settings details missing."
    }

    ### <summary>
    ###  Disk encryption information missing.
    ### </summary>
    ### <param name="vmName">Virtual machine name.</param>
    ### <param name="diskName">Disk name.</param>
    ### <return>Error string.</return>
    static [string] DiskEncryptionInfoMissing([string] $vmName, [string] $diskName)
    {
        return "Virtual machine $vmName encrypted but disk encryption " + `
        "settings missing for disk - $diskName."
    }

    ### <summary>
    ###  Secret encryption failed.
    ### </summary>
    ### <param name="message">Error message.</param>
    ### <return>Error string.</return>
    static [string] SecretEncryptionFailed([string] $message)
    {
        return "Secret encryption failed with error - `n$message."
    }

    ### <summary>
    ###  Secret decryption failed.
    ### </summary>
    ### <param name="message">Error message.</param>
    ### <return>Error string.</return>
    static [string] SecretDecryptionFailed([string] $message)
    {
        return "Secret decryption failed with error - `n$message."
    }

    ### <summary>
    ###  Access policy permissions missing.
    ### </summary>
    ### <param name="type">Resource type.</param>
    ### <param name="keyVaultName">Key vault name.</param>
    ### <param name="permissionsRequired">Permissions required for copy keys.</param>
    ### <return>Error string.</return>
    static [string] MissingPermissions(
        [string] $type,
        [string] $keyVaultName,
        [string[]] $permissionsRequired)
    {
        return "You do not have sufficient permissions to access '$type' in the key vault " + `
            "$keyVaultName. You need $($permissionsRequired -join ',') for key vault '$type'."
    }

    ### <summary>
    ###  User access policy missing.
    ### </summary>
    ### <param name="userId">User id.</param>
    ### <param name="keyVaultName">Key vault name.</param>
    ### <param name="allowedObjectIds">Allowed object ids.</param>
    ### <return>Error string.</return>
    static [string] UserMissingAccess(
        [string] $userId,
        [string] $keyVaultName,
        [string[]] $allowedObjectIds)
    {
        return "User with user id: $userId does not have access to the key vault " + `
            "$keyVaultName. Permitted object ids include - $($allowedObjectIds -join ',')."
    }

    ### <summary>
    ###  Key missing.
    ### </summary>
    ### <param name="keyName">Key name.</param>
    ### <param name="keyVersion">Key version.</param>
    ### <param name="keyVaultName">Key vault name.</param>
    ### <return>Error string.</return>
    static [string] KeyMissing([string] $keyName, [string] $keyVersion, [string] $keyVaultName)
    {
        return "Key with name: $keyName and version: $keyVersion could not be found in key " + `
            "vault $keyVaultName."
    }

    ### <summary>
    ###  Subscriptions missing.
    ### </summary>
    ### <param name="tenantId">Tenant Id.</param>
    ### <return>Error string.</return>
    static [string] NoSubscriptionsFound([string] $tenantId)
    {
        return "No subscriptions could be found under tenant '$tenantId'. Verify that there " + `
            "are subscriptions and you're logged in correctly."
    }


    ### <summary>
    ### ARM call failed.
    ### </summary>
    ### <param name="exceptionStr">Exception as string.</param>
    ### <param name="requestStr">Request as string.</param>
    ### <return>Error string.</return>
    static [string] ArmCallFailed([string] $exceptionStr, [string] $requestStr)
    {
        return "ARM call failed with the following error:`n$exceptionStr" + `
            "`nThe request information:`n$requestStr."
    }

    ### <summary>
    ### Api version missing.
    ### </summary>
    ### <return>Error string.</return>
    static [string] ApiVersionMissing()
    {
        return "API version related information is missing."
    }

    ### <summary>
    ### URL tokens missing.
    ### </summary>
    ### <return>Error string.</return>
    static [string] UrlTokensMissing()
    {
        return "Tokens for URL construction are missing."
    }

    ### <summary>
    ### Invalid ARM id input.
    ### </summary>
    ### <return>Error string.</return>
    static [string] InvalidArmIdInput()
    {
        return "The resource ARM id input is invalid."
    }

    ### <summary>
    ### Invalid label token input.
    ### </summary>
    ### <param name="armId">Resource ARM id.</param>
    ### <param name="tokenCount">Count of tokens.</param>
    ### <return>Error string.</return>
    static [string] InvalidLabelTokenInput(
        [string] $armId,
        [int] $tokenCount)
    {
        return "Labelled tokens cannot be created for ARM id - '$armId', as the token count " +
            "($tokenCount) is odd."
    }
}
#EndRegion

#region UI

### <summary>
### Displays messages when cursor hovers over UI objects.
### </summary>
function Show-Help
{
    $InfoToolTip.SetToolTip($this, $this.Tag)
}

### <summary>
### Gets list of resource groups for selected subscription and populates dropdown.
### </summary>
function Get-ResourceGroups
{
    $SubscriptionName = $this.SelectedItem.ToString()
    if ($SubscriptionName)
    {
        $LoadingLabel.Text = [ConstantStrings]::loadingRG

        Select-AzSubscription -SubscriptionName $SubscriptionName
        $ResourceProvider = Get-AzResourceProvider -ProviderNamespace Microsoft.Compute

        # Locations taken from resource type: availabilitySets instead of resource type: Virtual machines,
        # just to stay in parallel with the Portal.
        $Locations = ($ResourceProvider[0].Locations) | ForEach-Object {
            $_.Split(' ').tolower() -join ''} | Sort-Object
        $ResourceGroupLabel = $FormElements["ResourceGroupLabel"]
        $ResourceGroupDropDown = $FormElements["ResourceGroupDropDown"]
        $VmListBox = $FormElements["VmListBox"]
        $LocationDropDown = $FormElements["LocationDropDown"]
        $ResourceGroupLabel.Enabled = $true
        $ResourceGroupDropDown.Enabled = $true
        $ResourceGroupDropDown.Items.Clear()
        $VmListBox.Items.Clear()
        $LocationDropDown.Items.Clear()
        $ResourceGroupDropDown.Text = [string]::Empty

        [array]$ResourceGroupArray = (Get-AzResourceGroup).ResourceGroupName | Sort-Object

        foreach ($Item in $ResourceGroupArray)
        {
            $SuppressOutput = $ResourceGroupDropDown.Items.Add($Item)
        }

        if($ResourceGroupArray)
        {
            $Longest = ($ResourceGroupArray | Sort-Object Length -Descending)[0]
            $ResourceGroupDropDown.DropDownWidth = ([System.Windows.Forms.TextRenderer]::MeasureText($Longest, `
                $ResourceGroupDropDown.Font).Width, $ResourceGroupDropDown.Width | Measure-Object -Maximum).Maximum
        }

        foreach ($Item in $Locations)
        {
            $SuppressOutput = $LocationDropDown.Items.Add($Item)
        }

        if($Locations)
        {
            $Longest = ($Locations | Sort-Object Length -Descending)[0]
            $LocationDropDown.DropDownWidth = ([System.Windows.Forms.TextRenderer]::MeasureText($Longest, `
                $LocationDropDown.Font).Width, $LocationDropDown.Width | Measure-Object -Maximum).Maximum
        }

        for ($Index = 4; $Index -lt $FormElementsList.Count; $Index++)
        {
            $FormElements[$FormElementsList[$Index]].Enabled = $false
        }

        $LoadingLabel.Text = [string]::Empty
    }
}

### <summary>
### Gets list of VMs for selected resource group and populates checklist.
### </summary>
function Get-VirtualMachines
{
    $ResourceGroupName = $this.SelectedItem.ToString()
    if ($ResourceGroupName)
    {
        $LoadingLabel.Text = [string]::Empty
        $VmListBox = $FormElements["VmListBox"]
        $VmListBox.Items.Clear()
        $FormElements["VmLabel"].Enabled = $true
        $FormElements["LocationLabel"].Enabled = $true
        $VmListBox.Enabled = $true
        $LocationDropDown.Enabled = $true
        $LocationDropDown.Text = [string]::Empty

        $VmList = (Get-AzVm -ResourceGroupName $ResourceGroupName) | Sort-Object Name

        foreach ($Item in $VmList)
        {
            if (($null -ne $Item.Extensions -and $Item.Extensions.Count -gt 0) -and
                ($Item.Extensions.Id | ForEach-Object { `
                    $_.split('/')[-1].tolower().contains( `
                        [ConstantStrings]::adeExtensionPrefix)}) -contains $true)
            {
                $SuppressOutput = $VmListBox.Items.Add($Item.Name)
            }
        }

        if($VmList -and ($VmListBox.Items.Count -gt 0))
        {
            $Longest = ($VmList.Name | Sort-Object Length -Descending)[0]
            $Size = [System.Windows.Forms.TextRenderer]::MeasureText($Longest, `
                $VmListBox.Font).Width

            if ($Size -gt $VmListBox.Width)
            {
                $VmListBox.Width = $Size + 30
                $UserInputForm.Width = $Size + 60
            }
        }
        else
        {
            $LoadingLabel.Text = [ConstantStrings]::noAdeVmInResourceGroup
        }

        for ($Index = 8; $Index -lt $FormElementsList.Count; $Index++)
        {
            $FormElements[$FormElementsList[$Index]].Enabled = $false
        }
    }
}

### <summary>
### Disable and clears remaining options when VM list modified.
### </summary>
function Disable-RestOfOptions
{
    $FormElements["LocationDropDown"].Text = [string]::Empty
    $FormElements["BekDropDown"].Text = [string]::Empty
    $FormElements["KekDropDown"].Text = [string]::Empty

    for ($Index = 8; $Index -lt $FormElementsList.Count; $Index++)
    {
        if ($FormElements[$FormElementsList[$Index]].Text -ne [ConstantStrings]::notApplicable)
        {
            $FormElements[$FormElementsList[$Index]].Enabled = $false
        }
    }
}

### <summary>
### Gets list of target key vaults for KEK and BEK for selected VM(s) and populates dropdown.
### </summary>
function Get-KeyVaults
{
    $LocationName = $this.SelectedItem.ToString()

    if ([string]::IsNullOrEmpty($LocationName))
    {
        return
    }

    $BekDropDown = $FormElements["BekDropDown"]
    $KekDropDown = $FormElements["KekDropDown"]
    $ResourceGroupDropDown = $FormElements["ResourceGroupDropDown"]
    $VmSelected = $FormElements["VmListBox"].CheckedItems
    $FailCount = 0

    if ($VmSelected)
    {
        $LoadingLabel.Text = [ConstantStrings]::loadingBEK
        $Bek = $Kek = [string]::Empty
        $Index = 0

        while ((-not $Kek) -and ($Index -lt $VmSelected.Count))
        {
            $Vm = Get-AzVM -ResourceGroupName `
                $ResourceGroupDropDown.SelectedItem.ToString() -Name $VmSelected[$Index]

            if (($null -eq $Vm.StorageProfile.OsDisk.EncryptionSettings) -or `
                (-not $Vm.StorageProfile.OsDisk.EncryptionSettings.Enabled))
            {
                $Vm = Get-AzVM -ResourceGroupName `
                    $ResourceGroupDropDown.SelectedItem.ToString() -Name $VmSelected[$Index] -Status

                $Disks = $Vm.Disks
                $IsNotEncrypted = $true

                foreach ($Disk in $Disks)
                {
                    if ($null -ne $Disk.EncryptionSettings)
                    {
                        $IsNotEncrypted = $false
                        $Bek = $Disk.EncryptionSettings[0].DiskEncryptionKey
                        $Kek = $Disk.EncryptionSettings[0].KeyEncryptionKey

                        break
                    }
                }

                if($IsNotEncrypted)
                {
                    throw [Errors]::EncryptionInfoMissing($vm.Name)
                }
            }
            else
            {
                $Bek = $Vm.StorageProfile.OsDisk.EncryptionSettings.DiskEncryptionKey
                $Kek = $Vm.StorageProfile.OsDisk.EncryptionSettings.KeyEncryptionKey
            }

            $Index++
        }

        if (-not $Bek)
        {
            $BekDropDown.Text = [ConstantStrings]::notApplicable
            $BekDropDown.Enabled = $false
            $FailCount += 1
        }
        else
        {
            $BekKeyVaultName = $Bek.SourceVault.Id.Split('/')[-1] + $LocationName

            if ($BekKeyVaultName.Length -ge [ConstantStrings]::keyVaultNameMaxLength)
            {
                $allowedLength = [ConstantStrings]::keyVaultNameMaxLength - $LocationName.Length
                $BekKeyVaultName =
                    ($Bek.SourceVault.Id.Split('/')[-1]).Substring(0, $allowedLength) + `
                    $LocationName
            }

            $BekKeyVault = Get-AzResource -Name $BekKeyVaultName

            if (-not $BekKeyVault)
            {
                $BekKeyVaultName = [ConstantStrings]::newPrefix + $BekKeyVaultName
                $BekDropDown.Items.Add($BekKeyVaultName)
            }

            $BekDropDown.Text = $BekKeyVaultName
        }

        $LoadingLabel.Text = [ConstantStrings]::loadingKEK

        if (-not $Kek)
        {
            $KekDropDown.Text = [ConstantStrings]::notApplicable
            $KekDropDown.Enabled = $false
            $FailCount += 1
        }
        else
        {
            $KekKeyVaultName = $Kek.SourceVault.Id.Split('/')[-1] + $LocationName

            if ($KekKeyVaultName.Length -ge [ConstantStrings]::keyVaultNameMaxLength)
            {
                $allowedLength = [ConstantStrings]::keyVaultNameMaxLength - $LocationName.Length
                $KekKeyVaultName =
                    ($Kek.SourceVault.Id.Split('/')[-1]).Substring(0, $allowedLength) + `
                    $LocationName
            }

            $KekKeyVault = Get-AzResource -Name $KekKeyVaultName

            if (-not $KekKeyVault)
            {
                $KekKeyVaultName = [ConstantStrings]::newPrefix + $KekKeyVaultName
                $KekDropDown.Items.Add($KekKeyVaultName)
            }

            $KekDropDown.Text = $KekKeyVaultName
        }

        if ($FailCount -lt 2)
        {
            if ($BekDropDown.Items.Count -le 1)
            {
                $KeyVaultList = (Get-AzKeyVault | Where-Object { `
                    $_.Location -like $LocationName}).VaultName | Sort-Object

                foreach ($Item in $KeyVaultList)
                {
                    $SuppressOutput = $BekDropDown.Items.Add($Item)
                    $SuppressOutput = $KekDropDown.Items.Add($Item)
                }

                if($KeyVaultList)
                {
                    if($Bek)
                    {
                        $Longest = ($KeyVaultList + $BekKeyVaultName | Sort-Object Length -Descending)[0]
                        $BekDropDown.DropDownWidth = ([System.Windows.Forms.TextRenderer]::MeasureText($Longest, `
                            $BekDropDown.Font).Width, $BekDropDown.Width | Measure-Object -Maximum).Maximum
                    }

                    if($Kek)
                    {
                        $Longest = ($KeyVaultList + $KekKeyVaultName  | Sort-Object Length -Descending)[0]
                        $KekDropDown.DropDownWidth = ([System.Windows.Forms.TextRenderer]::MeasureText($Longest, `
                            $KekDropDown.Font).Width, $KekDropDown.Width | Measure-Object -Maximum).Maximum
                    }
                }
            }

            for ($Index = 8; $Index -lt $FormElementsList.Count; $Index++)
            {
                if ($FormElements[$FormElementsList[$Index]].Text -ne [ConstantStrings]::notApplicable)
                {
                    $FormElements[$FormElementsList[$Index]].Enabled = $true
                }
            }
        }

        $LoadingLabel.Text = [string]::Empty
    }
    else
    {
        $BekDropDown.Items.Clear()
        $KekDropDown.Items.Clear()
    }
}

### <summary>
### Gets list of all options selected on submission and closes the form.
### </summary>
function Get-AllSelections
{
    $UserInputs["ResourceGroupName"] = $FormElements["ResourceGroupDropDown"].SelectedItem.ToString()
    $UserInputs["VmNameArray"] = $FormElements["VmListBox"].CheckedItems
    $UserInputs["TargetLocation"] = $FormElements["LocationDropDown"].SelectedItem.ToString()
    $BekKeyVault = $FormElements["BekDropDown"].Text.Split(')')
    $UserInputs["TargetBekVault"] = $BekKeyVault[$BekKeyVault.Count - 1]
    $KekKeyVault = $FormElements["KekDropDown"].Text.Split(')')
    $UserInputs["TargetKekVault"] = $KekKeyVault[$KekKeyVault.Count - 1]
    $UserInputForm.Close()
}

### <summary>
### Applies the formatting common to all UI objects.
### </summary>
### <param name="UiObject">UI object to be formatted.</param>
### <param name="Formattings">Custom formatting values.</param>
function Add-CommonFormatting(
    $UiObject,
    [System.Collections.Hashtable] $Formattings)
{
    $UiObject.Enabled = $false
    $UiObject.Font = "Microsoft Sans Serif, 10"
    $UiObject.ForeColor = "#5c7290"
    $UiObject.width = $Formattings["width"] * $WidthRatio
    $UiObject.height = $Formattings["height"] * $HeightRatio

    $UiObject.location =
        New-Object System.Drawing.Point(
            $($Formattings["location"][0] * $WidthRatio),
            $($Formattings["location"][1] * $HeightRatio))
}

### <summary>
### Generates the graphical user interface to get all inputs.
### </summary>
function Generate-UserInterface
{
    $Size = [System.Windows.Forms.SystemInformation]::PrimaryMonitorSize
    $WidthRatio = [Convert]::ToInt32($Size.Width/1620)
    $HeightRatio = [Convert]::ToInt32($Size.Height/1080)

    $UserInputForm = New-Object System.Windows.Forms.Form
    $SubscriptionLabel = New-Object System.Windows.Forms.Label
    $SubscriptionDropDown = New-Object System.Windows.Forms.ComboBox
    $ResourceGroupLabel = New-Object System.Windows.Forms.Label
    $ResourceGroupDropDown = New-Object System.Windows.Forms.ComboBox
    $VmLabel = New-Object System.Windows.Forms.Label
    $VmListBox = New-Object System.Windows.Forms.CheckedListBox
    $LocationLabel = New-Object System.Windows.Forms.Label
    $LocationDropDown = New-Object System.Windows.Forms.ComboBox
    $BekLabel = New-Object System.Windows.Forms.Label
    $BekDropDown = New-Object System.Windows.Forms.ComboBox
    $KekLabel = New-Object System.Windows.Forms.Label
    $KekDropDown = New-Object System.Windows.Forms.ComboBox
    $LoadingLabel = New-Object System.Windows.Forms.Label
    $SelectButton = New-Object System.Windows.Forms.Button
    $InfoToolTip = New-Object System.Windows.Forms.ToolTip

    $FormElementsList = @("SubscriptionLabel", "SubscriptionDropDown", "ResourceGroupLabel", `
        "ResourceGroupDropDown", "VmLabel", "VmListBox", "LocationLabel", "LocationDropDown", `
        "BekLabel", "BekDropDown", "KekLabel", "KekDropDown", "SelectButton")
    $FormElements = @{"SubscriptionLabel" = $SubscriptionLabel;` "SubscriptionDropDown" = `
        $SubscriptionDropDown; "ResourceGroupLabel" = $ResourceGroupLabel; "ResourceGroupDropDown" = `
        $ResourceGroupDropDown;` "VmLabel" = $VmLabel; "VmListBox" = $VmListBox; "LocationLabel" = `
        $LocationLabel; "LocationDropDown" = $LocationDropDown; "BekLabel" = $BekLabel; "BekDropDown" = `
        $BekDropDown; "KekLabel" = $KekLabel; "KekDropDown" = $KekDropDown; "SelectButton" = $SelectButton}

    # Applying formatting to various UI objects

    $UserInputForm.ClientSize = "$(445*$WidthRatio), $(620*$HeightRatio)"
    $UserInputForm.text = "User Inputs"
    $UserInputForm.BackColor = "#ffffff"
    $UserInputForm.TopMost = $false
    $UserInputForm.AutoScaleMode = 'Font'

    $SubscriptionLabelFormatting = @{"location"=@(10, 90); "width"=88; "height"=30}
    Add-CommonFormatting -UiObject $SubscriptionLabel -Formattings $SubscriptionLabelFormatting
    $SubscriptionLabel.text = "Subscription"
    $SubscriptionLabel.AutoSize = $true
    $SubscriptionLabel.Enabled = $true
    $SubscriptionLabel.Tag = "Specify the Azure subscription ID."
    $SubscriptionLabel.Add_MouseHover({Show-Help})

    $SubscriptionDropDownFormatting = @{"location"=@(10, 121); "width"=424; "height"=66}
    Add-CommonFormatting -UiObject $SubscriptionDropDown -Formattings `
        $SubscriptionDropDownFormatting
    $SubscriptionDropDown.Enabled = $true
    $SubscriptionDropDown.DropDownHeight = 150 * $HeightRatio
    $SubscriptionDropDown.AutoSize = $true
    $SubscriptionDropDown.Font = "Microsoft Sans Serif, $(10 * $HeightRatio)"
    $SubscriptionDropDown.Add_SelectedIndexChanged({Get-ResourceGroups})

    $ResourceGroupDropDownFormatting = @{"location"=@(10, 189); "width"=424; "height"=60}
    Add-CommonFormatting -UiObject $ResourceGroupDropDown -Formattings `
        $ResourceGroupDropDownFormatting
    $ResourceGroupDropDown.DropDownHeight = 150 * $HeightRatio
    $ResourceGroupDropDown.Font = "Microsoft Sans Serif, $(10 * $HeightRatio)"
    $ResourceGroupDropDown.Add_SelectedIndexChanged({Get-VirtualMachines})

    $ResourceGroupLabelFormatting = @{"location"=@(10, 163); "width"=25; "height"=10}
    Add-CommonFormatting -UiObject $ResourceGroupLabel -Formattings $ResourceGroupLabelFormatting
    $ResourceGroupLabel.text = "Resource Group"
    $ResourceGroupLabel.AutoSize = $true
    $ResourceGroupLabel.Tag = "Specify the source resource group containing the virtual machines."
    $ResourceGroupLabel.Add_MouseHover({Show-Help})

    $VmListBoxFormatting = @{"location"=@(10, 255); "width"=424; "height"=95}
    Add-CommonFormatting -UiObject $VmListBox -Formattings $VmListBoxFormatting
    $VmListBox.CheckOnClick = $true
    $VmListBox.Font = "Microsoft Sans Serif, $(10 * $HeightRatio)"
    $VmListBox.Add_SelectedIndexChanged({Disable-RestOfOptions})

    $VmLabelFormatting = @{"location"=@(10, 233); "width"=25; "height"=10}
    Add-CommonFormatting -UiObject $VmLabel -Formattings $VmLabelFormatting
    $VmLabel.text = "Choose virtual machine(s)"
    $VmLabel.AutoSize = $true
    $VmLabel.Tag = "Select the virtual machines whose Disk Encryption Keys need to be copied to DR location."
    $VmLabel.Add_MouseHover({Show-Help})

    $BekDropDownFormatting = @{"location"=@(10, 445); "width"=424; "height"=30}
    Add-CommonFormatting -UiObject $BekDropDown -Formattings $BekDropDownFormatting
    $BekDropDown.DropDownHeight = 150 * $HeightRatio
    $BekDropDown.Font = "Microsoft Sans Serif, $(10 * $HeightRatio)"

    $BekLabelFormatting = @{"location"=@(10, 420); "width"=25; "height"=10}
    Add-CommonFormatting -UiObject $BekLabel -Formattings $BekLabelFormatting
    $BekLabel.text = "Target Disk Encryption Key vault"
    $BekLabel.AutoSize = $true
    $BekLabel.Tag = "Specify the target disk encryption key vault in DR region where the keys will be copied to."
    $BekLabel.Add_MouseHover({Show-Help})

    $KekDropDownFormatting = @{"location"=@(10, 506); "width"=424; "height"=30}
    Add-CommonFormatting -UiObject $KekDropDown -Formattings $KekDropDownFormatting
    $KekDropDown.DropDownHeight = 150 * $HeightRatio
    $KekDropDown.Font = "Microsoft Sans Serif, $(10 * $HeightRatio)"

    $KekLabelFormatting = @{"location"=@(10, 480); "width"=25; "height"=10}
    Add-CommonFormatting -UiObject $KekLabel -Formattings $KekLabelFormatting
    $KekLabel.text = "Target Key Encryption Key vault"
    $KekLabel.AutoSize = $true
    $KekLabel.Tag = "Specify the target key encryption key vault in DR region where the keys will be copied to."
    $KekLabel.Add_MouseHover({Show-Help})

    $LocationDropDownFormatting = @{"location"=@(10, 386); "width"=424; "height"=20}
    Add-CommonFormatting -UiObject $LocationDropDown -Formattings $LocationDropDownFormatting
    $LocationDropDown.DropDownHeight = 150 * $HeightRatio
    $LocationDropDown.Font = "Microsoft Sans Serif, $(10 * $HeightRatio)"
    $LocationDropDown.Add_SelectedIndexChanged({Get-KeyVaults})

    $LocationLabelFormatting = @{"location"=@(10, 360); "width"=25; "height"=10}
    Add-CommonFormatting -UiObject $LocationLabel -Formattings $LocationLabelFormatting
    $LocationLabel.text = "Target Location"
    $LocationLabel.AutoSize = $true
    $LocationLabel.Tag = "Select the Disaster Recovery (DR) location."
    $LocationLabel.Add_MouseHover({Show-Help})

    $LoadingLabelFormatting = @{"location"=@(150, 535); "width"=25; "height"=10}
    Add-CommonFormatting -UiObject $LoadingLabel -Formattings $LoadingLabelFormatting
    $LoadingLabel.text = ""
    $LoadingLabel.AutoSize = $true
    $LoadingLabel.Enabled = $true
    $LoadingLabel.Add_MouseHover({Show-Help})

    $SelectButtonFormatting = @{"location"=@(184, 580); "width"=75; "height"=30}
    Add-CommonFormatting -UiObject $SelectButton -Formattings $SelectButtonFormatting
    $SelectButton.BackColor = "#eeeeee"
    $SelectButton.text = "Select"
    $SelectButton.Add_Click({Get-AllSelections})

    $MsLogo = New-Object System.Windows.Forms.PictureBox
    $MsLogo.width = 140 * $WidthRatio
    $MsLogo.height = 80 * $HeightRatio
    $MsLogo.location = New-Object System.Drawing.Point($(150 * $WidthRatio), $(10 * $HeightRatio))
    $MsLogo.imageLocation = "https://c.s-microsoft.com/en-us/CMSImages/ImgOne.jpg?version=D418E733-821C-244F-37F9-DC865BDEFEC0"
    $MsLogo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::zoom

    # Populating the subscription dropdown and launching the form

    $Subscriptions = Get-AzSubscription

    if ($null -eq $Subscriptions -or 1 -gt $Subscriptions.Count)
    {
        throw [Errors]::NoSubscriptionsFound((Get-AzContext).Tenant.Id)
    }

    [array]$SubscriptionArray = ($Subscriptions.Name | Sort-Object)

    foreach ($Item in $SubscriptionArray)
    {
        $SuppressOutput = $SubscriptionDropDown.Items.Add($Item)
    }

    $Longest = ($SubscriptionArray | Sort-Object Length -Descending)[0]
    $SubscriptionDropDown.DropDownWidth = ([System.Windows.Forms.TextRenderer]::MeasureText($Longest, `
        $SubscriptionDropDown.Font).Width, $SubscriptionDropDown.Width | Measure-Object -Maximum).Maximum

    $UserInputForm.controls.AddRange($FormElements.Values + $LoadingLabel)
    $UserInputForm.controls.AddRange($MsLogo)
    [void]$UserInputForm.ShowDialog()
}
#endregion

### <summary>
### Encrypts the secret based on the key provided.
### </summary>
### <param name="DecryptedValue">Decrypted secret value.</param>
### <param name="EncryptedAlgorithm">Name of the encryption algorithm used.</param>
### <param name="AccessToken">Access token for the key vault.</param>
### <param name="KeyId">Id of the key to be used for encryption.</param>
function Encrypt-Secret(
    $DecryptedValue,
    [string]$EncryptedAlgorithm,
    [string]$AccessToken,
    [string]$KeyId)
{
    $Body = @{
        'value' = $DecryptedValue
        'alg'   = $EncryptedAlgorithm}

    $BodyJson = ConvertTo-Json -InputObject $Body

    $Params = @{
        ContentType = [ConstantStrings]::contentType
        Headers     = @{
            [ConstantStrings]::authHeader = [ConstantStrings]::tokenType + " " + $AccessToken }
        Method      = [ConstantStrings]::httpPost
        URI         = "$KeyId" + '/encrypt?api-version=7.1'
        Body        = $BodyJson}

    try
    {
        $OutputLogger.Log(
            $MyInvocation,
            "Starting REST call - " + $Params.URI,
            [LogType]::INFO)
        $Response = Invoke-RestMethod @Params
    }
    catch
    {
        $errorStr = Out-String -InputObject $PSItem

        Write-Verbose "`nEncrypt failure: `n$errorStr"
        throw [Errors]::SecretEncryptionFailed($errorStr)
    }
    finally
    {
        Write-Verbose "`nEncrypt request: `n$(Out-String -InputObject $Params)"
        Write-Verbose "`nEncrypt resonse: `n$(Out-String -InputObject $Response)"
    }

    return $Response
}

### <summary>
### Decrypts the secret based on the key provided.
### </summary>
### <param name="EncryptedValue">Encrypted secret value.</param>
### <param name="EncryptedAlgorithm">Name of the encryption algorithm used.</param>
### <param name="AccessToken">Access token for the key vault.</param>
### <param name="KeyId">Id of the key to be used for decryption.</param>
function Decrypt-Secret(
    $EncryptedValue,
    [string]$EncryptedAlgorithm,
    [string]$AccessToken,
    [string]$KeyId)
{
    $Body = @{
        'value' = $EncryptedValue
        'alg'   = $EncryptedAlgorithm}

    $BodyJson = ConvertTo-Json -InputObject $Body

    $Params = @{
        ContentType = [ConstantStrings]::contentType
        Headers     = @{
            [ConstantStrings]::authHeader = [ConstantStrings]::tokenType + " " + $AccessToken }
        Method      = [ConstantStrings]::httpPost
        URI         = "$KeyId" + '/decrypt?api-version=7.1'
        Body        = $BodyJson}

    try
    {
        $OutputLogger.Log(
            $MyInvocation,
            "Starting REST call - " + $Params.URI,
            [LogType]::INFO)
        $Response = Invoke-RestMethod @Params
    }
    catch
    {
        $errorStr = Out-String -InputObject $PSItem

        Write-Verbose "`nDecrypt failure: `n$errorStr"
        throw [Errors]::SecretDecryptionFailed($errorStr)
    }
    finally
    {
        Write-Verbose "`nDecrypt request: `n$(Out-String -InputObject $Params)"
        Write-Verbose "`nDecrypt resonse: `n$(Out-String -InputObject $Response)"
    }

    return $Response
}

#Region Utilities

### <summary>
### Extracts the labelled tokens from the ARM id.
### </summary>
### <param name="armId">Resource ARM id.</param>
### <returns>Labelled tokens in lowercase.</returns>
function Extract-LabelledTokensFromId([string] $armId)
{
    if ([string]::IsNullOrEmpty($armId))
    {
        throw [Errors]::InvalidArmIdInput()
    }

    $tokens = $armId.ToLower().Trim('/').Split('/')

    if (($tokens.Count % 2) -ne 0)
    {
        throw [Errors]::InvalidLabelTokenInput($armId.ToLower().Trim('/'), $tokens.Count)
    }

    $labelledTokens = [System.Collections.Hashtable]::New()

    for ($index=0; $index -lt $tokens.Count; $index += 2)
    {
        $labelledTokens.Add($tokens[$index], $tokens[$index + 1])
    }

    return $labelledTokens
}

### <summary>
### Extracts the resource name from ARM id.
### </summary>
### <param name="armId">Resource ARM id.</param>
### <returns>Resource name.</returns>
function Extract-ParentResourceNameFromId([string] $armId)
{
    if ([string]::IsNullOrEmpty($armId))
    {
        throw [Errors]::InvalidArmIdInput()
    }

    $tokens = $armId.Trim('/').Split('/')

    if ($tokens.Count -lt 9)
    {
        throw [Errors]::InvalidArmIdInput()
    }

    return $tokens[-3]
}

### <summary>
### Extracts the resource group from ARM id.
### </summary>
### <param name="armId">Resource ARM id.</param>
### <returns>Resource group name.</returns>
function Extract-ResourceGroupFromId([string] $armId)
{
    $tokens = Extract-LabelledTokensFromId -ArmId $armId

    return $tokens[[ConstantStrings]::resourceGroups.ToLower()]
}

### <summary>
### Extracts the resource name from ARM id.
### </summary>
### <param name="armId">Resource ARM id.</param>
### <returns>Resource name.</returns>
function Extract-ResourceNameFromId([string] $armId)
{
    if ([string]::IsNullOrEmpty($armId))
    {
        throw [Errors]::InvalidArmIdInput()
    }

    $tokens = $armId.Trim('/').Split('/')

    return $tokens[-1]
}

### <summary>
### Extracts the resource type from ARM id.
### </summary>
### <param name="armId">Resource ARM id.</param>
### <returns>Resource name.</returns>
function Extract-ResourceTypeFromId([string] $armId)
{
    if ([string]::IsNullOrEmpty($armId))
    {
        throw [Errors]::InvalidArmIdInput()
    }

    $tokens = $armId.Trim('/').Split('/')

    return $tokens[-2]
}

### <summary>
### Forms the url string from the tokens passed.
### </summary>
### <param name="apiVersion">Api version.</param>
### <param name="tokens">Url string tokens.</param>
### <returns>Url string.</returns>
function Get-UrlString([string] $apiVersion, [string[]]$tokens)
{
    if ([string]::IsNullOrEmpty($apiVersion))
    {
        throw [Errors]::ApiVersionMissing()
    }

    if ($null -eq $tokens)
    {
        throw [Errors]::UrlTokensMissing()
    }

    $context = Get-AzContext

    $url = ($context.Environment.ResourceManagerUrl).TrimEnd('/') + '/'
    $url += $tokens.Trim('/') -Join '/'
    $url = $url.Trim('/')
    $url += '?' + [ConstantStrings]::apiVersion + '=' + $apiVersion

    return $url
}
#EndRegion

#Region REST

### <summary>
### Invokes ARM call in a uniform manner.
### </summary>
### <param name="parameters">REST call parameters.</param>
### <returns>Response.</returns>
function Invoke-ArmCall($parameters)
{
    try
    {
        $response = Invoke-RestMethod @parameters
    }
    catch
    {
        throw [Errors]::ArmCallFailed(
            $(Out-String -InputObject $PSItem),
            $(Out-String -InputObject $parameters))
    }
    finally
    {
        Write-Verbose "`nRequest: `n$(Out-String -InputObject $Params)"
        Write-Verbose "`nResonse: `n$(Out-String -InputObject $Response)"
    }

    return $response
}

### <summary>
### Gets the resource links at resource group scope.
### </summary>
### <param name="resourceGroupName">Resource group name.</param>
### <param name="filterBySourceType">Type to filter resource link sources by.</param>
### <param name="filterByTargetType">Type to filter resource link targets by.</param>
### <returns>List of resource link source id to target id mappings.</returns>
function Get-ResourceLinks(
    [string] $resourceGroupName,
    [string] $filterBySourceType,
    [string] $filterByTargetType)
{
    Write-Host -ForegroundColor Green "Fetching resource links under '$resourceGroupName'" `
        "resource group..."

    $context = Get-AzContext
    $token = Get-AzAccessToken -ResourceTypeName Arm
    $url = Get-UrlString -ApiVersion $([ConstantStrings]::resourceLinksApiVersion) -Tokens `
        @(
            [ConstantStrings]::subscriptions,
            $context.Subscription.Id,
            [ConstantStrings]::resourceGroups,
            $resourceGroupName,
            [ConstantStrings]::providers,
            [ConstantStrings]::resourcesProvider,
            [ConstantStrings]::resourceLinks
        )

    $params = @{
        ContentType = [ConstantStrings]::contentType
        Headers     = @{
            [ConstantStrings]::authHeader = "Bearer $($token.Token)"}
        Method      = [ConstantStrings]::httpGet
        URI         = $url
    }

    $response = Invoke-ArmCall -Parameters $params

    if ($null -eq $response)
    {
        return $null
    }

    $properties = $response.value.properties

    $OutputLogger.LogObject(
        $MyInvocation,
        $properties,
        $null,
        [LogType]::INFO)

    if (-not [string]::IsNullOrEmpty($filterBySourceType))
    {
        $properties = $properties | `
            Where-Object {
                $(Extract-ResourceTypeFromId -ArmId $_.SourceId) -like $filterBySourceType
            }
    }

    if (-not [string]::IsNullOrEmpty($filterByTargetType))
    {
        $properties = $properties | `
            Where-Object {
                $(Extract-ResourceTypeFromId -ArmId $_.TargetId) -like $filterByTargetType
            }
    }

    return $properties
}
#EndRegion

### <summary>
###  Gets a list of source information objects from list of VM names.
### </summary>
### <param name="VmArray">Gets the list of VM names.</param>
### <param name="SourceResourceGroupName">Gets the source resource group name.</param>
### <return>List of source information objects.</return>
function New-Sources {
    param (
        [string[]] $VmArray,
        [string] $SourceResourceGroupName
    )

    $SourceList = @()

    foreach($VmName in $VmArray)
    {
        $Vm = Get-AzVm -ResourceGroupName $SourceResourceGroupName -Name $VmName

        if (($null -eq $Vm.StorageProfile.OsDisk.EncryptionSettings) -or `
            (-not $Vm.StorageProfile.OsDisk.EncryptionSettings.Enabled))
        {
            $OutputLogger.Log(
                $MyInvocation,
                "VM - $($Vm.Name), is One-Pass Encrypted.",
                [LogType]::INFO)

            $Vm = Get-AzVm -ResourceGroupName $SourceResourceGroupName -Name $VmName -Status
            $Disks = $Vm.Disks

            for($i=0; $i -lt $Disks.Count; $i++)
            {
                $Disk = $Disks[$i]
                $Source = [Source]::new($VmName, $Disk.Name)

                if($null -ne $Disks[$i].EncryptionSettings)
                {
                    $Source.Bek = $Disk.EncryptionSettings[0].DiskEncryptionKey
                    $Source.Kek = $Disk.EncryptionSettings[0].KeyEncryptionKey

                    $SourceList += $Source
                }
                else
                {
                    $OutputLogger.Log(
                        $MyInvocation,
                        "Virtual machine $VmName encrypted but disk ($($Disk.Name)) not encrypted.",
                        [LogType]::OUTPUT)
                }
            }

            Write-Host "`n"
        }
        else
        {
            $OutputLogger.Log(
                $MyInvocation,
                "VM - $($Vm.Name), is Two-Pass Encrypted.",
                [LogType]::INFO)

            # Passing null string inorder to differentiate between 1-pass and 2-pass from the logs
            $Source = [Source]::new($VmName, "")

            $Source.Bek = $Vm.StorageProfile.OsDisk.EncryptionSettings.DiskEncryptionKey
            $Source.Kek = $Vm.StorageProfile.OsDisk.EncryptionSettings.KeyEncryptionKey

            $SourceList += $Source
        }
    }

    return $SourceList
}

### <summary>
### Copies all access policies from source to newly created target key vault.
### </summary>
### <param name="TargetKeyVaultName">Name of the target key vault.</param>
### <param name="TargetResourceGroupName">Name of the target resource group.</param>
### <param name="SourceKeyVaultName">Name of the source key vault.</param>
### <param name="SourceAccessPolicies">List of the source access policies to be copied.</param>
function Copy-AccessPolicies(
    [string]$TargetKeyVaultName,
    [string]$TargetResourceGroupName,
    [string]$SourceKeyVaultName,
    $SourceAccessPolicies)
{
    $Index = 0

    foreach ($AccessPolicy in $SourceAccessPolicies)
    {
        $SetPolicyCommand = "Set-AzKeyVaultAccessPolicy -VaultName $TargetKeyVaultName" + `
        " -ResourceGroupName $TargetResourceGroupName -ObjectId $($AccessPolicy.ObjectId)" + ' '

        if ($AccessPolicy.Permissions.Keys)
        {
            $AddKeys = " -PermissionsToKeys $($AccessPolicy.Permissions.Keys -join ',')"
            $SetPolicyCommand += $AddKeys
        }

        if ($AccessPolicy.Permissions.Secrets)
        {
            $AddSecrets = " -PermissionsToSecrets $($AccessPolicy.Permissions.Secrets -join ',')"
            $SetPolicyCommand += $AddSecrets
        }

        if ($AccessPolicy.Permissions.Certificates)
        {
            $AddCertificates = " -PermissionsToCertificates $($AccessPolicy.Permissions.Certificates -join ',')"
            $SetPolicyCommand += $AddCertificates
        }

        if ($AccessPolicy.Permissions.Storage)
        {
            $AddStorage = " -PermissionsToStorage $($AccessPolicy.Permissions.Storage -join ',')"
            $SetPolicyCommand += $AddStorage
        }

        try
        {
            Invoke-Expression -Command $SetPolicyCommand
        }
        catch
        {
            $WarningString = "Unable to copy access policy for Object Id: $($AccessPolicy.ObjectId) because " + `
                "of the following issue:`n $($PSItem.Exception.Message)"
            Write-Warning $WarningString
            $OutputLogger.LogObject(
                $MyInvocation,
                $PSItem,
                "Unable to copy access policy for Object Id: $($AccessPolicy.ObjectId)",
                [LogType]::WARNING)
        }

        $Index++
        Write-Progress -Activity "Copying access policies from $SourceKeyVaultName to $TargetKeyVaultName" `
            -Status "Access Policy $Index of $($SourceAccessPolicies.Count)" `
            -PercentComplete ($Index / $SourceAccessPolicies.Count * 100)
    }
}

### <summary>
### Compares the key vault permissions with minimum required.
### </summary>
### <param name="ResourceObject"Switch to check if access policies list obtained from resource object.</param>
### <param name="KeyVaultName">Name of the key vault which is to be checked.</param>
### <param name="PermissionsRequired">List of minimum permissions required.</param>
### <param name="AccessPolicies">List of the key vault's access policies.</param>
function Compare-Permissions(
    [switch] $ResourceObject,
    [string] $KeyVaultName,
    [string[]] $PermissionsRequired,
    $AccessPolicies)
{
    $PermissionsType = 'keys'

    foreach ($Policy in $AccessPolicies)
    {
        if ($Policy.ObjectId -eq $UserId)
        {
            $OutputLogger.LogObject(
                $MyInvocation,
                $Policy,
                "Access policy for $UserId",
                [LogType]::INFO)

            if($ResourceObject)
            {
                $Permissions = $Policy.Permissions.Keys

                if($Secret)
                {
                    $Permissions = $Policy.Permissions.Secrets
                    $PermissionsType = "secrets"
                }

                $Permissions = $Permissions | ForEach-Object{$_.ToLower()}

                if (-not $Permissions -or (($PermissionsRequired | ForEach-Object { $Permissions.Contains($_)}) -contains $false))
                {
                    throw [Errors]::MissingPermissions(
                        $PermissionsType,
                        $KeyVaultName,
                        $PermissionsRequired)
                }
            }
            else
            {
                $Permissions = $Policy.PermissionsToKeys

                if($Secret)
                {
                    $Permissions = $Policy.PermissionsToSecrets
                    $PermissionsType = "secrets"
                }

                $Permissions = $Permissions | ForEach-Object{$_.ToLower()}

                if (-not $Permissions -or (($PermissionsRequired | ForEach-Object { $Permissions.Contains($_)}) -contains $false))
                {
                    throw [Errors]::MissingPermissions(
                        $PermissionsType,
                        $KeyVaultName,
                        $PermissionsRequired)
                }
            }

            return
        }
    }

    throw [Errors]::UserMissingAccess($UserId, $KeyVaultName, $AccessPolicies.ObjectId)
}

### <summary>
### Conducts few prerequisite steps checking permissions and existence of the target key vaults.
### </summary>
### <param name="Secret">Whether the prerequisite check is happening for secrets.</param>
### <param name="EncryptionKey">Disk or key encryption key whose key vault needs to be checked.</param>
### <param name="TargetKeyVaultName">Name of the target key vault.</param>
### <param name="TargetPermissions">Minimum permissions required for keys and secrets in target key vault.</param>
### <param name="IsKeyVaultNew">Bool reference to whether a new target vault is created or not.</param>
function Conduct-TargetKeyVaultPreReq(
    [switch] $Secret,
    $EncryptionKey,
    $TargetKeyVaultName,
    $TargetPermissions,
    [ref]$IsKeyVaultNew)
{
    try
    {
        $TargetKeyVault = Get-AzKeyVault -VaultName $TargetKeyVaultName
    }
    catch
    {
        # Target key vault does not exist
        $TargetKeyVault = $null

        $OutputLogger.Log(
            $MyInvocation,
            "Target Key Vault - $TargetKeyVaultName, doesn't exist.",
            [LogType]::INFO)
    }

    if (-not $TargetKeyVault)
    {
        $IsKeyVaultNew.Value = $true

        $OutputLogger.Log(
            $MyInvocation,
            "Creating key vault $TargetKeyVaultName",
            [LogType]::OUTPUT)

        $KeyVaultResource = Get-AzResource -ResourceId $EncryptionKey.SourceVault.Id
        $TargetResourceGroupName = "$($KeyVaultResource.ResourceGroupName)" + "-asr"

        try
        {
            $TargetResourceGroup = Get-AzResourceGroup -Name $TargetResourceGroupName
        }
        catch
        {
            # Target resource group does not exist
            $TargetResourceGroup = $null

            $OutputLogger.Log(
                $MyInvocation,
                "Target RG - $TargetResourceGroupName, doesn't exist.",
                [LogType]::INFO)
        }

        if (-not $TargetResourceGroup)
        {
            New-AzResourceGroup -Name $TargetResourceGroupName -Location $TargetLocation
        }

        $SuppressOutput = New-AzKeyVault -VaultName $TargetKeyVaultName -ResourceGroupName `
            $TargetResourceGroupName -Location $TargetLocation `
            -EnabledForDeployment:$KeyVaultResource.Properties.EnabledForDeployment `
            -EnabledForTemplateDeployment:$KeyVaultResource.Properties.EnabledForTemplateDeployment `
            -EnabledForDiskEncryption:$KeyVaultResource.Properties.EnabledForDiskEncryption `
            -Sku $KeyVaultResource.Properties.Sku.name -Tag $KeyVaultResource.Tags
    }
    else
    {
        # Check only when existing BEK key vault or existing KEK key vault different from secret key vault.
        if($Secret -or (-not $IsBekKeyVaultNew) -or ($TargetBekVault -ne $TargetKeyVaultName))
        {
            # Checking whether user has required permissions to the Target Key vault
            Compare-Permissions -KeyVaultName $TargetKeyVault.VaultName -PermissionsRequired $TargetPermissions `
            -AccessPolicies $TargetKeyVault.AccessPolicies
        }
    }
}

### <summary>
### Conducts few prerequisite steps checking permissions of source key vault.
### </summary>
### <param name="Secret">Whether the prerequisite check is happening for secrets.</param>
### <param name="EncryptionKey">Disk or key encryption key whose key vault needs to be checked.</param>
### <param name="SourcePermissions">Minimum permissions required for keys and secrets in source key vault.</param>
### <return name="KeyVaultResource">Source key vault object associated with the encryption key</return>
function Conduct-SourceKeyVaultPreReq(
    [switch] $Secret,
    $EncryptionKey,
    $SourcePermissions)
{
    $KeyVaultResource = Get-AzResource -ResourceId $EncryptionKey.SourceVault.Id

    # Checking whether user has required permissions to the Source Key vault
    Compare-Permissions -KeyVaultName $KeyVaultResource.Name -PermissionsRequired $SourcePermissions `
        -AccessPolicies $KeyVaultResource.Properties.AccessPolicies -ResourceObject

    return $KeyVaultResource
}

### <summary>
### Create a secret in the target key vault.
### </summary>
### <param name="Secret">Value of the secret text.</param>
### <param name="ContentType">Type of secret to be created - Wrapped BEK or BEK.</param>
function Create-Secret(
    $Secret,
    [string]$ContentType)
{
    $SecureSecret = ConvertTo-SecureString $Secret -AsPlainText -Force
    $OutputSecret = Set-AzKeyVaultSecret -VaultName $TargetBekVault -Name $BekSecret.Name -SecretValue `
        $SecureSecret -tags $BekTags -ContentType $ContentType

    $OutputLogger.Log(
        $MyInvocation,
        "Copying 'Disk Encryption Key' for '$SourceName'.",
        [LogType]::OUTPUT)
    $OutputLogger.Log(
        $MyInvocation,
        "TargetBEKVault: $TargetBekVault",
        [LogType]::OUTPUT)
    $OutputLogger.Log(
        $MyInvocation,
        "TargetBEKId: $($OutputSecret.Id)",
        [LogType]::OUTPUT)
}

### <summary>
### Create a secret in the target key vault.
### </summary>
### <param name="MoveCollection">Move collection.</param>
### <param name="TargetBekVaultName">Target BEK vault name.</param>
### <param name="TargetKekVaultName">Target BEK vault name.</param>
function Add-ResourceMoverMSIAccessPolicy(
    $MoveCollection,
    [string] $TargetBekVaultName,
    [string] $TargetKekVaultName)
{
    if ([string]::IsNullOrEmpty($MoveCollection.IdentityPrincipalId))
    {
        $OutputLogger.Log(
            $MyInvocation,
            "Move collection- $($MoveCollection.Name), has no MSI assigned." + `
            "Identity type - $($MoveCollection.IdentityType).",
            [LogType]::OUTPUT)
        return
    }

    $OutputLogger.Log(
        $MyInvocation,
        "Giving move collection- $($MoveCollection.Name), access to BEK vault - " + `
        "$($TargetBekVaultName). Adding access policy for - $($MoveCollection.IdentityPrincipalId)",
        [LogType]::OUTPUT)

    $ObjectId = $MoveCollection.IdentityPrincipalId

    Set-AzKeyVaultAccessPolicy -VaultName $TargetBekVaultName -ObjectId $ObjectId `
        -PermissionsToKeys get, list -PermissionsToSecrets get, list

    if (-not [string]::IsNullOrEmpty($TargetKekVaultName))
    {
        $OutputLogger.Log(
            $MyInvocation,
            "Giving move collection- $($MoveCollection.Name), access to KEK vault - " + `
            "$($TargetKekVaultName). Adding access policy for - $ObjectId",
            [LogType]::OUTPUT)

        Set-AzKeyVaultAccessPolicy -VaultName $TargetKekVaultName -ObjectId $ObjectId `
            -PermissionsToKeys get, list -PermissionsToSecrets get, list
    }
}

### <summary>
### Main flow of code for copying keys.
### </summary>
### <return name="CompletedList">List of VMs for which CopyKeys ran successfully</return>
function Start-CopyKeys
{
    $Context = Get-AzContext
    $Subscriptions = Get-AzSubscription -ErrorAction SilentlyContinue

    if($null -eq $Context -or $null -eq $Subscriptions)
    {
        $SuppressOutput = Login-AzAccount -ErrorAction Stop
    }

    $CompletedList = @()
    $UserInputs = New-Object System.Collections.Hashtable
    Write-Verbose "Starting user interface to get inputs"
    Generate-UserInterface

    $ResourceGroupName = $UserInputs["ResourceGroupName"]
    $VmNameArray = $UserInputs["VmNameArray"]
    $TargetLocation = $UserInputs["TargetLocation"]
    $TargetBekVault = $UserInputs["TargetBekVault"]
    $TargetKekVault = $UserInputs["TargetKekVault"]


    if($null -eq $Context)
    {
        $Context = Get-AzContext
    }

    $OutputLogger.Log(
        $MyInvocation,
        "SubscriptionId: $($Context.Subscription.Id)",
        [LogType]::INFO)
    $OutputLogger.LogObject(
        $MyInvocation,
        $UserInputs,
        "User inputs.",
        [LogType]::INFO)

    $TenantId = $Context.Tenant.Id
    $AccessToken = (Get-AzAccessToken -ResourceTypeName KeyVault).Token
    $UserPrincipalName = (Get-AzContext).Account.Id
    $UserId = (Get-AzAdUser -UserPrincipalName $UserPrincipalName).Id

    $OutputLogger.Log(
        $MyInvocation,
        "`nStarting CopyKeys for UserId: $UserId, UserPrincipalName: $UserPrincipalName",
        [LogType]::OUTPUT)

    $IsFirstBekVault = $IsFirstKekVault = $true
    $FirstBekVault = $FirstKekVault = $null
    $IsBekKeyVaultNew = $IsKekKeyVaultNew = $false

    $SourceList = New-Sources -VmArray $VmNameArray -SourceResourceGroupName $ResourceGroupName

    foreach($Source in $SourceList)
    {
        try
        {
            $VmName = $Source.Name

            # Only VMName as source name if 2 pass else VMName - DiskName
            $SourceName = if ([string]::IsNullOrEmpty($Source.DiskName)) { $Source.Name } else `
                { $Source.Name + " - " + $Source.DiskName }

            # If output diskName is empty -> 2-pass else 1-pass
            $OutputLogger.LogObject(
                $MyInvocation,
                $Source,
                "Source information.",
                [LogType]::INFO)

            $Bek = $Source.Bek
            $Kek = $Source.Kek

            if (-not $Bek)
            {
                throw [Errors]::DiskEncryptionInfoMissing($VmName, $Source.DiskName)
            }

            $BekKeyVaultResource = Conduct-SourceKeyVaultPreReq -EncryptionKey $Bek -SourcePermissions `
                $SourceSecretsPermissions -Secret

            $OutputLogger.Log(
                $MyInvocation,
                "VM/Disk name: $SourceName",
                [LogType]::OUTPUT)
            $OutputLogger.Log(
                $MyInvocation,
                "SourceBEKVault: $($BekKeyVaultResource.Name)",
                [LogType]::OUTPUT)
            $OutputLogger.Log(
                $MyInvocation,
                "SourceBEKId: $($Bek.SecretUrl)",
                [LogType]::OUTPUT)

            if ($IsFirstBekVault)
            {
                Conduct-TargetKeyVaultPreReq -EncryptionKey $Bek -TargetKeyVaultName $TargetBekVault `
                    -IsKeyVaultNew ([ref]$IsBekKeyVaultNew) -TargetPermissions $TargetSecretsPermissions -Secret

                $FirstBekVault = $BekKeyVaultResource
                $IsFirstBekVault = $false
            }

            # Getting the BEK secret value text.
            [uri]$Url = $Bek.SecretUrl
            $BekSecret = Get-AzKeyVaultSecret -VaultName $BekKeyVaultResource.Name -Version $Url.Segments[3] `
                -Name $Url.Segments[2].TrimEnd("/")
            $BekSecretBase64 = $BekSecret.SecretValueText

            if ([string]::IsNullOrEmpty($BekSecretBase64))
            {
                $BekSecretBase64 = Get-AzKeyVaultSecret -VaultName $BekKeyVaultResource.Name -Version $Url.Segments[3] `
                -Name $Url.Segments[2].TrimEnd("/") -AsPlainText
            }

            $BekTags = $BekSecret.Attributes.Tags

            if ($Kek)
            {
                $KekKeyVaultResource = Conduct-SourceKeyVaultPreReq -EncryptionKey $Kek `
                    -SourcePermissions $SourceKeysPermissions

                $OutputLogger.Log(
                    $MyInvocation,
                    "VM/Disk name: $SourceName",
                    [LogType]::INFO)
                $OutputLogger.Log(
                    $MyInvocation,
                    "SourceKEKVault: $($KekKeyVaultResource.Name)",
                    [LogType]::OUTPUT)
                $OutputLogger.Log(
                    $MyInvocation,
                    "SourceKEKId: $($Kek.KeyUrl)",
                    [LogType]::OUTPUT)

                if ($IsFirstKekVault)
                {
                    Conduct-TargetKeyVaultPreReq -EncryptionKey $Kek -TargetKeyVaultName $TargetKekVault `
                        -IsKeyVaultNew ([ref]$IsKekKeyVaultNew) -TargetPermissions $TargetKeysPermissions

                    if ($IsKekKeyVaultNew -or ($IsBekKeyVaultNew -and ($TargetBekVault -eq $TargetKekVault)))
                    {
                        # In case of new target key vault, initially encrypt and create permissions are given
                        # which are then updated with all actual permissions during Copy-AccessPolicies
                        Set-AzKeyVaultAccessPolicy -VaultName $TargetKekVault -ObjectId $UserId `
                            -PermissionsToKeys $TargetKeysPermissions
                    }

                    $FirstKekVault = $KekKeyVaultResource
                    $IsFirstKekVault = $false
                }

                $BekEncryptionAlgorithm = $BekSecret.Attributes.Tags.DiskEncryptionKeyEncryptionAlgorithm

                [uri]$Url = $Kek.KeyUrl
                $KekKey = Get-AzKeyVaultKey -VaultName $KekKeyVaultResource.Name -Version $Url.Segments[3] `
                    -Name $Url.Segments[2].TrimEnd("/")

                if(-not $Kekkey)
                {
                    throw [Errors]::KeyMissing(
                        $Url.Segments[2].TrimEnd("/"),
                        $Url.Segments[3],
                        $KekKeyVaultResource.Name)
                }

                $NewKekKey = Get-AzKeyVaultKey -VaultName $TargetKekVault -Name $KekKey.Name `
                    -ErrorAction SilentlyContinue

                if (-not $NewKekKey)
                {
                    # Creating the new KEK
                    $NewKekKey = Add-AzKeyVaultKey -VaultName $TargetKekVault -Name $KekKey.Name `
                        -Destination Software -Size $Kekkey.KeySize

                    $OutputLogger.Log(
                        $MyInvocation,
                        "Copying 'Key Encryption Key' for '$SourceName'",
                        [LogType]::OUTPUT)
                }
                else
                {
                    # Using existing KEK
                    $OutputLogger.Log(
                        $MyInvocation,
                        "Using existing key $($KekKey.Name) for '$SourceName'.",
                        [LogType]::OUTPUT)
                }

                $OutputLogger.Log(
                    $MyInvocation,
                    "TargetKEKVault: $TargetKekVault",
                    [LogType]::OUTPUT)
                $OutputLogger.Log(
                    $MyInvocation,
                    "TargetKEKId: $($NewKekKey.Id)",
                    [LogType]::OUTPUT)

                # Decrypting Wrapped-BEK
                $DecryptedSecret = Decrypt-Secret -EncryptedValue $BekSecretBase64 -EncryptedAlgorithm `
                    $BekEncryptionAlgorithm -AccessToken $AccessToken -KeyId $Kekkey.Key.Kid

                # Encrypting BEK with new KEK
                $EncryptedSecret = Encrypt-Secret -DecryptedValue $DecryptedSecret.value -EncryptedAlgorithm `
                    $BekEncryptionAlgorithm -AccessToken $AccessToken -KeyId $NewKekKey.Key.Kid

                $BekTags.DiskEncryptionKeyEncryptionKeyURL = $NewKekKey.Key.Kid
                Create-Secret -Secret $EncryptedSecret.value -ContentType "Wrapped BEK"
            }
            else
            {
                Create-Secret -Secret $BekSecretBase64 -ContentType "BEK"
            }

            $CompletedList += $SourceName
        }
        catch
        {
            Write-Warning "CopyKeys not completed for $SourceName`n`n"
            $IncompleteList[$SourceName] = $_
        }
    }

    if ($IsKekKeyVaultNew)
    {
        $OutputLogger.Log(
            $MyInvocation,
            "Copying access policies from $($FirstKekVault.Name) to $TargetKekVault.",
            [LogType]::INFO)

        # Copying access policies to new KEK target key vault
        $TargetKekRgName = "$($FirstKekVault.ResourceGroupName)" + "-asr"
        Copy-AccessPolicies -TargetKeyVaultName $TargetKekVault -TargetResourceGroupName $TargetKekRgName `
            -SourceKeyVaultName $FirstKekVault.Name -SourceAccessPolicies `
            $FirstKekVault.Properties.AccessPolicies
    }

    if ($IsBekKeyVaultNew)
    {
        $OutputLogger.Log(
            $MyInvocation,
            "Copying access policies from $($FirstBekVault.Name) to $TargetBekVault.",
            [LogType]::INFO)

        # Copying access policies to new BEK target key vault
        $TargetBekRgName = "$($FirstBekVault.ResourceGroupName)" + "-asr"
        Copy-AccessPolicies -TargetKeyVaultName $TargetBekVault -TargetResourceGroupName $TargetBekRgName `
            -SourceKeyVaultName $FirstBekVault.Name -SourceAccessPolicies `
            $FirstBekVault.Properties.AccessPolicies
    }

    if ($AllowResourceMoverAccess)
    {
        $ResourceLinks = Get-ResourceLinks -ResourceGroupName $ResourceGroupName `
            -FilterBySourceType $([ConstantStrings]::vmType) -filterByTargetType `
            $([ConstantStrings]::moveResourceType)

        if ($null -eq $ResourceLinks)
        {
            $message = "None of the VMs are in any Move Collection. Skipping Resource Mover " + `
                "MSI access checks."

            Write-Warning $message
            $OutputLogger.Log(
                $MyInvocation,
                $message,
                [LogType]::WARNING)
        }
        else
        {
            $VmMCDict = @{}
            $MoveResourcesList = [System.Collections.Generic.HashSet[string]]::New()

            $SuppressOutput = $ResourceLinks | ForEach-Object { `
                    $VmMCDict.Add(
                        $(Extract-ResourceNameFromId -armId $_.sourceId),
                        $_.targetid)
                    $MoveResourcesList.Add($_.targetid)}

            $OutputLogger.LogObject(
                $MyInvocation,
                $VmMCDict,
                "Move collections -",
                [LogType]::INFO)

            foreach ($Id in $MoveResourcesList)
            {
                $MoveCollection = Get-AzResourceMoverMoveCollection -Name `
                    $(Extract-ParentResourceNameFromId -armId $Id) -ResourceGroupName `
                    $(Extract-ResourceGroupFromId -armId $Id)

                $SuppressOutput = Add-ResourceMoverMSIAccessPolicy -MoveCollection $MoveCollection `
                    -TargetBekVaultName $TargetBekVault -TargetKekVaultName $TargetKekVault
            }
        }
    }

    return $CompletedList
}

$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue"
$SourceSecretsPermissions = @('get')
$TargetSecretsPermissions = @('set')
$SourceKeysPermissions = @('get', 'decrypt')
$TargetKeysPermissions = @('get', 'create', 'encrypt')

try
{
    $StartTime = Get-Date -Format 'dd-MM-yyyy-HH-mm-ss'
    $CompletedList = @()
    $IncompleteList = New-Object System.Collections.Hashtable
    $OutputLogger = [Logger]::new('CopyKeys-' + $StartTime, $FilePath)
    $OutputLogger.Log(
        $MyInvocation,
        "CopyKeys started - $StartTime.",
        [LogType]::INFO)

    $CompletedList = Start-CopyKeys
}
catch
{
    $UnknownError = (Out-String -InputObject $PSItem)
    Write-Host -ForegroundColor Red -BackgroundColor Black $UnknownError

    $OutputLogger.LogObject(
        $MyInvocation,
        $PSItem,
        "Unknown error",
        [LogType]::ERROR)
}
finally
{
    # Summarizes the CopyKeys status for various Vms
    if($CompletedList.Count -gt 0)
    {
        $OutputLogger.Log(
            $MyInvocation,
            "`nCopyKeys succeeded for VMs:`n`t $($CompletedList -join "`n`t").",
            [LogType]::OUTPUT)
    }
    $IncompleteList.Keys | ForEach-Object {
        Write-Host -ForegroundColor Yellow "`nCopyKeys failed for $_ with - `n"
        $KnownError = Out-String -InputObject $IncompleteList[$_]
        Write-Host -ForegroundColor Red -BackgroundColor Black $KnownError

        $OutputLogger.LogObject(
            $MyInvocation,
            $IncompleteList[$_],
            "CopyKeys failed for $_.",
            [LogType]::ERROR)
    }

    $EndTime = Get-Date -Format 'dd/MM/yyyy HH:mm:ss'
    $OutputLogger.Log(
        $MyInvocation,
        "CopyKeys completed - $EndTime.",
        [LogType]::INFO)
}
