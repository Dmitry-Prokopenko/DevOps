# Variables
module_number="module-4"
task_number="task-2"
location="eastus"
user="" # Replace with the email of the user or service principal
rg_name="resource-group-${module_number}-${task_number}"
storage_account_name="storage${RANDOM}${RANDOM}" # Must be globally unique
container_name="lifecycle-container"
policy_name="lifecycle-policy"


# Step 1: Login to Azure (if not already logged in)
az account clear
az config set core.enable_broker_on_windows=false
az login


# Step 2: Create a Resource Group
az group create --name $rg_name --location $location


# Step 3: Create a Storage Account
az storage account create \
  --name $storage_account_name \
  --resource-group $rg_name \
  --location $location \
  --sku Standard_LRS \
  --kind StorageV2


# Step 4: Create a Blob Container
az storage container create \
  --account-name $storage_account_name \
  --name $container_name \
  --auth-mode login \
  --fail-on-exist


# Step 5: Assign Role to a User
storage_account_id=$(az storage account show \
  --name $storage_account_name \
  --resource-group $rg_name \
  --query id \
  --output tsv)

az role assignment create \
  --assignee $user \
  --role "Storage Blob Data Owner" \
  --scope "${storage_account_id:1}"


# Step 6: Upload Multiple Files of Varying Sizes
for i in {1..3}; do
  file_name="$(git rev-parse --show-toplevel)/sample-file-${i}.txt"
  echo "This is sample file number $i" > $file_name
  az storage blob upload \
    --account-name $storage_account_name \
    --container-name $container_name \
    --name sample-file-${i}.txt \
    --auth-mode login \
    --file $file_name
  rm -f $file_name
done


# Step 7: Define the Lifecycle Management Policy
policy=$(cat <<EOF
{
  "rules": [
    {
      "enabled": true,
      "name": "move-to-cool-archive-delete",
      "type": "Lifecycle",
      "definition": {
        "actions": {
          "baseBlob": {
            "tierToCool": {
              "daysAfterModificationGreaterThan": 0
            },
            "tierToArchive": {
              "daysAfterModificationGreaterThan": 3
            },
            "delete": {
              "daysAfterModificationGreaterThan": 6
            }
          }
        },
        "filters": {
          "blobTypes": ["blockBlob"]
        }
      }
    }
  ]
}
EOF
)

echo "$policy" > "$(git rev-parse --show-toplevel)/lifecycle-policy.json"


# Apply the policy to the storage account
az storage account management-policy create \
  --account-name $storage_account_name \
  --resource-group $rg_name \
  --policy "@$(git rev-parse --show-toplevel)/lifecycle-policy.json"


# Step 8: Verify the Policy
az storage account management-policy show \
  --account-name $storage_account_name \
  --resource-group $rg_name


# Step 9: Verify the Results
# List blobs to check their access tier, lastModified
az storage blob list \
  --account-name $storage_account_name \
  --container-name $container_name \
  --auth-mode login \
  --query "[].{name:name, tier:properties.blobTier, lastModified:properties.lastModified}" \
  --output table


# Step 10: Clean Up Resources
rm -rf "$(git rev-parse --show-toplevel)/lifecycle-policy.json"
az group delete --name $rg_name --yes --no-wait
