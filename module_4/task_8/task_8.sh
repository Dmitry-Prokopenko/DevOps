# Variables
module_number="module-4"
task_number="task-8"
location="canadacentral"
rg_name="resource-group-${module_number}-${task_number}"
sql_server_name="sqlserver${RANDOM}${RANDOM}"
sql_db_name="test-db"
admin_user="sqladmin"
admin_password="${RANDOM}${RANDOM}${RANDOM}Ll~"
pricing_tier="Basic"
table_name="Products"

# Step 1: Login to Azure (if not already logged in)
az account clear
az config set core.enable_broker_on_windows=false
az login


# Step 2: Create a Resource Group
az group create --name $rg_name --location $location


# Step 4: Register "Microsoft.Sql"
# az provider register --namespace "Microsoft.Sql"


# Step 3: Create a Logical SQL Server
az sql server create \
  --name $sql_server_name \
  --resource-group $rg_name \
  --location $location \
  --admin-user $admin_user \
  --admin-password $admin_password 


# Step 4: Configure a Firewall Rule to Allow Access
az sql server firewall-rule create \
  --resource-group $rg_name \
  --server $sql_server_name \
  --name "AllowAzureIPs" \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 255.255.255.255


# Step 5: Create an Azure SQL Database
az sql db create \
  --resource-group $rg_name \
  --server $sql_server_name \
  --name $sql_db_name \
  --service-objective $pricing_tier


# Step 6: Use Azure SQL Query Editor to Execute SQL Commands
# Note: Requires Azure CLI interactive execution or pre-configured SQL client

# Create the SQL commands
sql_create_table="
CREATE TABLE ${table_name} (
    ID INT PRIMARY KEY,
    Name NVARCHAR(50),
    Price DECIMAL(10, 2)
);
"

sql_insert_data="
INSERT INTO ${table_name} (ID, Name, Price) VALUES
(1, 'ProductA', 10.00),
(2, 'ProductB', 20.50),
(3, 'ProductC', 15.75);
"

sql_query_data="SELECT * FROM ${table_name};"

# SQL Server connection string
sql_connection_string="tcp:${sql_server_name}.database.windows.net,1433"

# Execute SQL Commands via Azure CLI (Interactive Login Required)
sqlcmd -S $sql_connection_string -d $sql_db_name -U $admin_user -P $admin_password -Q "$sql_create_table"
sqlcmd -S $sql_connection_string -d $sql_db_name -U $admin_user -P $admin_password -Q "$sql_insert_data"
sqlcmd -S $sql_connection_string -d $sql_db_name -U $admin_user -P $admin_password -Q "$sql_query_data"

# Step 7: Clean Up Resources 
az group delete --name $rg_name --yes --no-wait
