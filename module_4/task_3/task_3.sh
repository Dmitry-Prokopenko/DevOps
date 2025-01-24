# Variables
module_number="module-4"
task_number="task-3"
location="eastus"
user="" # Replace with the email of the user or service principal
rg_name="resource-group-${module_number}-${task_number}"
storage_account_name="storage${RANDOM}${RANDOM}"  # Must be globally unique
queue_name="task-queue"

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


# Step 4: Create a Queue
az storage queue create \
  --account-name $storage_account_name \
  --name $queue_name \
  --auth-mode login


# Step 5: Assign Role to a User
storage_account_id=$(az storage account show \
  --name $storage_account_name \
  --resource-group $rg_name \
  --query id \
  --output tsv)

az role assignment create \
  --assignee $user \
  --role "Storage Queue Data Contributor" \
  --scope "${storage_account_id:1}"


# Step 6: Add Messages to the Queue (Use Azure CLI)
az storage message put \
  --account-name $storage_account_name \
  --queue-name $queue_name \
  --auth-mode login \
  --content "Message 1: Process task 1"

az storage message put \
  --account-name $storage_account_name \
  --queue-name $queue_name \
  --auth-mode login \
  --content "Message 2: Process task 2"

az storage message put \
  --account-name $storage_account_name \
  --queue-name $queue_name \
  --auth-mode login \
  --content "Message 3: Process task 3"


# Step 7: List Messages in the Queue (Check if they were added)
az storage message peek \
  --account-name $storage_account_name \
  --queue-name $queue_name \
  --auth-mode login \
  --num-messages 5


# Step 8: Dequeue and Process Messages (Using Azure CLI)
# Dequeue the first message and process it
message=$(az storage message get \
  --account-name $storage_account_name \
  --queue-name $queue_name \
  --auth-mode login \
  --num-messages 1 \
  --query "[0].content" \
  --output tsv)

echo "Processing message: $message"


# Step 9: Delete Processed Message from the Queue
get_message_0=$(az storage message get \
  --account-name $storage_account_name \
  --queue-name $queue_name \
  --auth-mode login \
  --num-messages 1 \
  --query "[0]")

message_id=$(echo $get_message_0 | jq -r '.id')
pop_receipt=$(echo $get_message_0 | jq -r '.popReceipt')

az storage message delete \
  --id $message_id \
  --pop-receipt $pop_receipt \
  --queue-name $queue_name \
  --account-name $storage_account_name \
  --auth-mode login


# Step 10: Verify Message Removal from Queue
az storage message peek \
  --account-name $storage_account_name \
  --queue-name $queue_name \
  --auth-mode login \
  --num-messages 5


# Step 11: Clean Up Resources
az group delete --name $rg_name --yes --no-wait
