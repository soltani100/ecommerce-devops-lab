provider "aws" {
  region = "us-east-1"
}

############################
# VPC
############################
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Main-VPC"
  }
}

############################
# Internet Gateway
############################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "Main-IGW"
  }
}

############################
# Public Subnet A
############################
resource "aws_subnet" "public_subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet-A"
  }
}

############################
# Public Subnet B
############################
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet-B"
  }
}

############################
# Route Table Public
############################
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Public-RT"
  }
}

############################
# Route Table Association A
############################
resource "aws_route_table_association" "public_assoc_a" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_rt.id
}

############################
# Route Table Association B
############################
resource "aws_route_table_association" "public_assoc_b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

############################
# Security Group for ALB
############################
resource "aws_security_group" "alb_sg" {
  name        = "ALB-SG"
  description = "Allow HTTP and HTTPS"
  vpc_id      = aws_vpc.main.id

  ##########################
  # HTTP
  ##########################
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ##########################
  # HTTPS
  ##########################
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ##########################
  # Outbound
  ##########################
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
  name        = "EC2-SG"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.main.id

  ##########################
  # HTTP depuis ALB
  ##########################
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ##########################
  # SSH pour Ansible
  ##########################
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"

    # Remplace par ton IP publique
    cidr_blocks = ["0.0.0.0/0"]
  }

  ##########################
  # Outbound
  ##########################
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
  subnet_id                   = aws_subnet.public_subnet_a.id
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
  subnet_id                   = aws_subnet.public_subnet_b.id
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
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb_sg.id
  ]

  subnets = [
    aws_subnet.public_subnet_a.id,
    aws_subnet.public_subnet_b.id
  ]

  tags = {
    Name = "Web-ALB"
  }
}

############################
# Target Group
############################
resource "aws_lb_target_group" "tg" {
  name     = "TG-WebApps"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

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
  name = "cpu-alerts"
}

############################
# Email Subscription
############################
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "admin@example.com"
}

############################
# CloudWatch Alarm Web1
############################
resource "aws_cloudwatch_metric_alarm" "cpu_alarm_web1" {
  alarm_name          = "HighCPU-Web1"
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

############################
# CloudWatch Alarm Web2
############################
resource "aws_cloudwatch_metric_alarm" "cpu_alarm_web2" {
  alarm_name          = "HighCPU-Web2"
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
