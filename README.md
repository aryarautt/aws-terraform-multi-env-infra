# Production-Ready Multi-Environment AWS Infrastructure with Terraform

Infrastructure-as-Code that provisions standardized, secure, multi-AZ AWS environments — **dev, staging and production** — from a single set of reusable Terraform modules.

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.10-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-VPC%20%7C%20EC2%20%7C%20ALB%20%7C%20RDS-232F3E?logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## Note on live infrastructure

This infrastructure is intentionally **not left running**. It is provisioned, verified, documented and destroyed each working session — `terraform destroy` is part of the workflow, not an afterthought.

Verification evidence for each environment (Terraform state inventory, AWS resource listings, target health checks, HTTP responses) is captured in [`docs/evidence/`](docs/evidence/).

---

## Problem statement

A company provisions AWS infrastructure manually through the console. The result:

| Problem | Consequence |
|---|---|
| Environments configured by hand | dev, staging and production drift apart; bugs appear only in production |
| No record of what exists or why | Nobody can answer "who created this and can we delete it?" |
| Security applied inconsistently | One environment blocks public S3 access, another does not |
| Changes are slow and risky | A new environment takes days and is never quite identical |
| No review, no rollback | A misclick in the console is instantly live with no audit trail |

**This project replaces that with version-controlled, reviewable, repeatable infrastructure.** The same modules build all three environments; only sizing and safety settings differ.

---

## Architecture

```
                                Internet
                                    │
                          ┌─────────▼─────────┐
                          │ Internet Gateway  │
                          └─────────┬─────────┘
   ┌──────────────────────────────  │  ──────────────────────────────┐
   │  VPC 10.0.0.0/16 (dev)         │                                │
   │                                │                                │
   │        AZ-a                    │                    AZ-b        │
   │  ┌──────────────────────────┐  │  ┌──────────────────────────┐  │
   │  │ PUBLIC   10.0.0.0/24     │◄─┴─►│ PUBLIC   10.0.1.0/24     │  │
   │  │  ▪ ALB node              │     │  ▪ ALB node              │  │
   │  │  ▪ NAT Gateway ──────────┼─────┼──┐                       │  │
   │  └───────────┬──────────────┘     └──┼──────────┬────────────┘  │
   │              │ HTTP :80              │          │               │
   │  ┌───────────▼──────────────┐     ┌──▼──────────▼────────────┐  │
   │  │ PRIVATE APP 10.0.10.0/24 │     │ PRIVATE APP 10.0.11.0/24 │  │
   │  │  ▪ EC2 (no public IP)    │     │  ▪ EC2 (no public IP)    │  │
   │  └───────────┬──────────────┘     └──────────┬───────────────┘  │
   │              │ PostgreSQL :5432              │                  │
   │  ┌───────────▼──────────────┐     ┌──────────▼───────────────┐  │
   │  │ PRIVATE DB  10.0.20.0/24 │     │ PRIVATE DB  10.0.21.0/24 │  │
   │  │  ▪ RDS primary           │◄───►│  ▪ RDS standby (Multi-AZ)│  │
   │  │  ▪ NO internet route     │     │  ▪ NO internet route     │  │
   │  └──────────────────────────┘     └──────────────────────────┘  │
   │                                                                 │
   │  S3 Gateway Endpoint (free) ──► S3        VPC Flow Logs ──► CW  │
   └─────────────────────────────────────────────────────────────────┘

   Outside the VPC, reached via IAM roles:
   ▪ S3 (application data)   ▪ CloudWatch (logs, metrics, alarms)
   ▪ Secrets Manager (RDS-managed credentials)
```

### Traffic flow

| Path | How it works |
|---|---|
| **User → ALB** | DNS resolves to AWS-managed public IPs. The ALB is the only internet-facing component, and lives in public subnets. |
| **ALB → EC2** | The ALB terminates the client connection and opens a **new** one to a healthy target in a private subnet. Allowed because the app Security Group references the ALB's Security Group, not a CIDR. |
| **EC2 → RDS** | Private app subnet to private DB subnet, port 5432 only. The DB Security Group accepts the app Security Group and nothing else. |
| **EC2 → S3** | Over a free **S3 Gateway Endpoint**, staying on the AWS backbone. Authenticated by the instance's IAM role — no access keys. |
| **EC2 → Internet** | Outbound only, via NAT Gateway. The internet cannot initiate a connection back. |
| **Admin → EC2** | AWS Systems Manager Session Manager. No SSH, no bastion, no open port 22, no key pairs. |

### Security boundaries

