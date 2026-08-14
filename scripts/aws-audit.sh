#!/usr/bin/env bash
#
# aws-audit.sh
# ------------
# "What is running in my AWS account right now, and is any of it
#  costing me money?"
#
# Run this:
#   - Before starting the project (to find leftovers from the last 2 years)
#   - At the END of every working session (to confirm you destroyed everything)
#
# This script is READ-ONLY. It creates nothing, deletes nothing, costs nothing.
#
# Usage:
#   chmod +x aws-audit.sh
#   ./aws-audit.sh                    # uses default profile + region
#   ./aws-audit.sh terraform ap-south-1
#
set -uo pipefail

PROFILE="${1:-default}"
REGION="${2:-ap-south-1}"

AWS="aws --profile $PROFILE --region $REGION --output text"

hdr() {
  echo ""
  echo "-------------------------------------------------------------"
  echo " $1"
  echo "-------------------------------------------------------------"
}

none_if_empty() {
  local out
  out="$(cat)"
  if [ -z "$out" ] || [ "$out" = "None" ]; then
    echo "  (none)  OK"
  else
    echo "$out" | sed 's/^/  /'
  fi
}

echo "============================================================="
echo " AWS ACCOUNT AUDIT"
echo " Profile: $PROFILE   Region: $REGION"
echo "============================================================="

hdr "WHO AM I"
aws sts get-caller-identity --profile "$PROFILE" --output table 2>&1 | sed 's/^/  /'

# =============================================================
# THINGS THAT COST MONEY EVERY HOUR
# =============================================================

hdr "NAT GATEWAYS   (~\$40/month each - the biggest silent cost)"
$AWS ec2 describe-nat-gateways \
  --filter "Name=state,Values=available,pending" \
  --query 'NatGateways[].[NatGatewayId,VpcId,State]' 2>/dev/null | none_if_empty

hdr "EC2 INSTANCES  (running instances are billed per second)"
$AWS ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running,pending,stopping" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`].Value|[0]]' 2>/dev/null | none_if_empty

hdr "LOAD BALANCERS (~\$17/month each)"
$AWS elbv2 describe-load-balancers \
  --query 'LoadBalancers[].[LoadBalancerName,Type,State.Code]' 2>/dev/null | none_if_empty

hdr "RDS DATABASES  (~\$13/month each + storage)"
$AWS rds describe-db-instances \
  --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus,MultiAZ]' 2>/dev/null | none_if_empty

hdr "ELASTIC IPs    (\$0.005/hr each when NOT attached to a running instance)"
$AWS ec2 describe-addresses \
  --query 'Addresses[].[PublicIp,AssociationId,InstanceId]' 2>/dev/null | none_if_empty

hdr "EBS VOLUMES    (billed even when detached / unused)"
$AWS ec2 describe-volumes \
  --query 'Volumes[].[VolumeId,Size,State,VolumeType]' 2>/dev/null | none_if_empty

hdr "EBS SNAPSHOTS  (small but they accumulate forever)"
$AWS ec2 describe-snapshots --owner-ids self \
  --query 'Snapshots[].[SnapshotId,VolumeSize,StartTime]' 2>/dev/null | none_if_empty

# =============================================================
# THINGS THAT ARE FREE BUT WORTH KNOWING ABOUT
# =============================================================

hdr "VPCs           (free - but check for leftovers from old projects)"
$AWS ec2 describe-vpcs \
  --query 'Vpcs[].[VpcId,CidrBlock,IsDefault]' 2>/dev/null | none_if_empty

hdr "S3 BUCKETS     (storage is cheap, but check what is in them)"
aws s3 ls --profile "$PROFILE" 2>/dev/null | sed 's/^/  /' || echo "  (none)  OK"

# =============================================================
# SECURITY HYGIENE
# =============================================================

hdr "IAM USERS"
$AWS iam list-users --query 'Users[].[UserName,CreateDate]' 2>/dev/null | none_if_empty

hdr "IAM ACCESS KEYS  (each one is a long-lived credential that can leak)"
for u in $(aws iam list-users --profile "$PROFILE" --query 'Users[].UserName' --output text 2>/dev/null); do
  keys=$(aws iam list-access-keys --profile "$PROFILE" --user-name "$u" \
    --query 'AccessKeyMetadata[].[AccessKeyId,Status,CreateDate]' --output text 2>/dev/null)
  if [ -n "$keys" ]; then
    echo "  USER: $u"
    echo "$keys" | sed 's/^/    /'
  fi
done

hdr "ROOT ACCESS KEYS  (must be 0)"
root_keys=$(aws iam get-account-summary --profile "$PROFILE" \
  --query 'SummaryMap.AccountAccessKeysPresent' --output text 2>/dev/null)
if [ "$root_keys" = "0" ]; then
  echo "  0  -- GOOD"
else
  echo "  $root_keys  -- DANGER: delete root access keys immediately"
fi

hdr "SECURITY GROUPS OPEN TO THE WORLD (0.0.0.0/0)"
$AWS ec2 describe-security-groups \
  --query 'SecurityGroups[?IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]].[GroupId,GroupName,Description]' 2>/dev/null | none_if_empty

# =============================================================
# COST
# =============================================================

hdr "MONTH-TO-DATE SPEND"
START=$(date -u +%Y-%m-01)
END=$(date -u +%Y-%m-%d)
if [ "$START" = "$END" ]; then
  echo "  (first of the month - no data yet)"
else
  aws ce get-cost-and-usage \
    --profile "$PROFILE" \
    --time-period Start="$START",End="$END" \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --query 'ResultsByTime[0].Total.UnblendedCost.[Amount,Unit]' \
    --output text 2>/dev/null | sed 's/^/  /' \
    || echo "  (Cost Explorer not enabled, or no permission - enable it in the Billing console)"
fi

echo ""
echo "============================================================="
echo " AUDIT COMPLETE"
echo ""
echo " Reminder: this only checked region '$REGION'."
echo " Resources can hide in other regions. To check everywhere:"
echo "   for r in \$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do"
echo "     ./aws-audit.sh $PROFILE \$r"
echo "   done"
echo "============================================================="
