param(
    [string] $VaultSubscriptionId,
    [string] $VaultResourceGroupName,
    [string] $VaultName,
    [string] $PrimaryRegion,
    [string] $RecoveryRegion,
    [string] $policyName = 'A2APolicy',
	[string] $sourceVmARMIdsCSV,
	[string] $TargetResourceGroupId,
    [string] $TargetVirtualNetworkId,
	[string] $PrimaryStagingStorageAccount,
    [string] $RecoveryReplicaDiskAccountType = 'Standard_LRS',
    [string] $RecoveryTargetDiskAccountType = 'Standard_LRS'
)

$CRLF = "`r`n"

# Initialize the designated output of deployment script that can be accessed by various scripts in the template.
$DeploymentScriptOutputs = @{}
$sourceVmARMIds = New-Object System.Collections.ArrayList
foreach ($sourceId in $sourceVmARMIdsCSV.Split(','))
{
    $sourceVmARMIds.Add($sourceId.Trim())
}

$message = 'Enable replication will be triggered for following {0} VMs' -f $sourceVmARMIds.Count
foreach ($sourceVmArmId in $sourceVmARMIds) {
	$message += "`n $sourceVmARMId"
}
Write-Output $message

Write-Output $CRLF

# Setup the vault context.
$message = 'Setting Vault context using vault {0} under resource group {1} in subscription {2}.' -f $VaultName, $VaultResourceGroupName, $VaultSubscriptionId
Write-Output $message
Select-AzSubscription -SubscriptionId $VaultSubscriptionId
$vault = Get-AzRecoveryServicesVault -ResourceGroupName $VaultResourceGroupName -Name $VaultName
Set-AzRecoveryServicesAsrVaultContext -vault $vault
$message = 'Vault context set.'
Write-Output $message
Write-Output $CRLF

# Lookup and create replicatio fabrics if required.
$azureFabrics = get-asrfabric
Foreach($fabric in $azureFabrics) {
    $message = 'Fabric {0} in location {1}.' -f $fabric.Name, $fabric.FabricSpecificDetails.Location
    Write-Output $message
}

# Setup the fabrics. Create if the fabrics do not already exist.
$PrimaryRegion = $PrimaryRegion.Replace(' ', '')
$RecoveryRegion = $RecoveryRegion.Replace(' ', '')
$priFab = $azureFabrics | where {$_.FabricSpecificDetails.Location -like $PrimaryRegion}
if ($priFab -eq $null) {
    Write-Output 'Primary Fabric does not exist. Creating Primary Fabric.'
    $job = New-ASRFabric -Azure -Name $primaryRegion -Location $primaryRegion
    do {
        Start-Sleep -Seconds 50
        $job = Get-AsrJob -Job $job
    } while ($job.State -ne 'Succeeded' -and $job.State -ne 'Failed' -and $job.State -ne 'CompletedWithInformation')

	if ($job.State -eq 'Failed') {
       $message = 'Job {0} failed for {1}' -f $job.DisplayName, $job.TargetObjectName
       Write-Output $message
       foreach ($er in $job.Errors) {
        foreach ($pe in $er.ProviderErrorDetails) {
            $pe
        }

        foreach ($se in $er.ServiceErrorDetails) {
            $se
        }
       }

       throw $message
    }
    $priFab = get-asrfabric -Name $primaryRegion
    Write-Output 'Created Primary Fabric.'
}

$recFab = $azureFabrics | where {$_.FabricSpecificDetails.Location -eq $RecoveryRegion}
if ($recFab -eq $null) {
    Write-Output 'Recovery Fabric does not exist. Creating Recovery Fabric.'
    $job = New-ASRFabric -Azure -Name $recoveryRegion -Location $recoveryRegion
    do {
        Start-Sleep -Seconds 50
        $job = Get-AsrJob -Job $job
    } while ($job.State -ne 'Succeeded' -and $job.State -ne 'Failed' -and $job.State -ne 'CompletedWithInformation')

	if ($job.State -eq 'Failed') {
       $message = 'Job {0} failed for {1}' -f $job.DisplayName, $job.TargetObjectName
       Write-Output $message
       foreach ($er in $job.Errors) {
        foreach ($pe in $er.ProviderErrorDetails) {
            $pe
        }

        foreach ($se in $er.ServiceErrorDetails) {
            $se
        }
       }

       throw $message
    }
    $recFab = get-asrfabric -Name $RecoveryRegion
    Write-Output 'Created Recovery Fabric.'
}

