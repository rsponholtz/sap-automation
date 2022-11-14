#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error when substituting.
set -eu

#--------------------------------------+---------------------------------------8
#                                                                              |
# Setup variables                                                              |
#                                                                              |
#--------------------------------------+---------------------------------------8
green="\e[1;32m" ; reset="\e[0m" ; boldred="\e[1;31m"
__basedir=`pwd`
acss_environment=${ACSS_ENVIRONMENT}
acss_sap_product=${ACSS_SAP_PRODUCT}
acss_workloads_extension_url="https://github.com/Azure/Azure-Center-for-SAP-solutions-preview/raw/main/CLI_Documents/ACSS_CLI_Extension/workloads-0.1.0-py3-none-any.whl"
#--------------------------------------+---------------------------------------8

#--------------------------------------+---------------------------------------8
#                                                                              |
# Install ACSS Workloads extension for Azure CLI                               |
#                                                                              |
#--------------------------------------+---------------------------------------8
set -x
if [ -z "$(az extension list | grep \"name\": | grep \"workloads\")" ]
then
  echo -e "$green--- Installing ACSS \"Workloads\" CLI extension ---$reset"
  wget $acss_workloads_extension_url || exit 1
  az extension add --source=./workloads-0.1.0-py3-none-any.whl --yes || exit 1
else
  echo -e "$green--- ACSS \"Workloads\" CLI extension already installed ---$reset"
fi
set +x
#--------------------------------------+---------------------------------------8

#--------------------------------------+---------------------------------------8
#                                                                              |
# Authenticate to Azure                                                        |
#                                                                              |
#--------------------------------------+---------------------------------------8
az login --service-principal --username $(ARM_CLIENT_ID) --password=$ARM_CLIENT_SECRET --tenant $(ARM_TENANT_ID)  --output none
#--------------------------------------+---------------------------------------8

#--------------------------------------+---------------------------------------8
#                                                                              |
# Initialize Terraform and access State File                                   |
#                                                                              |
#--------------------------------------+---------------------------------------8
# Get Terraform State Outputs
# TODO: Should test if Terraform is available or needs to be installed
#
echo -e "$green--- Initializing Terraform for: $SAP_SYSTEM_CONFIGURATION_NAME ---$reset"
__configDir=${__basedir}/WORKSPACES/SYSTEM/${SAP_SYSTEM_FOLDER}
__moduleDir=${__basedir}/deploy/terraform/run/sap_system/
TF_DATA_DIR=${__configDir}

cd ${__configDir}

# Init Terraform
__output=$( \
terraform -chdir="${__moduleDir}"                                                       \
init -upgrade=true                                                                      \
--backend-config "subscription_id=${ARM_SUBSCRIPTION_ID}"                               \
--backend-config "resource_group_name=${TERRAFORM_REMOTE_STORAGE_RESOURCE_GROUP_NAME}"  \
--backend-config "storage_account_name=${TERRAFORM_REMOTE_STORAGE_ACCOUNT_NAME}"        \
--backend-config "container_name=tfstate"                                               \
--backend-config "key=${SAP_SYSTEM_FOLDER}.terraform.tfstate"                           \
)
[ $? -ne 0 ] && echo "$__output" && exit 1
echo -e "$green--- Successfully configured the backend "azurerm"! Terraform will automatically use this backend unless the backend configuration changes. ---$reset"

# Fetch values from Terraform State file
acss_scs_vm_id=$(     terraform -chdir="${__moduleDir}" output scs_vm_ids                  | awk -F\" '{print $2}' | tr -d '\n\r\t[:space:]')
acss_sid=$(           terraform -chdir="${__moduleDir}" output sid                         | tr -d '"')
acss_resource_group=$(terraform -chdir="${__moduleDir}" output created_resource_group_name | tr -d '"')
acss_location=$(      terraform -chdir="${__moduleDir}" output region                      | tr -d '"')

unset TF_DATA_DIR __configDir __moduleDir __output
cd $__basedir
#--------------------------------------+---------------------------------------8

#--------------------------------------+---------------------------------------8
#                                                                              |
# Register in ACSS                                                             |
#                                                                              |
#--------------------------------------+---------------------------------------8
echo -e "$green--- Registering SID: $acss_sid in ACSS ---$reset"

# Create JSON Payload as variable
acss_configuration=$(cat << EOF
  {
    "configurationType": "Discovery",
    "centralServerVmId": "${acss_scs_vm_id}"
  }
EOF
)

# ACSS Registration Command
set -x

az workloads sap-virtual-instance create              \
--sap-virtual-instance-name  "${acss_sid}"            \
--resource-group             "${acss_resource_group}" \
--location                   "${acss_location}"       \
--environment                "${acss_environment}"    \
--sap-product                "${acss_sap_product}"    \
--configuration              "${acss_configuration}"  \
  || exit 1

set +x
#--------------------------------------+---------------------------------------8