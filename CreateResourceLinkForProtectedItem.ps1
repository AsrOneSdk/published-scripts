Param
(
    [Parameter( `
        Mandatory=$true, `
        HelpMessage = 'Enter VM Subscription Id to be used.')]
        [string]$VMSubscriptionId,
    [Parameter( `
        Mandatory=$true, `
        HelpMessage = 'Specify the name of the Resource group in which your VM is located.')]
        [string]$VMRgName,
    [Parameter( `
        Mandatory=$true, `
        HelpMessage = 'Specify the name of the VM.')]
        [string]$vmName,
    [Parameter( `
        Mandatory=$true, `
        HelpMessage = 'Specify the name of the Resource group in which your Vault is located.')]
        [string]$vaultRGName,
    [Parameter( `
        Mandatory=$true, `
        HelpMessage = 'Enter Vault Subscription Id to be used.')]
        [string]$VaultSubscriptionId,
    [Parameter( `
        Mandatory=$true, `
        HelpMessage = 'Specify the name of the Vault.')]
        [string]$vaultName,
    [Parameter( `
        Mandatory=$false, `
        HelpMessage = 'The login environmnet to be used. The default value is AzureCloud for public clouds. For Governemnt clouds, specify as AzureUSGovernment. For more details about Government clouds, refer:  https://docs.microsoft.com/en-us/azure/azure-government/documentation-government-get-started-connect-with-ps')]
        [string]$loginEnvironment ="AzureCloud"
)

### <summary>
### Retrieves an Azure access token in plain text format for a specified resource or tenant.
### This function handles secure tokens and converts them to plain text for easier usage in scenarios
### where plain text tokens are required.
### </summary>
### <param name="ResourceUrl">Optional parameter specifying the resource URL for which the token is requested.</param>
### <param name="ResourceTypeName">Optional parameter specifying the resource type name for which the token is requested.</param>
### <param name="TenantId">Optional parameter specifying the tenant ID for which the token is requested.</param>
### <return>
### Returns an object containing the access token in plain text format and other token details.
### </return>
function Get-PlainTextAzAccessToken {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(ParameterSetName = 'ByResourceUrl')]
        [string]$ResourceUrl,

        [Parameter(ParameterSetName = 'ByResourceTypeName')]
        [string]$ResourceTypeName,

        [Parameter(ParameterSetName = 'ByTenantId')]
        [string]$TenantId
    )

    # Build parameter dictionary dynamically
    $params = @{}
    if ($PSCmdlet.ParameterSetName -eq 'ByResourceUrl') {
        $params['ResourceUrl'] = $ResourceUrl
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'ByResourceTypeName') {
        $params['ResourceTypeName'] = $ResourceTypeName
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'ByTenantId') {
        $params['TenantId'] = $TenantId
    }

    $tokenResponse = Get-AzAccessToken @params

    # Handle SecureString token
    if ($tokenResponse.Token -is [System.Security.SecureString]) {
        $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenResponse.Token)
        try {
            $plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }

        # Replace the Token property with plain text
        $tokenResponse | Add-Member -MemberType NoteProperty -Name Token -Value $plainToken -Force
    }

    return $tokenResponse
}

# Sign-in with Azure account credentials
Login-AzAccount -Environment $loginEnvironment 

#Select Azure Subscription
Select-AzSubscription -SubscriptionId $VaultSubscriptionId

$context = Get-AzContext
$azureUrl = $context.Environment.ResourceManagerUrl
$vmId = '/subscriptions/' + $VMSubscriptionId + '/resourceGroups/' + $VMRgName + '/providers/Microsoft.Compute/virtualMachines/' + $vmName + '/'
$vmARMId ='/subscriptions/' + $VMSubscriptionId + '/resourceGroups/' + $VMRgName + '/providers/Microsoft.Compute/virtualMachines/' + $vmName

# Get the protected item ARM Id.
$vault = Get-AzRecoveryServicesVault -ResourceGroupName $vaultRGName -Name $vaultName
Set-AzRecoveryServicesAsrVaultContext -Vault $vault
$protectedItems = Get-AzRecoveryServicesAsrFabric | Get-AzRecoveryServicesAsrProtectionContainer | Get-AzRecoveryServicesAsrReplicationProtectedItem  | where-object {$_.ProviderSpecificDetails.FabricObjectId.toLower() -eq $vmARMId.ToLower()}
$protectedItems.Name
$protectedItems.Id

$resourceLinkName = "ASR-Protect-" + $protectedItems.Name
$resourceLinkSourceId = '/subscriptions/' + $VMSubscriptionId + '/resourceGroups/' + $VMRgName + '/providers/Microsoft.Compute/virtualMachines/' + $vmName + '/'
$resourceLinkId = $resourceLinkSourceId + "providers/Microsoft.Resources/links/" + $resourceLinkName
$resourceLinkTargetId = $protectedItems.Id + "/"
$linkNotes = ""

# Target Id
if ($VMSubscriptionId -ne $VaultSubscriptionId)
{
    Write-Host "This is a cross subscription scenario"
    $resourceLinkNotes = New-Object System.Collections.Generic.Dictionary"[String,String]"
    $resourceLinkNotes.Add("protectedItemArmId",$resourceLinkTargetId)
    $resourceLinkTargetId = $resourceLinkSourceId  + "ProtectedItemArmId/" + $protectedItems.Name + "-nonexistent-use-from-linknotes/"
    $linkNotes =  ConvertTo-Json -InputObject $resourceLinkNotes 
}

$resourceLinkTargetId
$resourceLinkSourceId
$resourceLinkName  

# Trigger creation of resource link.
$token = (Get-PlainTextAzAccessToken).Token
$Header = @{"authorization" = "Bearer $token"}
$Header['Content-Type'] = "application\json"

$Url =  $azureUrl + "subscriptions/" + $VMSubscriptionId + "/resourcegroups/" + $VMRgName + "/providers/microsoft.compute/virtualmachines/" + $vmName + "/providers/Microsoft.Resources/links/" +  $resourceLinkName + "?api-version=2016-09-01"
$url

### Creating the request body 
$body = @{
        "properties"= @{
        "sourceId"= $resourceLinkSourceId 
        "targetId"=  $resourceLinkTargetId
        "notes"= $linkNotes
      }
      "id"= $resourceLinkId
      "type"= "Microsoft.Resources/links"
      "name"= $resourceLinkName 
}

$BodyJson = ConvertTo-Json -Depth 8 -InputObject $body
$getpd = Invoke-WebRequest -Uri $Url -Headers $Header -Method 'PUT' -ContentType "application/json" -Body $BodyJson  -UseBasicParsing
