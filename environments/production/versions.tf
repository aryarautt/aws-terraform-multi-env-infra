###############################################################################
# VERSION CONSTRAINTS
#
# Why pin versions at all:
#   Without constraints, `terraform init` downloads the newest provider
#   available. A new major release can rename or remove arguments, so code
#   that worked yesterday fails today with no change on your side.
#
# The operators:
#   >= 1.10.0        at least this version
#   ~> 5.70          any 5.x at or above 5.70, but NOT 6.0
#   >= 5.70, < 7.0   explicit range - what this project uses
#
# required_version >= 1.10.0 is NOT arbitrary. Native S3 state locking
# (`use_lockfile = true` in backend.tf) was introduced in Terraform 1.10.
# On an older version, `terraform init` will fail with an unsupported
# argument error.
#
# The .terraform.lock.hcl file, which IS committed to git, records the
# exact provider versions and checksums actually selected - so your
# machine, a teammate's machine, and CI all resolve identically.
###############################################################################

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70, < 7.0"
    }
  }
}
