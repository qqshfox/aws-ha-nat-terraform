variable "aws_region" {
  default = ""
}

variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}

variable "vpc_name" {
  default = "VPC Created by Terraform"
}

variable "vpc_azs" {
  default = ["a", "b"]
}

variable "aws_subnet_bits" {
  default = 8
}

variable "aws_security_group_ssh_cidr_blocks" {
  default = ["0.0.0.0/0"]
}

variable "ec2_ami" {
  default = "ami-b23fad8b"
}

variable "ec2_instance_type" {
  default = "t2.micro"
}

variable "ec2_key_name" {
  default = ""
}

variable "ec2_termination_protection" {
  default = true
}

variable "nat_monitor_num_pings" {
  default = 3
}

variable "nat_monitor_ping_timeout" {
  default = 1
}

variable "nat_monitor_wait_between_pings" {
  default = 2
}

variable "nat_monitor_wait_for_instance_stop" {
  default = 60
}

variable "nat_monitor_wait_for_instance_start" {
  default = 300
}
