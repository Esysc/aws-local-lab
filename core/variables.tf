variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "key_name" {
  description = "Name of an existing AWS key pair to use for SSH access (required when use_local=false)"
  type        = string
  default     = ""

  validation {
    condition     = var.use_local || length(trim(var.key_name)) > 0
    error_message = "variable 'key_name' must be set when TF_VAR_use_local=false (real AWS runs require an SSH key pair)."
  }
}

variable "aws_profile" {
  description = "AWS CLI profile name to use when not running against LocalStack"
  type        = string
  default     = "Administrator"
}

variable "use_local" {
  description = "When true, configure provider to talk to LocalStack instead of real AWS"
  type        = bool
  default     = true
}

variable "localstack_endpoint" {
  description = "LocalStack edge service endpoint (when using LocalStack)"
  type        = string
  default     = "http://localhost:4566"
}

variable "domain" {
  description = "The domain to be used by the httpCheck script. When running locally (use_local=true) this can be empty."
  type        = string
  default     = ""

  validation {
    condition     = var.use_local || length(trim(var.domain)) > 0
    error_message = "variable 'domain' must be set when TF_VAR_use_local=false (real AWS runs require a domain)."
  }
}

variable "ami_id" {
  description = "Fallback AMI id used when running locally (LocalStack)."
  type        = string
  default     = "ami-0c02fb55956c7d316"
}

variable "localstack_pro" {
  description = "When true, LocalStack Pro feature set is available (enables advanced services in local mode)."
  type        = bool
  default     = false
}

variable "allowed_public_cidrs" {
  description = "CIDR blocks considered 'public' for example ingress rules. Default is restricted to the VPC network for local development.\nSet to [\"0.0.0.0/0\"] to allow internet-wide access (not recommended for production)."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "bastion_host" {
  description = "Host to reach the bastion. When running locally this defaults to 127.0.0.1 (exported by lab-run.sh)."
  type        = string
  default     = "127.0.0.1"
}

variable "bastion_ssh_port" {
  description = "SSH port for the bastion when running locally (default matches docker-compose mapping)."
  type        = number
  default     = 2222
}

variable "ssh_private_key_path" {
  description = "Local path to the SSH private key used to connect to the bastion when running locally. lab-run.sh generates and exports this as TF_VAR_ssh_private_key_path." 
  type        = string
  default     = ""
}

variable "ssh_user" {
  description = "Username to use for SSH connections to the bastion (local or remote)."
  type        = string
  default     = "root"
}

variable "local_web_port" {
  description = "Host port mapped to the local web container (used when TF_VAR_use_local=true)."
  type        = number
  default     = 9080
}

variable "docker_host" {
  description = "Docker host address used by the Terraform Docker provider. Set via TF_VAR_docker_host or DOCKER_HOST. Example: unix:///var/run/docker.sock or tcp://127.0.0.1:2375"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "web_ssh_port" {
  description = "SSH port mapped to the web container on the host."
  type        = number
  default     = 2223
}
