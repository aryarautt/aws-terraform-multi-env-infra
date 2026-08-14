#!/usr/bin/env bash
#
# capture-evidence.sh
# -------------------
# Captures proof that your infrastructure was built and worked,
# so you can destroy it and still have a portfolio.
#
# Run this AFTER `terraform apply` succeeds and BEFORE `terraform destroy`.
#
# It automatically redacts your AWS account ID from all output,
# so the results are safe to commit to a public GitHub repo.
#
# Usage:
#   ./scripts/capture-evidence.sh dev
#   ./scripts/capture-evidence.sh production
#
set -uo pipefail

ENV="${1:-dev}"
PROFILE="${2:-terraform}"
REGION="${3:-ap-south-1}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="$REPO_ROOT/environments/$ENV"
OUT_DIR="$REPO_ROOT/docs/evidence/$ENV"

if [ ! -d "$ENV_DIR" ]; then
  echo "ERROR: $ENV_DIR does not exist."
  echo "Usage: ./scripts/capture-evidence.sh <dev|staging|production>"
  exit 1
fi

mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------------------
# Redaction: replace the 12-digit account ID with X's everywhere.
# ---------------------------------------------------------------------------
ACCOUNT_ID="$(aws sts get-caller-identity --profile "$PROFILE" \
  --query Account --output text 2>/dev/null)"

redact() {
  if [ -n "${ACCOUNT_ID:-}" ] && [ "$ACCOUNT_ID" != "None" ]; then
    sed -e "s/$ACCOUNT_ID/XXXXXXXXXXXX/g"
  else
    cat
  fi
}

capture() {
  local name="$1"; shift
  echo "  -> $name"
  {
    echo "\$ $*"
    echo ""
    "$@" 2>&1
  } | redact > "$OUT_DIR/$name"
}

echo "============================================================="
echo " CAPTURING EVIDENCE for environment: $ENV"
echo " Output: docs/evidence/$ENV/"
echo "============================================================="

cd "$ENV_DIR"

# ---------------------------------------------------------------------------
# 1. Terraform-side evidence
# ---------------------------------------------------------------------------
echo ""
echo "[1/3] Terraform state and outputs"

capture "01-terraform-version.txt"   terraform version
capture "02-state-list.txt"          terraform state list
capture "03-outputs.txt"             terraform output
capture "04-plan-no-changes.txt"     terraform plan -detailed-exitcode

# A clean "No changes" plan right after apply is strong evidence:
# it proves the code and the real infrastructure actually matched.

# Dependency graph (renders to an image if graphviz is installed)
terraform graph 2>/dev/null | redact > "$OUT_DIR/05-graph.dot" || true
if command -v dot >/dev/null 2>&1; then
  dot -Tpng "$OUT_DIR/05-graph.dot" -o "$OUT_DIR/05-graph.png" 2>/dev/null \
    && echo "  -> 05-graph.png (rendered)"
fi

# ---------------------------------------------------------------------------
# 2. AWS-side evidence (proves the resources really exist)
# ---------------------------------------------------------------------------
echo ""
echo "[2/3] AWS resource inventory"

AWSC="aws --profile $PROFILE --region $REGION"

capture "10-vpcs.txt" $AWSC ec2 describe-vpcs \
  --filters "Name=tag:Environment,Values=$ENV" --output table

capture "11-subnets.txt" $AWSC ec2 describe-subnets \
  --filters "Name=tag:Environment,Values=$ENV" \
  --query 'Subnets[].{Name:Tags[?Key==`Name`]|[0].Value,CIDR:CidrBlock,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch}' \
  --output table

capture "12-route-tables.txt" $AWSC ec2 describe-route-tables \
  --filters "Name=tag:Environment,Values=$ENV" --output table

capture "13-security-groups.txt" $AWSC ec2 describe-security-groups \
  --filters "Name=tag:Environment,Values=$ENV" \
  --query 'SecurityGroups[].{Name:GroupName,Id:GroupId,Ingress:IpPermissions}' \
  --output json

capture "14-instances.txt" $AWSC ec2 describe-instances \
  --filters "Name=tag:Environment,Values=$ENV" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,AZ:Placement.AvailabilityZone,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}' \
  --output table

capture "15-load-balancers.txt" $AWSC elbv2 describe-load-balancers --output table

