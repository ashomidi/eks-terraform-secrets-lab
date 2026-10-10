variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "eks-postgres-lab"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "Subnets for EKS worker nodes (public, no NAT Gateway needed -- keeps cost down)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "db_subnet_cidrs" {
  description = "Subnets for RDS (isolated, no internet route needed)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "cluster_version" {
  type    = string
  default = "1.35"
}

variable "node_instance_type" {
  type    = string
  default = "t3.small"
}

variable "node_desired_size" {
  type    = number
  default = 1
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 2
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appadmin"
}

variable "db_password" {
  description = "Set via TF_VAR_db_password env var -- do not commit a value here"
  type        = string
  sensitive   = true
}

variable "create_read_replica" {
  description = "Set false while iterating to save free-tier hours; true when you want to practice replication"
  type        = bool
  default     = true
}
