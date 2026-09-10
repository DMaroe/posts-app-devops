# Application load balancers, one per app tier.
#
# The frontend balancer is internet-facing and is the only public entry point
# to the system. The backend balancer is internal, so the API is reachable from
# the frontend tier inside the VPC but never from the internet.
#
# Both balancers also give each tier a stable DNS name. Instance IPs change
# every time the auto scaling group replaces an instance, so nothing in this
# project addresses instances directly any more.

resource "aws_security_group" "frontend_alb_sg" {
  name        = "frontend-alb-sg"
  description = "Public HTTP access to the frontend load balancer"

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "backend_alb_sg" {
  name        = "backend-alb-sg"
  description = "API access to the internal backend load balancer from the frontend tier"

  ingress {
    protocol        = "tcp"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.frontend_sg.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# FRONTEND - internet facing
resource "aws_lb" "frontend" {
  name               = "posts-app-frontend-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.frontend_alb_sg.id]
  subnets            = local.usable_subnet_ids
}

resource "aws_lb_target_group" "frontend" {
  name                 = "posts-app-frontend-tg"
  port                 = 8081
  protocol             = "HTTP"
  vpc_id               = data.aws_vpc.default.id
  deregistration_delay = 30

  health_check {
    path                = "/status"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

resource "aws_lb_listener" "frontend" {
  load_balancer_arn = aws_lb.frontend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# BACKEND - internal only
resource "aws_lb" "backend" {
  name               = "posts-app-backend-alb"
  load_balancer_type = "application"
  internal           = true
  security_groups    = [aws_security_group.backend_alb_sg.id]
  subnets            = local.usable_subnet_ids
}

resource "aws_lb_target_group" "backend" {
  name                 = "posts-app-backend-tg"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = data.aws_vpc.default.id
  deregistration_delay = 30

  # /status answers 200 whether or not the database is reachable, so a backend
  # instance stays in service during a database outage instead of being
  # replaced in a loop by the auto scaling group.
  health_check {
    path                = "/status"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

resource "aws_lb_listener" "backend" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

output "frontend_url" {
  value = "http://${aws_lb.frontend.dns_name}"
}

output "frontend_alb_dns_name" {
  value = aws_lb.frontend.dns_name
}

output "backend_alb_dns_name" {
  value = aws_lb.backend.dns_name
}
