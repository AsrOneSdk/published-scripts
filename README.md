# published-scripts

## CopyKeys

This script copies the disk encryption keys and key encryption keys for Azure Disk Encryption (ADE) enabled VMs from the source region to disaster recovery (DR) region. Azure Site Recovery requires the keys to enable replication for these VMs to another region. The script outputs a file containing all the results that are vital for protection and for troubleshooting.

### parameters

- name="**_FilePath_**" - **Optional** parameter defining the location of the output file.

### updates

| Date | Notes |
|--|--|
|01/21 | - Improved Authentication mechanism with Get-AzAccessToken.</br> - Removed dependence on deprecated key vault properties.</br> - Improved logging. |
