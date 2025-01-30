#!/bin/bash

# Variables
module_number="module-5"
task_number="task-8"
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

# Step 2: Get principal id
my_principal_id=$(az account show --query user.name --output tsv)

# Step 3: Create Resource Group
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

aks_id=$(az aks show --name $aks_name --resource-group $rg_name --query id --output tsv)

az role assignment create \
  --assignee $my_principal_id \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --scope "${aks_id:1}"

# Step 5: Connect to Cluster

# Install kubectl
# https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/#install-nonstandard-package-tools
# Install kubelogin
# https://azure.github.io/kubelogin/install.html#windows

az aks get-credentials --resource-group $rg_name --name $aks_name --overwrite-existing
kubelogin convert-kubeconfig -l azurecli

# Step 6: Deploy Nginx with CPU requests
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
  replicas: 2
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
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
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
  external_ip=$(kubectl get service $nginx_service --namespace $nginx_namespace --output jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -n "$external_ip" ]; then
    break
  fi
  echo "Waiting for IP..."
  sleep 10
done

echo "NGINX accessible at: http://$external_ip"
curl -sI http://$external_ip


# Step 9: Setup HPA
kubectl autoscale deployment $nginx_app \
  --namespace $nginx_namespace \
  --cpu-percent=35 \
  --min=2 \
  --max=5

kubectl get hpa --namespace $nginx_namespace

# Step 10: Load Simulation
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: load-generator
  namespace: $nginx_namespace
spec:
  restartPolicy: Never
  containers:
    - name: load-generator
      image: busybox
      command:
        - /bin/sh
        - -c
        - |
          while true; do 
            # Internal service request
            wget -q -O- http://$nginx_service.$nginx_namespace.svc.cluster.local >/dev/null &  
            # External public IP request
            wget -q -O- http://$external_ip >/dev/null &  
            wait
          done
EOF


kubectl get pods --namespace $nginx_namespace
# kubectl delete pod load-generator --namespace $nginx_namespace
# kubectl describe pod --namespace $nginx_namespace load-generator


# Step 11: Monitor Scaling
kubectl get hpa --namespace $nginx_namespace --watch


# Step 13: Clean resources
az group delete --name $rg_name --yes --no-wait
