output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_ipv4_cidr" {
  description = "VPC IPv4 CIDR"
  value       = aws_vpc.main.cidr_block
}

output "vpc_ipv6_cidr" {
  description = "VPC IPv6 CIDR"
  value       = aws_vpc.main.ipv6_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = [for s in aws_subnet.private : s.id]
}

output "public_route_table_id" {
  description = "Public route table ID"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "Private route table ID"
  value       = aws_route_table.private.id
}

output "internet_gateway_id" {
  description = "IGW ID"
  value       = aws_internet_gateway.igw.id
}

output "egress_only_internet_gateway_id" {
  description = "EIGW ID (IPv6)"
  value       = try(aws_egress_only_internet_gateway.eigw[0].id, null)
}
