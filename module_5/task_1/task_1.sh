#!/bin/bash

# Variables
module_number="module-5"
task_number="task-1"
location="eastus"
# In the provided subscription, I'm using prokopenko RG
# rg_name="resource-group-${module_number}-${task_number}"
rg_name="prokopenko"
acr_name="acr${module_number//-/}${task_number//-/}${RANDOM}" # Must be globally unique
aci_name="aci-${module_number}-${task_number}"
dns_label="aci-dns-${module_number}-${task_number}-${RANDOM}"
docker_image="flask-app:latest"


# Step 1: Login to Azure
az account clear
az config set core.enable_broker_on_windows=false
az login


# Step 2: Create Resource Group
az group create --name $rg_name --location $location


# Step 3: Create Azure Container Registry (Basic tier)
az acr create \
  --resource-group $rg_name \
  --name $acr_name \
  --sku Basic \
  --admin-enabled true


# Step 4: Create Flask App and Dockerfile
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


# Step 5: Build and Push Image to ACR
az acr build \
  --registry $acr_name \
  --image $docker_image \
  --file $(git rev-parse --show-toplevel)/Dockerfile . 


# Step 6: Deploy Container Instance (B1s - 1 vCPU, 1.5GB RAM)
az container create \
  --resource-group $rg_name \
  --name $aci_name \
  --image $acr_name.azurecr.io/$docker_image \
  --cpu 1 \
  --memory 1.5 \
  --registry-login-server $acr_name.azurecr.io \
  --registry-username $(az acr credential show --name $acr_name --query username -o tsv) \
  --registry-password $(az acr credential show --name $acr_name --query passwords[0].value -o tsv) \
  --dns-name-label $dns_label \
  --os-type "Linux" \
  --ports 80


# Step 7: Verify Deployment
fqdn=$(az container show \
  --resource-group $rg_name \
  --name $aci_name \
  --query "ipAddress.fqdn" \
  --output tsv)

echo "Application URL: http://$fqdn"
curl -s http://$fqdn


# Step 8: Clean Up
rm -f "$(git rev-parse --show-toplevel)/app.py" $(git rev-parse --show-toplevel)/Dockerfile
az group delete --name $rg_name --yes --no-wait

