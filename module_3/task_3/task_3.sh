# Variables
module_number="module-3"
task_number="task-3"
location="eastus"
rg_name="resource-group-${module_number}-${task_number}"
vnet_name="vnet-${module_number}-${task_number}"
sub_name="sub-${module_number}-${task_number}"
nsg_name="nsg-${module_number}-${task_number}"
lb_name="lb-${module_number}-${task_number}"
frontend_ip_name="frontend-ip-${module_number}-${task_number}"
backend_pool_name="backend-pool-${module_number}-${task_number}"
probe_name="probe-${module_number}-${task_number}"
vm_name_1="vm1-${module_number}-${task_number}"
vm_name_2="vm2-${module_number}-${task_number}"
public_ip_name="public-ip-${module_number}-${task_number}"
ssh_name="ssh-${module_number}-${task_number}"
nic_name_1="nic-1-${module_number}-${task_number}"
nic_name_2="nic-2-${module_number}-${task_number}"

# Step 1: Login to Azure
az account clear
az config set core.enable_broker_on_windows=false
az login

# Step 2: Create Resource Group
az group create --name $rg_name --location $location

# Step 3: Create a Virtual Network and Subnet
az network vnet create \
  --resource-group $rg_name \
  --name $vnet_name \
  --address-prefix 10.0.0.0/16 \
  --subnet-name $sub_name \
  --subnet-prefix 10.0.0.0/24
  
# Step 4: Create NICs
az network nic create \
    --name $nic_name_1 \
    --resource-group $rg_name \
    --vnet-name $vnet_name \
    --subnet $sub_name 

az network nic create \
    --name $nic_name_2 \
    --resource-group $rg_name \
    --vnet-name $vnet_name \
    --subnet $sub_name 

# Step 5: Create a Network Security Group (NSG)
az network nsg create \
  --resource-group $rg_name \
  --name $nsg_name

# Step 6: Add NSG Rules for HTTP (Port 80)
az network nsg rule create \
  --resource-group $rg_name \
  --nsg-name $nsg_name \
  --name AllowHTTP \
  --priority 1000 \
  --protocol Tcp \
  --destination-port-ranges 80 \
  --source-address-prefixes Internet \
  --access Allow

# Step 7: Apply NSG on sunet level
az network vnet subnet update \
  --resource-group $rg_name \
  --vnet-name $vnet_name \
  --name $sub_name \
  --network-security-group $nsg_name

# Step 8: Generate SSH Key Pair
ssh-keygen -t rsa -b 2048 -f ~/.ssh/${ssh_name} -N ""

# Step 9: Create First Linux VM (VM1)
az vm create \
  --resource-group $rg_name \
  --name $vm_name_1 \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --admin-username azureuser \
  --ssh-key-values "~/.ssh/${ssh_name}.pub" \
  --nics $nic_name_1 \
  --public-ip-address ""

# Step 10: Create Second Linux VM (VM2)
az vm create \
  --resource-group $rg_name \
  --name $vm_name_2 \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --admin-username azureuser \
  --ssh-key-values "~/.ssh/${ssh_name}.pub" \
  --nics $nic_name_2 \
  --public-ip-address ""

# Step 11: Install NGINX on VM1
az vm run-command invoke \
   --resource-group $rg_name \
   --name $vm_name_1 \
   --command-id RunShellScript \
   --scripts "sudo apt-get update && sudo apt-get install -y nginx && echo '${vm_name_1}: Welcome to NGINX' | sudo tee /var/www/html/index.html && sudo systemctl restart nginx"

# Step 12: Install NGINX on VM2
az vm run-command invoke \
   --resource-group $rg_name \
   --name $vm_name_2 \
   --command-id RunShellScript \
   --scripts "sudo apt-get update && sudo apt-get install -y nginx && echo '${vm_name_2}: Welcome to NGINX' | sudo tee /var/www/html/index.html && sudo systemctl restart nginx"

# Step 13: Create Load Balancer
az network lb create \
  --resource-group $rg_name \
  --name $lb_name \
  --sku Standard \
  --location $location \
  --frontend-ip-name $frontend_ip_name \
  --backend-pool-name $backend_pool_name

# Step 14: Create publick IP
az network public-ip create \
  --resource-group $rg_name \
  --name $public_ip_name \
  --sku Standard \
  --allocation-method Static

# Step 15: Update frontend config (add publick IP)
az network lb frontend-ip update \
  --resource-group $rg_name \
  --lb-name $lb_name \
  --name $frontend_ip_name \
  --public-ip-address $public_ip_name


# Step 16: Add VMs to pool
az network nic ip-config address-pool add \
    --address-pool $backend_pool_name \
    --ip-config-name "ipconfig1" \
    --nic-name $nic_name_1 \
    --resource-group $rg_name \
    --lb-name $lb_name

az network nic ip-config address-pool add \
    --address-pool $backend_pool_name \
    --ip-config-name "ipconfig1" \
    --nic-name $nic_name_2 \
    --resource-group $rg_name \
    --lb-name $lb_name

# Step 17: Create Health Probe
az network lb probe create \
  --resource-group $rg_name \
  --lb-name $lb_name \
  --name $probe_name \
  --protocol Http \
  --port 80 \
  --interval 5 \
  --threshold 2 \
  --path "//"

# Step 18: Create Load Balancer Rule for HTTP Traffic
az network lb rule create \
  --resource-group $rg_name \
  --lb-name $lb_name \
  --name "HTTP-Rule" \
  --protocol Tcp \
  --frontend-port 80 \
  --backend-port 80 \
  --frontend-ip-name $frontend_ip_name \
  --backend-pool-name $backend_pool_name \
  --probe $probe_name

# # Step 19: Get Public IP Address of Load Balancer
lb_ip=$(az network public-ip show \
  --resource-group $rg_name \
  --name $public_ip_name \
  --query "ipAddress" \
  --output tsv)

# Step 20: Test Load Balancer in Browser
echo "http://${lb_ip}"
curl "http://${lb_ip}"

# Step 21: Verify Traffic Distribution
# You should see different content from VM1 and VM2 as the load balancer alternates between the VMs.
# Stop and start a VM to see that works fine.

# Step 22: Clean Up
rm -rf ~/.ssh/${ssh_name} ~/.ssh/${ssh_name}.pub
az group delete --name $rg_name --yes --no-wait
