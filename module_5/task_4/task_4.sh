#!/bin/bash

# Variables
module_number="module-5"
task_number="task-4"
location="eastus"
# In the provided subscription, I'm using prokopenko RG
# rg_name="resource-group-${module_number}-${task_number}"
rg_name="prokopenko"
acr_name="acr${module_number//-/}${task_number//-/}${RANDOM}"
aci_name="aci-${module_number}-${task_number}"
dns_label="aci-dns-${module_number}-${task_number}-${RANDOM}"
docker_image="flask-app:latest"
# Key Vault variables
keyvault_name="kv-${module_number}-${task_number}-${RANDOM}"
secret_name="my-secret"
secret_value="supersecretvalue"


# Step 1: Login to Azure
az account clear
az config set core.enable_broker_on_windows=false
az login


# Step 2: Get my principal id
my_principal_id=$(az account show \
  --query user.name \
  --output tsv)


# Step 3: Create Resource Group (if not exists)
az group create --name $rg_name --location $location


# Step 4: Create Azure Container Registry
az acr create \
  --resource-group $rg_name \
  --name $acr_name \
  --sku Basic \
  --admin-enabled true


# Step 5: Create Key Vault and secret
az keyvault create \
  --name $keyvault_name \
  --resource-group $rg_name \
  --location $location

akv_id=$(az keyvault show \
  --name $keyvault_name \
  --resource-group $rg_name \
  --query id \
  --output tsv)

az role assignment create \
  --assignee $my_principal_id \
  --role "Key Vault Administrator" \
  --scope "${akv_id:1}"

az keyvault secret set \
  --vault-name $keyvault_name \
  --name $secret_name \
  --value $secret_value


# Step 6: Create application files
cat > "$(git rev-parse --show-toplevel)/app.py" << EOF
from flask import Flask
import os
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

app = Flask(__name__)

keyvault_name = os.environ["KEY_VAULT_NAME"]
secret_name = os.environ["SECRET_NAME"]
keyvault_url = f"https://{keyvault_name}.vault.azure.net"

credential = DefaultAzureCredential()
client = SecretClient(vault_url=keyvault_url, credential=credential)

@app.route('/')
def hello():
    retrieved_secret = client.get_secret(secret_name)
    return f'Secret value: {retrieved_secret.value}'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
EOF

cat > "$(git rev-parse --show-toplevel)/Dockerfile" << EOF
FROM python:3.9-alpine
WORKDIR /app
COPY app.py .
RUN pip install Flask azure-keyvault-secrets azure-identity
EXPOSE 80
CMD ["python", "app.py"]
EOF


# Step 7: Build and push image
az acr build --registry $acr_name --image $docker_image --file "$(git rev-parse --show-toplevel)/Dockerfile" .


# Step 8: Deploy container with managed identity
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
  --os-type Linux \
  --ports 80 \
  --assign-identity \
  --environment-variables KEY_VAULT_NAME=$keyvault_name SECRET_NAME=$secret_name


# Step 9: Assign Key Vault access
aci_principal_id=$(az container show --resource-group $rg_name --name $aci_name --query 'identity.principalId' -o tsv)

az role assignment create \
  --assignee $aci_principal_id \
  --role "Key Vault Secrets User" \
  --scope "${akv_id:1}"


# Step 10: Verify access
fqdn=$(az container show --resource-group $rg_name --name $aci_name --query 'ipAddress.fqdn' -o tsv)
echo "Access your application at: http://$fqdn"
curl -s "http://${fqdn}"


# Step 11: Clean Up
rm -f "$(git rev-parse --show-toplevel)/app.py" "$(git rev-parse --show-toplevel)/Dockerfile"
az group delete --name $rg_name --yes --no-wait
