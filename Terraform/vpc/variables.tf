variable vpc_cidr {
  type        = string
  default     = "10.168.0.0/23"
  description = "vpc cidr"
}
variable public_subnet_1 {
  type        = string
  default     = "10.168.0.0/25"
  description = "public subnet 1"
}

variable public_subnet_2 {
  type        = string
  default     = "10.168.0.128/25"
  description = "public subnet 2"
}

variable private_subnet_1 {
  type        = string
  default     = "10.168.1.0/25"
  description = "private subnet"
}

variable private_subnet_2 {
  type        = string
  default     = "10.168.1.128/25"
  description = "private subnet 2"
}

variable common_tag {
  type        = string
  default     = "devops_project"
  description = "tag for vpc resources"
}