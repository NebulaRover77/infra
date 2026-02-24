variable "profile" {
  type        = string
  description = "AWS CLI profile name (optional). If null, AWS provider uses the default credential chain."
  default     = null
}

variable "region" {
  type        = string
  description = "Primary AWS region (also used as the pool locale for top-level pools)."
  default     = "us-east-1"
}

variable "additional_operating_regions" {
  type        = list(string)
  description = "Additional operating regions for IPAM. A /16 IPv4 regional pool will be created in each."
  default     = []
}

variable "ipam_description" {
  type        = string
  description = "Description for the IPAM."
  default     = "Primary IPAM managed by Terraform"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}

# -------------------------
# IPv4 (private) hierarchy
# -------------------------
variable "ipv4_supernet" {
  type        = string
  description = "Top-level private IPv4 supernet for the IPAM (RFC1918)."
  default     = "10.0.0.0/8"
}

variable "ipv4_top_pool_name" {
  type        = string
  description = "Name tag for the IPv4 top-level pool."
  default     = "ipv4-top-10-8"
}

variable "ipv4_regional_pool_name_prefix" {
  type        = string
  description = "Prefix for Name tags of regional IPv4 pools (suffix will be region)."
  default     = "ipv4-regional-10-8"
}

# VPC allocation sizing from the *regional* /16 pools
# Default is /22 as requested; allow range /20..../24
variable "vpc_default_netmask" {
  type        = number
  description = "Default netmask length for VPC allocations from the regional IPv4 pools."
  default     = 22
  validation {
    condition     = var.vpc_default_netmask >= 16 && var.vpc_default_netmask <= 28
    error_message = "vpc_default_netmask must be between 16 and 28."
  }
}

variable "vpc_min_netmask" {
  type        = number
  description = "Minimum netmask length allowed for VPC allocations from the regional IPv4 pools."
  default     = 20
  validation {
    condition     = var.vpc_min_netmask >= 16 && var.vpc_min_netmask <= 28
    error_message = "vpc_min_netmask must be between 16 and 28."
  }
}

variable "vpc_max_netmask" {
  type        = number
  description = "Maximum netmask length allowed for VPC allocations from the regional IPv4 pools."
  default     = 24
  validation {
    condition     = var.vpc_max_netmask >= 16 && var.vpc_max_netmask <= 28
    error_message = "vpc_max_netmask must be between 16 and 28."
  }
}

# Terraform doesn't allow validation blocks to reference other variables directly in a portable way,
# so we enforce via a precondition in main.tf (see note below).

# -------------------------
# IPv6 (public) top-level
# -------------------------
variable "ipv6_pool_name" {
  type        = string
  description = "Name tag for the IPv6 top-level pool."
  default     = "ipv6-top"
}

variable "ipv6_top_netmask_length" {
  type        = number
  description = "Netmask length to request from Amazon for the top-level IPv6 pool."
  default     = 52
}

# Allocation sizes out of the IPv6 pool (e.g., /56 per VPC)
variable "ipv6_default_netmask" {
  type    = number
  default = 56
}

variable "ipv6_min_netmask" {
  type    = number
  default = 56
}

variable "ipv6_max_netmask" {
  type    = number
  default = 56
}
