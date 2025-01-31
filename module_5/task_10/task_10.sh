#!/bin/bash

# Variables
module_number="module-5"
task_number="task-10"
location="eastus"
# In the provided subscription, I'm using prokopenko RG
# rg_name="resource-group-${module_number}-${task_number}"
rg_name="prokopenko"
aks_name="aks-${module_number}-${task_number}-$RANDOM"
argocd_namespace="argocd"
app_name="nginx"
app_namespace="nginx-public"
initial_image="nginx:1.18-alpine"
updated_image="nginx:1.19-alpine"


# Step 1: Login to Azure
az account clear
az config set core.enable_broker_on_windows=false
az login


# Step 2: Get principal id
my_principal_id=$(az account show --query user.name --output tsv)


# Step 3: Create Resource Group
az group create --name $rg_name --location $location


# Step 4: Create AKS cluster
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


# Step 5: Get AKS credentials

# Install kubectl
# https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/#install-nonstandard-package-tools
# Install kubelogin
# https://azure.github.io/kubelogin/install.html#windows

az aks get-credentials \
  --resource-group $rg_name \
  --name $aks_name \
  --overwrite-existing
kubelogin convert-kubeconfig -l azurecli


# Step 6: Install ArgoCD
kubectl create namespace $argocd_namespace
kubectl apply --namespace $argocd_namespace -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Change ArgoCD server service type to LoadBalancer
kubectl patch svc argocd-server --namespace $argocd_namespace --patch '{"spec": {"type": "LoadBalancer"}}'

# Wait for ArgoCD to be ready
kubectl wait --namespace $argocd_namespace \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=300s


# Get ArgoCD access information
argocd_password=$(kubectl --namespace $argocd_namespace get secret argocd-initial-admin-secret --output jsonpath='{.data.password}' | base64 -d)
argocd_ip=$(kubectl get svc argocd-server --namespace $argocd_namespace --output jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "URL: http://${argocd_ip}"
echo "Username: admin"
echo "Password: $argocd_password"


# Step 7: Deploy NGINX application through ArgoCD
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $app_namespace
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $app_name
  namespace: $argocd_namespace
spec:
  destination:
    server: https://kubernetes.default.svc
    namespace: $app_namespace
  source:
    helm:
      parameters:
      - name: image.tag
        value: "1.18.0"
    repoURL: https://charts.bitnami.com/bitnami
    chart: $app_name # Explicit chart name (in my case the 'app_name==nginx')
    targetRevision: 13.2.23
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# Wait for initial deployment
kubectl wait --namespace $app_namespace \
  --for=condition=available deployment/$app_name \
  --timeout=300s


# Step 8: Get initial service IP
nginx_ip=$(kubectl --namespace $app_namespace get svc $app_name --output jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Initial Application URL: http://$nginx_ip"
curl -s http://$nginx_ip


# Step 9: Perform image update
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $app_name
  namespace: $argocd_namespace
spec:
  destination:
    server: https://kubernetes.default.svc
    namespace: $app_namespace
  source:
    helm:
      parameters:
      - name: image.tag
        value: "1.19.0"
    repoURL: https://charts.bitnami.com/bitnami
    chart: $app_name # Explicit chart name (in my case the 'app_name==nginx')
    targetRevision: 13.2.23
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF


# Step 10: Verify update
kubectl rollout status deployment/$app_name --namespace $app_namespace


# Step 11: Get updated service IP
echo "Updated Application URL: http://$nginx_ip"
curl -s http://$nginx_ip


# Step 12: Cleanup
az group delete --name $rg_name --yes --no-wait
