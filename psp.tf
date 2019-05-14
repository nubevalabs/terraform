variable "Namespace" {
  type = "string"
  default = "nubeva.internal"
  description = "The 'domainname' portion of the PSP service"
}

variable "Alias" {
  type = "string"
  default = "psp"
  description = "The 'hostname' portion of the PSP service"
}

variable "KeyName" {
  type = "string"
  description = "Name of an existing EC2 KeyPair to enable SSH access to the ECS instances."
}

variable "VPC" {
  type = "string"
  description = "Select the VPC to install into."
}

variable "PrivateSubnets" {
  type = "list"
  description = "Select at least one subnet in your selected VPC, it should have internet access provisioned via a NAT gateway. For a high availability configuration select one more subnet in another availability zone."
}

variable "MaxSize" {
  type = "string"
  default = "5"
  description = "Maximum number of instances that can be launched in your ECS cluster."
}
variable "NetworkTooLowThreshold" {
  type = "string"
  default = "37500000000"
  description = "Threshold at which cluster scales down (Bytes received per instance over a minute)"
}
variable "NetworkTooHighThreshold" {
  type = "string"
  default = "60000000000"
  description = "Threshold at which cluster scales up (Bytes received per instance over a minute)"
}

variable "InstanceType" {
  type = "string"
  default = "r4.large"
}

variable "IsDevelopmentVersion" {
  type = "string"
  default = "false"
}

variable "NuToken" {
  type = "string"
  description = "Nubeva Token for registering agent"
}

  variable "PSPID" {
  type = "string"
  description = "Nubeva PSP Identifier"
}

variable "ProjectID" {
  description = "Nubeva Project Identifier" # Used only to generate return URL
  type = "string"
  default = ""
}

variable "BackendURL" {
  type = "string"
  description = "Nubeva Prisms backend API URL"
  default = "https://i.nuos.io/api/1.1/wf"
}
variable "region" {
  type = "string"
  description = "AWS Region to deploy to"
}

provider "aws" {
  region     = "${var.region}"
}


locals {
  # Note: terraform doesn't have a stack name.  Using the following instead, since
  # the frontend needs to be unique in an AWS account anyway
  psp_name = "${var.Alias}-${replace(var.Namespace,".","-")}"
  callback_url = "https://i.nuos.io${var.IsDevelopmentVersion == "true" ? "version-test" : ""}/topo"
}

data "aws_caller_identity" "current" {}

data "aws_ami" "latest_ecs" {
  most_recent = true
  owners = ["591542846629"] # AWS

  filter {
    name   = "name"
    values = ["*amzn2-ami-ecs*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "template_file" "user_data" {
  template = "${file("${path.module}/templates/user_data.sh")}"
  vars {
    cluster_name      = "${aws_ecs_cluster.PSPCluster.name}"
    cloudwatch_log_group = "${aws_cloudwatch_log_group.CloudwatchLogsGroup.name}"
  }
}

resource "aws_iam_role" "NubevaIAMRole" {
  name = "NubevaIAMRole-${local.psp_name}"
  assume_role_policy = <<DEFINITION
{
  "Statement": [
    {
      "Action": [
        "sts:AssumeRole"
      ],
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ec2.amazonaws.com"
        ]
      }
    }
  ]
}
DEFINITION
  path = "/"
}

