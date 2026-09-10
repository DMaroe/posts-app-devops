# Launch templates and auto scaling groups for the two stateless app tiers.
#
# A deployment works by changing var.image_tag, which changes the launch
# template's user data, which creates a new launch template version. The auto
# scaling groups are pinned to the latest version, so that change triggers a
# rolling instance refresh: instances are replaced a portion at a time while
# the rest keep serving traffic behind the load balancer.

locals {
  ecr_registry = split("/", aws_ecr_repository.frontend.repository_url)[0]
}

resource "aws_launch_template" "frontend" {
  name_prefix   = "posts-app-frontend-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer_key.key_name

  vpc_security_group_ids = [aws_security_group.frontend_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ecr_pull_profile.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data/app_tier.sh.tftpl", {
    compose_file = file("${path.module}/../docker-compose-frontend.yml")
    aws_region   = var.aws_region
    ecr_registry = local.ecr_registry

    # The frontend talks to the backend through the internal load balancer, so
    # it never needs to know a backend instance address.
    env_file = <<-EOT
      FRONTEND_IMAGE=${aws_ecr_repository.frontend.repository_url}:${var.image_tag}
      BACKEND_HOST=${aws_lb.backend.dns_name}
    EOT
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "Frontend Server"
      Tier = "frontend"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "backend" {
  name_prefix   = "posts-app-backend-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.deployer_key.key_name

  vpc_security_group_ids = [aws_security_group.backend_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ecr_pull_profile.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data/app_tier.sh.tftpl", {
    compose_file = file("${path.module}/../docker-compose-backend.yml")
    aws_region   = var.aws_region
    ecr_registry = local.ecr_registry

    env_file = <<-EOT
      BACKEND_IMAGE=${aws_ecr_repository.backend.repository_url}:${var.image_tag}
      DB_HOST=${aws_instance.db_server.private_ip}
      DB_USER=${var.db_user}
      DB_PASSWORD=${var.db_password}
    EOT
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "Backend Server"
      Tier = "backend"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "frontend" {
  name                = "posts-app-frontend-asg"
  min_size            = var.app_instance_count
  max_size            = var.app_instance_count * 2
  desired_capacity    = var.app_instance_count
  vpc_zone_identifier = local.usable_subnet_ids
  target_group_arns   = [aws_lb_target_group.frontend.arn]

  # Health is judged by the load balancer, so an instance that boots but fails
  # to serve traffic gets replaced instead of sitting there broken.
  health_check_type         = "ELB"
  health_check_grace_period = 600

  wait_for_capacity_timeout = "15m"

  launch_template {
    id      = aws_launch_template.frontend.id
    version = aws_launch_template.frontend.latest_version
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }
}

resource "aws_autoscaling_group" "backend" {
  name                = "posts-app-backend-asg"
  min_size            = var.app_instance_count
  max_size            = var.app_instance_count * 2
  desired_capacity    = var.app_instance_count
  vpc_zone_identifier = local.usable_subnet_ids
  target_group_arns   = [aws_lb_target_group.backend.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 600

  wait_for_capacity_timeout = "15m"

  launch_template {
    id      = aws_launch_template.backend.id
    version = aws_launch_template.backend.latest_version
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }
}

output "frontend_asg_name" {
  value = aws_autoscaling_group.frontend.name
}

output "backend_asg_name" {
  value = aws_autoscaling_group.backend.name
}
