# Variables
module_number="module-4"
task_number="task-4"
location="westus"
user="" # Replace with the email of the user or service principal
rg_name="resource-group-${module_number}-${task_number}"
storage_account_name="storage${RANDOM}${RANDOM}"  # Must be globally unique
file_share_name="file-share-${module_number}-${task_number}"

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


# Step 4: Create an Azure File Share
az storage share-rm create \
  --storage-account $storage_account_name \
  --name $file_share_name \
  --quota 100


# Step 5: Assign Role to a User
storage_account_id=$(az storage account show \
  --name $storage_account_name \
  --resource-group $rg_name \
  --query id \
  --output tsv)

az role assignment create \
  --assignee $user \
  --role "Storage File Data SMB Share Elevated Contributor" \
  --scope "${storage_account_id:1}"


# Step 6: Upload a File to the File Share
# Create a local test file to upload
echo "This is a sample file for Azure File Share" > "$(git rev-parse --show-toplevel)/sample-file.txt"

# Upload the file to the Azure File Share
az storage file upload \
  --account-name $storage_account_name \
  --share-name $file_share_name \
  --enable-file-backup-request-intent \
  --source "$(git rev-parse --show-toplevel)/sample-file.txt" \
  --auth-mode login


# Step 7: Mount to Windows
key=$(az storage account keys list \
  --account-name $storage_account_name \
  --query "[0].value" \
  --output tsv)

net use Z: \\\\$storage_account_name.file.core.windows.net\\$file_share_name /user:localhost\\$storage_account_name $key


# Step 8: Clean Up Resources
rm "$(git rev-parse --show-toplevel)/sample-file.txt"
az group delete --name $rg_name --yes --no-wait
