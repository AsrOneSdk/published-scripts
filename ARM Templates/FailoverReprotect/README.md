# Trigger Failover and Re-protect for Protected Instances using ASR

This ARM template triggers Failover and Reprotect operations for ASR Protected Instances.

`Tags: ASR, Site Recovery, Failover, Reprotect`

## Solution overview and deployed resources

Executing this template will deploy a Powershell Script of name "FailoverAndReprotect" and then trigger it. After triggering, Azure VMs will get failed over to their configured recovery region, and re-protected back to source.

## Prerequisites

Prior to running this ARM template, following things need to be taken care:

- There exists no resource of the name "FailoverAndReprotect" in the resource group where the template is being deployed.
- You need one or more Azure VMs. Verify that [Windows](https://docs.microsoft.com/azure/site-recovery/azure-to-azure-support-matrix#windows) or [Linux](https://docs.microsoft.com/azure/site-recovery/azure-to-azure-support-matrix#replicated-machines---linux-file-systemguest-storage) VMs are supported.
- Review VM [compute](https://docs.microsoft.com/azure/site-recovery/azure-to-azure-support-matrix#replicated-machines---compute-settings), [storage](https://docs.microsoft.com/azure/site-recovery/azure-to-azure-support-matrix#replicated-machines---storage), and [networking](https://docs.microsoft.com/azure/site-recovery/azure-to-azure-support-matrix#replicated-machines---networking) requirements.

## Inputs Required

The template expects the following inputs:
| Parameters| Description|
|-|-|
|identity|ARM ID of a user managed identity that has contributor access to the source, target, and the resource group where the template is being deployed.|
| vaultSubscriptionId| Subscription Id of the Subscription where Vault is present|
| vaultResourceGroupName| Name of the Resource Group where the Vault is present|
| vaultName| Name of the Vault |
| primaryRegion| Primary Region of the VMs |
| recoveryRegion| Target Region of the VMs |
| sourceVmARMIds| Comma Separated List of Azure VM ARM IDs|
| recoveryStagingStorageAccount | ARM ID of the storage account used to cache replication data in the source region.|
| recoveryReplicaDiskAccountType| Type of the Storage account to be used for Disk used for replication.|
| recoveryTargetDiskAccountType| Type of the Storage account to be used for Recovery Target Disk.|

Most of these values will exceed the 32-limit character limit present in the portal. We recommend using Powershell or Azure CLI to deploy the template.

## Deployment steps

You can click the "deploy to Azure" button at the beginning of this document or follow the instructions for command line deployment using the Azure documentation:
- [Deploy resources with Resource Manager templates and Azure PowerShell](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-template-deploy) [_recommended_]
- [Deploy resources with Resource Manager templates and Azure CLI](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-template-deploy-cli)

After the completion of operation, please delete the "FailoverAndReprotect" resource from the Resource Group.