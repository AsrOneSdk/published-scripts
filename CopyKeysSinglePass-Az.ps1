### ---------------------------------------------------------------
### <script name=CopyKeys>
### <summary>
### This script copies the disk encryption keys and key encryption
### keys for Azure Disk Encryption (ADE) enabled VMs from the source
### region to disaster recovery (DR) region. Azure Site Recovery requires
### the keys to enable replication for these VMs to another region.
### </summary>
###
### <param name="FilePath">Optional parameter defining the location of the output file.</param>
### <param name="ForceDebug">Optional parameter forcing debug output without any prompts.</param>
### <param name="Verbose">Optional parameter to enable verbose logging messages.</param>
### ---------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false,
               HelpMessage="Location of the output file.")]
    [string]$FilePath = $null,

    [Parameter(Mandatory = $false,
               HelpMessage="Forces debug output without any prompts.")]
    [switch]$ForceDebug)

### Checking for module versions and assemblies.
###Requires -Modules @{ ModuleName="Az"; ModuleVersion="6.8.1" }
Set-StrictMode -Version 1.0
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

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
    ###  Log type is debug.
    ### </summary>
    DEBUG = 2

    ### <summary>
    ###  Log type is information.
    ### </summary>
    INFO = 3

    ### <summary>
    ###  Log type is output.
    ### </summary>
    OUTPUT = 4
}

### <summary>
###  Class to log results.
### </summary>
class Logger
{
    ### <summary>
    ###  Gets the output file name.
    ### </summary>
    [string]$FileName

    ### <summary>
    ###  Gets the output file location.
    ### </summary>
    [string]$FilePath

    ### <summary>
    ###  Gets the debug segment status.
    ### </summary>
    [bool]$IsDebugSegmentOpen

    ### <summary>
    ###  Gets the debug output.
    ### </summary>
    [System.Object[]]$DebugOutput

    ### <summary>
    ###  Initializes an instance of class OutLogger.
    ### </summary>
    ### <param name="Name">Name of the file.</param>
    ### <param name="Path">Local or absolute path to the file.</param>
    Logger(
        [String]$Name,
        [string]$Path)
    {
        $this.FileName = $Name
        $this.FilePath = $Path
        $this.IsDebugSegmentOpen = $false
    }

    ### <summary>
    ###  Gets the full file path.
    ### </summary>
    [String] GetFullPath()
    {
        $Path = $this.FileName + '.log'

        if($this.FilePath)
        {
            if (-not (Test-Path $this.FilePath))
            {
                Write-Warning "Invalid file path: $($this.FilePath)"
                return $Path
            }

            if ($this.FilePath[-1] -ne "\")
            {
                $this.FilePath = $this.FilePath + "\"
            }

            $Path = $this.FilePath + $Path
        }

        return $Path
    }


    ### <summary>
    ###  Gets the full file path.
    ### </summary>
    ### <param name="InvocationInfo">Gets the invocation information.</param>
    ### <param name="Message">Gets the message to be logged.</param>
    ### <param name="Type">Gets the type of log.</param>
    ### <return>String containing the formatted message - Type: DateTime ScriptName Line [Method]: Message.</return>
    [String] GetFormattedMessage(
        [System.Management.Automation.InvocationInfo] $InvocationInfo,
        [string]$Message,
        [LogType] $Type)
    {
        $DateTime = Get-Date -uFormat "%d/%m/%Y %r"
        $Line = $Type.ToString() + "`t`t: $DateTime "
        $Line += "$($InvocationInfo.ScriptName.split('\')[-1]):$($InvocationInfo.ScriptLineNumber) " + `
        "[$($InvocationInfo.InvocationName)]: "
        $Line += $Message

        return $Line
    }

    ### <summary>
    ###  Starts the debug segment.
    ### </summary>
    [Void] StartDebugLog()
    {
        $script:DebugPreference = "Continue"
        $this.IsDebugSegmentOpen = $true
    }

    ### <summary>
    ###  Stops the debug segment.
    ### </summary>
    [Void] StopDebugLog()
    {
        $script:DebugPreference = "SilentlyContinue"
        $this.IsDebugSegmentOpen = $false
    }

    ### <summary>
    ###  Gets the debug output and stores it in $DebugOutput.
    ### </summary>
    ### <param name="Command">Command whose debug output needs to be redirected.</param>
    ### <return>Command modified to get the debug output to the success stream to be stored in a variable.</return>
    [string] GetDebugOutput([string]$Command)
    {
        if ($this.IsDebugSegmentOpen)
        {
            return '$(' + $Command + ') 5>&1'
        }

        return $Command
    }

    ### <summary>
    ###  Redirects the debug output to the output file.
    ### </summary>
    ### <param name="InvocationInfo">Gets the invocation information.</param>
    ### <param name="Command">Gets the command whose debug output needs to be redirected.</param>
    ### <return>Command modified to redirect debug stream to the log file.</return>
    [string] RedirectDebugOutput(
        [System.Management.Automation.InvocationInfo] $InvocationInfo,
        [string]$Command)
    {
        if ($this.IsDebugSegmentOpen)
        {
            $this.Log(
                $InvocationInfo,
                "Debug output for command: $Command`n",
                [LogType]::DEBUG)
            return $Command + " 5>> $($this.GetFullPath())"
        }

