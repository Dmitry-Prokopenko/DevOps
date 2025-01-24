# Variables
module_number="module-4"
task_number="task-1"
location="eastus"
user="" # Replace with the email of the user or service principal
rg_name="resource-group-${module_number}-${task_number}"
storage_account_name="storage${RANDOM}${RANDOM}" # Must be globally unique
container_name="container-${module_number}-${task_number}"
sample_file="sample-text-${module_number}-${task_number}.txt"
downloaded_file="downloaded-${sample_file}"
path_to_sample_file="$(git rev-parse --show-toplevel)/${sample_file}"
path_to_downloaded_file="$(git rev-parse --show-toplevel)/${downloaded_file}"


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
  --allow-blob-public-access \
  --sku Standard_LRS \
  --kind StorageV2

# Step 4: Create a Blob Container with Public Access
az storage container create \
  --account-name $storage_account_name \
  --name $container_name \
  --auth-mode login \
  --fail-on-exist \
  --public-access blob

storage_account_id=$(az storage account show \
  --name $storage_account_name \
  --resource-group $rg_name \
  --query id \
  --output tsv)

az role assignment create \
  --assignee $user \
  --role "Storage Blob Data Owner" \
  --scope "${storage_account_id:1}"
# Code: MissingSubscription
# Message: The request did not have a subscription or a valid tenant level resource provider.

# Step 5: Create a Sample Text File Locally
echo "This is a sample text file for module ${module_number}, task ${task_number}" > $path_to_sample_file

# Step 6: Upload the Sample File to the Blob Container
az storage blob upload \
  --account-name $storage_account_name \
  --container-name $container_name \
  --name $sample_file \
  --auth-mode login \
  --file $path_to_sample_file

# Step 7: Verify the Upload by Listing Blobs in the Container
az storage blob list \
  --account-name $storage_account_name \
  --container-name $container_name \
  --auth-mode login \
  --output table


# Step 8: Download the File to Verify Retrieval
az storage blob download \
  --account-name $storage_account_name \
  --container-name $container_name \
  --auth-mode login \
  --name $sample_file \
  --file $path_to_downloaded_file


# Step 9: Compare the Original and Downloaded File
if cmp -s $path_to_sample_file $path_to_downloaded_file; then
  echo "File verification successful: The downloaded file matches the uploaded file."
else
  echo "File verification failed: The downloaded file does not match the uploaded file."
fi


# Step 101: Clean Up Local Files (Optional)
rm -f $path_to_sample_file $path_to_downloaded_file

# Step 11: Remove the Resource Group
# Uncomment the next line if you want to delete all created resources
az group delete --name $rg_name --yes --no-wait
