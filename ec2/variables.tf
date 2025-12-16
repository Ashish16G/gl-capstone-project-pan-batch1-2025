variable ami_image {
  type        = string
  default     = "ami-01760eea5c574eb86"
  description = "Amazon linux image id"
}

variable instance_type {
  type        = string
  default     = "t2.micro"
  description = "Developement server"
}

variable sshkeyname {
  type        = string
  default     = "training.pem"
  description = "ssh key to login instance"
}

variable storageallocated {
  type        = string
  default     = "30GiB"
  description = "ec2 instance storage"
}


variable subnet {
  type        = string
  default     = "subnet-0129e99e311da32dd"
  description = "subnet id"
}


variable commontag {
  type        = string
  default     = "devops_project"
  description = ""
}