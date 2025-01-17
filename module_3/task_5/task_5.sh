# Variables
module_number="module-3"
task_number="task-5"
location="canadacentral" # "eastus"
rg_name="resource-group-${module_number}-${task_number}"
app_name="webapp-${module_number}-${task_number}"
plan_name="appservice-plan-${module_number}-${task_number}"

# Step 1: Login to Azure
az account clear
az config set core.enable_broker_on_windows=false
az login

# Step 2: Create a Resource Group
az group create --name $rg_name --location $location

# Step 4: Register "Microsoft.Web"
# az provider register --namespace "Microsoft.Web"

# Step 4: Create an App Service Plan (Free Tier)
az appservice plan create \
  --name $plan_name \
  --resource-group $rg_name \
  --location $location \
  --sku P0V3 \
  --is-linux

# Step 4: Create a Web App
az webapp create \
  --name $app_name \
  --resource-group $rg_name \
  --plan $plan_name \
  --runtime "PYTHON:3.9"

# Step 5: Deploy the Application
# Sample "Hello World" Python app deployment using GitHub
# Replace with your repository URL or use the sample below
sample_repo="https://github.com/Azure-Samples/python-docs-hello-world"

az webapp deployment source config \
  --name $app_name \
  --resource-group $rg_name \
  --repo-url $sample_repo \
  --branch master \
  --manual-integration

# Step 6: Enable App Service Logs
az webapp log config \
  --name $app_name \
  --resource-group $rg_name \
  --application-logging filesystem \
  --level verbose \
  --web-server-logging filesystem \
  --detailed-error-messages true \
  --failed-request-tracing true

# Step 7: Test the Deployment
# Get the URL of the deployed application
app_url=$(az webapp show \
  --name $app_name \
  --resource-group $rg_name \
  --query "defaultHostName" \
  --output tsv)

# Test the deployed application
echo "Deployed Web App URL: http://${app_url}"
curl "http://${app_url}"

# Step 8: Clean up Resources
az group delete --name $rg_name --yes --no-wait