$message = 'Primary Fabric {0}' -f $priFab.Id
Write-Output $message
$message = 'Recovery Fabric {0}' -f $recFab.Id
Write-Output $message
Write-Output $CRLF

$DeploymentScriptOutputs['PrimaryFabric'] = $priFab.Name
$DeploymentScriptOutputs['RecoveryFabric'] = $recFab.Name

# Setup the Protection Containers. Create if the protection containers do not already exist.
$priContainer = Get-ASRProtectionContainer -Fabric $priFab
if ($priContainer -eq $null) {
    Write-Output 'Primary Protection container does not exist. Creating Primary Protection Container.'
    $job = New-AzRecoveryServicesAsrProtectionContainer -Name $priFab.Name.Replace(' ', '') -Fabric $priFab
    do {
        Start-Sleep -Seconds 50
        $job = Get-AsrJob -Job $job
    } while ($job.State -ne 'Succeeded' -and $job.State -ne 'Failed' -and $job.State -ne 'CompletedWithInformation')

	if ($job.State -eq 'Failed') {
       $message = 'Job {0} failed for {1}' -f $job.DisplayName, $job.TargetObjectName
       Write-Output $message
       foreach ($er in $job.Errors) {
        foreach ($pe in $er.ProviderErrorDetails) {
            $pe
        }

        foreach ($se in $er.ServiceErrorDetails) {
            $se
        }
       }

       throw $message
    }
    $priContainer = Get-ASRProtectionContainer -Name $priFab.Name -Fabric $priFab
    Write-Output 'Created Primary Protection Container.'
}

$recContainer = Get-ASRProtectionContainer -Fabric $recFab
if ($recContainer -eq $null) {
    Write-Output 'Recovery Protection container does not exist. Creating Recovery Protection Container.'
    $job = New-AzRecoveryServicesAsrProtectionContainer -Name $recFab.Name.Replace(' ', '') -Fabric $recFab
    do {
        Start-Sleep -Seconds 50
        $job = Get-AsrJob -Job $job
    } while ($job.State -ne 'Succeeded' -and $job.State -ne 'Failed' -and $job.State -ne 'CompletedWithInformation')

	if ($job.State -eq 'Failed') {
       $message = 'Job {0} failed for {1}' -f $job.DisplayName, $job.TargetObjectName
       Write-Output $message
       foreach ($er in $job.Errors) {
        foreach ($pe in $er.ProviderErrorDetails) {
            $pe
        }

        foreach ($se in $er.ServiceErrorDetails) {
            $se
        }
       }

       throw $message
    }
    $recContainer = Get-ASRProtectionContainer -Name $recFab.Name -Fabric $recFab
    Write-Output 'Created Recovery Protection Container.'
}


$message = 'Primary Protection Container {0}' -f $priContainer.Id
Write-Output $message
$message = 'Recovery Protection Container {0}' -f $recContainer.Id
Write-Output $message
Write-Output $CRLF

$DeploymentScriptOutputs['PrimaryProtectionContainer'] = $priContainer.Name
$DeploymentScriptOutputs['RecoveryProtectionContainer'] = $recContainer.Name

# Setup the protection container mapping. Create one if it does not already exist.
$primaryProtectionContainerMapping = Get-ASRProtectionContainerMapping -ProtectionContainer $priContainer | where {$_.TargetProtectionContainerId -like $recContainer.Id}
if ($primaryProtectionContainerMapping -eq $null) {
    Write-Output 'Protection Container mapping does not already exist. Creating protection container.' 
    $policy = Get-ASRPolicy -Name $policyName
    if ($policy -eq $null) {
        Write-Output 'Replication policy does not already exist. Creating Replication policy.' 
        $job = New-ASRPolicy -AzureToAzure -Name $policyName -RecoveryPointRetentionInHours 1 -ApplicationConsistentSnapshotFrequencyInHours 1
        do {
            Start-Sleep -Seconds 50
            $job = Get-AsrJob -Job $job
        } while ($job.State -ne 'Succeeded' -and $job.State -ne 'Failed' -and $job.State -ne 'CompletedWithInformation')

	    if ($job.State -eq 'Failed') {
           $message = 'Job {0} failed for {1}' -f $job.DisplayName, $job.TargetObjectName
           Write-Output $message
           foreach ($er in $job.Errors) {
            foreach ($pe in $er.ProviderErrorDetails) {
                $pe
            }

            foreach ($se in $er.ServiceErrorDetails) {
                $se
            }
           }

           throw $message
        }
        $policy = Get-ASRPolicy -Name $policyName
        Write-Output 'Created Replication policy.' 
    }

    $protectionContainerMappingName = $priContainer.Name +  'To' + $recContainer.Name
    $job = New-ASRProtectionContainerMapping -Name $protectionContainerMappingName -Policy $policy -PrimaryProtectionContainer $priContainer -RecoveryProtectionContainer $recContainer
    do {
        Start-Sleep -Seconds 50
        $job = Get-AsrJob -Job $job
    } while ($job.State -ne 'Succeeded' -and $job.State -ne 'Failed' -and $job.State -ne 'CompletedWithInformation')

	if ($job.State -eq 'Failed') {
       $message = 'Job {0} failed for {1}' -f $job.DisplayName, $job.TargetObjectName
       Write-Output $message
       foreach ($er in $job.Errors) {
        foreach ($pe in $er.ProviderErrorDetails) {
            $pe
        }

        foreach ($se in $er.ServiceErrorDetails) {
            $se
        }
       }

       throw $message
    }	
	$primaryProtectionContainerMapping = Get-ASRProtectionContainerMapping -Name $protectionContainerMappingName -ProtectionContainer $priContainer
    Write-Output 'Created Primary Protection Container mappings.'   
}

