TF ?= terraform
AV ?= 

.PHONY: init fmt validate plan apply destroy

init:
	$(AV)$(TF) init

fmt:
	$(TF) fmt

validate:
	$(TF) validate

plan:
	$(AV)$(TF) plan

apply:
	$(AV)$(TF) apply

destroy:
	$(AV)$(TF) destroy -auto-approve

# Usage examples:
# With aws-vault: `make AV="aws-vault exec <profile> -- " apply`
# Or set AV in environment: `export AV="aws-vault exec <profile> -- "`
