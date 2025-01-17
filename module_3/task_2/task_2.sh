# Variables
module_number="module-3"
task_number="task-2"
location="eastus"
rg_name="resource-group-${module_number}-${task_number}"
vnet_name="vnet-${module_number}-${task_number}"
sub_name="sub-${module_number}-${task_number}"
nsg_name="nsg-${module_number}-${task_number}"
vm_name="vm-${task_number}" # vm_name="vm-${module_number}-${task_number}" --> cannot be more than 15 characters long
admin_username="azureuser"
admin_password="${RANDOM}${RANDOM}${RANDOM}Ll~"

# Step 1: Login to Azure
az account clear
az config set core.enable_broker_on_windows=false
az login

# Step 2: Create a Resource Group
az group create --name $rg_name --location $location

# Step 3: Create a Virtual Network and Subnet
az network vnet create \
  --resource-group $rg_name \
  --name $vnet_name \
  --address-prefix 10.0.0.0/16 \
  --subnet-name $sub_name \
  --subnet-prefix 10.0.0.0/24

# Step 4: Create a Network Security Group (NSG)
az network nsg create \
  --resource-group $rg_name \
  --name $nsg_name

# Add NSG Rules for RDP (Port 3389) and HTTP (Port 80)
az network nsg rule create \
  --resource-group $rg_name \
  --nsg-name $nsg_name \
  --name AllowRDP \
  --priority 1000 \
  --protocol Tcp \
  --destination-port-ranges 3389 \
  --access Allow

az network nsg rule create \
  --resource-group $rg_name \
  --nsg-name $nsg_name \
  --name AllowHTTP \
  --priority 1010 \
  --protocol Tcp \
  --destination-port-ranges 80 \
  --access Allow

# Step 5: Create a Windows VM
az vm create \
  --resource-group $rg_name \
  --name $vm_name \
  --image Win2019Datacenter \
  --size Standard_B1s \
  --admin-username $admin_username \
  --admin-password $admin_password \
  --nsg $nsg_name 

# Step 6: Install IIS (Web Server)
az vm run-command invoke \
  --resource-group $rg_name \
  --name $vm_name \
  --command-id RunPowerShellScript \
  --scripts "Install-WindowsFeature -Name Web-Server -IncludeManagementTools"

# Step 7: Deploy a Simple Test HTML Page
az vm run-command invoke \
  --resource-group $rg_name \
  --name $vm_name \
  --command-id RunPowerShellScript \
  --scripts 'New-Item -Path "C:\\inetpub\\wwwroot\\index.html" -ItemType File -Value "<html><body><h1>Welcome to Azure Windows VM!</h1></body></html>"'

# Step 8: Get the Public IP Address of the VM
ip=$(az vm show \
  --resource-group $rg_name \
  --name $vm_name \
  --show-details \
  --query publicIps \
  --output tsv)

# Step 9: Verify Access to the Test Page
echo "http://${ip}"
curl "http://${ip}"


# Step 10: Verification for RDP Access
echo "Use Remote Desktop to connect to:"
echo "$ip"
echo "$admin_username"
echo "$admin_password"

# Step 11: Remove a Resource Group
az group delete --name $rg_name --yes --no-wait
