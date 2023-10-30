# CopyKeys

This script copies the disk encryption keys and key encryption keys for Azure Disk Encryption (ADE) enabled VMs from the source region to disaster recovery (DR) region. Azure Site Recovery requires the keys to enable replication for these VMs to another region. The script outputs a file containing all the results that are vital for protection and for troubleshooting.

## parameters

- name="**_FilePath_**" - **Optional** parameter defining the location of the output file.
- name="**_AllowResourceMoverAccess_**" - **Optional** switch parameter indicating if the MSI created by Azure Resource Mover for moving the selected VM resources need to be given access to the target BEK/KEK key vaults.

## updates

| Date | Notes |
|--|--|
|01/21 | - Improved Authentication mechanism with Get-AzAccessToken.</br> - Removed dependence on deprecated key vault properties.</br> - Improved logging. |
|02/23 | - Fixed GUI issues in case of varying resolution.</br> - Fixed login bug in case of expired context. |
|02/28 | - Removing hardcoded vault endpoint and replacing it with one provided by KeyVault RP. |
|04/09 | - Providing MoveCollection MSI with appropriate target key vault access in case the script is used for Azure Resource Mover. |
|30/10/2023 | - Handling case when extensions list is empty but not null
