# Interview and resume preparation

**Read this before putting the repository on your resume.** Everything below is claimable only because it genuinely exists in the code — but you need to be able to explain it, because interviewers will ask.

---

## Resume bullet points

Use two or three. Each maps to code you can point at.

> **Designed and implemented a multi-environment AWS infrastructure-as-code platform using Terraform**, provisioning isolated dev, staging and production environments from eight reusable modules — reducing environment provisioning from manual console work to a single reviewed `terraform apply` and eliminating configuration drift between environments.

> **Architected a secure multi-AZ VPC** with three-tier subnet isolation (public, private application, private database), NAT Gateways, and Security Groups that reference one another rather than IP ranges — placing all compute and data resources in private subnets with no inbound internet access.

> **Eliminated all long-lived AWS credentials** across the stack: EC2 instances authenticate via IAM instance profiles, CI/CD authenticates via GitHub Actions OIDC federation, database passwords are generated and rotated by AWS Secrets Manager and never enter Terraform state, and IMDSv2 is enforced to close the SSRF-to-credential-theft path.

> **Implemented remote Terraform state on S3 with native state locking, versioning and encryption**, isolating each environment's state and enabling safe concurrent work — using Terraform 1.10+ `use_lockfile` rather than the deprecated DynamoDB pattern.

> **Built a GitHub Actions CI/CD pipeline** running format, validation and plan on every pull request with the plan posted as a PR comment, automated apply to dev and staging, and a required-reviewer approval gate before production.

### Shorter variants, if space is tight

- Built a production-oriented AWS infrastructure-as-code platform in Terraform (VPC, ALB, Auto Scaling, RDS, S3, IAM, CloudWatch) with reusable modules driving three isolated environments
- Implemented least-privilege IAM, private-subnet isolation, encryption at rest and in transit, and zero long-lived credentials via OIDC and instance profiles
- Automated the Terraform workflow with GitHub Actions: PR-time plan review, environment promotion, and a manual approval gate for production

---

## What you can legitimately claim

### Claim confidently

**Terraform** — modules, variables with validation blocks, outputs, locals, data sources, `count` for conditional resources, `dynamic` blocks, lifecycle rules (`create_before_destroy`, `prevent_destroy`, `ignore_changes`), version constraints, remote state with locking, `templatefile()`, dependency management

**AWS networking** — VPC design, CIDR planning with `cidrsubnet()`, multi-AZ subnets, Internet Gateway, NAT Gateway, route tables, VPC Gateway Endpoints, VPC Flow Logs, Security Groups

**AWS compute and data** — EC2 Launch Templates, Auto Scaling Groups with instance refresh, Application Load Balancer with health checks and listener rules, RDS PostgreSQL with Multi-AZ and automated backups, S3 with lifecycle policies

**Security** — IAM roles, instance profiles, trust policies, least-privilege policy authoring, permissions boundaries, Secrets Manager, KMS encryption, IMDSv2, OIDC federation, confused-deputy protection

**Practices** — infrastructure as code, environment isolation, immutable infrastructure, defence in depth, CI/CD for infrastructure, cost optimisation

### Be careful how you phrase these

| Don't say | Do say |
|---|---|
| "Managed production infrastructure" | "Built a production-*oriented* architecture as a personal project" |
| "Reduced costs by 60%" | "Designed environment-specific cost controls — dev runs without a NAT Gateway, saving ~$40/month per environment" |
| "Led infrastructure for a team" | "Designed the repository structure and module interfaces so multiple engineers could work without conflicts" |
| "Deployed at scale" | "Designed for horizontal scaling via Auto Scaling Groups with CPU target tracking" |

**Never claim production traffic, uptime SLAs, or team leadership.** One follow-up question exposes it, and being caught overstating is far worse than a smaller honest claim.

---

## GitHub repository description

**Short (the About field, 350 char limit):**

> Production-oriented AWS infrastructure as code. Terraform modules provisioning isolated dev/staging/production environments: multi-AZ VPC with three-tier subnet isolation, ALB + Auto Scaling, private RDS with Secrets Manager, least-privilege IAM, CloudWatch, and GitHub Actions CI/CD with OIDC — zero long-lived credentials.

