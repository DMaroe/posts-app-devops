# IAM role + instance profile so EC2 instances can pull images from ECR
# without needing AWS credentials baked into Ansible/user-data.

resource "aws_iam_role" "ec2_ecr_pull_role" {
  name = "posts-app-ec2-ecr-pull-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.ec2_ecr_pull_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ec2_ecr_pull_profile" {
  name = "posts-app-ec2-ecr-pull-profile"
  role = aws_iam_role.ec2_ecr_pull_role.name
}
