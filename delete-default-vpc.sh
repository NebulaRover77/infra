#!/usr/bin/env bash
# delete-default-vpc.sh
#
# Deletes the DEFAULT VPC (and its dependencies) in one region or all regions.
#
# Usage:
#   ./delete-default-vpc.sh --profile AWSPowerUserAccess-569260898148 --region us-east-1
#   ./delete-default-vpc.sh --profile AWSPowerUserAccess-569260898148 --all-regions
#   ./delete-default-vpc.sh --profile AWSPowerUserAccess-569260898148 --all-regions --dry-run
#
# Notes:
# - This only targets VPCs where IsDefault=true.
# - Deletion order: VPC endpoints, NAT GWs, EIPs, ENIs (if possible), IGWs, subnets, non-main RTBs, non-default NACLs, SGs (non-default), then VPC.
# - If something is in use (EC2, RDS, EKS, etc.), deletion will fail; the script prints remaining dependencies.

set -euo pipefail

PROFILE=""
REGION=""
ALL_REGIONS="false"
DRY_RUN="false"

die() { echo "ERROR: $*" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY-RUN: $*"
  else
    eval "$@"
  fi
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

need aws

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2;;
    --region) REGION="$2"; shift 2;;
    --all-regions) ALL_REGIONS="true"; shift;;
    --dry-run) DRY_RUN="true"; shift;;
    -h|--help)
      sed -n '1,40p' "$0"
      exit 0
      ;;
    *) die "Unknown arg: $1";;
  esac
done

[[ -n "$PROFILE" ]] || die "--profile is required"
if [[ "$ALL_REGIONS" != "true" && -z "$REGION" ]]; then
  die "Provide --region or --all-regions"
fi

aws_cli() {
  aws --profile "$PROFILE" "$@"
}

list_regions() {
  aws_cli ec2 describe-regions --query "Regions[].RegionName" --output text | tr '\t' '\n'
}

find_default_vpc() {
  local r="$1"
  aws_cli --region "$r" ec2 describe-vpcs \
    --filters Name=isDefault,Values=true \
    --query "Vpcs[0].VpcId" --output text 2>/dev/null || true
}

print_deps() {
  local r="$1" vpc="$2"
  echo "Remaining dependencies in $r for $vpc (if any):"
  aws_cli --region "$r" ec2 describe-vpc-endpoints --filters Name=vpc-id,Values="$vpc" --query "VpcEndpoints[].VpcEndpointId" --output text || true
  aws_cli --region "$r" ec2 describe-nat-gateways --filter Name=vpc-id,Values="$vpc" --query "NatGateways[].NatGatewayId" --output text || true
  aws_cli --region "$r" ec2 describe-network-interfaces --filters Name=vpc-id,Values="$vpc" --query "NetworkInterfaces[].NetworkInterfaceId" --output text || true
  aws_cli --region "$r" ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values="$vpc" --query "InternetGateways[].InternetGatewayId" --output text || true
  aws_cli --region "$r" ec2 describe-subnets --filters Name=vpc-id,Values="$vpc" --query "Subnets[].SubnetId" --output text || true
}

