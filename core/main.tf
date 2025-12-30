terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 2.20"
    }
  }
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  # Support both real AWS and LocalStack for local testing.
  # Use `TF_VAR_use_local=true` to point the provider to LocalStack.
  region = var.region

  # When using real AWS, set a profile. When using LocalStack, credentials below are used.
  profile = var.use_local ? "" : var.aws_profile

  access_key                  = var.use_local ? "test" : null
  secret_key                  = var.use_local ? "test" : null
  skip_credentials_validation = var.use_local ? true : false
  skip_metadata_api_check     = var.use_local ? true : false

  endpoints {
    ec2         = var.use_local ? var.localstack_endpoint : null
    s3          = var.use_local ? var.localstack_endpoint : null
    elb         = var.use_local ? var.localstack_endpoint : null
    autoscaling = var.use_local ? var.localstack_endpoint : null
    route53     = var.use_local ? var.localstack_endpoint : null
    cloudwatch  = var.use_local ? var.localstack_endpoint : null
    iam         = var.use_local ? var.localstack_endpoint : null
  }
}

data "aws_ami" "ubuntu" {
  count       = var.use_local ? 0 : 1
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

locals {
  resolved_ami   = var.use_local ? var.ami_id : data.aws_ami.ubuntu[0].id
  advanced_count = var.use_local ? (var.localstack_pro ? 1 : 0) : 1
}

# Base64-encoded index.html content to inject via user-data template
locals {
  index_html_b64     = base64encode(file("${path.module}/../local_web/index.html"))
  bastion_pubkey_b64 = try(base64encode(file("${path.module}/../.local/ssh/id_rsa.pub")), "")
}

# Create a new VPC using the 10.0.0.0/16 CIDR block
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "main"
  }
}

# Flow logs: record VPC traffic to CloudWatch Logs (skipped for LocalStack/local runs)
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = var.use_local ? 0 : 1
  name              = "/aws/vpc/flow-logs/${aws_vpc.main.id}"
  retention_in_days = 30
}

resource "aws_iam_role" "vpc_flow_logs_role" {
  count = var.use_local ? 0 : 1
  name  = "vpc-flow-logs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Principal = { Service = "vpc-flow-logs.amazonaws.com" },
      Effect    = "Allow",
      Sid       = ""
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs_policy" {
  count = var.use_local ? 0 : 1
  name  = "vpc-flow-logs-policy"
  role  = aws_iam_role.vpc_flow_logs_role[0].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "vpc" {
  count                = var.use_local ? 0 : 1
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  iam_role_arn         = aws_iam_role.vpc_flow_logs_role[0].arn
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
}

# Create 3 subnets for the created VPC

resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  tags = {
    Name = "Public Subnet Main"
  }
}
resource "aws_subnet" "public_eu_west_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "eu-west-1a"

  tags = {
    Name = "Public Subnet eu-west-1a"
  }
}

resource "aws_subnet" "public_eu_west_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-1b"

  tags = {
    Name = "Public Subnet eu-west-1b"
  }
}

# Create a new internet gateway for the VPC
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "Public Subnets Route Table for My VPC"
  }
}

resource "aws_route_table_association" "my_vpc_eu_west_1a_public" {
  subnet_id      = aws_subnet.public_eu_west_1a.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "my_vpc_eu_west_1b_public" {
  subnet_id      = aws_subnet.public_eu_west_1b.id
  route_table_id = aws_route_table.main.id
}


# Create a new security group that allows inbound ssh requests
resource "aws_security_group" "allow_inbound_ssh" {
  name        = "allow-inbound-ssh"
  description = "Allow inbound SSH traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    description = "SSH from allowed public CIDRs"
    cidr_blocks = var.allowed_public_cidrs
  }
}
# Create a new security group that allows inbound ssh requests only on private network
resource "aws_security_group" "allow_inbound_ssh_private" {
  name        = "allow-inbound-ssh-private"
  description = "Allow inbound SSH private traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    description = "SSH from VPC internal CIDR"
    cidr_blocks = ["10.0.0.0/16"]
  }
}
# Create a new security group that allows outbound traffic
resource "aws_security_group" "allow_outbound_traffic" {
  name        = "allow-outbound-traffic"
  description = "Allow all outbound traffic"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Allow outbound to allowed public CIDRs"
    cidr_blocks = var.allowed_public_cidrs
  }

}

