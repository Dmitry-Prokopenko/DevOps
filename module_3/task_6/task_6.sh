# Variables
module_number="module-3"
task_number="task-6"
location="canadacentral" # Use desired location
rg_name="resource-group-${module_number}-${task_number}"
function_app_name="functionapp-${module_number}-${task_number}"
storage_account_name="storage${RANDOM}${RANDOM}" # Must be globally unique

# Step 1: Login to Azure
az account clear
az config set core.enable_broker_on_windows=false
az login

# Step 2: Create a Resource Group
az group create --name $rg_name --location $location

# Step 3: Create a Storage Account
az storage account create \
  --name $storage_account_name \
  --location $location \
  --resource-group $rg_name \
  --sku Standard_LRS

# Step 4: Create a Function App
az functionapp create \
  --name $function_app_name \
  --storage-account $storage_account_name \
  --consumption-plan-location $location \
  --resource-group $rg_name \
  --deployment-source-url https://github.com/Azure-Samples/functions-quickstart-javascript \
  --deployment-source-branch main \
  --functions-version 4 \
  --disable-app-insights true \
  --runtime node

# Step 5: Create Application Insights and link it to the Function App
az monitor app-insights component create \
  --app $function_app_name \
  --location $location \
  --resource-group $rg_name \
  --application-type web

instrumentation_key=$(az monitor app-insights component show \
  --app $function_app_name \
  --resource-group $rg_name \
  --query "instrumentationKey" -o tsv)

# Step 6: Update Function App settings with the Instrumentation Key
az webapp config appsettings set \
  --name $function_app_name \
  --resource-group $rg_name \
  --settings "APPINSIGHTS_INSTRUMENTATIONKEY=$instrumentation_key"

# Step 7: Test the Function
function_app_url=$(az functionapp show --name $function_app_name --resource-group $rg_name --query "defaultHostName" -o tsv)
echo "Test your Function App with the following URLs:"
echo "With name parameter: https://${function_app_url}/api/httpexample?name=Azure"
echo "Without name parameter: https://${function_app_url}/api/httpexample"

# Step 8: Retrieve the Function App metrics
az monitor app-insights query \
  --app $function_app_name \
  --resource-group $rg_name \
  --analytics-query "requests | limit 10" \
  --query "tables[*].rows[*]"

# Step 9: Retrieve the Function App metrics
az monitor metrics list \
  --resource $function_app_name \
  --resource-group $rg_name \
  --resource-type "Microsoft.Web/sites" \
  --metric "FunctionExecutionUnits" \
  --interval PT1H \
  --query "value[*].errorCode"

# Step 10: Clean up resources
az group delete --name $rg_name --yes --no-wait
