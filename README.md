PSP Deployment Using Terraform

1.	Setup source instance and tool instance in the Nubeva SaaS GUI.

2.	Download and decompress the terraform.zip file in this repo

3.	Update the variables in the terraform.tfvars file which is included in the zipfile.

region, KeyName, VPC, PrivateSubnets, NuToken, and PSPID are the minimum number of variables that need to be specified—the remainder of this document will reference variables.

4.	run the following commands:
terraform init && terraform apply
