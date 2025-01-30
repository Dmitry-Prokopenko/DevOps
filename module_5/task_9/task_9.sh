#!/bin/bash

# Variables
module_number="module-5"
task_number="task-9"
location="eastus"
# In the provided subscription, I'm using prokopenko RG
# rg_name="resource-group-${module_number}-${task_number}"
rg_name="prokopenko"
aks_name="aks-${module_number}-${task_number}"
acr_name="acr${module_number//-/}${task_number//-/}${RANDOM}"
nodejs_app="nodejs-app"
nodejs_namespace="nodejs-namespace"
nodejs_service="nodejs-service"


# Step 1: Login to Azure
az account clear
az config set core.enable_broker_on_windows=false
az login


# Step 2: Get principal id
my_principal_id=$(az account show --query user.name --output tsv)


# Step 3: Create Resource Group
az group create --name $rg_name --location $location


# Step 4: Create ACR
az acr create \
  --resource-group $rg_name \
  --name $acr_name \
  --sku Basic \
  --admin-enabled true


# Step 5: Create AKS Cluster
az aks create \
  --resource-group $rg_name \
  --name $aks_name \
  --location $location \
  --node-count 1 \
  --node-vm-size "Standard_B2s" \
  --attach-acr $acr_name \
  --generate-ssh-keys

aks_id=$(az aks show --name $aks_name --resource-group $rg_name --query id --output tsv)

az role assignment create \
  --assignee $my_principal_id \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --scope "${aks_id:1}"


# Step 6: Connect to AKS

# Install kubectl
# https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/#install-nonstandard-package-tools
# Install kubelogin
# https://azure.github.io/kubelogin/install.html#windows

az aks get-credentials \
  --resource-group $rg_name \
  --name $aks_name \
  --overwrite-existing
kubelogin convert-kubeconfig -l azurecli



# Step 6: Create initial application files
cat <<EOF > server.js
const http = require('http');
const server = http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'text/plain'});
  res.end('Hello from AKS Node.js application v1!\n');
});
server.listen(80, '0.0.0.0');
EOF

cat <<EOF > Dockerfile
FROM node:14-alpine
WORKDIR /app
COPY server.js .
EXPOSE 80
CMD ["node", "server.js"]
EOF


# Step 8: Build and push initial image
az acr build \
  --registry $acr_name \
  --image $nodejs_app:v1 \
  --file Dockerfile .


# Step 9: Deploy initial version
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $nodejs_namespace
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $nodejs_app
  namespace: $nodejs_namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $nodejs_app
  template:
    metadata:
      labels:
        app: $nodejs_app
    spec:
      containers:
      - name: $nodejs_app
        image: $acr_name.azurecr.io/$nodejs_app:v1
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: $nodejs_service
  namespace: $nodejs_namespace
spec:
  type: LoadBalancer
  selector:
    app: $nodejs_app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
EOF


# Step 10: Wait for initial IP
echo "Waiting for v1 IP..."
while true; do
  nodejs_ip=$(kubectl get svc/$nodejs_service --namespace $nodejs_namespace --output jsonpath='{.status.loadBalancer.ingress[0].ip}')
  [ -n "$nodejs_ip" ] && break
  sleep 5
done
echo "v1 IP: $nodejs_ip"
curl -s http://$nodejs_ip


# Step 11: Update application
sed -i 's/v1!/v2!/' server.js


# Step 12: Build and push updated image
az acr build \
  --registry $acr_name \
  --image $nodejs_app:v2 \
  --file Dockerfile .


# Step 13: Perform rolling update
kubectl set image deployment/$nodejs_app --namespace $nodejs_namespace $nodejs_app=$acr_name.azurecr.io/$nodejs_app:v2


# Step 14: Verify update
kubectl rollout status deployment/$nodejs_app --namespace $nodejs_namespace
curl -s http://$nodejs_ip


# Step 15: Cleanup
rm -f "$(git rev-parse --show-toplevel)/server.js" "$(git rev-parse --show-toplevel)/Dockerfile"
az group delete --name $rg_name --yes --no-wait