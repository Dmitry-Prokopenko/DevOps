# Variables
module_number="module-4"
task_number="task-7"
ssh_name="ssh-${module_number}-${task_number}"
location="eastus"
user="" # Replace with the email of the user or service principal
rg_name="resource-group-${module_number}-${task_number}"
vnet_name="vnet-${module_number}-${task_number}"
sub_name="sub-${module_number}-${task_number}"
nsg_name="nsg-${module_number}-${task_number}"
vm_name="vm-${module_number}-${task_number}"
storage_account_name="securestorage${RANDOM}${RANDOM}" # Must be globally unique
container_name="secure-container"

# Step 1: Login to Azure (if not already logged in)
az account clear
az config set core.enable_broker_on_windows=false
az login

# Step 2: Create a Resource Group
az group create --name $rg_name --location $location

# Step 3: Create a Storage Account
az storage account create \
  --name $storage_account_name \
  --resource-group $rg_name \
  --location $location \
  --sku Standard_LRS \
  --kind StorageV2

# Step 4: Create a Blob Container
az storage container create \
  --account-name $storage_account_name \
  --name $container_name \
  --auth-mode login

# Step 5: Assign Storage Blob Data Contributor Role to a User or Service Principal
storage_account_id=$(az storage account show \
  --name $storage_account_name \
  --resource-group $rg_name \
  --query id \
  --output tsv)

az role assignment create \
  --assignee $user \
  --role "Storage Blob Data Contributor" \
  --scope "${storage_account_id:1}"

# Step 6: Verify Access for Authorized User
sample_file_name="sample-file.txt"
sample_file_path="$(git rev-parse --show-toplevel)/${sample_file_name}"
echo "This is a secure sample file." > $sample_file_path

az storage blob upload \
  --account-name $storage_account_name \
  --container-name $container_name \
  --name $sample_file_name \
  --file $sample_file_path \
  --auth-mode login

# Step 7: Verify Access Denial for Unauthorized User
# For this step, attempt access with a different user or unauthenticated context.

# Step 1: Generate an SSH Key Pair
ssh-keygen -t rsa -b 2048 -f ~/.ssh/${ssh_name} -N ""
ls -la ~/.ssh/

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

# Step 8: Create a Virtual Machine with a System-Assigned Managed Identity
az vm create \
  --resource-group $rg_name \
  --name $vm_name \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --admin-username azureuser \
  --ssh-key-values "~/.ssh/${ssh_name}.pub" \
  --assign-identity "[system]" \
  --nsg $nsg_name 

# Step 9: Assign Storage Blob Data Reader Role to the VM's Managed Identity
vm_identity=$(az vm show \
  --name $vm_name \
  --resource-group $rg_name \
  --query identity.principalId \
  --output tsv)

az role assignment create \
  --assignee $vm_identity \
  --role "Storage Blob Data Reader" \
  --scope "${storage_account_id:1}"

# Step 10: Verify Managed Identity Access from the VM
ip=$(az vm show \
  --resource-group $rg_name \
  --name $vm_name \
  --show-details \
  --query publicIps \
  --output tsv)

# Step 10: Verification SSH After Provisioning
ssh -i "~/.ssh/${ssh_name}" "azureuser@${ip}"

# On the VM, run the following commands to test access:
curl -L https://aka.ms/InstallAzureCli | bash
exec -l $SHELL
az login --identity
storage_account_name="" # specify the name of storage
container_name="secure-container"
az storage blob list \
  --account-name $storage_account_name \
  --container-name $container_name \
  --auth-mode login \
  --output table
exit

# Step 11: Clean Up Resources 
rm $sample_file_path
rm -rf ~/.ssh/${ssh_name} ~/.ssh/${ssh_name}.pub
az group delete --name $rg_name --yes --no-wait
