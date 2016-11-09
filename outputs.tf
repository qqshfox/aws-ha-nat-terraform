output "vpc" {
  value = "${aws_vpc.vpc.id}"
}

output "availability_zones" {
  value = ["${aws_subnet.public.*.availability_zone}"]
}

output "public_subnets" {
  value = ["${aws_subnet.public.*.id}"]
}

output "private_route_tables" {
  value = ["${aws_route_table.private.*.id}"]
}

output "private_subnets" {
  value = ["${aws_subnet.private.*.id}"]
}

output "instances" {
  value = ["${aws_instance.nat.*.id}"]
}

output "ips" {
  value = ["${aws_eip.eip.*.public_ip}"]
}
