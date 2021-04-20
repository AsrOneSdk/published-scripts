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
        Mandatory=$false, `
        HelpMessage = 'The login environmnet to be used. The default value is AzureCloud for public clouds. For Givernemnt clouds, specify as AzureUSGovernment. For more details about Government clouds, refer:  https://docs.microsoft.com/en-us/azure/azure-government/documentation-government-get-started-connect-with-ps')]
        [string]$loginEnvironment ="AzureCloud"
)


# Sign-in with Azure account credentials
Login-AzAccount -Environment $loginEnvironment 

#Select Azure Subscription
Select-AzSubscription -SubscriptionId $subscriptionId

# Remove any locks t
$locks = Get-AzResourceLock -ResourceGroupName $rgName -ResourceName $vmName -ResourceType Microsoft.Compute/virtualMachines
if ($locks -ne $null -and $locks.Count -ge 0){
	$canDelete =  Read-Host 'The VM has locks that could prevent cleanup of Azure Site Recovery stale links left from previous protection. Do you want the locks deleted to ensure cleanup goes smoothly? Reply with Y/N.'
	
	if ($canDelete.ToLower() -eq "y"){
		Foreach ($lock in $locks) {
			$lockId = $lock.LockId
			Remove-AzResourceLock -LockId $lockId -Force
			Write-Host "Removed Lock $lockId for $vmName"
		}	
	}
}

$context = Get-AzContext

$azureUrl = $context.Environment.ResourceManagerUrl

$linksResourceId = $azureUrl + "subscriptions/" + $subscriptionId  + '/providers/Microsoft.Resources/links'
$vmId = '/subscriptions/' + $subscriptionId + '/resourceGroups/' + $rgName + '/providers/Microsoft.Compute/virtualMachines/' + $vmName + '/'

Write-Host $("Deleting links for $vmId using resourceId: $linksResourceId")
 

$links = @(Get-AzResource -ResourceId $linksResourceId|  Where-Object {$_.Properties.sourceId -match $vmId -and $_.Properties.targetId.ToLower().Contains("microsoft.recoveryservices/vaults")})
Write-Host "Links to be deleted"
$links

#Delete all links which are of type 
Foreach ($link in $links)

{
 Write-Host $("Deleting link " + $link.Name)
 Remove-AzResource -ResourceId $link.ResourceId -Force
}


$links = @(Get-AzResource -ResourceId $linksResourceId|  Where-Object {$_.Properties.sourceId -match $vmId -and $_.Properties.targetId.ToLower().Contains("/protecteditemarmid/")})
Write-Host "Cross subscription Links to be deleted"
$links


#Delete all links which are of type 
Foreach ($link in $links)

{
 Write-Host $("Deleting link " + $link.Name)
 Remove-AzResource -ResourceId $link.ResourceId -Force
}
 
Write-Host $("Deleted all links ")