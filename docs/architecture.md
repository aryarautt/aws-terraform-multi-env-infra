# Architecture and design decisions

This document explains **why** the infrastructure is shaped the way it is. Every non-obvious choice is recorded here with its trade-off.

---

## 1. Network topology

### CIDR plan

| Environment | VPC CIDR | Public | Private app | Private DB |
|---|---|---|---|---|
| dev | `10.0.0.0/16` | 10.0.0.0/24, 10.0.1.0/24 | 10.0.10.0/24, 10.0.11.0/24 | 10.0.20.0/24, 10.0.21.0/24 |
| staging | `10.1.0.0/16` | 10.1.0.0/24, 10.1.1.0/24 | 10.1.10.0/24, 10.1.11.0/24 | 10.1.20.0/24, 10.1.21.0/24 |
| production | `10.2.0.0/16` | 10.2.0.0/24, 10.2.1.0/24 | 10.2.10.0/24, 10.2.11.0/24 | 10.2.20.0/24, 10.2.21.0/24 |

**Why a /16 per environment.** 65,536 addresses is far more than needed today, but VPC CIDR blocks cannot be shrunk and expanding them is disruptive. A /16 leaves room for years of growth at no cost — unused private IP space is free.

**Why non-overlapping ranges.** VPC peering, Transit Gateway and site-to-site VPN all require non-overlapping CIDRs. Two VPCs both using `10.0.0.0/16` can never be connected without renumbering one of them, which means recreating every subnet and everything in it. Choosing distinct ranges on day one costs nothing; retrofitting them is a migration project.

**Why subnets are computed, not hardcoded.** `cidrsubnet(var.vpc_cidr, 8, count.index)` derives each subnet from the VPC CIDR. Changing the VPC range requires no other edits, and there is no arithmetic to get wrong.

**Why the numbering has gaps** (public 0–1, app 10–11, db 20–21). Adding a fourth tier later — a cache subnet, a management subnet — slots into the unused range without renumbering anything that exists. Renumbering forces a destroy and recreate of every affected subnet.

### Three subnet tiers, not two

Most tutorials use public + private. This project separates the database into its own tier because that separation lets the **route table** enforce isolation, not just the Security Group.

| Tier | Route to `0.0.0.0/0` | Contains |
|---|---|---|
| Public | Internet Gateway | ALB nodes, NAT Gateway |
| Private app | NAT Gateway (outbound only) | EC2 instances |
| **Private DB** | **none** | RDS |

The database subnet's route table has no default route at all. Even if someone attached a permissive Security Group to the RDS instance by mistake, there is **no network path** out of that subnet. Two independent controls must both fail for the database to be exposed — defence in depth rather than a single point of correctness.

### Why the NAT Gateway is a variable

A NAT Gateway costs roughly **$40/month** and is not in any AWS free tier. Its only job is letting private instances make *outbound* connections.

| Environment | Setting | Reasoning |
|---|---|---|
| dev | `enable_nat_gateway = false` | Saves ~$40/mo. The free S3 Gateway Endpoint still provides S3 access, and Session Manager still works. Trade-off: `dnf update` in user data fails. |
| staging | one shared | Egress behaviour is exercised (third-party API calls, package installs) at half the cost. Trade-off: an AZ failure takes out egress VPC-wide. |
| production | **one per AZ** | With a shared gateway, losing its AZ removes egress from *every* private subnet, including healthy AZs — converting a single-AZ incident into a full outage and defeating the multi-AZ design. |

This is a genuine Terraform pattern, not a cost hack: the widely used community VPC module exposes the same two flags for the same reason.

### S3 Gateway Endpoint

Gateway endpoints are **free** (Interface endpoints are not). Routing S3 traffic through one means it never traverses the public internet and never incurs NAT data-processing charges. It is what makes `enable_nat_gateway = false` viable in dev.

---

## 2. Security Group design

Rules reference **other Security Groups**, never CIDR ranges:

```hcl
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id   # not a CIDR
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
```

**Why this matters.** A CIDR-based rule such as `10.0.10.0/24` allows *anything* that lands in that subnet — including a future resource that has no business reaching the database. A Security Group reference allows only workloads carrying that specific group. Instances can be replaced, scaled or moved between subnets and the rule stays exactly as correct as the day it was written.

### The rule matrix

| Group | Ingress | Egress |
|---|---|---|
| `alb` | 80, 443 from `0.0.0.0/0` | app port → `app` SG **only** |
| `app` | app port from `alb` SG **only** | 80/443 to internet; DB port → `db` SG |
| `db` | DB port from `app` SG **only** | **none** |

Two deliberate choices:

**The ALB has restricted egress.** The default "allow all outbound" would let a compromised load balancer scan the entire VPC. It only needs to reach the app tier.

**The database has no egress rules at all.** Security Groups are stateful, so replies to queries still return automatically. Denying egress means a compromised database cannot exfiltrate data outward or fetch a second-stage payload.

### No SSH, anywhere

There is no port 22 rule in the codebase. Administrative access is **AWS Systems Manager Session Manager**, which works through an outbound HTTPS connection initiated by the instance.

| | Bastion + SSH | Session Manager |
|---|---|---|
| Inbound port open | yes (22) | **none** |
| Key management | distribute, rotate, revoke | **none** |
| Extra host to patch | yes | no |
| Audit trail | sshd logs on the host | **CloudTrail, centrally** |
| Access control | Linux users and keys | **IAM policies** |

`0.0.0.0/0` on port 22 is one of the most common findings in a real security review. This design makes it structurally impossible.

---

## 3. Compute