$reverseContainerMapping = Get-ASRProtectionContainerMapping -ProtectionContainer $recContainer | where {$_.TargetProtectionContainerId -like $priContainer.Id}
if ($reverseContainerMapping -eq $null) {
    Write-Output 'Reverse Protection container does not already exist. Creating Reverse protection container.' 
    if ($policy -eq $null) {
        Write-Output 'Replication policy does not already exist. Creating Replication policy.' 
        $job = New-ASRPolicy -AzureToAzure -Name $policyName -RecoveryPointRetentionInHours 1 -ApplicationConsistentSnapshotFrequencyInHours 1
        do {
            Start-Sleep -Seconds 50
            $job = Get-AsrJob -Job $job
        } while ($job.State -ne 'Succeeded' -and $job.State -ne 'Failed' -and $job.State -ne 'CompletedWithInformation')

	    if ($job.State -eq 'Failed') {
           $message = 'Job {0} failed for {1}' -f $job.DisplayName, $job.TargetObjectName
           Write-Output $message
           foreach ($er in $job.Errors) {
            foreach ($pe in $er.ProviderErrorDetails) {
                $pe
            }

            foreach ($se in $er.ServiceErrorDetails) {
                $se
            }
           }

           throw $message
         }
            $policy = Get-ASRPolicy -Name $policyName
            Write-Output 'Created Replication policy.' 
    }

    $protectionContainerMappingName = $recContainer.Name + 'To' + $priContainer.Name
    $job = New-ASRProtectionContainerMapping -Name $protectionContainerMappingName -Policy $policy -PrimaryProtectionContainer $recContainer `
        -RecoveryProtectionContainer $priContainer
    do {
        Start-Sleep -Seconds 50
        $job = Get-AsrJob -Job $job
    } while ($job.State -ne 'Succeeded' -and $job.State -ne 'Failed' -and $job.State -ne 'CompletedWithInformation')

	if ($job.State -eq 'Failed') {
       $message = 'Job {0} failed for {1}' -f $job.DisplayName, $job.TargetObjectName
       Write-Output $message
       foreach ($er in $job.Errors) {
        foreach ($pe in $er.ProviderErrorDetails) {
            $pe
        }

        foreach ($se in $er.ServiceErrorDetails) {
            $se
        }
       }

       throw $message
    }	
	$reverseContainerMapping = Get-ASRProtectionContainerMapping -Name $protectionContainerMappingName -ProtectionContainer $recContainer    
    Write-Output 'Created Recovery Protection Container mappings.'
}

$message = 'Protection Container mapping {0}' -f $primaryProtectionContainerMapping.Id
Write-Output $message
Write-Output $CRLF

$DeploymentScriptOutputs['PrimaryProtectionContainerMapping'] = $primaryProtectionContainerMapping.Name
$DeploymentScriptOutputs['RecoveryProtectionContainerMapping'] = $reverseContainerMapping.Name

# Start enabling replication for all the VMs.
$enableReplicationJobs = New-Object System.Collections.ArrayList
foreach ($sourceVmArmId in $sourceVmARMIds) {
	# Trigger Enable protection
	$vmIdTokens = $sourceVmArmId.Split('/');
	$vmName = $vmIdTokens[8]
	$vmResourceGroupName = $vmIdTokens[4]
	$message = 'Enable protection to be triggered for {0} using VM name {1} as protected item ARM name.' -f $sourceVmArmId, $vmName
	$vm = Get-AzVM -ResourceGroupName $vmResourceGroupName -Name $vmName
	Write-Output $message
	$diskList =  New-Object System.Collections.ArrayList

	$osDisk =	New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig -DiskId $Vm.StorageProfile.OsDisk.ManagedDisk.Id `
		-LogStorageAccountId $PrimaryStagingStorageAccount -ManagedDisk  -RecoveryReplicaDiskAccountType $RecoveryReplicaDiskAccountType `
		-RecoveryResourceGroupId  $TargetResourceGroupId -RecoveryTargetDiskAccountType $RecoveryTargetDiskAccountType          
	$diskList.Add($osDisk)
	
	foreach($dataDisk in $script:AzureArtifactsInfo.Vm.StorageProfile.DataDisks)
	{
		$disk = New-AzRecoveryServicesAsrAzureToAzureDiskReplicationConfig -DiskId $dataDisk.ManagedDisk.Id `
			-LogStorageAccountId $PrimaryStagingStorageAccount -ManagedDisk  -RecoveryReplicaDiskAccountType $RecoveryReplicaDiskAccountType `
			-RecoveryResourceGroupId  $TargetResourceGroupId -RecoveryTargetDiskAccountType $RecoveryTargetDiskAccountType
		$diskList.Add($disk)
	}
	
	$message = 'Enable protection being triggered.'
	Write-Output $message
	
	$job = New-ASRReplicationProtectedItem -Name $vmName -ProtectionContainerMapping $primaryProtectionContainerMapping `
		-AzureVmId $vm.ID -AzureToAzureDiskReplicationConfiguration $diskList -RecoveryResourceGroupId $TargetResourceGroupId `
		-RecoveryAzureNetworkId $TargetVirtualNetworkId
	$enableReplicationJobs.Add($job)
}

Write-Output $CRLF

# Monitor each enable replication job.
$protectedItemArmIds = New-Object System.Collections.ArrayList
foreach ($job in $enableReplicationJobs) {
	do {
		Start-Sleep -Seconds 50
		$job = Get-AsrJob -Job $job
		Write-Output $job.State
	} while ($job.State -ne 'Succeeded' -and $job.State -ne 'Failed' -and $job.State -ne 'CompletedWithInformation')

	if ($job.State -eq 'Failed') {
       $message = 'Job {0} failed for {1}' -f $job.DisplayName, $job.TargetObjectName
       Write-Output $message
       foreach ($er in $job.Errors) {
        foreach ($pe in $er.ProviderErrorDetails) {
            $pe
        }

        foreach ($se in $er.ServiceErrorDetails) {
            $se
        }
       }

       throw $message
    }
	$targetObjectName = $job.TargetObjectName
	$message = 'Enable protection completed for {0}. Waiting for IR.' -f $targetObjectName
	Write-Output $message
	
	$startTime = $job.StartTime
	$irFinished = $false
	do 
	{
		$irJobs = Get-ASRJob | where {$_.JobType -like '*IrCompletion' -and $_.TargetObjectName -eq $targetObjectName -and $_.StartTime -gt $startTime} | Sort-Object StartTime -Descending | select -First 2  
		if ($irJobs -ne $null -and $irJobs.Length -ne $0) {
			$secondaryIrJob = $irJobs | where {$_.JobType -like 'SecondaryIrCompletion'}
			if ($secondaryIrJob -ne $null -and $secondaryIrJob.Length -ge $1) {
				$irFinished = $secondaryIrJob.State -eq 'Succeeded' -or $secondaryIrJob.State -eq 'Failed'
			}
			else {
				$irFinished = $irJobs.State -eq 'Failed'
			}
		}
	
		if (-not $irFinished) {
			Start-Sleep -Seconds 50
		}
	} while (-not $irFinished)
	
	$message = 'IR completed for {0}.' -f $targetObjectName
	Write-Output $message
	
	$rpi = Get-ASRReplicationProtectedItem -Name $targetObjectName -ProtectionContainer $priContainer
	
	$message = 'Enable replciation completed for {0}.' -f $rpi.ID
	Write-Output $message
	$protectedItemArmIds.Add($rpi.Id)
}


$DeploymentScriptOutputs['ProtectedItemArmIds'] = $protectedItemArmIds -join ','	

# Log consolidated output.
Write-Output 'Infrastrucure Details'
foreach ($key in $DeploymentScriptOutputs.Keys)
{
    $message = '{0} : {1}' -f $key, $DeploymentScriptOutputs[$key]
    Write-Output $message
}