1. **VPC** — nothing outside can reach in without an explicit gateway
2. **Subnet tier + route tables** — controls whether a subnet has any internet path at all. The DB tier has none.
3. **Security Groups** — reference each other rather than IP ranges, so rules stay correct as instances come and go
4. **IAM** — scoped to specific resource ARNs; temporary credentials only

Full design rationale: [`docs/architecture.md`](docs/architecture.md).

---

## Technologies

**Terraform** `>= 1.10` · modules, variables, outputs, locals, data sources, `count`, `dynamic` blocks, lifecycle rules, validation blocks, version constraints, remote state with native S3 locking

**AWS** · VPC · Subnets (3 tiers) · Internet Gateway · NAT Gateway · Route Tables · VPC Endpoints · VPC Flow Logs · Security Groups · EC2 · Launch Templates · Auto Scaling Groups · Application Load Balancer · RDS PostgreSQL · S3 · IAM · Secrets Manager · CloudWatch (logs, metrics, alarms, dashboards) · SNS

**CI/CD** · GitHub Actions with OIDC federation (no stored AWS credentials)

---

## Repository structure

```
.
├── bootstrap/                 Run ONCE. Creates the S3 state bucket and
│                              the GitHub Actions OIDC role. Uses local
│                              state, solving the chicken-and-egg problem
│                              of "what creates the state backend?"
│
├── modules/                   HOW to build each component. Environment-agnostic.
│   ├── vpc/                   Network: subnets, IGW, NAT, route tables, endpoints
│   ├── security-groups/       Layered firewall rules that reference each other
│   ├── iam/                   EC2 instance role, least privilege, scoped ARNs
│   ├── ec2/                   Launch template + Auto Scaling Group
│   ├── alb/                   Load balancer, target group, listeners, health checks
│   ├── rds/                   PostgreSQL, encrypted, private, Secrets Manager
│   ├── s3/                    Bucket with public access blocked, versioned
│   └── cloudwatch/            Log groups, alarms, dashboard, SNS
│
├── environments/              WHAT to build and HOW BIG.
│   ├── dev/                   Cheapest config that still exercises the design
│   ├── staging/               Production's shape at smaller scale
│   └── production/            Multi-AZ, backups, deletion protection
│
├── .github/workflows/         fmt → validate → plan on PR; apply on merge
├── docs/                      Architecture, security notes, evidence
├── scripts/                   Cost audit, evidence capture
└── Makefile                   make plan ENV=dev
```

Each module contains the same five files — `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md` — so any engineer can navigate an unfamiliar one immediately.

### How code duplication is avoided

`modules/` and `environments/` split along a single line:

> **`modules/` describes *how* to build something. `environments/` describes *what* to build and *how big*.**

`environments/dev/main.tf`, `staging/main.tf` and `production/main.tf` are **byte-identical**. Every difference between the three lives in `terraform.tfvars`. The VPC module has no idea whether it is building dev or production — it takes a CIDR and a set of flags.

That is what makes environment drift structurally impossible rather than merely discouraged.

---

## Environment differences

| Setting | dev | staging | production | Why |
|---|---|---|---|---|
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 | No overlap, so VPCs can be peered later |
| NAT Gateway | **none** | 1 shared | **1 per AZ** | dev saves ~$40/mo; prod survives an AZ outage |
| Instance type | t3.micro | t3.small | t3.medium | Capacity, not behaviour |
| Desired capacity | 1 | 2 | 3 | prod min=2 survives losing one instance |
| Autoscaling | off | on | on | Validated in staging before prod depends on it |
| RDS class | db.t4g.micro | db.t4g.small | db.t4g.medium | |
| RDS Multi-AZ | no | no | **yes** | Automatic failover in 60–120s; doubles cost |
| Backup retention | 1 day | 7 days | **30 days** | 30 days of point-in-time recovery |
| Deletion protection | off | off | **on** | Prod cannot be destroyed without a deliberate two-step change |
| Final snapshot | skipped | skipped | **taken** | Accidental prod teardown stays recoverable |
| S3 force destroy | yes | yes | **no** | A destroy against prod data fails loudly |
| Log retention | 7 days | 30 days | 90 days | Investigate incidents found weeks later |
| Detailed monitoring | off | on | on | 1-min metrics during an incident, not 5-min |
| Flow logs | off | on | on | Security investigation capability |

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Terraform `>= 1.10` | **Required.** Native S3 state locking (`use_lockfile`) was added in 1.10 |
| AWS CLI v2 | For authentication and verification |
| An AWS account | With a non-root IAM identity |
| Git | |

---

## Setup

### 1. Authenticate securely

This project assumes an IAM role with MFA rather than using long-lived access keys directly.

`~/.aws/config`:

