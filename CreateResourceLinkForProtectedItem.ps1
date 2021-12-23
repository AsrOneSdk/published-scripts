Param
(
    [Parameter( `
        Mandatory=$true, `
        HelpMessage = 'Enter subscription Id to be used.')]
        [string]$subscriptionId,
    [Parameter( `
        Mandatory=$true, `
        HelpMessage = 'Specify the name of the Resource group in which your VM is located.')]
        [string]$rgName,
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
        HelpMessage = 'Specify the name of the Vault.')]
        [string]$vaultName,
    [Parameter( `
        Mandatory=$false, `
        HelpMessage = 'The login environmnet to be used. The default value is AzureCloud for public clouds. For Governemnt clouds, specify as AzureUSGovernment. For more details about Government clouds, refer:  https://docs.microsoft.com/en-us/azure/azure-government/documentation-government-get-started-connect-with-ps')]
        [string]$loginEnvironment ="AzureCloud"
)


# Sign-in with Azure account credentials
Login-AzAccount -Environment $loginEnvironment 

#Select Azure Subscription
Select-AzSubscription -SubscriptionId $subscriptionId

$context = Get-AzContextParam
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
$token = (Get-AzAccessToken).Token
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

$azureUrl = $context.Environment.ResourceManagerUrl
$vmId = '/subscriptions/' + $subscriptionId + '/resourceGroups/' + $rgName + '/providers/Microsoft.Compute/virtualMachines/' + $vmName + '/'
$vmARMId ='/subscriptions/' + $subscriptionId + '/resourceGroups/' + $rgName + '/providers/Microsoft.Compute/virtualMachines/' + $vmName

# Get the protected item ARM Id.
$vault = Get-AzRecoveryServicesVault -ResourceGroupName $vaultRGName -Name $vaultName
Set-AzRecoveryServicesAsrVaultContext -Vault $vault
$protectedItems = Get-AzRecoveryServicesAsrFabric | Get-AzRecoveryServicesAsrProtectionContainer | Get-AzRecoveryServicesAsrReplicationProtectedItem  | where-object {$_.ProviderSpecificDetails.FabricObjectId.toLower() -eq $vmARMId.ToLower()}
$protectedItems.Name
$protectedItems.Id

$resourceLinkName = "ASR-Protect-" + $protectedItems.Name
$resourceLinkTargetId = $protectedItems.Id + "/"
$resourceLinkSourceId = '/subscriptions/' + $subscriptionId + '/resourceGroups/' + $rgName + '/providers/Microsoft.Compute/virtualMachines/' + $vmName + '/'
$resourceLinkId = $resourceLinkSourceId + "providers/Microsoft.Resources/links/" + $resourceLinkName
$resourceLinkTargetId
$resourceLinkSourceId
$resourceLinkName  

# Trigger creation of resource link.
$token = (Get-AzAccessToken).Token
$Header = @{"authorization" = "Bearer $token"}
$Header['Content-Type'] = "application\json"

$Url =  $azureUrl + "subscriptions/" + $subscriptionId  + "/resourcegroups/" + $rgName + "/providers/microsoft.compute/virtualmachines/" + $vmName + "/providers/Microsoft.Resources/links/" +  $resourceLinkName + "?api-version=2016-09-01"
$url

### Creating the request body 
$body = @{
        "properties"= @{
        "sourceId"= $resourceLinkSourceId 
        "targetId"=  $resourceLinkTargetId
        "notes"= ""
      }
      "id"= $resourceLinkId
      "type"= "Microsoft.Resources/links"
      "name"= $resourceLinkName 
}

$BodyJson = ConvertTo-Json -Depth 8 -InputObject $body
$getpd = Invoke-WebRequest -Uri $Url -Headers $Header -Method 'PUT' -ContentType "application/json" -Body $BodyJson  -UseBasicParsing
