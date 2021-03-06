# Enabling Replication with ASR

This ARM template enables Site Recovery customers to Enable Replication at scale for their Protected Azure VMs.

`Tags: ASR, Site Recovery, Enable Replication`

## Solution overview and deployed resources

Executing this template will deploy a Powershell Script of name "Enable-Replication" and then trigger it. After triggering, Azure VMs will be protected against the Recovery Services Vault.

## Prerequisites

Prior to running this ARM template, following things need to be taken care:

- There exists no resource of the name "Enable-Replication" in the resource group where the template is being deployed.
- A Recovery Services Vault should exist. Please refer [here](https://docs.microsoft.com/azure/site-recovery/quickstart-create-vault-template) to create one.
- [Review supported regions](https://docs.microsoft.com/azure/site-recovery/azure-to-azure-support-matrix#region-support). You can set up disaster recovery for Azure VMs between any two regions in the same geography.
- You need one or more Azure VMs. Verify that [Windows](https://docs.microsoft.com/azure/site-recovery/azure-to-azure-support-matrix#windows) or [Linux](https://docs.microsoft.com/azure/site-recovery/azure-to-azure-support-matrix#replicated-machines---linux-file-systemguest-storage) VMs are supported.
- Review VM [compute](https://docs.microsoft.com/azure/site-recovery/azure-to-azure-support-matrix#replicated-machines---compute-settings), [storage](https://docs.microsoft.com/azure/site-recovery/azure-to-azure-support-matrix#replicated-machines---storage), and [networking](https://docs.microsoft.com/azure/site-recovery/azure-to-azure-support-matrix#replicated-machines---networking) requirements.
- This tutorial presumes that VMs aren't encrypted. If you want to set up disaster recovery for encrypted VMs, [follow this article](https://docs.microsoft.com/azure/site-recovery/azure-to-azure-how-to-enable-replication-ade-vms)

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
| policyName| Preferred Policy Name for the DR VMs.|
| sourceVmARMIds| Comma Separated List of Azure VM ARM IDs|
| targetResourceGroupId| ARM ID of the Resource Group to create VMs in the DR Region.|
| targetVirtualNetworkId| ARM ID of the Virtual Network to be used by VMs in the DR Region.|
| primaryStagingStorageAccount | ARM ID of the storage account used to cache replication data in the source region.|
| recoveryReplicaDiskAccountType| Type of the Storage account to be used for Disk used for replication.|
| recoveryTargetDiskAccountType| Type of the Storage account to be used for Recovery Target Disk.|

Most of these values will exceed the 32-limit character limit present in the portal. We recommend using Powershell or Azure CLI to deploy the template.

## Deployment steps

You can click the "deploy to Azure" button at the beginning of this document or follow the instructions for command line deployment using the Azure documentation:

- [Deploy resources with Resource Manager templates and Azure PowerShell](https://docs.microsoft.com/azure/azure-resource-manager/resource-group-template-deploy) [_recommended_]
- [Deploy resources with Resource Manager templates and Azure CLI](https://docs.microsoft.com/azure/azure-resource-manager/resource-group-template-deploy-cli)

After the completion of operation, please delete the "EnableReplication" resource from the Resource Group.