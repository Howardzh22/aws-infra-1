# aws-infra

*terraform
//First, install the HashiCorp tap, a repository of all our Homebrew packages.

brew tap hashicorp/tap

//Now, install Terraform with hashicorp/tap/terraform.

brew install hashicorp/tap/terraform

//To update to the latest version of Terraform, first update Homebrew.

brew update

//Then, run the upgrade command to download and use the latest Terraform version.

brew upgrade hashicorp/tap/terraform

//Enable tab completion by zsh

touch ~/.bashrc

//Then install the autocomplete package.

terraform -install-autocomplete

//init
terraform fmt && terraform init

//validate
terraform validate

//plan and apply
terraform plan -var-file="var.tfvars" && terraform plan -var-file="var.tfvars"
