output vpc-id {
  value       = aws_vpc.devops_project.id
    description = "VPC ID"
}

output  public-subnet-1-id {
  value       = aws_subnet.public_subnet_1.id
    description = "Public Subnet 1 ID"
}
output  public-subnet-2-id {
  value       = aws_subnet.public_subnet_2.id
    description = "Public Subnet 2 ID"
}
