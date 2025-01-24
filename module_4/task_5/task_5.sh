# Variables
module_number="module-4"
task_number="task-5"
location="eastus"
user="" # Replace with the email of the user or service principal
rg_name="resource-group-${module_number}-${task_number}"
storage_account_name="storage${RANDOM}${RANDOM}"  # Must be globally unique
table_name="employeedata"

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


# Step 4: Create a Table
az storage table create \
  --name $table_name \
  --account-name $storage_account_name \
  --auth-mode login


# Step 5: Assign Role to a User
storage_account_id=$(az storage account show \
  --name $storage_account_name \
  --resource-group $rg_name \
  --query id \
  --output tsv)

az role assignment create \
  --assignee $user \
  --role "Storage Table Data Contributor" \
  --scope "${storage_account_id:1}"


# Step 6: Add Sample Data to the Table
az storage entity insert \
  --account-name $storage_account_name \
  --table-name $table_name \
  --entity PartitionKey=Employee RowKey=1 EmployeeID=1001 Name="Alice Johnson" Role="Manager" \
  --auth-mode login

az storage entity insert \
  --account-name $storage_account_name \
  --table-name $table_name \
  --entity PartitionKey=Employee RowKey=2 EmployeeID=1002 Name="Bob Smith" Role="Developer" \
  --auth-mode login

az storage entity insert \
  --account-name $storage_account_name \
  --table-name $table_name \
  --entity PartitionKey=Employee RowKey=3 EmployeeID=1003 Name="Charlie Brown" Role="Developer" \
  --auth-mode login


# Step 7: Query the Table for Specific Data (e.g., Role = Developer)
az storage entity query \
  --account-name $storage_account_name \
  --table-name $table_name \
  --filter "PartitionKey eq 'Employee' and Role eq 'Developer'" \
  --auth-mode login


# Step 8: Delete Specific Entries from the Table (e.g., RowKey = 3)
az storage entity delete \
  --account-name $storage_account_name \
  --table-name $table_name \
  --partition-key Employee \
  --row-key 3 \
  --auth-mode login


# Step 9: Verify Changes (List Remaining Entries)
az storage entity query \
  --account-name $storage_account_name \
  --table-name $table_name \
  --filter "PartitionKey eq 'Employee'" \
  --auth-mode login


# Step 10: Clean Up Resources
az group delete --name $rg_name --yes --no-wait
