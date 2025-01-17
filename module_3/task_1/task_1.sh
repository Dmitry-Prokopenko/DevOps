# Variables
module_number="module-3"
taks_number="task-1"
ssh_name="ssh-${module_number}-${taks_number}"
location="eastus"
rg_name="resource-group-${module_number}-${taks_number}"
vnet_name="vnet-${module_number}-${taks_number}"
sub_name="sub-${module_number}-${taks_number}"
nsg_name="nsg-${module_number}-${taks_number}"
vm_name="vm-${module_number}-${taks_number}"

# Step 1: Generate an SSH Key Pair
ssh-keygen -t rsa -b 2048 -f ~/.ssh/${ssh_name} -N ""
ls -la ~/.ssh/

# Step 2: Login to Azure
az account clear
az config set core.enable_broker_on_windows=false
az login

# Step 3: Create a Resource Group
az group create --name $rg_name --location $location

# Step 3: Create a Virtual Network and Subnet
az network vnet create \
  --resource-group $rg_name \
  --name $vnet_name \
  --address-prefix 10.0.0.0/16 \
  --subnet-name $sub_name \
  --subnet-prefix 10.0.0.0/24

# Step 5: Create a Network Security Group (NSG)
az network nsg create \
  --resource-group $rg_name \
  --name $nsg_name

# Add NSG Rules for SSH (Port 22) and HTTP (Port 80)
az network nsg rule create \
  --resource-group  $rg_name \
  --nsg-name $nsg_name \
  --name AllowSSH \
  --priority 1000 \
  --protocol Tcp \
  --destination-port-ranges 22 \
  --access Allow

az network nsg rule create \
  --resource-group $rg_name \
  --nsg-name $nsg_name \
  --name AllowHTTP \
  --priority 1010 \
  --protocol Tcp \
  --destination-port-ranges 80 \
  --access Allow

# Step 6: Create a Linux VM
az vm create \
  --resource-group $rg_name \
  --name $vm_name \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --admin-username azureuser \
  --ssh-key-values "~/.ssh/${ssh_name}.pub" \
  --nsg $nsg_name 

# Step 7: Install NGINX
az vm run-command invoke \
   --resource-group $rg_name \
   --name $vm_name \
   --command-id RunShellScript \
   --scripts "sudo apt-get update && sudo apt-get install -y nginx && sudo systemctl restart nginx"

# Step 8: Get IP address
ip=$(az vm show \
  --resource-group $rg_name \
  --name $vm_name \
  --show-details \
  --query publicIps \
  --output tsv)

# Step 9: Verification NGINX After Provisioning
echo "http://${ip}"
curl "http://${ip}"

# Step 10: Verification SSH After Provisioning
ssh -i "~/.ssh/${ssh_name}" "azureuser@${ip}"

# Step 11: Remove an SSH Key Pair
rm -rf ~/.ssh/${ssh_name} ~/.ssh/${ssh_name}.pub

# Step 12: Remove a Resource Group
az group delete --name $rg_name --yes --no-wait
