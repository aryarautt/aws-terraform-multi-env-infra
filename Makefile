# Makefile
#
# Shortcuts that reduce typing and, more importantly, reduce the chance of
# running a production command from a dev directory.
#
#   make plan ENV=dev
#   make apply ENV=staging
#   make destroy ENV=dev
#
# ENV defaults to dev deliberately: if you forget the flag, the safest
# environment is the one that runs.

ENV ?= dev
DIR  = environments/$(ENV)
PROFILE ?= terraform
REGION  ?= ap-south-1

.PHONY: help fmt fmt-check validate init plan apply destroy check evidence audit clean

help:
	@echo "Usage: make <target> ENV=<dev|staging|production>"
	@echo ""
	@echo "  fmt         Rewrite all .tf files into canonical format"
	@echo "  fmt-check   Fail if formatting is wrong (used in CI)"
	@echo "  init        Download providers and configure the backend"
	@echo "  validate    Check syntax and types      (free, no AWS calls)"
	@echo "  plan        Show what would change      (free, read-only)"
	@echo "  apply       Apply the saved plan"
	@echo "  destroy     Tear the environment down"
	@echo "  check       fmt-check + init + validate for EVERY environment"
	@echo "  evidence    Capture portfolio evidence before destroying"
	@echo "  audit       List anything still running and costing money"
	@echo ""
	@echo "Current: ENV=$(ENV)  PROFILE=$(PROFILE)  REGION=$(REGION)"

fmt:
	terraform fmt -recursive

fmt-check:
	terraform fmt -check -recursive -diff

init:
	cd $(DIR) && terraform init

validate:
	cd $(DIR) && terraform validate

plan:
	cd $(DIR) && terraform plan -out=tfplan

apply:
	cd $(DIR) && terraform apply tfplan

destroy:
	@echo "About to DESTROY the '$(ENV)' environment."
	@read -p "Type the environment name to confirm: " c; \
	  [ "$$c" = "$(ENV)" ] || { echo "Aborted."; exit 1; }
	cd $(DIR) && terraform destroy

# Validate every environment without touching AWS. Safe to run any time.
check: fmt-check
	@for e in dev staging production; do \
	  echo "==> $$e"; \
	  ( cd environments/$$e && terraform init -backend=false -input=false >/dev/null && terraform validate ) || exit 1; \
	done
	@for m in modules/*/; do \
	  echo "==> $$m"; \
	  ( cd $$m && terraform init -backend=false -input=false >/dev/null && terraform validate ) || exit 1; \
	done
	@echo "All configurations valid."

evidence:
	./scripts/capture-evidence.sh $(ENV) $(PROFILE) $(REGION)

audit:
	./scripts/aws-audit.sh $(PROFILE) $(REGION)

clean:
	find . -type d -name ".terraform" -prune -exec rm -rf {} +
	find . -type f -name "tfplan" -delete
