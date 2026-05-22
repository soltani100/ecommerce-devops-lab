provider "aws" {
  region = "us-east-1"
}

############################
# Utiliser le VPC par défaut EXISTANT (ne pas en créer un nouveau)
############################
data "aws_vpc" "default" {
  default = true
}

############################
# Récupérer les subnets publics du VPC par défaut
############################
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

data "aws_subnet" "public_a" {
  id = data.aws_subnets.public.ids[0]
}

data "aws_subnet" "public_b" {
  id = data.aws_subnets.public.ids[1]
}

############################
# Variables pour noms uniques
############################
variable "suffix" {
  description = "Suffix unique pour les ressources"
  type        = string
  default     = ""
}

locals {
  resource_suffix = var.suffix != "" ? var.suffix : formatdate("YYYYMMDDhhmmss", timestamp())
}

############################
# Security Group for ALB
############################
resource "aws_security_group" "alb_sg" {
  name        = "ALB-SG-${local.resource_suffix}"
  description = "Allow HTTP and HTTPS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ALB-SG"
  }
}

############################
# Security Group for EC2
############################
resource "aws_security_group" "ec2_sg" {
  name        = "EC2-SG-${local.resource_suffix}"
  description = "Allow HTTP and SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "EC2-SG"
  }
}

############################
# EC2 Web1
############################
resource "aws_instance" "web1" {
  ami                         = "ami-0c02fb55956c7d316"
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnet.public_a.id
  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.ec2_sg.id
  ]

  key_name = "mykey"

  tags = {
    Name = "EC2-Web-1"
  }
}

############################
# EC2 Web2
############################
resource "aws_instance" "web2" {
  ami                         = "ami-0c02fb55956c7d316"
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnet.public_b.id
  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.ec2_sg.id
  ]

  key_name = "mykey"

  tags = {
    Name = "EC2-Web-2"
  }
}

############################
# Application Load Balancer
############################
resource "aws_lb" "alb" {
  name               = "web-alb-${local.resource_suffix}"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb_sg.id
  ]

  subnets = [
    data.aws_subnet.public_a.id,
    data.aws_subnet.public_b.id
  ]

  tags = {
    Name = "Web-ALB"
  }
}

############################
# Target Group
############################
resource "aws_lb_target_group" "tg" {
  name     = "TG-WebApps-${local.resource_suffix}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "TG-WebApps"
  }
}

############################
# Attach EC2 to Target Group
############################
resource "aws_lb_target_group_attachment" "web1_attach" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "web2_attach" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web2.id
  port             = 80
}

############################
# Listener HTTP
############################
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

############################
# SNS Topic
############################
resource "aws_sns_topic" "alerts" {
  name = "cpu-alerts-${local.resource_suffix}"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "admin@example.com"
}

############################
# CloudWatch Alarms
############################
resource "aws_cloudwatch_metric_alarm" "cpu_alarm_web1" {
  alarm_name          = "HighCPU-Web1-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 75

  dimensions = {
    InstanceId = aws_instance.web1.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "cpu_alarm_web2" {
  alarm_name          = "HighCPU-Web2-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 75

  dimensions = {
    InstanceId = aws_instance.web2.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

############################
# Outputs
############################
output "instance_public_ips" {
  value = [
    aws_instance.web1.public_ip,
    aws_instance.web2.public_ip
  ]
  description = "Public IP addresses of the EC2 instances"
}

output "alb_dns_name" {
  value = aws_lb.alb.dns_name
  description = "DNS name of the Application Load Balancer"
}

output "vpc_id" {
  value = data.aws_vpc.default.id
  description = "ID du VPC par défaut utilisé"
}