resource "aws_iam_role_policy" "NubevaIAMPolicy" {
  name = "NubevaIAMPolicy-${local.psp_name}"
  role = "${aws_iam_role.NubevaIAMRole.id}"

  policy = <<EOF
{
  "Statement": [
    {
      "Action": [
        "ecs:DeregisterContainerInstance",
        "ecs:DiscoverPollEndpoint",
        "ecs:Poll",
        "ecs:RegisterContainerInstance",
        "ecs:StartTelemetrySession",
        "ecs:Submit*",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "ecs:UpdateService"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "ecs:DeleteCluster"
      ],
      "Resource": "${aws_ecs_cluster.PSPCluster.arn}",
      "Effect": "Allow"
    },
    {
      "Action": [
        "ecs:DeleteAttributes"
      ],
      "Resource": "*",
      "Effect": "Allow",
      "Condition": {
        "StringEquals": {
          "ecs:cluster": "${aws_ecs_cluster.PSPCluster.arn}"
        }
      }
    },
    {
      "Action": [
        "sdb:ListDomains"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "sdb:*"
      ],
      "Resource": "arn:aws:sdb:*:${data.aws_caller_identity.current.account_id}:domain/${var.PSPID}",
      "Effect": "Allow"
    },
    {
      "Action": [
        "iam:DeleteInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile"
      ],
      "Resource": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*NubevaInstanceProfile*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "iam:DeleteRole",
        "iam:DeleteRolePolicy"
      ],
      "Resource": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*NubevaIAMRole*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "servicediscovery:DeleteNamespace",
        "servicediscovery:DeleteService",
        "servicediscovery:GetOperation",
        "autoscaling:DeletePolicy",
        "cloudwatch:DeleteAlarms",
        "ec2:DescribeSecurityGroups",
        "ecs:DeleteService",
        "ecs:DescribeServices",
        "ecs:DeregisterTaskDefinition",
        "ecs:DeleteAttributes",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeScalingActivities",
        "route53:DeleteHostedZone"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:DeleteAutoScalingGroup"
      ],
      "Resource": "${aws_autoscaling_group.PSPAutoScalingGroup.arn}",
      "Effect": "Allow"
    },
    {
      "Action": [
        "logs:DeleteLogGroup"
      ],
      "Resource": "${aws_cloudwatch_log_group.CloudwatchLogsGroup.arn}",
      "Effect": "Allow"
    }
  ]
}
  EOF
}

resource "aws_ecs_cluster" "PSPCluster" {
  name = "nubevapsp-${local.psp_name}"
}


########
# Security Groups
########


