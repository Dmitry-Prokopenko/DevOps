# Variables
module_number="module-4"
task_number="task-10"
location="canadacentral"
secondary_region="canadaeast"
rg_name="resource-group-${module_number}-${task_number}"
cosmos_account_name="cosmosaccount${RANDOM}${RANDOM}"
database_name="SampleDB"
container_name="Items"
partition_key="//category"
consistency_level="Session"  # Set your consistency level here, for example: "Session", "Eventual", "Strong"

# Step 1: Login to Azure (if not already logged in)
az account clear
az config set core.enable_broker_on_windows=false
az login


# Step 2: Create a Resource Group
az group create --name $rg_name --location $location


# Step 3: Register "Microsoft.DocumentDB"
# az provider register --namespace "Microsoft.DocumentDB"


# Step 4: Create a Cosmos DB Account
az cosmosdb create \
  --name $cosmos_account_name \
  --resource-group $rg_name \
  --locations regionName=$location isZoneRedundant=false \
  --default-consistency-level $consistency_level \
  --kind GlobalDocumentDB


# Step 5: Create a Database in Cosmos DB
az cosmosdb sql database create \
  --account-name $cosmos_account_name \
  --resource-group $rg_name \
  --name $database_name


# Step 6: Create a Container with Partition Key
az cosmosdb sql container create \
  --account-name $cosmos_account_name \
  --resource-group $rg_name \
  --database-name $database_name \
  --name $container_name \
  --partition-key-path $partition_key


# Step 7: Retrieve Keys and Endpoint for API Calls
cosmos_key=$(az cosmosdb keys list --name $cosmos_account_name --resource-group $rg_name --type keys --query "primaryMasterKey" -o tsv)
cosmos_endpoint=$(az cosmosdb show --name $cosmos_account_name --resource-group $rg_name --query "documentEndpoint" -o tsv)


# Step 8: Install dependencies (if not installed yet)
# pip install azure-cosmos


# Step 9: Insert random data into Cosmos DB via the Python script
python3 "$(git rev-parse --show-toplevel)/module_4/task_10/create_cosmos_items.py" \
  --endpoint $cosmos_endpoint \
  --key $cosmos_key \
  --database_name $database_name \
  --container_name $container_name \
  --num_items 3


# Step 10: Configure and Test Consistency Levels
# The consistency level is already set to "Session" during the Cosmos DB account creation.
# You can verify the consistency level using the following command:
az cosmosdb show \
  --name $cosmos_account_name \
  --resource-group $rg_name \
  --query "consistencyPolicy.defaultConsistencyLevel"


# Step 11: Run performance test with the specified consistency level
python3 "$(git rev-parse --show-toplevel)/module_4/task_10/cosmos_performance_test.py" \
  --endpoint $cosmos_endpoint \
  --key $cosmos_key \
  --database_name $database_name \
  --container_name $container_name


# Step 12: Enable Global Distribution and Test Replication
# Add a secondary region (e.g., "canadaeast")
az cosmosdb update \
  --name $cosmos_account_name \
  --resource-group $rg_name \
  --locations regionName=$location failoverPriority=0 isZoneRedundant=false \
  --locations regionName=$secondary_region failoverPriority=1 isZoneRedundant=false


# Step 13: Test the replication by querying data from the secondary region
python3 "$(git rev-parse --show-toplevel)/module_4/task_10/cosmos_replication_test.py" \
  --endpoint $cosmos_endpoint \
  --key $cosmos_key \
  --database_name $database_name \
  --container_name $container_name \
  --secondary_region $secondary_region


# Step 14: Optionally, change failover priority
az cosmosdb failover-priority-change \
  --name $cosmos_account_name \
  --resource-group $rg_name \
  --failover-policies "$location=1" "$secondary_region=0"


# Step 15: Test the replication by querying data from the new secondary region
python3 "$(git rev-parse --show-toplevel)/module_4/task_10/cosmos_replication_test.py" \
  --endpoint $cosmos_endpoint \
  --key $cosmos_key \
  --database_name $database_name \
  --container_name $container_name \
  --secondary_region $location

# Step 16: Clean Up Resources
az group delete --name $rg_name --yes --no-wait
