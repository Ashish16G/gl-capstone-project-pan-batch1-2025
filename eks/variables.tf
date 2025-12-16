variable cluster_name {
  type        = string
  default     = "capstone_project"
  description = "eks cluster name"
}
variable region {
  type        = string
  default     = "ap-south-1"
  description = "default eks region"
}


variable bucket_name {
  type        = string
  default     = "eiminenace-capstone-project"
  description = "s3 backend configurations for eks"
}

variable controle_plane_iam_role {
  type        = string
  default     = "arn:aws:iam::117930648227:role/eks-master-role"
  description = "IAM role for control plane"
}

variable eks_version {
  type        = string
  default     = "1.30"
  description = "eks version to be deployed"
}

variable workernode_iam_role {
  type        = string
  default     = "arn:aws:iam::117930648227:role/eks-worker-nodes"
  description = "IAM role for worker nodes"
}

variable ssh_key_name {
  type        = string
  default     = "keypairinstance1"
  description = "ssh key for logging in to worker nodes"
}

variable workernode_instance_type {
  type        = string
  default     = "t2.micro"
  description = "description"
}

variable workernode_storage {
  type        = number
  default     = 30
  description = "disk allocated to worker nodes"
}

variable desired_size {
  type        = string
  default     = "3"
  description = "desired number of worker nodes"
}
variable maximum_worker_nodes {
  type        = string
  default     = "5"
  description = "maximum number of worker nodes"
}

variable min_worker_nodes {
  type        = string
  default     = "1"
  description = "min number of worker nodes"
}
variable profile {
  type        = string
  default     = "dev"
  description = "aws resource creation profile"
}

variable vpc_id {
  type        = string
  default     = "vpc-0601551ed90c6d9f6"
  description = "description"
}

variable subnet_ids {
  type        = list
  default     = ["subnet-058f52152d620e822","subnet-0e66b368e185b3742"]
  description = "description"
}