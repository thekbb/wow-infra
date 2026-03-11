variable "allowed_ingress_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to connect to NLB listeners (3724/8085)."
  default     = ["0.0.0.0/0"]
}

variable "auth_container_port" {
  type        = number
  description = "Authserver container port."
  default     = 3724
}

variable "auth_desired_count" {
  type        = number
  description = "Desired count for authserver service."
  default     = 1
}

variable "auth_image" {
  type        = string
  description = "Authserver image URI."
  default     = "acore/ac-wotlk-authserver:master"
}

variable "client_data_image" {
  type        = string
  description = "Client data image URI."
  default     = "acore/ac-wotlk-client-data:master"
}

variable "db_allocated_storage" {
  type        = number
  description = "RDS allocated storage (GiB)."
  default     = 50
}

variable "db_auth_name" {
  type        = string
  description = "Auth database name."
  default     = "acore_auth"
}

variable "db_characters_name" {
  type        = string
  description = "Characters database name."
  default     = "acore_characters"
}

variable "db_engine_version" {
  type        = string
  description = "RDS MySQL engine version."
  default     = "8.4"
}

variable "db_import_image" {
  type        = string
  description = "DB bootstrap/import image URI."
  default     = "acore/ac-wotlk-db-import:master"
}

variable "db_instance_class" {
  type        = string
  description = "RDS instance class."
  default     = "db.t4g.medium"
}

variable "db_name" {
  type        = string
  description = "Initial database name."
  default     = "acore_auth"
}

variable "db_username" {
  type        = string
  description = "Master username for RDS."
  default     = "acore"
}

variable "db_world_name" {
  type        = string
  description = "World database name."
  default     = "acore_world"
}

variable "desired_task_cpu" {
  type        = number
  description = "Task CPU units for both services."
  default     = 1024
}

variable "desired_task_memory" {
  type        = number
  description = "Task memory (MiB) for both services."
  default     = 2048
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch Logs retention in days."
  default     = 14
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDRs (one per AZ)."
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDRs (one per AZ)."
  default     = ["10.20.0.0/24", "10.20.1.0/24"]

  validation {
    condition = (
      length(var.public_subnet_cidrs) == length(var.private_subnet_cidrs) &&
      length(var.public_subnet_cidrs) > 0 &&
      length(var.public_subnet_cidrs) <= 2
    )
    error_message = "public_subnet_cidrs must be non-empty, match private_subnet_cidrs, and fit the two hardcoded us-east-2 AZs."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR for the VPC."
  default     = "10.20.0.0/16"
}

variable "world_container_port" {
  type        = number
  description = "Worldserver container port."
  default     = 8085
}

variable "world_desired_count" {
  type        = number
  description = "Desired count for worldserver service."
  default     = 1
}

variable "world_image" {
  type        = string
  description = "Worldserver image URI."
  default     = "acore/ac-wotlk-worldserver:master"
}
