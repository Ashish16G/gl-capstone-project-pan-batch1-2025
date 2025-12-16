output public-ip {
  value       = aws_instance.prod_server.public_ip
  sensitive   = false
  description = "public ip address of the EC2 instance"
}
