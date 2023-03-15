# AWS infrastructure resources

resource "tls_private_key" "global_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_sensitive_file" "ssh_private_key_pem" {
  filename        = "${path.module}/id_rsa"
  content         = tls_private_key.global_key.private_key_pem
  file_permission = "0600"
}

resource "local_file" "ssh_public_key_openssh" {
  filename = "${path.module}/id_rsa.pub"
  content  = tls_private_key.global_key.public_key_openssh
}

# Temporary key pair used for SSH accesss
resource "aws_key_pair" "quickstart_key_pair" {
  key_name_prefix = "${var.prefix}-scoobychat-"
  public_key      = tls_private_key.global_key.public_key_openssh
}

resource "aws_vpc" "scoobychat_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = {
    Name = "${var.prefix}-scoobychat-vpc"
  }
}

resource "aws_internet_gateway" "scoobychat_gateway" {
  vpc_id = aws_vpc.scoobychat_vpc.id

  tags = {
    Name = "${var.prefix}-scoobychat-gateway"
  }
}

resource "aws_subnet" "scoobychat_subnet_b" {
  vpc_id = aws_vpc.scoobychat_vpc.id

  cidr_block        = "10.0.0.0/24"
  availability_zone = var.aws_zone

  tags = {
    Name = "${var.prefix}-scoobychat-subnet"
  }
}

resource "aws_subnet" "scoobychat_subnet_a" {
  vpc_id = aws_vpc.scoobychat_vpc.id

  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "${var.prefix}-scoobychat-subnet"
  }
}

resource "aws_route_table" "scoobychat_route_table" {
  vpc_id = aws_vpc.scoobychat_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.scoobychat_gateway.id
  }

  tags = {
    Name = "${var.prefix}-scoobychat-route-table"
  }
}

resource "aws_route_table_association" "scoobychat_route_table_association_a" {
  subnet_id      = aws_subnet.scoobychat_subnet_a.id
  route_table_id = aws_route_table.scoobychat_route_table.id
}

resource "aws_route_table_association" "scoobychat_route_table_association_b" {
  subnet_id      = aws_subnet.scoobychat_subnet_b.id
  route_table_id = aws_route_table.scoobychat_route_table.id
}

# Security group to allow all traffic
resource "aws_security_group" "scoobychat_sg_allowall" {
  name        = "${var.prefix}-scoobychat-allowall"
  description = "scoobychat quickstart - allow all traffic"
  vpc_id      = aws_vpc.scoobychat_vpc.id

  ingress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Creator = "scoobychat-quickstart"
  }
}

# AWS EC2 instance for creating a single node RKE cluster and installing the scoobychat server
resource "aws_instance" "scoobychat_server" {
  count = 0

  depends_on = [
    aws_route_table_association.scoobychat_route_table_association_a
  ]
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  key_name                    = aws_key_pair.quickstart_key_pair.key_name
  vpc_security_group_ids      = [aws_security_group.scoobychat_sg_allowall.id]
  subnet_id                   = aws_subnet.scoobychat_subnet_a.id
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Prepare the server'",
      "echo 'Wait from snap service is running'",
      "cloud-init status --wait > /dev/null",
      "systemctl status snapd.service --wait  > /dev/null",
      "systemctl status snapd.seeded.service --wait > /dev/null",
      "sudo snap refresh --",
      "echo 'Install Microk8s'",
      "sudo snap install microk8s --classic --channel=1.26 > /dev/null",
      "echo 'Prepare the Microk8s user 1 - '$USER",
      "sudo usermod -a -G microk8s ubuntu > /dev/null",
      "echo 'Prepare the Microk8s user 2'",
      "sudo chown -f -R ubuntu ~/.kube > /dev/null",
      "echo 'Prepare the Microk8s user 3'",
      #"sudo newgrp microk8s > /dev/null",
      "echo 'Wait for the Microk8s is ready'",
      "sudo microk8s status --wait-ready > /dev/null",
      "echo 'Enable adds-on Microk8s'",
      "sudo microk8s enable dns hostpath-storage ingress registry helm3",
      "echo 'Microk8s installation completed!'",
      "echo 'Install infra for scoobychat'",
      "sudo microk8s kubectl config view -o jsonpath='{.users[?(@.name == \"admin\")].user.token}' --raw=true > /tmp/token",
      "sudo cat /tmp/token",
      "echo 'Tudo pronto!'"
    ]

    connection {
      type        = "ssh"
      host        = self.public_ip
      user        = local.node_username
      private_key = tls_private_key.global_key.private_key_pem
    }
  }

  tags = {
    Name    = "${var.prefix}-scoobychat-server"
    Creator = "scoobychat-quickstart"
  }
}

