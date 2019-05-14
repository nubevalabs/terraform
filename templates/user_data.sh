#!/bin/bash
# adapted from https://github.com/arminc/terraform-ecs/tree/master/modules/ecs_instances/templates

#Using script from http://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_cloudwatch_logs.html
# Install awslogs and the jq JSON parser
yum install -y awslogs jq aws-cli

# ECS config
{
  echo "ECS_CLUSTER=${cluster_name}"
  echo 'ECS_AVAILABLE_LOGGING_DRIVERS=["json-file","awslogs"]'
} >> /etc/ecs/ecs.config

# Inject the CloudWatch Logs configuration file contents
cat > /etc/awslogs/awslogs.conf <<- EOF
[general]
state_file = /var/lib/awslogs/agent-state        
 
[/var/log/dmesg]
file = /var/log/dmesg
log_group_name = ${cloudwatch_log_group}
log_stream_name = ${cluster_name}/dmesg/{container_instance_id}

[/var/log/messages]
file = /var/log/messages
log_group_name = ${cloudwatch_log_group}
log_stream_name = ${cluster_name}/messages/{container_instance_id}
datetime_format = %b %d %H:%M:%S

[/var/log/docker]
file = /var/log/docker
log_group_name = ${cloudwatch_log_group}
log_stream_name = ${cluster_name}/docker/{container_instance_id}
datetime_format = %Y-%m-%dT%H:%M:%S.%f

[/var/log/ecs/ecs-init.log]
file = /var/log/ecs/ecs-init.log.*
log_group_name = ${cloudwatch_log_group}
log_stream_name = ${cluster_name}/ecs-init/{container_instance_id}
datetime_format = %Y-%m-%dT%H:%M:%SZ

[/var/log/ecs/ecs-agent.log]
file = /var/log/ecs/ecs-agent.log.*
log_group_name = ${cloudwatch_log_group}
log_stream_name = ${cluster_name}/ecs-agent/{container_instance_id}
datetime_format = %Y-%m-%dT%H:%M:%SZ

[/var/log/ecs/audit.log]
file = /var/log/ecs/audit.log.*
log_group_name = ${cloudwatch_log_group}
log_stream_name = ${cluster_name}/ecs-audit/{container_instance_id}
datetime_format = %Y-%m-%dT%H:%M:%SZ

EOF

# Set the region to send CloudWatch Logs data to (the region where the container instance is located)
region=$(curl 169.254.169.254/latest/meta-data/placement/availability-zone | sed s'/.$//')
sed -i -e "s/region = us-east-1/region = $region/g" /etc/awslogs/awscli.conf

# Set the ip address of the node 
container_instance_id=$(curl 169.254.169.254/latest/meta-data/local-ipv4)
sed -i -e "s/{container_instance_id}/$container_instance_id/g" /etc/awslogs/awslogs.conf

# start the awslogs service and enable it to start whenever the system reboots.
systemctl start awslogsd
systemctl enable awslogsd.service

# may be necessary - but most likely the health check issue
# amazon-linux-extras disable docker && amazon-linux-extras install -y ecs && systemctl enable --now --no-block ecs
sed -i '/After=cloud-final.service/d' /usr/lib/systemd/system/ecs.service
systemctl daemon-reload

#Get ECS instance info, althoug not used in this user_data it self this allows you to use
#az(availability zone) and region
until $(curl --output /dev/null --silent --head --fail http://localhost:51678/v1/metadata); do
  printf '.'
  sleep 5
done
instance_arn=$(curl -s http://localhost:51678/v1/metadata | jq -r '. | .ContainerInstanceArn' | awk -F/ '{print $NF}' )
az=$(curl -s http://instance-data/latest/meta-data/placement/availability-zone)
region=$${az:0:$${#az} - 1}

echo "Done"