        return $Command
    }

    ### <summary>
    ###  Appends a message to the output file.
    ### </summary>
    ### <param name="InvocationInfo">Gets the invocation information.</param>
    ### <param name="Message">Gets the message to be logged.</param>
    ### <param name="Type">Gets the type of log.</param>
    [Void] Log(
        [System.Management.Automation.InvocationInfo] $InvocationInfo,
        [string]$Message,
        [LogType] $Type)
    {
        switch ($Type) {

            ([LogType]::OUTPUT) {
                Out-File -FilePath $($this.GetFullPath()) -InputObject $Message -Append -NoClobber
                break
            }

            Default {
                Out-File -FilePath $($this.GetFullPath()) -InputObject $this.GetFormattedMessage(
                    $InvocationInfo,
                    $Message,
                    $Type) -Append -NoClobber
            }
        }
    }
}

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
        $LoadingLabel.Text = "Loading resource groups"

        Select-AzSubscription -SubscriptionName $SubscriptionName
        $ResourceProvider = Get-AzResourceProvider -ProviderNamespace Microsoft.Compute

        # Locations taken from resource type: availabilitySets instead of resource type: Virtual machines,
        # just to stay in parallel with the Portal.
        $Locations = ($ResourceProvider[0].Locations) | % { $_.Split(' ').tolower() -join ''} | sort
        $ResourceGroupLabel = $FormElements["ResourceGroupLabel"]
        $ResourceGroupDropDown = $FormElements["ResourceGroupDropDown"]
        $VmListBox = $FormElements["VmListBox"]
        $LocationDropDown = $FormElements["LocationDropDown"]
        $ResourceGroupLabel.Enabled = $true
        $ResourceGroupDropDown.Enabled = $true
        $ResourceGroupDropDown.Items.Clear()
        $VmListBox.Items.Clear()
        $LocationDropDown.Items.Clear()
        $ResourceGroupDropDown.Text = ""

        [array]$ResourceGroupArray = (Get-AzResourceGroup).ResourceGroupName | sort

        foreach ($Item in $ResourceGroupArray)
        {
            $SuppressOutput = $ResourceGroupDropDown.Items.Add($Item)
        }

        if($ResourceGroupArray)
        {
            $Longest = ($ResourceGroupArray | sort Length -Descending)[0]
            $ResourceGroupDropDown.DropDownWidth = ([System.Windows.Forms.TextRenderer]::MeasureText($Longest, `
                $ResourceGroupDropDown.Font).Width, $ResourceGroupDropDown.Width | Measure-Object -Maximum).Maximum
        }

        foreach ($Item in $Locations)
        {
            $SuppressOutput = $LocationDropDown.Items.Add($Item)
        }

        if($Locations)
        {
            $Longest = ($Locations | sort Length -Descending)[0]
            $LocationDropDown.DropDownWidth = ([System.Windows.Forms.TextRenderer]::MeasureText($Longest, `
                $LocationDropDown.Font).Width, $LocationDropDown.Width | Measure-Object -Maximum).Maximum
        }

        for ($Index = 4; $Index -lt $FormElementsList.Count; $Index++)
        {
            $FormElements[$FormElementsList[$Index]].Enabled = $false
        }

        $LoadingLabel.Text = ""
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
        $LoadingLabel.Text = ""
        $VmListBox = $FormElements["VmListBox"]
        $VmListBox.Items.Clear()
        $FormElements["VmLabel"].Enabled = $true
        $FormElements["LocationLabel"].Enabled = $true
        $VmListBox.Enabled = $true
        $LocationDropDown.Enabled = $true
        $LocationDropDown.Text = ""

        $VmList = (Get-AzVm -ResourceGroupName $ResourceGroupName) | sort Name

        foreach ($Item in $VmList)
        {
            if (($Item.Extensions -ne $null) -and
                ($Item.Extensions.Id | % {$_.split('/')[-1].tolower().contains('azurediskencryption')}) -contains $true)
            {
                $SuppressOutput = $VmListBox.Items.Add($Item.Name)
            }
        }

        if($VmList -and ($VmListBox.Items.Count -gt 0))
        {
            $Longest = ($VmList.Name | sort Length -Descending)[0]
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
            $LoadingLabel.Text = "Selected resource group does `nnot contain any encrypted VMs."
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
    $FormElements["LocationDropDown"].Text = ""
    $FormElements["BekDropDown"].Text = ""
    $FormElements["KekDropDown"].Text = ""

    for ($Index = 8; $Index -lt $FormElementsList.Count; $Index++)
    {
        if ($FormElements[$FormElementsList[$Index]].Text -ne 'Not Applicable')
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

    if ($LocationName)
    {
        $BekDropDown = $FormElements["BekDropDown"]
        $KekDropDown = $FormElements["KekDropDown"]
        $ResourceGroupDropDown = $FormElements["ResourceGroupDropDown"]
        $VmSelected = $FormElements["VmListBox"].CheckedItems
        $FailCount = 0

        if ($VmSelected)
        {
            $LoadingLabel.Text = "Loading target BEK vault"
            $Bek = $Kek = ""
            $Index = 0

            while ((-not $Kek) -and ($Index -lt $VmSelected.Count))
            {
                $Vm = Get-AzVM -ResourceGroupName `
                    $ResourceGroupDropDown.SelectedItem.ToString() -Name $VmSelected[$Index]

                if ($Vm.StorageProfile.OsDisk.EncryptionSettings -eq $null)
                {
                    $Vm = Get-AzVM -ResourceGroupName `
                        $ResourceGroupDropDown.SelectedItem.ToString() -Name $VmSelected[$Index] -Status

                    $Disks = $Vm.Disks
                    $IsNotEncrypted = $true

                    foreach ($Disk in $Disks)
                    {
                        if ($Disk.EncryptionSettings -ne $null)
                        {
                            $IsNotEncrypted = $false
                            $Bek = $Disk.EncryptionSettings[0].DiskEncryptionKey
                            $Kek = $Disk.EncryptionSettings[0].KeyEncryptionKey

                            break
                        }
                    }

                    if($IsNotEncrypted)
                    {
                        $ErrorString = "Virtual machine $VmName encrypted but encryption " + `
                            "settings details missing."
                        throw [System.MissingFieldException] $ErrorString
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
                $BekDropDown.Text = "Not Applicable"
                $BekDropDown.Enabled = $false
                $FailCount += 1
            }
            else
            {
                $BekKeyVaultName = $Bek.SourceVault.Id.Split('/')[-1] + '-asr'
                $BekKeyVault = Get-AzResource -Name $BekKeyVaultName

                if (-not $BekKeyVault)
                {
                    $BekKeyVaultName = '(new)' + $BekKeyVaultName
                    $BekDropDown.Items.Add($BekKeyVaultName)
                }

                $BekDropDown.Text = $BekKeyVaultName
            }

            $LoadingLabel.Text = "Loading target KEK vault"

            if (-not $Kek)
            {
                $KekDropDown.Text = "Not Applicable"
                $KekDropDown.Enabled = $false
                $FailCount += 1
            }
            else
            {
                $KekKeyVaultName = $Kek.SourceVault.Id.Split('/')[-1] + '-asr'
                $KekKeyVault = Get-AzResource -Name $KekKeyVaultName

                if (-not $KekKeyVault)
                {
                    $KekKeyVaultName = '(new)' + $KekKeyVaultName
                    $KekDropDown.Items.Add($KekKeyVaultName)
                }

                $KekDropDown.Text = $KekKeyVaultName
            }

            if ($FailCount -lt 2)
            {
                if ($BekDropDown.Items.Count -le 1)
                {
                    $KeyVaultList = (Get-AzKeyVault).VaultName | sort

                    foreach ($Item in $KeyVaultList)
                    {
                        $SuppressOutput = $BekDropDown.Items.Add($Item)
                        $SuppressOutput = $KekDropDown.Items.Add($Item)
                    }

                    if($KeyVaultList)
                    {
                        if($Bek)
                        {
                            $Longest = ($KeyVaultList + $BekKeyVaultName | sort Length -Descending)[0]
                            $BekDropDown.DropDownWidth = ([System.Windows.Forms.TextRenderer]::MeasureText($Longest, `
                                $BekDropDown.Font).Width, $BekDropDown.Width | Measure-Object -Maximum).Maximum
                        }

                        if($Kek)
                        {
                            $Longest = ($KeyVaultList + $KekKeyVaultName  | sort Length -Descending)[0]
                            $KekDropDown.DropDownWidth = ([System.Windows.Forms.TextRenderer]::MeasureText($Longest, `
                                $KekDropDown.Font).Width, $KekDropDown.Width | Measure-Object -Maximum).Maximum
                        }
                    }
                }

               for ($Index = 8; $Index -lt $FormElementsList.Count; $Index++)
                {
                    if ($FormElements[$FormElementsList[$Index]].Text -ne 'Not Applicable')
                    {
                        $FormElements[$FormElementsList[$Index]].Enabled = $true
                    }
                }
            }

            $LoadingLabel.Text = ""
        }
        else
        {
            $BekDropDown.Items.Clear()
            $KekDropDown.Items.Clear()
        }
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
    $UiObject.Font = 'Microsoft Sans Serif, 10'
    $UiObject.ForeColor = "#5c7290"
    $UiObject.width = $Formattings["width"]
    $UiObject.height = $Formattings["height"]
    $UiObject.location = New-Object System.Drawing.Point($Formattings["location"])
}

### <summary>
### Generates the graphical user interface to get all inputs.
### </summary>
function Generate-UserInterface
{
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

    $UserInputForm.ClientSize = '445,620'
    $UserInputForm.text = "User Inputs"
    $UserInputForm.BackColor = "#ffffff"
    $UserInputForm.TopMost = $false

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
    $SubscriptionDropDown.DropDownHeight = 150
    $SubscriptionDropDown.AutoSize = $true
    $SubscriptionDropDown.Add_SelectedIndexChanged({Get-ResourceGroups})

    $ResourceGroupDropDownFormatting = @{"location"=@(10, 189); "width"=424; "height"=60}
    Add-CommonFormatting -UiObject $ResourceGroupDropDown -Formattings `
        $ResourceGroupDropDownFormatting
    $ResourceGroupDropDown.DropDownHeight = 150
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
    $VmListBox.Add_SelectedIndexChanged({Disable-RestOfOptions})

    $VmLabelFormatting = @{"location"=@(10, 233); "width"=25; "height"=10}
    Add-CommonFormatting -UiObject $VmLabel -Formattings $VmLabelFormatting
    $VmLabel.text = "Choose virtual machine(s)"
    $VmLabel.AutoSize = $true
    $VmLabel.Tag = "Select the virtual machines whose Disk Encryption Keys need to be copied to DR location."
    $VmLabel.Add_MouseHover({Show-Help})

    $BekDropDownFormatting = @{"location"=@(10, 445); "width"=424; "height"=30}
    Add-CommonFormatting -UiObject $BekDropDown -Formattings $BekDropDownFormatting
    $BekDropDown.DropDownHeight = 150

    $BekLabelFormatting = @{"location"=@(10, 420); "width"=25; "height"=10}
    Add-CommonFormatting -UiObject $BekLabel -Formattings $BekLabelFormatting
    $BekLabel.text = "Target Disk Encryption Key vault"
    $BekLabel.AutoSize = $true
    $BekLabel.Tag = "Specify the target disk encryption key vault in DR region where the keys will be copied to."
    $BekLabel.Add_MouseHover({Show-Help})

    $KekDropDownFormatting = @{"location"=@(10, 506); "width"=424; "height"=30}
    Add-CommonFormatting -UiObject $KekDropDown -Formattings $KekDropDownFormatting
    $KekDropDown.DropDownHeight = 150

    $KekLabelFormatting = @{"location"=@(10, 480); "width"=25; "height"=10}
    Add-CommonFormatting -UiObject $KekLabel -Formattings $KekLabelFormatting
    $KekLabel.text = "Target Key Encryption Key vault"
    $KekLabel.AutoSize = $true
    $KekLabel.Tag = "Specify the target key encryption key vault in DR region where the keys will be copied to."
    $KekLabel.Add_MouseHover({Show-Help})

    $LocationDropDownFormatting = @{"location"=@(10, 386); "width"=424; "height"=20}
    Add-CommonFormatting -UiObject $LocationDropDown -Formattings $LocationDropDownFormatting
    $LocationDropDown.DropDownHeight = 150
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
    $MsLogo.width = 140
    $MsLogo.height = 80
    $MsLogo.location = New-Object System.Drawing.Point(150, 10)
    $MsLogo.imageLocation = "https://c.s-microsoft.com/en-us/CMSImages/ImgOne.jpg?version=D418E733-821C-244F-37F9-DC865BDEFEC0"
    $MsLogo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::zoom

    # Populating the subscription dropdown and launching the form

    [array]$SubscriptionArray = ((Get-AzSubscription).Name | sort)

    foreach ($Item in $SubscriptionArray)
    {
        $SuppressOutput = $SubscriptionDropDown.Items.Add($Item)
    }

    $Longest = ($SubscriptionArray | sort Length -Descending)[0]
    $SubscriptionDropDown.DropDownWidth = ([System.Windows.Forms.TextRenderer]::MeasureText($Longest, `
        $SubscriptionDropDown.Font).Width, $SubscriptionDropDown.Width | Measure-Object -Maximum).Maximum

    $UserInputForm.controls.AddRange($FormElements.Values + $LoadingLabel)
    $UserInputForm.controls.AddRange($MsLogo)
    [void]$UserInputForm.ShowDialog()
}

### <summary>
### Gets the authentication result to key vaults.
### </summary>
function Get-Authentication
{
    # Vault resources endpoint
    $ArmResource = "https://vault.azure.net"
    # Well known client ID for AzurePowerShell used to authenticate scripts to Azure AD.
    $ClientId = "1950a258-227b-4e31-a9cf-717495945fc2"
    $RedirectUri = "urn:ietf:wg:oauth:2.0:oob"
    $AuthorityUri = "https://login.windows.net/$TenantId"
    $AuthContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" `
        -ArgumentList $AuthorityUri
    $PlatformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" `
        -ArgumentList "Auto", $null
    $AuthResult = $AuthContext.AcquireTokenAsync($ArmResource, $ClientId, $RedirectUri, $PlatformParameters)

    return $AuthResult.Result
}

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
        ContentType = 'application/json'
        Headers     = @{
            'authorization' = "Bearer $AccessToken"}
        Method      = 'POST'
        URI         = "$KeyId" + '/encrypt?api-version=2016-10-01'
        Body        = $BodyJson}

    try
    {
        $Response = Invoke-RestMethod @Params
    }
    catch
    {
        $ErrorString = "You do not have sufficient permissions to encrypt. " + `
            'You need "ENCRYPT" permissions for key vault keys'
        throw [System.UnauthorizedAccessException] $ErrorString
    }
    finally
    {
        Write-Verbose "`nEncrypt request: `n$(ConvertTo-Json -InputObject $Params)"
        Write-Verbose "`nEncrypt resonse: `n$(ConvertTo-Json -InputObject $Response)"
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
        ContentType = 'application/json'
        Headers     = @{
            'authorization' = "Bearer $AccessToken"}
        Method      = 'POST'
        URI         = "$KeyId" + '/decrypt?api-version=2016-10-01'
        Body        = $BodyJson}

    try
    {
        $Response = Invoke-RestMethod @Params
    }
    catch
    {
        $ErrorString = "You do not have sufficient permissions to decrypt. " + `
            'You need "DECRYPT" permissions for key vault keys'
        throw [System.UnauthorizedAccessException] $ErrorString
    }
    finally
    {
        Write-Verbose "`nDecrypt request: `n$(ConvertTo-Json -InputObject $Params)"
        Write-Verbose "`nDecrypt resonse: `n$(ConvertTo-Json -InputObject $Response)"
    }

    return $Response
}

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

        if ($Vm.StorageProfile.OsDisk.EncryptionSettings -eq $null)
        {
            $Vm = Get-AzVm -ResourceGroupName $SourceResourceGroupName -Name $VmName -Status
            $Disks = $Vm.Disks

            for($i=0; $i -lt $Disks.Count; $i++)
            {
                $Disk = $Disks[$i]
                $Source = [Source]::new($VmName, $Disk.Name)

                if($Disks[$i].EncryptionSettings -ne $null)
                {
                    $Source.Bek = $Disk.EncryptionSettings[0].DiskEncryptionKey
                    $Source.Kek = $Disk.EncryptionSettings[0].KeyEncryptionKey

                    $SourceList += $Source
                }
                else
                {
                    Write-Host -ForegroundColor Green "Virtual machine $VmName encrypted but disk ($($Disk.Name)) "` "not encrypted."
                }
            }

            Write-Host "`n"
        }
        else
        {
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
    $ErrorString1 = "You do not have sufficient permissions to access "
    $ErrorString2 = " in the key vault $KeyVaultName. You need $($PermissionsRequired -join ',') for key vault "
    $PermissionsType = 'keys'
    foreach ($Policy in $AccessPolicies)
    {
        if ($Policy.ObjectId -eq $UserId)
        {
            if($ResourceObject)
            {
                $Permissions = $Policy.Permissions.Keys

                if($Secret)
                {
                    $Permissions = $Policy.Permissions.Secrets
                    $PermissionsType = "secrets"
                }

                $Permissions = $Permissions | %{$_.ToLower()}

                if (-not $Permissions -or (($PermissionsRequired | % { $Permissions.Contains($_)}) -contains $false))
                {
                    $ErrorString = $ErrorString1 + $PermissionsType + $ErrorString2
                    $ErrorString += $PermissionsType
                    throw [System.UnauthorizedAccessException] $ErrorString
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

                $Permissions = $Permissions | %{$_.ToLower()}

                if (-not $Permissions -or (($PermissionsRequired | % { $Permissions.Contains($_)}) -contains $false))
                {
                    $ErrorString = $ErrorString1 + $PermissionsType + $ErrorString2
                    $ErrorString += $PermissionsType + '.'
                    throw [System.UnauthorizedAccessException] $ErrorString
                }
            }

            return
        }
    }

    $ErrorString = "User with user id: $UserId does not have access to the key vault $KeyVaultName"

    throw [System.UnauthorizedAccessException] $ErrorString
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
    }

    if (-not $TargetKeyVault)
    {
        $IsKeyVaultNew.Value = $true
        Write-Host "Creating key vault $TargetKeyVaultName" -ForegroundColor Green

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
            -EnableSoftDelete:$KeyVaultResource.Properties.EnableSoftDelete -Sku $KeyVaultResource.Properties.Sku.name `
            -Tag $KeyVaultResource.Tags
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
    [string]$ContentType,
    [Logger]$Logger)
{
    $SecureSecret = ConvertTo-SecureString $Secret -AsPlainText -Force
    $OutputSecret = Set-AzureKeyVaultSecret -VaultName $TargetBekVault -Name $BekSecret.Name -SecretValue `
        $SecureSecret -tags $BekTags -ContentType $ContentType
    Write-Host 'Copying "Disk Encryption Key" for' "$VmName" -ForegroundColor Green
    $Logger.Log(
        $MyInvocation,
        "TargetBEKVault: $TargetBekVault",
        [LogType]::OUTPUT)
    $Logger.Log(
        $MyInvocation,
        "TargetBEKId: $($OutputSecret.Id)",
        [LogType]::OUTPUT)
}

### <summary>
### Main flow of code for copying keys.
### </summary>
### <return name="CompletedList">List of VMs for which CopyKeys ran successfully</return>
function Start-CopyKeys
{
    $Context = Get-AzContext

    if($Context -eq $null)
    {
        $SuppressOutput = Login-AzAccount -ErrorAction Stop
    }

    $OutputLogger = [Logger]::new('CopyKeys-' + $StartTime, $FilePath)

    $CompletedList = @()
    $UserInputs = New-Object System.Collections.Hashtable
    Write-Verbose "Starting user interface to get inputs"
    Generate-UserInterface

    if ($ForceDebug)
    {
        $Script:DebugPreference = "Continue"
    }

    $ResourceGroupName = $UserInputs["ResourceGroupName"]
    $VmNameArray = $UserInputs["VmNameArray"]
    $TargetLocation = $UserInputs["TargetLocation"]
    $TargetBekVault = $UserInputs["TargetBekVault"]
    $TargetKekVault = $UserInputs["TargetKekVault"]


    if($Context -eq $null)
    {
        $Context = Get-AzContext
    }

    Write-Verbose "`nSubscription Id: $($Context.Subscription.Id)"
    Write-Verbose "Inputs:`n$(ConvertTo-Json -InputObject $UserInputs)"

    $TenantId = $Context.Tenant.Id
    $AuthResult = Get-Authentication
    $AccessToken = $AuthResult.AccessToken
    $UserId = $AuthResult.UserInfo.UniqueId

    Write-Debug "`nStarting CopyKeys for UserId: $UserId`n"

    $IsFirstBekVault = $IsFirstKekVault = $true
    $FirstBekVault = $FirstKekVault = $null
    $IsBekKeyVaultNew = $IsKekKeyVaultNew = $false

    $OutputLogger.Log(
        $MyInvocation,
        "SubscriptionId: $($Context.Subscription.Id)",
        [LogType]::OUTPUT)
    $OutputLogger.Log(
        $MyInvocation,
        "ResourceGroupName: $ResourceGroupName",
        [LogType]::OUTPUT)
    $OutputLogger.Log(
        $MyInvocation,
        "TargetLocation: $TargetLocation",
        [LogType]::OUTPUT)

    $SourceList = New-Sources -VmArray $VmNameArray -SourceResourceGroupName $ResourceGroupName

    foreach($Source in $SourceList)
    {
        try
        {
            $VmName = $Source.Name

            # Only VMName as source name if 2 pass else VMName - DiskName
            $SourceName = if ($Source.DiskName -eq "") { $Source.Name } else { $Source.Name + " - " + $Source.DiskName }

            # If output diskName is empty -> 2-pass else 1-pass
            $OutputLogger.Log(
                $MyInvocation,
                "`nVMName: $($Source.Name)`nDiskName: $($Source.DiskName)",
                [LogType]::OUTPUT)

            $Bek = $Source.Bek
            $Kek = $Source.Kek

            if (-not $Bek)
            {
                throw [System.MissingFieldException] "Virtual machine $VmName encrypted but disk encryption " + `
                    "settings missing for disk - $($Source.DiskName)."
            }

            $BekKeyVaultResource = Conduct-SourceKeyVaultPreReq -EncryptionKey $Bek -SourcePermissions `
                $SourceSecretsPermissions -Secret

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
            $BekSecret = Get-AzureKeyVaultSecret -VaultName $BekKeyVaultResource.Name -Version $Url.Segments[3] `
                -Name $Url.Segments[2].TrimEnd("/")
            $BekSecretBase64 = $BekSecret.SecretValueText
            $BekTags = $BekSecret.Attributes.Tags

            if ($Kek)
            {
                $KekKeyVaultResource = Conduct-SourceKeyVaultPreReq -EncryptionKey $Kek `
                    -SourcePermissions $SourceKeysPermissions

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
                            -PermissionsToKeys 'Encrypt','Create','Get'
                    }

                    $FirstKekVault = $KekKeyVaultResource
                    $IsFirstKekVault = $false
                }

                $BekEncryptionAlgorithm = $BekSecret.Attributes.Tags.DiskEncryptionKeyEncryptionAlgorithm

                [uri]$Url = $Kek.KeyUrl
                $KekKey = Get-AzureKeyVaultKey -VaultName $KekKeyVaultResource.Name -Version $Url.Segments[3] `
                    -Name $Url.Segments[2].TrimEnd("/")

                if(-not $Kekkey)
                {
                    throw "Key with name: $($Url.Segments[2].TrimEnd("/")) " + `
                        "and version: $($Url.Segments[3]) could not be found in key vault $($KekKeyVaultResource.Name)"
                }

                $NewKekKey = Get-AzureKeyVaultKey -VaultName $TargetKekVault -Name $KekKey.Name `
                    -ErrorAction SilentlyContinue

                if (-not $NewKekKey)
                {
                    # Creating the new KEK
                    $NewKekKey = Add-AzureKeyVaultKey -VaultName $TargetKekVault -Name $KekKey.Name `
                        -Destination Software
                    Write-Host 'Copying "Key Encryption Key" for' "$VmName" -ForegroundColor Green
                }
                else
                {
                    # Using existing KEK
                    Write-Host "Using existing key $($KekKey.Name)" -ForegroundColor Green
                }

                $OutputLogger.Log(
                    $MyInvocation,
                    "TargetKEKVault: $TargetKekVault",
                    [LogType]::OUTPUT)

                $OutputLogger.Log(
                    $MyInvocation,
                    "TargetKEKId: $($NewKekKey.Id)",
                    [LogType]::OUTPUT)

                $TargetKekUri = "https://" + "$TargetKekVault" + ".vault.azure.net/keys/" + $NewKekKey.Name + '/' + `
                    $NewKekKey.Version

                # Decrypting Wrapped-BEK
                $DecryptedSecret = Decrypt-Secret -EncryptedValue $BekSecretBase64 -EncryptedAlgorithm `
                    $BekEncryptionAlgorithm -AccessToken $AccessToken -KeyId $Kekkey.Key.Kid

                # Encrypting BEK with new KEK
                $EncryptedSecret = Encrypt-Secret -DecryptedValue $DecryptedSecret.value -EncryptedAlgorithm `
                    $BekEncryptionAlgorithm -AccessToken $AccessToken -KeyId $TargetKekUri

                $BekTags.DiskEncryptionKeyEncryptionKeyURL = $TargetKekUri
                Create-Secret -Secret $EncryptedSecret.value -ContentType "Wrapped BEK"  -Logger $OutputLogger
            }
            else
            {
                Create-Secret -Secret $BekSecretBase64 -ContentType "BEK" -Logger $OutputLogger
            }

            $CompletedList += $SourceName
        }
        catch
        {
            Write-Warning "CopyKeys not completed for $SourceName`n"
            $IncompleteList[$SourceName] = $_
        }
    }

    if ($IsKekKeyVaultNew)
    {
        # Copying access policies to new KEK target key vault
        $TargetKekRgName = "$($FirstKekVault.ResourceGroupName)" + "-asr"
        Copy-AccessPolicies -TargetKeyVaultName $TargetKekVault -TargetResourceGroupName $TargetKekRgName `
            -SourceKeyVaultName $FirstKekVault.Name -SourceAccessPolicies `
            $FirstKekVault.Properties.AccessPolicies
    }

    if ($IsBekKeyVaultNew)
    {
        # Copying access policies to new BEK target key vault
        $TargetBekRgName = "$($FirstBekVault.ResourceGroupName)" + "-asr"
        Copy-AccessPolicies -TargetKeyVaultName $TargetBekVault -TargetResourceGroupName $TargetBekRgName `
            -SourceKeyVaultName $FirstBekVault.Name -SourceAccessPolicies `
            $FirstBekVault.Properties.AccessPolicies
    }

    return $CompletedList
}

$ErrorActionPreference = "Stop"
$SourceSecretsPermissions = @('get')
$TargetSecretsPermissions = @('set')
$SourceKeysPermissions = @('get', 'decrypt')
$TargetKeysPermissions = @('get', 'create', 'encrypt')

try
{
    $StartTime = Get-Date -Format 'dd-MM-yyyy-HH-mm-ss-fff'
    Write-Verbose "$StartTime - CopyKeys started"
    $CompletedList = @()
    $DebugLogger = $null
    $IncompleteList = New-Object System.Collections.Hashtable

    if ($ForceDebug)
    {
        $Script:DebugPreference = "SilentlyContinue"
        $DebugLogger = [Logger]::new('CopyKeysDebug-' + $StartTime, $FilePath)
        $CompletedList = Start-CopyKeys 5> $DebugLogger.GetFullPath()
    }
    else
    {
        $CompletedList = Start-CopyKeys
    }
}
catch
{
    $UnknownError = "`nException: " + $PSItem.Exception.Message + `
        "`nAt: " + $PSItem.InvocationInfo.Line.Trim() + `
        "Line: " + $PSItem.InvocationInfo.ScriptLineNumber + "; Char:" + $PSItem.InvocationInfo.OffsetInLine + `
        "`nStackTrace: `n" + $PSItem.ScriptStackTrace + `
        "`nCategoryInfo: " + $PSItem.CategoryInfo.Category + ": " + $PSItem.CategoryInfo.Activity + ", " + `
            $PSItem.CategoryInfo.Reason + `
        "`nAn unknown exception occurred. Please contact support with the error details"
    Write-Host -ForegroundColor Red -BackgroundColor Black $UnknownError

    if($DebugLogger -ne $null)
    {
        $DebugLogger.Log(
            $MyInvocation,
            "`nERROR: " + $UnknownError,
            [LogType]::DEBUG)
    }
}
finally
{
    # Summarizes the CopyKeys status for various Vms
    if($CompletedList.Count -gt 0)
    {
        Write-Host -ForegroundColor Green "`nCopyKeys succeeded for VMs:`n`t$($CompletedList -join "`n`t")."

        if($DebugLogger -ne $null)
        {
            $DebugLogger.Log(
                $MyInvocation,
                "`nCopyKeys succeeded for VMs:`n`t $($CompletedList -join "`n`t").",
                [LogType]::DEBUG)
        }
    }
    $IncompleteList.Keys | % {
        Write-Host -ForegroundColor Green "`nCopyKeys failed for $_ with"
        $KnownError = "Exception: " + $IncompleteList[$_].Exception.Message + `
        "`nAt: " + $IncompleteList[$_].InvocationInfo.Line.Trim() + `
        "Line: " + $IncompleteList[$_].InvocationInfo.ScriptLineNumber + "; Char:" + `
            $IncompleteList[$_].InvocationInfo.OffsetInLine + `
        "`nStackTrace: `n" + $IncompleteList[$_].ScriptStackTrace + `
        "`nCategoryInfo: " + $IncompleteList[$_].CategoryInfo.Category + ": " + `
            $IncompleteList[$_].CategoryInfo.Activity + ", " + $IncompleteList[$_].CategoryInfo.Reason
        Write-Host -ForegroundColor Red -BackgroundColor Black $KnownError

        if($DebugLogger -ne $null)
        {
            $DebugLogger.Log(
                $MyInvocation,
                "`nCopyKeys failed for $_ with" + "`nERROR: " + $KnownError,
                [LogType]::DEBUG)
        }
    }

    Write-Verbose "$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss:fff') - CopyKeys completed"
}