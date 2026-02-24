terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

locals {
  # Regions that the IPAM will operate in (and where we create a /16 child pool)
  all_regions = toset(concat([var.region], var.additional_operating_regions))
}

resource "aws_vpc_ipam" "this" {
  description = var.ipam_description
  tier        = "free"

  # Primary region
  operating_regions {
    region_name = var.region
  }

  # Additional operating regions
  dynamic "operating_regions" {
    for_each = toset(var.additional_operating_regions)
    content {
      region_name = operating_regions.value
    }
  }

  lifecycle {
    precondition {
      condition     = var.vpc_min_netmask <= var.vpc_default_netmask && var.vpc_default_netmask <= var.vpc_max_netmask
      error_message = "Invalid VPC netmask settings: must satisfy vpc_min_netmask <= vpc_default_netmask <= vpc_max_netmask."
    }
  }


  tags = var.tags
}

#
# IPv4 top-level pool: 10.0.0.0/8 in PRIVATE default scope
#
resource "aws_vpc_ipam_pool" "ipv4_top" {
  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam.this.private_default_scope_id
  locale         = var.region

  description = "IPv4 top-level pool (10.0.0.0/8) for regional allocations"

  auto_import = false

  # This top pool is not directly used by VPCs; it only hands out /16s to regional child pools.
  allocation_default_netmask_length = 16
  allocation_min_netmask_length     = 16
  allocation_max_netmask_length     = 16

  tags = merge(var.tags, {
    Name = var.ipv4_top_pool_name
  })
}

resource "aws_vpc_ipam_pool_cidr" "ipv4_top_cidr" {
  ipam_pool_id = aws_vpc_ipam_pool.ipv4_top.id
  cidr         = var.ipv4_supernet
}

#
# IPv4 regional child pools:
# - One per region in local.all_regions
# - Each child pool gets a /16 from the top pool (no hardcoded CIDRs)
# - VPC allocations from the child pool are VARIABLE (default /22)
#
resource "aws_vpc_ipam_pool" "ipv4_regional" {
  for_each = local.all_regions

  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.this.private_default_scope_id
  source_ipam_pool_id = aws_vpc_ipam_pool.ipv4_top.id
  locale              = each.value

  description = "IPv4 regional pool (${each.value}) allocating VPC CIDRs (default /${var.vpc_default_netmask})"

  auto_import = false

  # VPC allocations from this pool: default /22, allow /20..../24 (configurable)
  allocation_default_netmask_length = var.vpc_default_netmask
  allocation_min_netmask_length     = var.vpc_min_netmask
  allocation_max_netmask_length     = var.vpc_max_netmask

  tags = merge(var.tags, {
    Name = "${var.ipv4_regional_pool_name_prefix}-${each.value}"
  })
}

# Request a /16 CIDR for each regional pool from the /8 parent pool
resource "aws_vpc_ipam_pool_cidr" "ipv4_regional_cidr" {
  for_each = local.all_regions

  ipam_pool_id   = aws_vpc_ipam_pool.ipv4_regional[each.value].id
  netmask_length = 16
}

#
# IPv6 top-level public pool: Amazon-assigned /52 (no CIDR hardcoding)
#
resource "aws_vpc_ipam_pool" "ipv6_top" {
  address_family = "ipv6"
  ipam_scope_id  = aws_vpc_ipam.this.public_default_scope_id
  locale         = var.region

  description = "Public IPv6 top-level pool (Amazon-assigned)"

  auto_import = false

  aws_service      = "ec2"
  public_ip_source = "amazon"

  # Typical: allocate /56 blocks out of the /52
  allocation_default_netmask_length = var.ipv6_default_netmask
  allocation_min_netmask_length     = var.ipv6_min_netmask
  allocation_max_netmask_length     = var.ipv6_max_netmask

  tags = merge(var.tags, {
    Name = var.ipv6_pool_name
  })
}

resource "aws_vpc_ipam_pool_cidr" "ipv6_top_cidr" {
  ipam_pool_id   = aws_vpc_ipam_pool.ipv6_top.id
  netmask_length = var.ipv6_top_netmask_length
}