```ini
[profile shravani-admin]
region = ap-south-1
output = json

[profile terraform]
role_arn         = arn:aws:iam::<ACCOUNT_ID>:role/TerraformExecutionRole
source_profile   = shravani-admin
mfa_serial       = arn:aws:iam::<ACCOUNT_ID>:mfa/shravani-admin
region           = ap-south-1
duration_seconds = 3600
```

The role's trust policy requires MFA, so a leaked access key alone cannot assume it:

```json
{
  "Condition": { "Bool": { "aws:MultiFactorAuthPresent": "true" } }
}
```

Verify — the ARN should contain `assumed-role`:

```bash
aws sts get-caller-identity --profile terraform
```

### 2. Bootstrap remote state

```bash
cd bootstrap
terraform init
terraform apply -var='github_allowed_subjects=["repo:YOUR-USER/YOUR-REPO:ref:refs/heads/main"]'
terraform output state_bucket_name
```

### 3. Point each environment at the bucket

Edit `environments/*/backend.tf` and replace the placeholder `bucket` value with the name from the previous step.

### 4. Deploy

```bash
cd environments/dev
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Or from the repo root: `make plan ENV=dev` then `make apply ENV=dev`.

---

## Terraform workflow

| Command | Purpose | When |
|---|---|---|
| `terraform fmt -recursive` | Canonical formatting | Before every commit |
| `terraform validate` | Syntax and type checking — **free, no AWS calls** | Before every plan |
| `terraform init` | Download providers, configure backend | First run, and after changing modules or backend |
| `terraform plan -out=tfplan` | Show what will change — **free, read-only** | Before every apply |
| `terraform apply tfplan` | Make the change | After reviewing the plan |
| `terraform destroy` | Tear down | End of every working session |

Always `plan -out=tfplan` then `apply tfplan`, rather than a bare `apply`. Applying a saved plan guarantees you get exactly what you reviewed — a bare `apply` re-plans, and infrastructure may have changed in between.

---

## Verification

After `terraform apply`:

```bash
# The whole path: internet → ALB → target group → EC2 in a private subnet
curl -I $(terraform output -raw application_url)     # expect HTTP/1.1 200 OK

# Targets healthy?
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) --output table

# Instances have NO public IP
aws ec2 describe-instances --filters "Name=tag:Environment,Values=dev" \
  --query 'Reservations[].Instances[].{Private:PrivateIpAddress,Public:PublicIpAddress}' --output table

# Database is not publicly accessible and is encrypted
aws rds describe-db-instances \
  --query 'DBInstances[].{Public:PubliclyAccessible,Encrypted:StorageEncrypted}' --output table

# Shell access with no SSH, no open port, no key pair
aws ssm start-session --target <instance-id>