**Topics to add:** `terraform` `aws` `infrastructure-as-code` `devops` `vpc` `iam` `rds` `cloudwatch` `github-actions` `oidc` `multi-environment` `cloud-security`

---

## How to describe the architecture out loud

Practise this until it's about 90 seconds. Structure: **problem → shape → security → operations.**

> "The problem was that environments were built by hand in the console, so dev, staging and production drifted apart and security was applied inconsistently.
>
> I built it as eight reusable Terraform modules, with three thin environment directories that just call those modules with different values. The environment `main.tf` files are byte-identical — every difference lives in `terraform.tfvars`. So drift isn't discouraged, it's structurally impossible.
>
> The network is a multi-AZ VPC with three subnet tiers. Public holds only the load balancer and NAT Gateway. Private-app holds the EC2 instances, which have no public IP. Private-database holds RDS, and that tier's route table has no default route at all — so even if a Security Group were misconfigured, there's no network path out. Two independent controls, not one.
>
> Security Groups reference each other rather than CIDR ranges, so the rules stay correct as instances are replaced. There's no SSH anywhere — access is Session Manager, so there's no inbound port, no keys, and every session is in CloudTrail.
>
> There are no long-lived credentials in the whole system. EC2 uses an instance profile, CI/CD uses GitHub OIDC, and the database password is generated by RDS into Secrets Manager, so it never touches Terraform state.
>
> State is in S3 with native locking — that's the Terraform 1.10 `use_lockfile` approach rather than the deprecated DynamoDB table — with a separate state key per environment."

Then stop. Let them pick the thread they care about.

---

## Interview questions

### Beginner

**Q: What is Infrastructure as Code and why use it?**
Defining infrastructure in version-controlled files rather than clicking through a console. You get repeatability (the same code produces the same environment every time), code review before changes reach production, a git history answering "who changed this and why", disaster recovery (rebuild an entire environment from code), and self-documenting infrastructure. In this project it's the direct fix for environment drift.

**Q: What is Terraform state?**
Terraform's record of every resource it manages and the mapping from your configuration to real AWS resource IDs. Without it Terraform can't tell the difference between "create this" and "this already exists" — it would try to recreate everything on every run.

**Q: Why remote state instead of a local file?**
Four reasons. Collaboration — teammates need the same view. Safety — two concurrent applies corrupt local state, so you need locking. Durability — a lost laptop means Terraform no longer knows what exists, while those resources keep running and billing. Security — state contains resource attributes in plaintext, so it needs encryption and access control.

**Q: What's the difference between a public and a private subnet?**
Entirely the route table. A public subnet's route table sends `0.0.0.0/0` to an Internet Gateway; a private one doesn't. The subnet resource itself has no "public" flag — it's determined by routing.

**Q: Internet Gateway vs NAT Gateway?**
An Internet Gateway is bidirectional: resources in public subnets can reach the internet and be reached from it. A NAT Gateway is outbound-only: private instances can initiate connections out and receive replies, but nothing on the internet can initiate a connection in. The NAT Gateway sits in a public subnet with an Elastic IP and forwards on the instance's behalf.

**Q: What is a Security Group?**
A stateful virtual firewall attached to a resource — not a subnet. Stateful means if you allow inbound traffic, the reply is automatically allowed out; you never write return rules. Default-deny: only what you explicitly allow gets through.

**Q: What does `terraform plan` do, and why always run it?**
It compares your configuration against state and against reality, then shows exactly what it would create, change or destroy — without changing anything. It's free and read-only. Running it first is how you catch that a small change would replace your database rather than modify it.

### Intermediate

**Q: How do you keep environments isolated?**
Four layers. Separate directories, so you're physically in a different place when you run a command. Separate state files (different `key` in the same bucket), so a dev destroy has no knowledge production exists. Separate VPCs with non-overlapping CIDRs. Different values in `terraform.tfvars` for sizing and safety settings.

**Q: How do you avoid duplicating Terraform code across environments?**
The split between `modules/` and `environments/`. Modules describe *how* to build something and are environment-agnostic; environments describe *what* to build and *how big*. The three environment `main.tf` files are byte-identical — only `terraform.tfvars` differs. Adding a resource means editing one module, and all three environments get it.

