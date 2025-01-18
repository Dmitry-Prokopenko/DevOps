# Variables
module_number="module-3"
task_number="task-4"
location="eastus"
rg_name="resource-group-${module_number}-${task_number}"
vnet_name="vnet-${module_number}-${task_number}"
sub_name="sub-${module_number}-${task_number}"
nsg_name="nsg-${module_number}-${task_number}"
vmss_name="vmss-${module_number}-${task_number}"
lb_name="lb-${module_number}-${task_number}"
frontend_ip_name="frontend-ip-${module_number}-${task_number}"
backend_pool_name="backend-pool-${module_number}-${task_number}"
probe_name="probe-${module_number}-${task_number}"
public_ip_name="public-ip-${module_number}-${task_number}"
ssh_name="ssh-${module_number}-${task_number}"

# Step 1: Login to Azure
az account clear
az config set core.enable_broker_on_windows=false
az login

# Step 2: Create Resource Group
az group create --name $rg_name --location $location

# Step 3: Create Public IP for Load Balancer
az network public-ip create \
  --resource-group $rg_name \
  --name $public_ip_name \
  --sku "Standard" \
  --allocation-method Static

# Step 4: Create Load Balancer
az network lb create \
  --resource-group $rg_name \
  --name $lb_name \
  --sku "Standard" \
  --frontend-ip-name $frontend_ip_name \
  --backend-pool-name $backend_pool_name \
  --public-ip-address $public_ip_name

# Step 5: Create Health Probe for Load Balancer
az network lb probe create \
  --resource-group $rg_name \
  --lb-name $lb_name \
  --name $probe_name \
  --protocol Http \
  --port 80 \
  --path "//" \
  --interval 5 \
  --threshold 2

# Step 6: Create Load Balancer Rule
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

# Step 7: Create a Virtual Network and Subnet
az network vnet create \
  --resource-group $rg_name \
  --name $vnet_name \
  --address-prefix 10.0.0.0/16 \
  --subnet-name $sub_name \
  --subnet-prefix 10.0.0.0/24

# Step 8: Create a Network Security Group (NSG)
az network nsg create \
  --resource-group $rg_name \
  --name $nsg_name

# Step 9: Add NSG Rules for HTTP (Port 80)
az network nsg rule create \
  --resource-group $rg_name \
  --nsg-name $nsg_name \
  --name AllowHTTP \
  --priority 1000 \
  --protocol Tcp \
  --destination-port-ranges 80 \
  --source-address-prefixes Internet \
  --access Allow

# Step 10: Apply NSG on sunet level
az network vnet subnet update \
  --resource-group $rg_name \
  --vnet-name $vnet_name \
  --name $sub_name \
  --network-security-group $nsg_name

# Step 11: Generate SSH Key Pair
ssh-keygen -t rsa -b 2048 -f ~/.ssh/${ssh_name} -N ""

# Step 12: Create VMSS with Custom Script Extension to Install NGINX
az vmss create \
  --resource-group $rg_name \
  --name $vmss_name \
  --image Ubuntu2204 \
  --upgrade-policy-mode Automatic \
  --admin-username azureuser \
  --ssh-key-values "~/.ssh/${ssh_name}.pub" \
  --instance-count 1 \
  --lb $lb_name \
  --backend-pool-name $backend_pool_name \
  --vm-sku Standard_B1s \
  --custom-data $(git rev-parse --show-toplevel)/module_3/task_4/cloud-init.txt \
  --public-ip-address "" \
  --subnet $sub_name \
  --vnet-name $vnet_name
# cloud-init.txt (to be placed in the same directory as the task_4.sh)

# Step 13: Get Public IP Address of Load Balancer
lb_ip=$(az network public-ip show \
  --resource-group $rg_name \
  --name $public_ip_name \
  --query "ipAddress" \
  --output tsv)

# Step 14: Test Load Balancer
# Need to wait a few minutes for success provision
echo "Load Balancer Public IP: http://${lb_ip}"
curl "http://${lb_ip}"

# Step 15: Scale the VMSS to Add More Instances
az vmss scale \
  --resource-group $rg_name \
  --name $vmss_name \
  --new-capacity 2

# Step 16: Verify Traffic Distribution
# You should see different content from VM1 and VM2 as the load balancer alternates between the VMs.
# Stop and start a VM to see that works fine.

# Step 17: Clean Up Resources
rm -rf ~/.ssh/${ssh_name} ~/.ssh/${ssh_name}.pub
az group delete --name $rg_name --yes --no-wait
