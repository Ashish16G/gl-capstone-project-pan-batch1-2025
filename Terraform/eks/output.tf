output cluster_url {
  value       = aws_eks_cluster.ekscluster.endpoint
  sensitive   = true
  description = "eks cluster url"
}