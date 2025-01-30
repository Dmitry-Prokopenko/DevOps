#!/bin/bash

# Variables
module_number="module-5"
task_number="task-2"
location="eastus"
# In the provided subscription, I'm using prokopenko RG
# rg_name="resource-group-${module_number}-${task_number}"
rg_name="prokopenko"
acr_name="acr${module_number//-/}${task_number//-/}${RANDOM}" # Must be globally unique
aci_name="aci-${module_number}-${task_number}"
dns_label="aci-dns-${module_number}-${task_number}-${RANDOM}"
docker_image="flask-app:latest"
env_var_name="APP_MESSAGE"
env_var_value="task_2"

# Step 1: Login to Azure
az account clear
az config set core.enable_broker_on_windows=false
az login

# Step 2: Create Resource Group (if not exists)
az group create --name $rg_name --location $location

# Step 3: Create Azure Container Registry (Basic tier)
az acr create \
  --resource-group $rg_name \
  --name $acr_name \
  --sku Basic \
  --admin-enabled true

# Step 4: Modify Flask App to Read Environment Variable and Create Dockerfile
cat > "$(git rev-parse --show-toplevel)/app.py" << EOF
from flask import Flask
import os

app = Flask(__name__)

@app.route('/')
def hello():
    message = os.getenv("${env_var_name}", "Default Message")
    return f"Message: Hello from Environment Variables! {message}"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
EOF

cat >"$(git rev-parse --show-toplevel)/Dockerfile" << EOF
FROM python:3.9-alpine
WORKDIR /app
COPY app.py ./
RUN pip install Flask
EXPOSE 80
CMD ["python", "app.py"]
EOF

# Step 5: Build and Push Image to ACR
az acr build \
  --registry $acr_name \
  --image $docker_image \
  --file $(git rev-parse --show-toplevel)/Dockerfile .

# Step 6: Deploy Container Instance with Environment Variable
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
  --ports 80 \
  --environment-variables $env_var_name=$env_var_value

# Step 7: Verify Deployment
fqdn=$(az container show \
  --resource-group $rg_name \
  --name $aci_name \
  --query "ipAddress.fqdn" \
  --output tsv)

echo "Application URL: http://$fqdn"
response=$(curl -s http://$fqdn)
echo "Response from Application: $response"

# Check if the response contains the environment variable value
if [[ "$response" == *"$env_var_value"* ]]; then
  echo "Environment variable is correctly configured and working."
else
  echo "Failed to verify environment variable."
fi

# Step 8: Clean Up
rm -f "$(git rev-parse --show-toplevel)/app.py" "$(git rev-parse --show-toplevel)/Dockerfile"
az group delete --name $rg_name --yes --no-wait
