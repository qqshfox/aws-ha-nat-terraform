provider "aws" {
  region = "${var.aws_region}"
}

resource "aws_vpc" "vpc" {
  cidr_block = "${var.vpc_cidr_block}"
  enable_dns_hostnames = true

  tags {
    Name = "${var.vpc_name}"
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.vpc.id}"
}

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.vpc.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.default.id}"
  }

  tags {
    Name = "Public"
  }
}

resource "aws_main_route_table_association" "public" {
  vpc_id = "${aws_vpc.vpc.id}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_subnet" "public" {
  count = "${length(var.vpc_azs)}"

  vpc_id = "${aws_vpc.vpc.id}"
  availability_zone = "${var.aws_region}${var.vpc_azs[count.index]}"
  cidr_block = "${cidrsubnet(var.vpc_cidr_block, var.aws_subnet_bits, count.index)}"
  map_public_ip_on_launch = true

  tags {
    Name = "Public subnet ${var.vpc_azs[count.index]}"
  }
}

resource "aws_route_table" "private" {
  count = "${length(var.vpc_azs)}"

  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name = "Private ${var.vpc_azs[count.index]}"
  }
}

resource "aws_subnet" "private" {
  count = "${length(var.vpc_azs)}"

  vpc_id = "${aws_vpc.vpc.id}"
  availability_zone = "${var.aws_region}${var.vpc_azs[count.index]}"
  cidr_block = "${cidrsubnet(var.vpc_cidr_block, var.aws_subnet_bits, length(var.vpc_azs) + count.index)}"
  map_public_ip_on_launch = false

  tags {
    Name = "Private subnet ${var.vpc_azs[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count = "${length(var.vpc_azs)}"

  subnet_id = "${element(aws_subnet.private.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"
}

resource "aws_security_group" "ssh" {
  name = "ssh"
  description = "SSH"
  vpc_id = "${aws_vpc.vpc.id}"

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["${var.aws_security_group_ssh_cidr_blocks}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_policy" "policy" {
  name = "nat-monitor-policy-${aws_vpc.vpc.id}"
  path = "/"
  description = "NAT Monitor Policy"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ec2:DescribeInstances",
                "ec2:CreateRoute",
                "ec2:ReplaceRoute",
                "ec2:StartInstances",
                "ec2:StopInstances"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_role" "role" {
  name = "nat-monitor-role-${aws_vpc.vpc.id}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com${replace(replace(var.aws_region, "/^cn-.*/", ".cn"), "/^[^\.].*$/", "")}"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "attachment" {
  name = "nat-monitor-policy-attachment-${aws_vpc.vpc.id}"
  roles = ["${aws_iam_role.role.name}"]
  policy_arn = "${aws_iam_policy.policy.arn}"
}

resource "aws_iam_instance_profile" "profile" {
  name = "nat-monitor-instance-profile-${aws_vpc.vpc.id}"
  roles = ["${aws_iam_role.role.name}"]
}

resource "aws_instance" "nat" {
  count = "${length(var.vpc_azs)}"

  ami = "${var.ec2_ami}"
  instance_type = "${var.ec2_instance_type}"
  availability_zone = "${var.aws_region}${var.vpc_azs[count.index]}"
  subnet_id = "${element(aws_subnet.public.*.id, count.index)}"
  private_ip = "${cidrhost(element(aws_subnet.public.*.cidr_block, count.index), 4)}"
  source_dest_check = false
  key_name = "${var.ec2_key_name}"
  monitoring = true
  iam_instance_profile = "${aws_iam_instance_profile.profile.name}"
  disable_api_termination = "${var.ec2_termination_protection}"
  vpc_security_group_ids = ["${aws_vpc.vpc.default_security_group_id}", "${aws_security_group.ssh.id}"]

  tags {
    Name = "${aws_vpc.vpc.tags.Name} NAT Node #${count.index + 1}"
  }
}

resource "aws_eip" "eip" {
  count = "${length(var.vpc_azs)}"

  instance = "${element(aws_instance.nat.*.id, count.index)}"
}

resource "aws_route" "nat" {
  count = "${length(var.vpc_azs)}"

  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"
  destination_cidr_block = "0.0.0.0/0"
  instance_id = "${element(aws_instance.nat.*.id, count.index)}"
}

resource "null_resource" "generate-nat-monitor-sh" {
  provisioner "local-exec" {
    command = "mkdir -p tmp && cp files/nat-monitor.sh tmp/ && for file in files/patches/*.patch; do patch tmp/nat-monitor.sh < \"$file\"; done"
  }
}

data "template_file" "nat-monitor-default" {
  count = "${length(var.vpc_azs)}"

  template = "${file("${path.module}/files/nat-monitor.default.template")}"

  vars {
    NAT_IDS = "${replace(join(" ", aws_instance.nat.*.id), "/\\s*${element(aws_instance.nat.*.id, count.index)}\\s*/", "")}"
    NAT_RT_IDS = "${replace(join(" ", aws_route_table.private.*.id), "/\\s*${element(aws_route_table.private.*.id, count.index)}\\s*/", "")}"
    My_RT_ID = "${element(aws_route_table.private.*.id, count.index)}"
    EC2_REGION = "${var.aws_region}"

    Num_Pings="${var.nat_monitor_num_pings}"
    Ping_Timeout="${var.nat_monitor_ping_timeout}"
    Wait_Between_Pings="${var.nat_monitor_wait_between_pings}"
    Wait_for_Instance_Stop="${var.nat_monitor_wait_for_instance_stop}"
    Wait_for_Instance_Start="${var.nat_monitor_wait_for_instance_start}"
  }
}

resource "null_resource" "provision" {
  count = "${length(var.vpc_azs)}"

  provisioner "file" {
    source = "tmp/nat-monitor.sh"
    destination = "/tmp/nat-monitor.sh"
  }

  provisioner "file" {
    source = "files/nat-monitor.init"
    destination = "/tmp/nat-monitor.init"
  }

  provisioner "file" {
    content = "${element(data.template_file.nat-monitor-default.*.rendered, count.index)}"
    destination = "/tmp/nat-monitor.default"
  }

  provisioner "file" {
    source = "files/nat-monitor.log-rotate"
    destination = "/tmp/nat-monitor.log-rotate"
  }

  provisioner "remote-exec" {
    inline = [
<<TFEOF
sudo sh - <<SUDOEOF
set -e

cp /tmp/nat-monitor.sh /usr/local/bin/
cp /tmp/nat-monitor.init /etc/init.d/nat-monitor
[ -d /etc/sysconfig ] && cp /tmp/nat-monitor.default /etc/sysconfig/nat-monitor
[ -d /etc/default ] && cp /tmp/nat-monitor.default /etc/default/nat-monitor
cp /tmp/nat-monitor.log-rotate /etc/logrotate.d/nat-monitor

chmod +x /usr/local/bin/nat-monitor.sh /etc/init.d/nat-monitor

chkconfig nat-monitor on
service nat-monitor restart

rm -rf /tmp/nat-monitor.*
SUDOEOF
TFEOF
    ]
  }

  connection {
    user = "ec2-user"
    host = "${element(aws_eip.eip.*.public_ip, count.index)}"
  }

  depends_on = ["null_resource.generate-nat-monitor-sh", "aws_instance.nat"]
}