**Q: Walk me through the traffic flow from a user to the database.**
User's DNS resolves the ALB name to AWS-managed public IPs. The request hits an ALB node in a public subnet; the ALB Security Group allows 80/443 from anywhere. The ALB picks a healthy target and opens a *new* connection to an EC2 instance in a private subnet — the client never connects to the instance directly, which is why it needs no public IP. The app Security Group accepts it because it references the ALB's Security Group. The app connects to RDS in the private database subnet on 5432; the DB Security Group accepts the app Security Group and nothing else. The credentials come from Secrets Manager, authorised by the instance's IAM role.

**Q: Why reference Security Groups instead of CIDR blocks?**
A CIDR rule like `10.0.10.0/24` allows anything in that subnet, including future resources that shouldn't reach the database. A Security Group reference allows only workloads carrying that group. Instances can be replaced, scaled or moved between subnets and the rule stays correct. It's identity-based rather than location-based.

**Q: How do you handle secrets?**
The database password is never in Terraform. Setting `manage_master_user_password = true` makes RDS generate it, store it in Secrets Manager encrypted with KMS, and rotate it. The critical detail is that passing a password as a variable — even a sensitive one — writes it in *plaintext into state*. Terraform state is not a secret store.

**Q: What is state locking and why does it matter?**
It stops two people applying at once. Without it, concurrent writes interleave and corrupt state — Terraform then loses track of resources that still exist and bill you. This project uses `use_lockfile = true`, native S3 locking via conditional writes, which needs Terraform 1.10+. The older DynamoDB table approach is deprecated.

**Q: What are Terraform modules and when should you write one?**
A reusable, self-contained group of `.tf` files with defined inputs and outputs — like a function. Write one when the same pattern is needed more than once, or when a concern is complex enough to deserve its own interface. Don't wrap a single resource in a module just to add indirection.

**Q: Why did you split the database into its own subnet tier?**
So the route table enforces isolation, not just the Security Group. The DB subnets have no `0.0.0.0/0` route at all. A Security Group misconfiguration alone can't expose the database — there's no network path. Two independent controls have to fail.

**Q: How do you prevent accidental production changes?**
Separate state and directories so you can't touch production by accident. `deletion_protection` on the ALB and RDS, requiring a deliberate two-step change before a destroy is even possible. `prevent_destroy` on the state bucket. `force_destroy = false` on production S3, so a destroy fails loudly rather than deleting data. And in CI, production applies require approval from a named reviewer, enforced by a GitHub Environment protection rule rather than by workflow code.

### Advanced

**Q: You need to enable encryption on an existing unencrypted RDS instance. How?**
You can't, in place — it's set at creation. The path is: take a snapshot, copy the snapshot with encryption enabled, restore from the encrypted copy to a new instance, then cut over. That means downtime or a replication-based migration. It's exactly why `storage_encrypted = true` is set from day one here.

**Q: Your ALB returns 503. Diagnose it.**
503 means no healthy targets. `describe-target-health` and read the `Reason` field — that's the fastest signal. `Target.ResponseCodeMismatch` means the health check path returns a non-2xx. `Target.Timeout` means the app Security Group isn't accepting traffic from the ALB's Security Group. `Elb.InitialHealthChecking` means it's still starting. If targets aren't registered at all, the ASG isn't attached to the target group. If the instance is registered but never becomes healthy, get in via Session Manager and check `/var/log/user-data.log` — bootstrap probably failed.

A subtler one: if `health_check_grace_period` is shorter than boot plus app start, the ASG kills instances before they can pass, and you get an infinite replacement loop.

**Q: Someone ran `terraform destroy` in production. What now?**
Prevention first: `deletion_protection` on ALB and RDS means the destroy would have failed partway. `skip_final_snapshot = false` means a final RDS snapshot exists. S3 has `force_destroy = false` and versioning, so objects survive.

Recovery: restore RDS from the final snapshot or a point-in-time backup, then `terraform apply` to rebuild everything else — that's the payoff of IaC. Afterwards: require approval for production applies, and remove destroy permissions from the CI role entirely.

