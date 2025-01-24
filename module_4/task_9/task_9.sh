# Variables
module_number="module-4"
task_number="task-9"
location="canadacentral"
rg_name="resource-group-${module_number}-${task_number}"
sql_server_name="sqlserver${RANDOM}${RANDOM}"
sql_db_name="backup-enabled-db"
restore_db_name="restored-db"
admin_user="sqladmin"
admin_password="${RANDOM}${RANDOM}${RANDOM}Ll~"
pricing_tier="GP_Gen5_2"  # General Purpose, 2 vCores (adjust as needed)
backup_retention_policy="P7D"  # 7 days for this example

# Step 1: Login to Azure (if not already logged in)
az account clear
az config set core.enable_broker_on_windows=false
az login

# Step 2: Create a Resource Group
az group create --name $rg_name --location $location

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

# Step 5: Create an Azure SQL Database with the Desired Service Tier
az sql db create \
  --resource-group $rg_name \
  --server $sql_server_name \
  --name $sql_db_name \
  --service-objective $pricing_tier \
  --backup-storage-redundancy "Geo"  # Enable geo-redundant storage for backups

# Step 6: Configure Long-Term Backup Retention
# Note: Adjust retention policy as needed (e.g., P1Y for 1 year, P10Y for 10 years)
az sql db ltr-policy set \
  --resource-group $rg_name \
  --server $sql_server_name \
  --name $sql_db_name \
  --weekly-retention $backup_retention_policy \
  --monthly-retention "P1M" \
  --yearly-retention "P1Y" \
  --week-of-year 1

# Step 7: Verify Backup Settings (Manual Step)
# You can use the Azure portal or CLI to confirm settings.
# Example CLI command:
az sql db ltr-policy show \
  --resource-group $rg_name \
  --server $sql_server_name \
  --name $sql_db_name

# Step 8: Test Restore Process by Creating a New Database from a Backup
# List available backups
available_backups=$(az sql db ltr-backup list \
  --location $location \
  --server $sql_server_name \
  --database $sql_db_name \
  --query "[0].id" \
  -o tsv)

# Restore the database (need to wait ~24 hours)
az sql db ltr-backup restore \
    --backup-id $available_backups \
    --dest-database $restore_db_name \
    --dest-resource-group $rg_name \
    --dest-server $sql_server_name

# Step 9: Clean Up Resources 
az group delete --name $rg_name --yes --no-wait