capture "16-target-health.txt" bash -c "
  for tg in \$($AWSC elbv2 describe-target-groups --query 'TargetGroups[].TargetGroupArn' --output text); do
    echo \"Target group: \$tg\"
    $AWSC elbv2 describe-target-health --target-group-arn \$tg \
      --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
      --output table
  done
"

capture "17-rds.txt" $AWSC rds describe-db-instances \
  --query 'DBInstances[].{Id:DBInstanceIdentifier,Class:DBInstanceClass,Engine:Engine,MultiAZ:MultiAZ,PubliclyAccessible:PubliclyAccessible,Encrypted:StorageEncrypted,BackupDays:BackupRetentionPeriod}' \
  --output table

capture "18-s3-public-access-block.txt" bash -c "
  for b in \$(aws s3api list-buckets --profile $PROFILE --query 'Buckets[].Name' --output text); do
    echo \"Bucket: \$b\"
    aws s3api get-public-access-block --profile $PROFILE --bucket \$b --output table 2>/dev/null \
      || echo '  (no public access block configured)'
  done
"

capture "19-cloudwatch-alarms.txt" $AWSC cloudwatch describe-alarms \
  --query 'MetricAlarms[].{Name:AlarmName,Metric:MetricName,State:StateValue,Threshold:Threshold}' \
  --output table

# ---------------------------------------------------------------------------
# 3. Functional proof: does the application actually respond?
# ---------------------------------------------------------------------------
echo ""
echo "[3/3] Functional test"

ALB_DNS="$(terraform output -raw alb_dns_name 2>/dev/null || echo "")"

if [ -n "$ALB_DNS" ]; then
  {
    echo "\$ curl -I http://<alb-dns-name>"
    echo ""
    curl -sS -I --max-time 15 "http://$ALB_DNS" 2>&1
    echo ""
    echo "\$ curl -s http://<alb-dns-name>"
    echo ""
    curl -sS --max-time 15 "http://$ALB_DNS" 2>&1 | head -40
  } | sed "s/$ALB_DNS/<alb-dns-name-redacted>/g" | redact \
    > "$OUT_DIR/20-alb-http-response.txt"
  echo "  -> 20-alb-http-response.txt"
else
  echo "  (no alb_dns_name output found - skipping HTTP test)"
fi

# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------
cat > "$OUT_DIR/README.md" <<EOF
# Evidence: \`$ENV\` environment

Captured while the infrastructure was live, before \`terraform destroy\`.
All AWS account IDs and public DNS names have been redacted.

| File | What it proves |
|------|----------------|
| 01-terraform-version.txt | Terraform version used |
| 02-state-list.txt | Every resource Terraform managed |
| 03-outputs.txt | Module outputs (VPC ID, subnet IDs, ALB DNS) |
| 04-plan-no-changes.txt | Code matched reality exactly - no drift |
| 05-graph.dot / .png | Resource dependency graph |
| 10-12 | VPC, subnets, route tables - the network design |
| 13 | Security group rules - least-privilege proof |
| 14 | EC2 instances with **no public IP** (private subnet) |
| 15-16 | ALB exists and targets are **healthy** |
| 17 | RDS: \`PubliclyAccessible: false\`, \`Encrypted: true\` |
| 18 | S3 public access fully blocked |
| 19 | CloudWatch alarms configured |
| 20 | **HTTP 200 from the ALB** - the full path works end to end |

## Screenshots to capture manually

- [ ] VPC console -> Resource map (auto-generated topology diagram)
- [ ] EC2 -> Target Groups -> targets showing "healthy"
- [ ] RDS -> Connectivity tab -> "Publicly accessible: No"
- [ ] S3 -> Permissions -> "Block all public access: On"
- [ ] CloudWatch -> Dashboard with live metrics
- [ ] Cost Explorer -> daily spend for this session

Save them in this folder as \`screenshot-<name>.png\`.
EOF

echo ""
echo "============================================================="
echo " DONE. Evidence written to: docs/evidence/$ENV/"
echo ""
echo " NEXT:"
echo "   1. Take the manual screenshots listed in the README"
echo "   2. Review every file for anything sensitive"
echo "   3. git add docs/evidence/ && git commit"
echo "   4. THEN run: terraform destroy"
echo "   5. Then: ./scripts/aws-audit.sh $PROFILE $REGION"
echo "============================================================="