resource "aws_instance" "main_bastion" {
  count         = var.use_local ? 0 : 1
  ami           = local.resolved_ami
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.main.id
  key_name      = var.key_name
  user_data     = templatefile("${path.module}/templates/bastion_user_data.tpl", { pubkey_b64 = local.bastion_pubkey_b64 })
  tags = {
    Name = "bastion-server-01"
  }
  vpc_security_group_ids = [
    aws_security_group.allow_inbound_ssh.id,
    aws_security_group.allow_outbound_traffic.id,
  ]
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }
}

resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP inbound connections"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    description = "HTTP from allowed public CIDRs"
    cidr_blocks = var.allowed_public_cidrs
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Allow outbound to allowed public CIDRs"
    cidr_blocks = var.allowed_public_cidrs
  }

  tags = {
    Name = "Allow HTTP(s) Security Group"
  }
}
resource "aws_launch_configuration" "web" {
  count       = local.advanced_count
  name_prefix = "web-server-"

  image_id                    = local.resolved_ami
  instance_type               = "t2.micro"
  key_name                    = var.key_name
  security_groups             = [aws_security_group.allow_http.id, aws_security_group.allow_inbound_ssh_private.id]
  associate_public_ip_address = true
  user_data                   = templatefile("${path.module}/templates/user_data.tpl", { index_b64 = local.index_html_b64 })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "elb_http" {
  name        = "elb_http"
  description = "Allow HTTP traffic to instances through Elastic Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    description = "HTTP from allowed public CIDRs"
    cidr_blocks = var.allowed_public_cidrs
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Allow outbound to allowed public CIDRs"
    cidr_blocks = var.allowed_public_cidrs
  }

  tags = {
    Name = "Allow HTTP(s) through ELB Security Group"
  }
}

resource "aws_elb" "web_elb" {
  count = local.advanced_count
  name  = "web-elb"
  security_groups = [
    aws_security_group.elb_http.id
  ]
  subnets = [
    aws_subnet.public_eu_west_1a.id,
    aws_subnet.public_eu_west_1b.id
  ]

  cross_zone_load_balancing = true

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    target              = "HTTP:80/"
  }

  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = "80"
    instance_protocol = "http"
  }

}

resource "aws_autoscaling_group" "web" {
  count = local.advanced_count
  name  = "${aws_launch_configuration.web[0].name}-asg"

  min_size         = 1
  desired_capacity = 2
  max_size         = 4

  health_check_type = "ELB"
  load_balancers    = local.advanced_count == 1 ? [aws_elb.web_elb[0].id] : []

  launch_configuration = aws_launch_configuration.web[0].name

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]

  metrics_granularity = "1Minute"

  vpc_zone_identifier = [
    aws_subnet.public_eu_west_1a.id,
    aws_subnet.public_eu_west_1b.id
  ]

  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "web"
    propagate_at_launch = true
  }

}

resource "aws_autoscaling_policy" "web_policy_up" {
  count                  = local.advanced_count
  name                   = "web_policy_up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web[0].name
}



resource "aws_route53_zone" "web-public-zone" {
  name     = "cloud-lab.example"
  comment  = "cloud-lab.example public zone"
  provider = aws
}
resource "aws_route53_record" "cloudlab" {
  count   = local.advanced_count
  zone_id = aws_route53_zone.web-public-zone.zone_id
  name    = "test.cloud-lab.example"
  type    = "A"
  alias {
    name                   = aws_elb.web_elb[0].dns_name
    zone_id                = aws_elb.web_elb[0].zone_id
    evaluate_target_health = true
  }
}


resource "aws_cloudwatch_metric_alarm" "web_cpu_alarm_up" {
  count               = local.advanced_count
  alarm_name          = "web_cpu_alarm_up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "60"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web[0].name
  }
  alarm_description = "This metric monitor EC2 instance CPU utilization"
  alarm_actions     = [aws_autoscaling_policy.web_policy_up[0].arn]
}

resource "aws_autoscaling_policy" "web_policy_down" {
  count                  = local.advanced_count
  name                   = "web_policy_down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web[0].name
}

resource "aws_cloudwatch_metric_alarm" "web_cpu_alarm_down" {
  count               = local.advanced_count
  alarm_name          = "web_cpu_alarm_down"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "10"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web[0].name
  }

  alarm_description = "This metric monitor EC2 instance CPU utilization"
  alarm_actions     = [aws_autoscaling_policy.web_policy_down[0].arn]
}

resource "aws_eip" "bastionip" {
  count    = var.use_local ? 0 : 1
  instance = aws_instance.main_bastion[0].id
}