resource "aws_security_group" "PSPSecurityGroup" {
  # The Security Group placed on the PSP containers themselves
  depends_on = ["aws_iam_role.NubevaIAMRole"] # ensure iam role is deleted last
  description = "PSP Security Group"
  vpc_id = "${var.VPC}"
  ingress { # allow vxlan
    from_port = 4789
    protocol = "udp"
    to_port = 4789
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "InstanceSecurityGroup" {
  #The security Group placed on the cluster instances
  depends_on = ["aws_iam_role.NubevaIAMRole"] # ensure iam role is deleted last
  description = "ECS Instance Security Group"
  vpc_id = "${var.VPC}"
  ingress {
    from_port = 22
    protocol = "tcp"
    to_port = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}


########
# Data Path
########

resource "aws_ecs_task_definition" "DataPathTask" {
  depends_on = ["aws_iam_role.NubevaIAMRole"] # ensure iam role is deleted last
  network_mode = "awsvpc"
  volume {
    name = "ProcMnt"
    host_path = "/proc/"
  }
  volume {
    name = "DockerSock"
    host_path = "/var/run/docker.sock"
  }
  family = "psp-datapath"
  container_definitions = <<DEFINITION
[
  {
  "MemoryReservation": 300,
  "MountPoints": [
    {
      "SourceVolume": "ProcMnt",
      "ContainerPath": "/host/proc/"
    },
    {
      "SourceVolume": "DockerSock",
      "ContainerPath": "/var/run/docker.sock"
    }
  ],
  "Name": "psp-data",
  "Image": "${var.IsDevelopmentVersion == "false" ? "nubeva/psp" : "nubeva/psp:master"}",
  "Privileged": true,
  "Environment": [
    {
      "Name": "NUBEVA_AWS_REGION",
      "Value": "${var.region}"
    }
  ],
  "Command": [
    "-vxlan-port",
    "4789",
    "--accept-eula",
    "--psp-id",
    "${var.PSPID}",
    "--debug",
    "${var.IsDevelopmentVersion == "true" ? "all" : "none"}"
  ],
  "LogConfiguration": {
    "LogDriver": "awslogs",
    "Options": {
      "awslogs-region": "${var.region}",
      "awslogs-stream-prefix": "pspdata",
      "awslogs-group": "${aws_cloudwatch_log_group.CloudwatchLogsGroup.name}"
    }
  },
  "Essential": true
}
]
DEFINITION
}

resource "aws_cloudwatch_log_group" "CloudwatchLogsGroup" {
  depends_on = ["aws_iam_role.NubevaIAMRole"] # ensure iam role is deleted last
  retention_in_days = 14
  name = "ECSLogGroup-${local.psp_name}"

}

resource "aws_ecs_service" "DataPathService" {
  depends_on = ["aws_iam_role.NubevaIAMRole", "aws_launch_configuration.ContainerInstances"] # ensure iam role is deleted last
  name = "DataPathService-${local.psp_name}"
  task_definition = "${aws_ecs_task_definition.DataPathTask.arn}"
  cluster = "${aws_ecs_cluster.PSPCluster.id}"
  scheduling_strategy = "DAEMON"
  network_configuration {
    subnets = "${var.PrivateSubnets}"
    security_groups = ["${aws_security_group.PSPSecurityGroup.id}"]
  }
  service_registries {
    registry_arn = "${aws_service_discovery_service.DataPathServiceDiscovery.arn}"
  }
}

resource "aws_service_discovery_service" "DataPathServiceDiscovery" {
  depends_on = ["aws_iam_role.NubevaIAMRole"] # ensure iam role is deleted last
  name = "${var.Alias}"
  "dns_config" {
    namespace_id = "${aws_service_discovery_private_dns_namespace.ServiceDiscoveryPSPNamespace.id}"
    "dns_records" {
      ttl = 30
      type = "A"
    }
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_private_dns_namespace" "ServiceDiscoveryPSPNamespace" {
  depends_on = ["aws_iam_role.NubevaIAMRole"] # ensure iam role is deleted last
  description = "Namespace for PSP service discovery"
  vpc = "${var.VPC}"
  name = "${var.Namespace}"
}

resource "aws_autoscaling_group" "PSPAutoScalingGroup" {
  depends_on = ["aws_iam_role.NubevaIAMRole"] # ensure iam role is deleted last
  tag {
    key = "Name"
    value = "PSPASG"
    propagate_at_launch = true
  }
  vpc_zone_identifier = "${var.PrivateSubnets}"
  launch_configuration = "${aws_launch_configuration.ContainerInstances.id}"
  min_size = 1
  max_size = "${var.MaxSize}"
  desired_capacity = 1
}


resource "aws_launch_configuration" "ContainerInstances" {
  name_prefix = "${local.psp_name}-"
  image_id = "${data.aws_ami.latest_ecs.id}"
  instance_type = "${var.InstanceType}"
  security_groups = ["${aws_security_group.InstanceSecurityGroup.id}"]
  iam_instance_profile = "${aws_iam_instance_profile.NubevaInstanceProfile.arn}"
  key_name = "${var.KeyName}"
  user_data = "${data.template_file.user_data.rendered}"
  # aws_launch_configuration can not be modified.
  # Therefore we use create_before_destroy so that a new modified aws_launch_configuration can be created
  # before the old one get's destroyed. That's why we use name_prefix instead of name.
  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_iam_instance_profile" "NubevaInstanceProfile" {
  path = "/"
  role = "${aws_iam_role.NubevaIAMRole.name}"
}

##############
# Control Path
##############

# The task definition is what defines how to run the container

# Note: No cleanup ref since not expected to clean ourselves up with terraform
resource "aws_ecs_task_definition" "ControlPathTask" {
  depends_on = ["aws_iam_role.NubevaIAMRole", "aws_ecs_service.DataPathService"]
  family = "psp-datapath"
  container_definitions = <<DEFINITION
  [
  {
    "MemoryReservation": 300,
    "LogConfiguration": {
      "LogDriver": "awslogs",
      "Options": {
        "awslogs-region": "${var.region}",
        "awslogs-stream-prefix": "psp-control",
        "awslogs-group": "${aws_cloudwatch_log_group.CloudwatchLogsGroup.name}"
      }
    },
    "Command": [
      "--accept-eula",
      "--baseurl",
      "${var.BackendURL}",
      "--nutoken",
      "${var.NuToken}",
      "--psp-id",
      "${var.PSPID}",
      "--frontend",
      "${var.Alias}.${var.Namespace}:4789"
    ],
    "Name": "psp-control",
  "Image": "${var.IsDevelopmentVersion == "false" ? "nubeva/psp-control" : "nubeva/psp-control:master"}",
    "Essential": true,
    "Environment": [
      {
        "Name": "NUBEVA_AWS_REGION",
        "Value": "${var.region}"
      }
    ]
  }
]
DEFINITION
}

resource "aws_ecs_service" "ControlPathService" {
  depends_on = ["aws_iam_role.NubevaIAMRole", "aws_launch_configuration.ContainerInstances"] # ensure iam role is deleted last
  name = "ControlPathService-${local.psp_name}"
  task_definition = "${aws_ecs_task_definition.ControlPathTask.arn}"
  desired_count = 2
  cluster = "${aws_ecs_cluster.PSPCluster.arn}"
}


########
# Autoscaling
########

resource "aws_autoscaling_policy" "InstanceScaleUp" {
  depends_on = ["aws_iam_role.NubevaIAMRole"] # ensure iam role is deleted last
  autoscaling_group_name = "${aws_autoscaling_group.PSPAutoScalingGroup.name}"
  name = "InstanceScaleUp-${local.psp_name}"
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  scaling_adjustment = 1
}

resource "aws_autoscaling_policy" "InstanceScaleDown" {
  depends_on = ["aws_iam_role.NubevaIAMRole"] # ensure iam role is deleted last
  autoscaling_group_name = "${aws_autoscaling_group.PSPAutoScalingGroup.name}"
  name = "InstanceScaleDown-${local.psp_name}"
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  scaling_adjustment = -1
}

resource "aws_cloudwatch_metric_alarm" "NetworkTooHighAlarm" {
  alarm_name = "ClusterAverageNetworkInTooHigh-${local.psp_name}"
  alarm_description = "Average NetworkIn"
  namespace = "AWS/EC2"
  metric_name = "NetworkIn"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 1
  period = 60
  statistic = "Average"
  alarm_actions = ["${aws_autoscaling_policy.InstanceScaleUp.arn}"]
  threshold = "${var.NetworkTooHighThreshold}"
  dimensions {
    AutoScalingGroupName = "${aws_autoscaling_group.PSPAutoScalingGroup.name}"
  }
}

resource "aws_cloudwatch_metric_alarm" "NetworkTooLowAlarm" {
  alarm_name = "ClusterAverageNetworkInTooLow-${local.psp_name}"
  alarm_description = "Average NetworkIn"
  namespace = "AWS/EC2"
  metric_name = "NetworkIn"
  comparison_operator = "LessThanThreshold"
  evaluation_periods = 1
  period = 60
  statistic = "Average"
  alarm_actions = ["${aws_autoscaling_policy.InstanceScaleDown.arn}"]
  threshold = "${var.NetworkTooLowThreshold}"
  dimensions {
    AutoScalingGroupName = "${aws_autoscaling_group.PSPAutoScalingGroup.name}"
  }
}

output "endpoint" {
  value = "${var.Alias}.${var.Namespace}:4789"
}

output "ReturnToUI" {
  value = "${local.callback_url}?ProjectID=${var.ProjectID}"
}