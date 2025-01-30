#!/bin/bash

# Due to the limitation on git bush that approach doesn't work
# Debug
# Command arguments: ['container', 'create', '--resource-group', 'prokopenko', '--name', 'aci-module-5-task-1', '--image', 'acrmodule5task17792.azurecr.io/flask-app:latest', '--cpu', '1', '--memory', '1.5', '--dns-name-label', 'aci-dns-module-5-task-1-28910', '--os-type', 'Linux', '--acr-identity', 'C:/Program Files/Git/subscriptions/9a6ae428-d8c3-44fe-bdf2-4e08593901a0/resourcegroups/prokopenko/providers/Microsoft.ManagedIdentity/userAssignedIdentities/aci-identity-module-5-task-1', '--assign-identity', 'C:/Program Files/Git/subscriptions/9a6ae428-d8c3-44fe-bdf2-4e08593901a0/resourcegroups/prokopenko/providers/Microsoft.ManagedIdentity/userAssignedIdentities/aci-identity-module-5-task-1', '--ports', '80', '--debug']

# Variables
module_number="module-5"
task_number="task-1"
location="eastus"
# In the provided subscription, I'm using prokopenko RG
# rg_name="resource-group-${module_number}-${task_number}"
rg_name="prokopenko"
acr_name="acr${module_number//-/}${task_number//-/}${RANDOM}"
aci_name="aci-${module_number}-${task_number}"
identity_name="aci-identity-${module_number}-${task_number}"
dns_label="aci-dns-${module_number}-${task_number}-${RANDOM}"
docker_image="flask-app:latest"

# Step 1: Login to Azure
az account clear
az config set core.enable_broker_on_windows=false
az login

# Step 2: Create Resource Group
az group create --name $rg_name --location $location

# Step 3: Create Azure Container Registry (Basic tier) with admin disabled
az acr create \
  --resource-group $rg_name \
  --name $acr_name \
  --sku Basic \
  --admin-enabled false

# Step 4: Create User-Assigned Managed Identity
az identity create \
  --resource-group $rg_name \
  --name $identity_name

# Step 5: Assign AcrPull Role to Managed Identity
acr_id=$(az acr show --name $acr_name --resource-group $rg_name --query id --output tsv)
principal_id=$(az identity show --resource-group $rg_name --name $identity_name --query principalId --output tsv)
az role assignment create \
  --assignee $principal_id \
  --scope "${acr_id:1}" \
  --role AcrPull

# Step 6: Create Flask App and Dockerfile
cat > "$(git rev-parse --show-toplevel)/app.py" << EOF
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return 'Hello from Azure Container Instances!'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
EOF

cat >"$(git rev-parse --show-toplevel)/Dockerfile" << EOF
FROM python:3.9-alpine
WORKDIR /app
COPY app.py .
RUN pip install Flask
EXPOSE 80
CMD ["python", "app.py"]
EOF

# Step 7: Build and Push Image to ACR
az acr build \
  --registry $acr_name \
  --image $docker_image \
  --file $(git rev-parse --show-toplevel)/Dockerfile . 

# Step 8: Deploy Container Instance with Managed Identity
identity_id=$(az identity show --resource-group $rg_name --name $identity_name --query id --output tsv)

az container create \
  --resource-group $rg_name \
  --name $aci_name \
  --image $acr_name.azurecr.io/$docker_image \
  --cpu 1 \
  --memory 1.5 \
  --dns-name-label $dns_label \
  --os-type "Linux" \
  --acr-identity $identity_id \
  --assign-identity $identity_id \
  --ports 80


# Step 9: Verify Deployment
fqdn=$(az container show \
  --resource-group $rg_name \
  --name $aci_name \
  --query "ipAddress.fqdn" \
  --output tsv)

echo "Application URL: http://$fqdn"
curl -s http://$fqdn

# Step 10: Clean Up
rm -f "$(git rev-parse --show-toplevel)/app.py" $(git rev-parse --show-toplevel)/Dockerfile
az group delete --name $rg_name --yes --no-wait
