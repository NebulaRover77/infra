output "ipam_id" {
  value = aws_vpc_ipam.this.id
}

output "private_default_scope_id" {
  value = aws_vpc_ipam.this.private_default_scope_id
}

output "public_default_scope_id" {
  value = aws_vpc_ipam.this.public_default_scope_id
}

output "ipv4_top_pool_id" {
  value = aws_vpc_ipam_pool.ipv4_top.id
}

output "ipv4_top_pool_cidr" {
  value = aws_vpc_ipam_pool_cidr.ipv4_top_cidr.cidr
}

output "ipv4_regional_pool_ids" {
  description = "Map of region => IPv4 regional pool ID"
  value       = { for r, p in aws_vpc_ipam_pool.ipv4_regional : r => p.id }
}

output "ipv4_regional_pool_cidrs" {
  description = "Map of region => assigned /16 CIDR for that regional pool"
  value       = { for r, c in aws_vpc_ipam_pool_cidr.ipv4_regional_cidr : r => c.cidr }
}

output "ipv6_pool_id" {
  value = aws_vpc_ipam_pool.ipv6_top.id
}

output "ipv6_top_assigned_cidr" {
  description = "Amazon-assigned IPv6 CIDR for the top-level pool (requested /52)"
  value       = aws_vpc_ipam_pool_cidr.ipv6_top_cidr.cidr
}
