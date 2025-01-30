#!/bin/bash

# Variables
module_number="module-5"
task_number="task-5"
location="eastus"
# In the provided subscription, I'm using prokopenko RG
# rg_name="resource-group-${module_number}-${task_number}"
rg_name="prokopenko"
aks_name="aks-${module_number}-${task_number}"
nginx_namespace="nginx-namespace" 
nginx_app="nginx" 
nginx_service="nginx-service" 

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


# Step 4: Create AKS Cluster
az aks create \
  --resource-group $rg_name \
  --name $aks_name \
  --location $location \
  --node-count 1 \
  --node-vm-size "Standard_B2s" \
  --enable-aad \
  --enable-azure-rbac \
  --generate-ssh-keys 

aks_id=$(az aks show \
  --name $aks_name \
  --resource-group $rg_name \
  --query id \
  --output tsv)

az role assignment create \
  --assignee $my_principal_id \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --scope "${aks_id:1}"


# Step 5: Connect to the Cluster

# Install kubectl
# https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/#install-nonstandard-package-tools
# Install kubelogin
# https://azure.github.io/kubelogin/install.html#windows

az aks get-credentials \
  --resource-group $rg_name \
  --name $aks_name \
  --overwrite-existing

kubelogin convert-kubeconfig -l azurecli


# Step 6: Deploy Nginx
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $nginx_namespace
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $nginx_app
  namespace: $nginx_namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $nginx_app
  template:
    metadata:
      labels:
        app: $nginx_app
    spec:
      containers:
      - name: $nginx_app
        image: $nginx_app
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: $nginx_service
  namespace: $nginx_namespace
spec:
  selector:
    app: $nginx_app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: LoadBalancer
EOF


# Step 7: Verify Deployment
while true; do
  external_ip=$(kubectl get service $nginx_service --namespace $nginx_namespace --outpu jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -n "$external_ip" ]; then
    break
  fi
  echo "Waiting for IP..."
  sleep 10
done

echo "NGINX accessible at: http://$external_ip"
curl -sI http://$external_ip

kubectl delete namespace $nginx_namespace


############ TASK 6 ############
task_number="task-6"
task6_acr_name="acr${module_number//-/}${task_number//-/}${RANDOM}"  # New ACR instance
nodejs_app="nodejs-app"
nodejs_namespace="nodejs-namespace"
nodejs_service="nodejs-service"


# Step 8: Create Azure Container Registry
az acr create \
  --resource-group $rg_name \
  --name $task6_acr_name \
  --sku Basic \
  --admin-enabled true


# Step 9: Attach ACR to AKS cluster
az aks update \
  --name $aks_name \
  --resource-group $rg_name \
  --attach-acr $task6_acr_name


# Step 10: Create simple Node.js application
cat > "$(git rev-parse --show-toplevel)/server.js" <<'EOF'
const http = require('http');
const server = http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'text/plain'});
  res.end('Hello from AKS Node.js application!\n');
});
server.listen(80, '0.0.0.0');
EOF

# Create Dockerfile
cat > $(git rev-parse --show-toplevel)/Dockerfile <<'EOF'
FROM node:14-alpine
WORKDIR /app
COPY server.js .
EXPOSE 80
CMD ["node", "server.js"]
EOF


# Step 11: Build and push image to ACR
az acr build \
  --registry $task6_acr_name \
  --image $nodejs_app:latest \
  --file $(git rev-parse --show-toplevel)/Dockerfile .


# Step 12: Deploy application
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
        image: $task6_acr_name.azurecr.io/$nodejs_app:latest
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


# Step 13: Verify Node.js deployment
echo "Waiting for Node.js application IP..."
while true; do
  nodejs_ip=$(kubectl get service $nodejs_service -n $nodejs_namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  [ -n "$nodejs_ip" ] && break
  sleep 10
done

echo "Node.js application URL: http://$nodejs_ip"
curl -sI http://$nodejs_ip


############ TASK 7 ############
configmap_name="app-config"
secret_name="app-secrets"


# Step 14:: Create ConfigMap
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: $configmap_name
  namespace: $nodejs_namespace
data:
  environment: "production"
  log_level: "info"
  api_endpoint: "https://api.example.com/v1"
---
apiVersion: v1
kind: Secret
metadata:
  name: $secret_name
  namespace: $nodejs_namespace
type: Opaque
data:
  api-key: $(echo -n 'secret-api-key' | base64)
  db-password: $(echo -n 'secret-db-password' | base64)
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
        image: $task6_acr_name.azurecr.io/$nodejs_app:latest
        ports:
        - containerPort: 80
        env:
        - name: ENVIRONMENT
          valueFrom:
            configMapKeyRef:
              name: $configmap_name
              key: environment
        - name: API_ENDPOINT
          valueFrom:
            configMapKeyRef:
              name: $configmap_name
              key: api_endpoint
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: $secret_name
              key: api-key
EOF


# Step 15: Test configuration
echo "Configured application URL: http://$nodejs_ip"
curl -s http://$nodejs_ip

pod_name=$(kubectl get pods -n $nodejs_namespace -l app=$nodejs_app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $nodejs_namespace $pod_name -- env | grep -E 'ENVIRONMENT|API_ENDPOINT|API_KEY'


# Step 16: Clean Up
rm -f "$(git rev-parse --show-toplevel)/server.js" "$(git rev-parse --show-toplevel)/Dockerfile"
az group delete --name $rg_name --yes --no-wait
