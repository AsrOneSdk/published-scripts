# published-scripts

## CopyKeys
This script copies the disk encryption keys and key encryption keys for Azure Disk Encryption (ADE) enabled VMs from the source region to disaster recovery (DR) region. Azure Site Recovery requires the keys to enable replication for these VMs to another region. The script outputs a file containing all the results that can be later used during protection.

| Parameters | Description |
|--|--|
|FilePath  | Optional parameter defining the location of the output file.|
|ForceDebug | Optional parameter forcing debug output without any prompts.|


## CopyKeys-Az
This script copies the disk encryption keys and key encryption keys for Azure Disk Encryption (ADE) enabled VMs from the source region to disaster recovery (DR) region. Azure Site Recovery requires the keys to enable replication for these VMs to another region. The script outputs a file containing all the results that can be later used during protection.

Updates
- Uses the latest Azure Powershell Az modules.
- Uses the updated Authentication mechanism as described [here](https://github.com/AsrOneSdk/published-scripts/issues/2)

| Parameters | Description |
|--|--|
|FilePath  | Optional parameter defining the location of the output file.|
|ForceDebug | Optional parameter forcing debug output without any prompts.|