delete_default_vpc_region() {
  local r="$1"

  local vpc
  vpc="$(find_default_vpc "$r")"
  if [[ -z "$vpc" || "$vpc" == "None" ]]; then
    echo "[$r] No default VPC found."
    return 0
  fi

  echo "[$r] Default VPC: $vpc"

  # Capture DHCP options set used by the default VPC
  local dhcp_id
  dhcp_id="$(aws_cli --region "$r" ec2 describe-vpcs \
    --vpc-ids "$vpc" \
    --query "Vpcs[0].DhcpOptionsId" \
    --output text || true)"
  echo "[$r] DHCP options set: $dhcp_id"

  # 1) Delete VPC endpoints (interface + gateway endpoints)
  local vpc_endpoints
  vpc_endpoints="$(aws_cli --region "$r" ec2 describe-vpc-endpoints \
    --filters Name=vpc-id,Values="$vpc" \
    --query "VpcEndpoints[].VpcEndpointId" --output text || true)"
  if [[ -n "${vpc_endpoints// }" ]]; then
    for ep in $vpc_endpoints; do
      echo "[$r] Deleting VPC endpoint $ep"
      run "aws --profile \"$PROFILE\" --region \"$r\" ec2 delete-vpc-endpoints --vpc-endpoint-ids $ep"
    done
  fi

  # 2) Delete NAT gateways (and release their EIPs)
  local nat_gws
  nat_gws="$(aws_cli --region "$r" ec2 describe-nat-gateways \
    --filter Name=vpc-id,Values="$vpc" \
    --query "NatGateways[].NatGatewayId" --output text || true)"
  if [[ -n "${nat_gws// }" ]]; then
    for nat in $nat_gws; do
      echo "[$r] Deleting NAT gateway $nat"
      run "aws --profile \"$PROFILE\" --region \"$r\" ec2 delete-nat-gateway --nat-gateway-id $nat"
    done
    echo "[$r] Waiting a bit for NAT gateways to start deleting (AWS may take a while)..."
  fi

  # 3) Try delete EIPs that are unattached (safe cleanup)
  local eips
  eips="$(aws_cli --region "$r" ec2 describe-addresses --query "Addresses[?AssociationId==null].AllocationId" --output text || true)"
  if [[ -n "${eips// }" ]]; then
    for alloc in $eips; do
      echo "[$r] Releasing unattached EIP $alloc"
      run "aws --profile \"$PROFILE\" --region \"$r\" ec2 release-address --allocation-id $alloc"
    done
  fi

  # 4) Detach + delete internet gateways attached to this VPC
  local igws
  igws="$(aws_cli --region "$r" ec2 describe-internet-gateways \
    --filters Name=attachment.vpc-id,Values="$vpc" \
    --query "InternetGateways[].InternetGatewayId" --output text || true)"
  if [[ -n "${igws// }" ]]; then
    for igw in $igws; do
      echo "[$r] Detaching IGW $igw"
      run "aws --profile \"$PROFILE\" --region \"$r\" ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpc"
      echo "[$r] Deleting IGW $igw"
      run "aws --profile \"$PROFILE\" --region \"$r\" ec2 delete-internet-gateway --internet-gateway-id $igw"
    done
  fi

  # 5) Delete subnets in the VPC
  local subnets
  subnets="$(aws_cli --region "$r" ec2 describe-subnets \
    --filters Name=vpc-id,Values="$vpc" \
    --query "Subnets[].SubnetId" --output text || true)"
  if [[ -n "${subnets// }" ]]; then
    for s in $subnets; do
      echo "[$r] Deleting subnet $s"
      run "aws --profile \"$PROFILE\" --region \"$r\" ec2 delete-subnet --subnet-id $s"
    done
  fi

  # 6) Delete non-main route tables
  local rtbs
  rtbs="$(aws_cli --region "$r" ec2 describe-route-tables \
    --filters Name=vpc-id,Values="$vpc" \
    --query "RouteTables[?Associations[?Main==\`true\`]==\`[]\`].RouteTableId" --output text || true)"
  if [[ -n "${rtbs// }" ]]; then
    for rtb in $rtbs; do
      echo "[$r] Deleting route table $rtb"
      run "aws --profile \"$PROFILE\" --region \"$r\" ec2 delete-route-table --route-table-id $rtb"
    done
  fi

  # 7) Delete non-default network ACLs
  local acls
  acls="$(aws_cli --region "$r" ec2 describe-network-acls \
    --filters Name=vpc-id,Values="$vpc" \
    --query "NetworkAcls[?IsDefault==\`false\`].NetworkAclId" --output text || true)"
  if [[ -n "${acls// }" ]]; then
    for acl in $acls; do
      echo "[$r] Deleting network ACL $acl"
      run "aws --profile \"$PROFILE\" --region \"$r\" ec2 delete-network-acl --network-acl-id $acl"
    done
  fi

  # 8) Delete non-default security groups (default SG can't be deleted until VPC is deleted)
  local sgs
  sgs="$(aws_cli --region "$r" ec2 describe-security-groups \
    --filters Name=vpc-id,Values="$vpc" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" --output text || true)"
  if [[ -n "${sgs// }" ]]; then
    for sg in $sgs; do
      echo "[$r] Deleting security group $sg"
      run "aws --profile \"$PROFILE\" --region \"$r\" ec2 delete-security-group --group-id $sg"
    done
  fi

  # 9) Final: delete the VPC
  echo "[$r] Deleting VPC $vpc"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY-RUN: aws --profile \"$PROFILE\" --region \"$r\" ec2 delete-vpc --vpc-id $vpc"
    return 0
  fi

  if ! aws_cli --region "$r" ec2 delete-vpc --vpc-id "$vpc"; then
    echo "[$r] Failed to delete VPC $vpc (DependencyViolation likely)."
    print_deps "$r" "$vpc"
    return 1
  fi

  # 10) Delete DHCP options set if it is now unused
  if [[ -n "${dhcp_id:-}" && "$dhcp_id" != "default" && "$dhcp_id" != "None" ]]; then
    local still_used
    still_used="$(aws_cli --region "$r" ec2 describe-vpcs \
      --filters Name=dhcp-options-id,Values="$dhcp_id" \
      --query "length(Vpcs)" \
      --output text || true)"

    if [[ "${still_used:-0}" == "0" ]]; then
      echo "[$r] Deleting DHCP options set $dhcp_id (unused)"
      run "aws --profile \"$PROFILE\" --region \"$r\" ec2 delete-dhcp-options --dhcp-options-id $dhcp_id"
    else
      echo "[$r] Not deleting DHCP options set $dhcp_id (still used by $still_used VPC(s))"
    fi
  fi

  echo "[$r] Deleted default VPC $vpc"
}

regions=()
if [[ "$ALL_REGIONS" == "true" ]]; then
  mapfile -t regions < <(list_regions)
else
  regions=("$REGION")
fi

fail=0
for r in "${regions[@]}"; do
  echo "=== Region: $r ==="
  if ! delete_default_vpc_region "$r"; then
    fail=1
  fi
done

exit $fail
