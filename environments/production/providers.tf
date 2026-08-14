###############################################################################
# PROVIDER CONFIGURATION
#
# Kept in its own file rather than inside main.tf. Terraform concatenates
# every .tf file in a directory, so this is purely for humans: when someone
# asks "which region and which credentials does dev use?", they open this
# file instead of scrolling through module wiring.
#
# NOTE: there are no credentials here. The provider uses the standard AWS
# credential chain - the named profile locally, and OIDC-assumed temporary
# credentials in CI. Hardcoding an access key in this file is the single
# most common and most damaging Terraform mistake.
###############################################################################

provider "aws" {
  region = var.aws_region

  # Local development uses a named profile that assumes a role with MFA.
  # In CI this is null and the OIDC-provided credentials are used instead.
  profile = var.aws_profile

  # default_tags applies these to EVERY resource this provider creates,
  # without each module having to handle it.
  #
  # Why tagging matters beyond tidiness:
  #   - Cost Explorer can break the bill down by Environment tag, so you
  #     can see exactly what dev costs versus production
  #   - You can find and clean up orphaned resources by tag
  #   - Automated policies can require tags before allowing creation
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
      CostCenter  = var.cost_center
    }
  }
}
