cls

$subscriptionId = Read-Host 'What is your Azure Subscription ID?'
$rgName = Read-Host 'Specify the name of the Resource group in which your VM is located'
$vmName = Read-Host 'Specify the name of the VM'

# Sign-in with Azure account credentials
Login-AzureRmAccount

# Select Azure Subscription
Select-AzureRmSubscription -SubscriptionId $subscriptionId

# Remove any locks t
$locks = Get-AzureRmResourceLock -ResourceGroupName $rgName -ResourceName $vmName -ResourceType Microsoft.Compute/virtualMachines
if ($locks -ne $null -and $locks.Count -ge 0){
	$canDelete =  Read-Host 'The VM has locks that could prevent cleanup of Azure Site Recovery stale links left from previous protection. Do you want the locks deleted to ensure cleanup goes smoothly? Reply with Y/N.'
	
	if ($canDelete.ToLower() -eq "y"){
		Foreach ($lock in $locks) {
			$lockId = $lock.LockId
			Remove-AzureRmResourceLock -LockId $lockId -Force
			Write-Host "Removed Lock $lockId for $vmName"
		}	
	}
}

$linksResourceId = 'https://management.azure.com/subscriptions/' + $subscriptionId  + '/providers/Microsoft.Resources/links'
$vmId = '/subscriptions/' + $subscriptionId + '/resourceGroups/' + $rgName + '/providers/Microsoft.Compute/virtualMachines/' + $vmName + '/'

Write-Host $("Deleting links for $vmId using resourceId: $linksResourceId")
 

$links = @(Get-AzureRmResource -ResourceId $linksResourceId|  Where-Object {$_.Properties.sourceId -match $vmId -and $_.Properties.targetId.ToLower().Contains("microsoft.recoveryservices/vaults")})
Write-Host "Links to be deleted"
$links

#Delete all links which are of type 
Foreach ($link in $links)

{
 Write-Host $("Deleting link " + $link.Name)
 Remove-AzureRmResource -ResourceId $link.ResourceId -Force
}


$links = @(Get-AzureRmResource -ResourceId $linksResourceId|  Where-Object {$_.Properties.sourceId -match $vmId -and $_.Properties.targetId.ToLower().Contains("/protecteditemarmid/")})
Write-Host "Cross subscription Links to be deleted"
$links


#Delete all links which are of type 
Foreach ($link in $links)

{
 Write-Host $("Deleting link " + $link.Name)
 Remove-AzureRmResource -ResourceId $link.ResourceId -Force
}
 
Write-Host $("Deleted all links ")
