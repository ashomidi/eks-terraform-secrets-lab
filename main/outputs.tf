output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}

output "db_main_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "db_replica_endpoint" {
  value = var.create_read_replica ? aws_db_instance.replica[0].endpoint : null
}