### Auto Scaling Group instead of `aws_instance`

| Capability | `aws_instance` | Launch Template + ASG |
|---|---|---|
| Replaces failed instances | no | **yes, automatically** |
| Spreads across AZs | manual | **built in** |
| Scaling | edit code | **change a number** |
| Rolling updates | destroy/recreate | **instance refresh** |

`health_check_type = "ELB"` is what makes self-healing real. The default `"EC2"` only checks that the hypervisor considers the instance alive — a server whose application has crashed still passes. Only the ELB check notices that it stopped serving traffic.

### IMDSv2 is enforced

```hcl
metadata_options {
  http_tokens                 = "required"
  http_put_response_hop_limit = 1
}
```

The Instance Metadata Service at `169.254.169.254` hands out the instance's temporary AWS credentials. Under IMDSv1 it answered any plain HTTP `GET` — meaning a Server-Side Request Forgery bug in the application could read those credentials. This was the mechanism behind several large cloud breaches.

IMDSv2 requires a `PUT` to obtain a session token first. SSRF cannot issue a `PUT`, so the attack class is closed. The hop limit of 1 stops containers reaching the metadata service through the host's network namespace.

---

## 4. Data

### The database password never exists in Terraform

The obvious approach is wrong:

```hcl
password = var.db_password   # DO NOT DO THIS
```

Even with `sensitive = true`, the value is written **in plaintext into `terraform.tfstate`**. Anyone who can read the state bucket can read the password.

This project uses:

```hcl
manage_master_user_password = true
```

RDS generates the password itself, stores it in Secrets Manager encrypted with KMS, and rotates it. The value never passes through Terraform, never enters state, and never appears in plan output. The application reads it at runtime via its IAM role, which is scoped to that one secret ARN.

### Encryption

| Layer | Control | Note |
|---|---|---|
| RDS at rest | `storage_encrypted = true` | **Cannot be enabled later** — an existing unencrypted instance must be snapshotted, restored encrypted, and cut over. Always start with it on. |
| RDS in transit | `rds.force_ssl = 1` | Unencrypted connections are refused outright |
| EBS at rest | `encrypted = true` | Free on gp3 |
| S3 at rest | SSE-S3 (AES256) | Free; SSE-KMS optional for per-key audit |
| S3 in transit | bucket policy `Deny` on `aws:SecureTransport = false` | |
| Terraform state | bucket-level SSE | State contains secrets by nature |

### S3 lockdown

All four public access block settings are on, and `object_ownership = "BucketOwnerEnforced"` disables ACLs entirely, making IAM the single source of truth for access.

The bucket policy carries two **explicit `Deny`** statements — non-TLS requests, and unencrypted uploads. An explicit Deny in IAM overrides every Allow anywhere, including a broader policy someone attaches later by mistake.

---

## 5. State management

| Property | Setting | Why |
|---|---|---|
| Backend | S3 | Shared, durable, versioned |
| Locking | `use_lockfile = true` | **Terraform ≥ 1.10.** Native S3 conditional writes. The DynamoDB approach is deprecated by HashiCorp. |
| Encryption | `encrypt = true` + bucket SSE | State contains resource attributes in plaintext |
| Versioning | enabled, 90-day retention | The only way to recover from state corruption |
| Isolation | one `key` per environment | A `destroy` in dev reads a different state file and has no knowledge production exists |
| Protection | `prevent_destroy` + `force_destroy = false` | Losing the state bucket means Terraform can no longer see resources that keep running and billing |

### Why bootstrap is separate

Circular dependency: every environment stores state in an S3 bucket, but something must create that bucket. `bootstrap/` runs **once, with local state**, creates the bucket and the GitHub OIDC role, and is then rarely touched again.

---

## 6. CI/CD authentication

GitHub Actions authenticates via **OIDC federation** — no AWS credentials are stored anywhere.

GitHub issues a short-lived, signed token asserting *"this is repo X, ref Y"*. AWS validates it against GitHub's public keys and exchanges it for temporary credentials.

The critical part is the trust policy condition:

```hcl
condition {
  test     = "StringLike"
  variable = "token.actions.githubusercontent.com:sub"
  values   = ["repo:owner/name:ref:refs/heads/main"]
}
```

Without pinning `sub` to a specific repository, **any repository on GitHub** could assume the role. This is the single most commonly misconfigured part of OIDC setups.

Compare with the alternative: a long-lived IAM access key in GitHub Secrets, which works from anywhere on the internet, forever, until someone notices it has leaked.

---

## 7. Decisions deliberately *not* made

Recorded so the omissions read as choices rather than oversights.

| Not used | Why |
|---|---|
| Terraform workspaces for environments | Workspaces share one backend config and one set of provider settings, making it easy to apply against the wrong environment. Separate directories with separate state keys are explicit and safer. |
| A single AWS account per environment | Strictly better isolation and the right answer at company scale, but it requires AWS Organizations — which converts a free-tier account to a paid plan immediately. Documented as a future improvement. |
| Aurora instead of RDS | More capable, but more expensive and more complex than this project needs. Aurora Serverless v2 is listed as a future improvement for its scale-to-zero behaviour. |
| Kubernetes / EKS | Would dominate the project and obscure the networking and IAM fundamentals this project is meant to demonstrate. The subnet tags for ELB auto-discovery are already present should it be added later. |
| Inline `ingress` blocks in Security Groups | Legacy pattern: changing one rule replaces the entire rule set, briefly dropping traffic. Separate rule resources change independently. |
| DynamoDB state locking | Deprecated by HashiCorp in favour of native S3 locking. |
