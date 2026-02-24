# infra/Makefile
# Terraform helpers for ./tfs using shared tfvars

TF_DIR := tfs
TFVARS := $(HOME)/private/shared/infra/ipam.tfvars

.PHONY: init plan apply destroy output fmt validate

init:
	cd $(TF_DIR) && terraform init

plan:
	cd $(TF_DIR) && terraform plan -var-file="$(TFVARS)"

apply:
	cd $(TF_DIR) && terraform apply -var-file="$(TFVARS)"

destroy:
	cd $(TF_DIR) && terraform destroy -var-file="$(TFVARS)"

output:
	cd $(TF_DIR) && terraform output

validate:
	cd $(TF_DIR) && terraform validate

fmt:
	cd $(TF_DIR) && terraform fmt -recursive