# Logs
aws logs tail $(terraform output -raw log_group_name) --follow
```

`terraform output verification_commands` prints these pre-filled.

Then capture evidence and tear down:

```bash
./scripts/capture-evidence.sh dev      # writes to docs/evidence/dev/
terraform destroy
./scripts/aws-audit.sh terraform ap-south-1   # confirm nothing survived
```

---

## Security

| Control | Implementation |
|---|---|
| No hardcoded credentials | EC2 uses an IAM instance profile; CI/CD uses GitHub OIDC; local use assumes a role with MFA |
| No SSH | Session Manager only. No port 22 rule exists anywhere in the codebase |
| Database not public | `publicly_accessible = false`, isolated subnets with **no internet route at all** |
| Database password | Generated by RDS, stored in Secrets Manager, **never enters Terraform state** |
| Encryption at rest | EBS, RDS, S3 and Terraform state all encrypted |
| Encryption in transit | `rds.force_ssl = 1`; S3 bucket policy denies non-TLS requests |
| S3 public access | All four public-access-block settings on; ACLs disabled entirely |
| IMDSv2 enforced | `http_tokens = "required"` closes the SSRF-to-credential-theft path |
| Least privilege IAM | Policies scoped to specific bucket and secret ARNs, never `"*"` |
| Confused deputy protection | `aws:SourceAccount` condition on the EC2 trust policy |
| Default SG locked down | Emptied of all rules per CIS benchmark |
| Layered Security Groups | Rules reference other Security Groups, not IP ranges |

### Deliberate learning shortcuts

Labelled honestly rather than hidden, each with its production alternative:

| Shortcut | Where | Production alternative |
|---|---|---|
| HTTP, no TLS certificate | `certificate_arn = null` | Free ACM certificate; module then creates an HTTPS listener and 301-redirects HTTP |
| `PowerUserAccess` on the CI role | `bootstrap/` | Scoped policy generated from CloudTrail via IAM Access Analyzer. Note PowerUser already excludes IAM writes, blocking privilege escalation |
| Application deployed via user data | `modules/ec2/` | Pre-baked AMI (Packer) or a container image from a versioned artifact store |

---

## Cost

**Not covered by any AWS free tier**, at any account age:

| Resource | Approx. cost |
|---|---|
| NAT Gateway | **~$40/month each** + $0.045/GB |
| Application Load Balancer | ~$17/month |
| RDS db.t4g.micro | ~$13/month + storage |
| EC2 t3.micro | ~$8/month each |

Also note: the **12-month free tier expires 12 months after account creation**. On an older account, EC2/RDS/ALB/S3 allowances are already gone.

| Environment | If left running |
|---|---|
| dev (NAT off) | ~$40/month |
| staging | ~$110/month |
| production | ~$240/month |

**A 3-hour dev session costs roughly $0.10.** The cost is not the resources — it is forgetting to destroy them.

Cost levers, all exposed as variables: `enable_nat_gateway`, `enable_rds`, `instance_type`, `asg_desired_capacity`, `db_multi_az`, `log_retention_days`.

---

## Troubleshooting

<details>
<summary><b>Error: Unsupported argument — use_lockfile</b></summary>

Terraform is older than 1.10. Check with `terraform -version` and upgrade. Do **not** work around this by switching to `dynamodb_table` — that approach is deprecated.
</details>

<details>
<summary><b>Error: NoSuchBucket / state bucket not found</b></summary>

The bootstrap step has not run, or `backend.tf` still contains the `aryarautt` placeholder. Run `cd bootstrap && terraform apply`, then copy `terraform output state_bucket_name` into each environment's `backend.tf`.
</details>

<details>
<summary><b>Error acquiring the state lock</b></summary>

Another apply is running, or a previous one crashed leaving a stale lock. Confirm nothing else is running, then `terraform force-unlock <LOCK_ID>`. Never force-unlock while a real apply is in progress — that is how state gets corrupted.
</details>

<details>
<summary><b>ALB returns 503 Service Unavailable</b></summary>

No healthy targets. Diagnose in order:
1. `aws elbv2 describe-target-health --target-group-arn <arn>` — read the `Reason` field
2. `Target.ResponseCodeMismatch` → the health check path returns a non-2xx status
3. `Target.Timeout` → the app Security Group is not accepting traffic from the ALB Security Group
4. `Elb.InitialHealthChecking` → still starting; wait for `health_check_grace_period`
5. Check `/var/log/user-data.log` via Session Manager to confirm bootstrap succeeded
</details>

<details>
<summary><b>Instances launch and terminate in a loop</b></summary>

`health_check_grace_period` is shorter than the boot plus application start time, so the ASG kills instances before they can become healthy. Raise it.
</details>

<details>
<summary><b>Cannot connect to RDS</b></summary>

By design — RDS is unreachable from outside the VPC. Connect from an EC2 instance via Session Manager. Then check: the DB Security Group allows the app Security Group on 5432, and `rds.force_ssl` means the client must use TLS.
</details>

<details>
<summary><b>S3 AccessDenied despite an IAM policy</b></summary>

Almost always bucket-level versus object-level ARN confusion. `s3:ListBucket` acts on `arn:aws:s3:::bucket`; `s3:GetObject` acts on `arn:aws:s3:::bucket/*`. They are different resources and need separate statements.
</details>

<details>
<summary><b>terraform destroy fails in production</b></summary>

Expected. `deletion_protection` is on for the ALB and RDS. Set `alb_deletion_protection = false` and `db_deletion_protection = false`, `terraform apply` that change, then destroy. The friction is the feature.
</details>

<details>
<summary><b>CIDR conflict on apply</b></summary>

Two environments were given overlapping `vpc_cidr` values. dev/staging/production use 10.0/10.1/10.2 precisely to avoid this.
</details>

---

## Cleanup

```bash
cd environments/dev
terraform destroy
cd ../..
./scripts/aws-audit.sh terraform ap-south-1     # verify nothing survived
```

Check for orphaned resources that outlive a destroy and keep billing: unattached Elastic IPs, EBS snapshots, RDS final snapshots, and CloudWatch log groups. The audit script reports all of these.

---

## Future improvements

- Replace `PowerUserAccess` on the CI role with a CloudTrail-derived scoped policy
- ACM certificate and Route 53 records for real HTTPS
- WAF in front of the ALB for OWASP Top 10 rules
- Aurora Serverless v2 instead of RDS, to scale to zero between sessions
- `terraform test` unit tests and Checkov policy scanning in CI
- Interface VPC endpoints for SSM and Secrets Manager, removing the NAT Gateway dependency entirely
- Multi-account structure (separate AWS accounts per environment) rather than one account with three VPCs

---

## License

MIT — see [LICENSE](LICENSE).