resource "aws_spot_instance_request" "test_worker" {
  count                       = 1
  ami                         = data.aws_ami.ubuntu.id
  spot_price                  = 0.0160
  instance_type               = var.instance_type
  spot_type                   = "one-time"
  #block_duration_minutes = 120
  wait_for_fulfillment        = true
  key_name                    = aws_key_pair.quickstart_key_pair.key_name
  associate_public_ip_address = true

  security_groups = ["${aws_security_group.scoobychat_sg_allowall.id}"]
  subnet_id       = "${aws_subnet.scoobychat_subnet_a.id}"

  root_block_device {
    volume_size = 20
    volume_type = "gp3"

  }
  provisioner "remote-exec" {
    inline = [
      "echo 'Prepare the server'",
      "echo 'Wait from snap service is running'",
      "cloud-init status --wait > /dev/null",
      "systemctl status snapd.service --wait  > /dev/null",
      "systemctl status snapd.seeded.service --wait > /dev/null",
      "sudo snap refresh --",
      "echo 'Install Microk8s'",
      "sudo snap install microk8s --classic --channel=1.26 > /dev/null",
      "echo 'Prepare the Microk8s user 1 - '$USER",
      "sudo usermod -a -G microk8s ubuntu > /dev/null",
      "echo 'Prepare the Microk8s user 2'",
      "sudo chown -f -R ubuntu ~/.kube > /dev/null",
      "echo 'Prepare the Microk8s user 3'",
      #"sudo newgrp microk8s > /dev/null",
      "echo 'Wait for the Microk8s is ready'",
      "sudo microk8s status --wait-ready > /dev/null",
      "echo 'Enable adds-on Microk8s'",
      "sudo microk8s enable dns hostpath-storage ingress registry helm3",
      "echo 'Microk8s installation completed!'",
      "echo 'Install infra for scoobychat'",
      "sudo microk8s kubectl config view -o jsonpath='{.users[?(@.name == \"admin\")].user.token}' --raw=true > /tmp/token",
      "sudo cat /tmp/token",
      "echo 'Tudo pronto!'"
    ]

    connection {
      type        = "ssh"
      host        = self.public_ip
      user        = local.node_username
      private_key = tls_private_key.global_key.private_key_pem
    }
  }

}


resource "aws_lb" "scoobychat_lb" {
  name               = "scoobychat-lb"
  internal           = false
  load_balancer_type = "application"


  subnets         = [aws_subnet.scoobychat_subnet_a.id, aws_subnet.scoobychat_subnet_b.id]
  security_groups = [aws_security_group.scoobychat_sg_allowall.id]


  tags = {
    Name = "scoobychat-lb"
  }
}

resource "aws_lb_target_group" "scoobychat_http" {
  name     = "scoobychat-http"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.scoobychat_vpc.id


  health_check {
    interval            = 10
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "scoobychat_https" {
  name     = "scoobychat-https"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.scoobychat_vpc.id


  health_check {
    interval            = 10
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTPS"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "scoobychat_kubectl" {
  name     = "scoobychat-kubectl"
  port     = 16443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.scoobychat_vpc.id


  health_check {
    interval            = 10
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTPS"
    matcher             = "401"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "scoobychat_registry" {
  name     = "scoobychat-registry"
  port     = 32000
  protocol = "HTTP"
  vpc_id   = aws_vpc.scoobychat_vpc.id


  health_check {
    interval            = 10
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.scoobychat_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.scoobychat_http.arn
  }
}


resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.scoobychat_lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-east-1:213745435605:certificate/72322bd1-3706-415d-9bee-e12d6683f098"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.scoobychat_https.arn
  }
}

resource "aws_lb_listener" "kubectl_listener" {
  load_balancer_arn = aws_lb.scoobychat_lb.arn
  port              = 16443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-east-1:213745435605:certificate/72322bd1-3706-415d-9bee-e12d6683f098"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.scoobychat_kubectl.arn
  }
}

resource "aws_lb_listener" "registry_listener" {
  load_balancer_arn = aws_lb.scoobychat_lb.arn
  port              = 32000
  protocol          = "HTTP"
  #ssl_policy        = "ELBSecurityPolicy-2016-08"
  #certificate_arn   = "arn:aws:acm:us-east-1:213745435605:certificate/72322bd1-3706-415d-9bee-e12d6683f098"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.scoobychat_registry.arn
  }
}

resource "aws_lb_target_group_attachment" "scoobychat_server_attachment_http" {
  target_group_arn = aws_lb_target_group.scoobychat_http.arn
  #target_id        = aws_instance.scoobychat_server.id
  target_id        = aws_spot_instance_request.test_worker[0].spot_instance_id
  port             = 80
}
resource "aws_lb_target_group_attachment" "scoobychat_server_attachment_https" {
  target_group_arn = aws_lb_target_group.scoobychat_https.arn
  #target_id        = aws_instance.scoobychat_server.id
  target_id        = aws_spot_instance_request.test_worker[0].spot_instance_id
  port             = 443
}
resource "aws_lb_target_group_attachment" "scoobychat_server_attachment_kubectl" {
  target_group_arn = aws_lb_target_group.scoobychat_kubectl.arn
  #target_id        = aws_instance.scoobychat_server.id
  target_id        = aws_spot_instance_request.test_worker[0].spot_instance_id
  port             = 16443
}
resource "aws_lb_target_group_attachment" "scoobychat_server_attachment_registry" {
  target_group_arn = aws_lb_target_group.scoobychat_registry.arn
  #target_id        = aws_instance.scoobychat_server.id
  target_id        = aws_spot_instance_request.test_worker[0].spot_instance_id
  port             = 32000
}

resource "aws_route53_record" "scoobychat_record" {
  zone_id = "Z034390712R6LN84KE3W7" # ID da sua Hosted Zone
  name    = "scoobychat" # Nome do registro DNS
  type    = "A" # Tipo de registro (neste caso, um registro A)

  alias {
    name                   = aws_lb.scoobychat_lb.dns_name
    zone_id                = aws_lb.scoobychat_lb.zone_id
    evaluate_target_health = true
  }
}
