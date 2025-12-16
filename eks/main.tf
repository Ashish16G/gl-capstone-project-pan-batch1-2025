module "vpc" {
  source  = "../vpc"
}


resource "aws_security_group" "controle_plane_security_group"{
  name = "controle_plane_security_group"
  description = "Security group for the elastic network interfaces between the control plane and the worker nodes"
  vpc_id = module.vpc.vpc-id
}

resource "aws_security_group_rule" "ControlPlaneIngressFromWorkerNodesHttps" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  source_security_group_id = aws_security_group.controle_plane_security_group.id
  security_group_id = aws_security_group.controle_plane_security_group.id
}


resource "aws_security_group_rule" "ControlPlaneEgressToWorkerNodesKubelet" {
  type              = "egress"
  from_port         = 10250
  to_port           = 10250
  protocol          = "tcp"
  source_security_group_id = aws_security_group.controle_plane_security_group.id
  security_group_id = aws_security_group.controle_plane_security_group.id
}
resource "aws_security_group_rule" "ControlPlaneEgressToWorkerNodesHttps" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  source_security_group_id = aws_security_group.controle_plane_security_group.id
  security_group_id = aws_security_group.controle_plane_security_group.id
}

# =============================================================================
resource "aws_security_group" "worker_node_security_group"{
  name = "worker_node_security_group"
  description = "Security group for all the worker nodes"
  vpc_id = module.vpc.vpc-id
}

resource "aws_security_group_rule" "WorkerNodesIngressFromWorkerNodes" {
  type              = "ingress"
  protocol          = "all"
  from_port         = 0
  to_port           = 0
  source_security_group_id = aws_security_group.worker_node_security_group.id
  security_group_id = aws_security_group.worker_node_security_group.id
}

resource "aws_security_group_rule" "WorkerNodesIngressFromControlPlaneKubelet" {
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 10250
  to_port           = 10250
  source_security_group_id = aws_security_group.worker_node_security_group.id
  security_group_id = aws_security_group.worker_node_security_group.id
}


resource "aws_security_group_rule" "WorkerNodesIngressFromControlPlaneHttps" {
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 443
  to_port           = 443
  source_security_group_id = aws_security_group.worker_node_security_group.id
  security_group_id = aws_security_group.worker_node_security_group.id
  
}
# ==========================================================================
resource "aws_security_group" "ssh_login_security_group"{
  name = "worker_node_security_group for ssh login"
  description = "Security group for all the worker nodes"
  vpc_id = module.vpc.vpc-id

  ingress {
    from_port = 22
    protocol  =  "tcp"
    to_port   = 22
    cidr_blocks = ["10.168.0.0/16"]
  }
  egress{
    from_port = 0
    to_port   = 0
    protocol  = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# ==================Controle plane creation ============================#



resource "aws_eks_cluster" "ekscluster" {
  name     = var.cluster_name
  role_arn = var.controle_plane_iam_role
  version  = var.eks_version

  vpc_config {
    subnet_ids = [module.vpc.public-subnet-1-id,module.vpc.public-subnet-2-id]
    security_group_ids = [aws_security_group.controle_plane_security_group.id]
  }

}


#==========================Workernodescreation=================================
resource "aws_eks_node_group" "private-nodes" {
  cluster_name    = aws_eks_cluster.ekscluster.name
  node_group_name = join("-",[var.cluster_name,"workernodes"])
  node_role_arn   = var.workernode_iam_role
  

  subnet_ids = [module.vpc.public-subnet-1-id,module.vpc.public-subnet-2-id]

  capacity_type  = "ON_DEMAND"
  instance_types = [var.workernode_instance_type]
  disk_size      =  var.workernode_storage


  scaling_config {
    desired_size = var.desired_size
    max_size     = var.maximum_worker_nodes
    min_size     = var.min_worker_nodes
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = var.cluster_name
  }
}