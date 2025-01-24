# Variables
module_number="module-4"
task_number="task-6"
location="eastus"
rg_name="resource-group-${module_number}-${task_number}"
storage_account_name="storage${RANDOM}${RANDOM}"  # Must be globally unique
container_name="blobcontainer"
file_share_name="fileshare"
queue_name="queue"
table_name="tabledata"

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

# Step 4: Create Services (Blob Container, File Share, Queue, and Table)
# Create a Blob container
az storage container create \
  --name $container_name \
  --account-name $storage_account_name

file_name="sample.txt"
file_path="$(git rev-parse --show-toplevel)/${file_name}"
echo "Sample content" > $file_path

# Add a sample blob to the container
az storage blob upload \
  --container-name $container_name \
  --file $file_path \
  --name $file_name \
  --account-name $storage_account_name

# Create a File share
az storage share-rm create \
  --name $file_share_name \
  --storage-account $storage_account_name

# Add a sample file to the File share
az storage file upload \
  --share-name $file_share_name \
  --source $file_path \
  --account-name $storage_account_name

# Create a Queue
az storage queue create \
  --name $queue_name \
  --account-name $storage_account_name

# Add a sample message to the Queue
az storage message put \
  --queue-name $queue_name \
  --content "Hello, this is a test message" \
  --account-name $storage_account_name

# Create a Table
az storage table create \
  --name $table_name \
  --account-name $storage_account_name

# Add sample data to the Table
az storage entity insert \
  --account-name $storage_account_name \
  --table-name $table_name \
  --entity PartitionKey=SamplePartition RowKey=1 Name="Example" Value="123" 

# Step 5: Generate SAS Tokens and Verify Access
# Generate a SAS token for Blob container (read-only access)
blob_sas=$(az storage container generate-sas \
  --name $container_name \
  --account-name $storage_account_name \
  --permissions r \
  --expiry $(date -u -d '1 hour' '+%Y-%m-%dT%H:%MZ') \
  --output tsv)

blob_sas_url="https://${storage_account_name}.blob.core.windows.net/${container_name}/${file_name}?${blob_sas}"
echo "Blob SAS URL: $blob_sas_url"

# Test Blob SAS URL (Requires CURL or HTTP client)
curl -I "$blob_sas_url"

# Generate a SAS token for File share (read/write access)
file_sas=$(az storage share generate-sas \
  --name $file_share_name \
  --account-name $storage_account_name \
  --permissions rw \
  --expiry $(date -u -d '1 hour' '+%Y-%m-%dT%H:%MZ') \
  --output tsv)

file_sas_url="https://${storage_account_name}.file.core.windows.net/${file_share_name}/${file_name}?${file_sas}"
echo "File SAS URL: $file_sas_url"
curl -I "$file_sas_url"

# Upload a file to verify "write" permission
uploaded_file_sas_url="https://${storage_account_name}.file.core.windows.net/${file_share_name}/sample_share.txt?${file_sas}"

curl "$uploaded_file_sas_url" \
  -X 'PUT' \
  -H 'Content-Length: 0' \
  -H 'x-ms-content-length: 60620' \
  -H 'x-ms-type: File' 

echo "Blob SAS URL: $uploaded_file_sas_url"
curl -I "$uploaded_file_sas_url"

# Generate a SAS token for Queue (add permissions)
queue_sas=$(az storage queue generate-sas \
  --name $queue_name \
  --account-name $storage_account_name \
  --permissions apru \
  --expiry $(date -u -d '1 hour' '+%Y-%m-%dT%H:%MZ') \
  --output tsv)

# Send Queue
curl -X POST \
  -H "Content-Type: application/xml" \
  -d '<?xml version="1.0" encoding="utf-8"?><QueueMessage><MessageText>Hello, Azure Queue!</MessageText></QueueMessage>' \
  "https://${storage_account_name}.queue.core.windows.net/${queue_name}/messages?${queue_sas}"

# Test Queue
curl -X GET \
  "https://${storage_account_name}.queue.core.windows.net/${queue_name}/messages?${queue_sas}"

# Generate a SAS token for Table (query permissions)
table_sas=$(az storage table generate-sas \
  --name $table_name \
  --account-name $storage_account_name \
  --permissions raud \
  --expiry $(date -u -d '1 hour' '+%Y-%m-%dT%H:%MZ') \
  --output tsv)

curl -X GET \
  -H "Accept: application/json;odata=nometadata" \
  "https://${storage_account_name}.table.core.windows.net/${table_name}()?${table_sas}"

# Step 6: Analyze Security Implications
# Display analysis
echo "Security Implications:"
echo "1. Ensure SAS tokens are distributed securely to avoid unauthorized access."
echo "2. Use minimal permissions required for the task (e.g., read-only for Blob)."
echo "3. Set short expiry times for SAS tokens to reduce risk in case of leaks."
echo "4. Monitor logs to track access using SAS tokens."

# Step 7: Clean Up Resources
rm $file_name
az group delete --name $rg_name --yes --no-wait
