variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "key_name" {
  description = "Name of an existing AWS key pair to use for SSH access (leave empty to set via provider/profile)"
  type        = string
  default     = ""
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