**Q: How would you make the CI role least-privilege?**
It currently uses `PowerUserAccess`, which is a labelled shortcut — though note it already excludes IAM writes, so a compromised pipeline can't escalate its own privileges. The proper approach is to run the pipeline for a few weeks, then use IAM Access Analyzer to generate a policy from the CloudTrail record of what it actually called. Add a permissions boundary so the role can't be granted more later, and scope resource ARNs by naming prefix — which this project already does for IAM role creation.

**Q: What is IMDSv2 and why enforce it?**
The Instance Metadata Service at `169.254.169.254` serves the instance's temporary AWS credentials. IMDSv1 answered any plain HTTP GET, so a Server-Side Request Forgery bug in the application could read those credentials — the mechanism behind several major cloud breaches. IMDSv2 requires a PUT to get a session token first, and SSRF can't issue a PUT. Setting `http_tokens = "required"` closes the entire class. The hop limit of 1 stops containers reaching it via the host's network namespace.

**Q: How does GitHub Actions authenticate without stored credentials?**
OIDC federation. GitHub issues a short-lived signed JWT asserting the repository, ref and workflow. AWS validates the signature against GitHub's public keys via a registered OIDC provider, then `AssumeRoleWithWebIdentity` exchanges it for temporary credentials.

The security-critical part is the trust policy's `sub` condition. Without pinning it to your specific repository, *any* GitHub repository could assume the role. That's the most commonly misconfigured piece of OIDC setups.

**Q: Terraform wants to replace a resource you only wanted to modify. What do you do?**
Read the plan for the `# forces replacement` marker — it names the exact attribute. Then decide: is that attribute genuinely immutable (like RDS `storage_encrypted`), in which case replacement is unavoidable and needs a migration plan? Or is it drift Terraform shouldn't manage, in which case `lifecycle { ignore_changes = [...] }` is right — as this project does for `engine_version`, since AWS applies minor upgrades automatically.

For genuinely unavoidable replacement of something stateful, `create_before_destroy` plus a migration is the pattern.

**Q: Why not use Terraform workspaces for environments?**
Workspaces share one backend configuration and one provider configuration, so the only thing distinguishing production from dev is a piece of CLI state that's easy to forget to switch. They also can't express structural differences well. Separate directories make the environment explicit in your shell path, allow genuinely different backend and provider configs, and let production hold different lifecycle rules. Workspaces are better suited to short-lived parallel instances of the *same* environment — per-developer sandboxes or per-PR previews.

**Q: How would you take this to genuine production readiness?**
Highest priority: real TLS with an ACM certificate, and a WAF in front of the ALB. Then separate AWS accounts per environment rather than one account with three VPCs — account boundaries are the strongest isolation AWS offers. Then a scoped CI policy replacing PowerUser, policy-as-code scanning like Checkov in the pipeline, and `terraform test` for module contracts. Operationally: alarms routed to a real on-call system rather than email, tested backup restores rather than assumed ones, and a runbook per alarm.

---

## Questions to ask them

Asking good questions signals seniority more than answering does.

- How do you manage Terraform state and prevent concurrent applies across the team?
- Do you use separate AWS accounts per environment, or separate VPCs in one account?
- What does your promotion path from dev to production look like — who approves?
- How do you handle secrets — Secrets Manager, Parameter Store, Vault?
- Are there parts of your infrastructure still managed manually, and what's blocking bringing them into code?
- How do you handle drift between what's in code and what's actually deployed?

---

## Be ready for the honesty question

**"Did you build this yourself or follow a tutorial?"**

Answer straight: it's a personal learning project, you designed the architecture and made the trade-off decisions deliberately, and you can walk through any file and explain why it's written that way. Then offer to do exactly that.

The tell interviewers look for is whether you can explain *why* — why three subnet tiers instead of two, why `use_lockfile` instead of DynamoDB, why the database has no egress rules. If you can answer those, how you learned it stops mattering.

**Before your interview**, make sure you can answer these three without looking:

1. Why does the database subnet have no route to `0.0.0.0/0`?
2. Why is `manage_master_user_password = true` better than a `password` variable?
3. What breaks if you set `single_nat_gateway = true` in production?
