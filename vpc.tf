resource "aws_vpc" "myapp" {
     cidr_block = "${var.vpc_cidr}"
}

resource "aws_subnet" "us-west-2a-public" {
    vpc_id = "${aws_vpc.myapp.id}"
	map_public_ip_on_launch = "true"
    cidr_block = "${var.public_subnet_cidr}"
    availability_zone = "us-west-2a"

    tags {
        Name = "Public 1A Subnet"
    }
}

resource "aws_subnet" "us-west-2b-public" {
    vpc_id = "${aws_vpc.myapp.id}"
	map_public_ip_on_launch = "true"
    cidr_block = "${var.public_b_subnet_cidr}"
    availability_zone = "us-west-2b"

    tags {
        Name = "Public 1B Subnet"
    }
}

resource "aws_internet_gateway" "gw" {
    vpc_id = "${aws_vpc.myapp.id}"

    tags {
        Name = "myapp gw"
    }
}

resource "aws_route_table" "us-west-2a-public" {
    vpc_id = "${aws_vpc.myapp.id}"

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.gw.id}"
    }

    tags {
        Name = "Public-Subnet-myapp"
    }
}

resource "aws_route_table_association" "us-west-2a-public" {
    subnet_id = "${aws_subnet.us-west-2a-public.id}"

    route_table_id = "${aws_route_table.us-west-2a-public.id}"
}

resource "aws_route_table_association" "us-west-2b-public" {
    subnet_id = "${aws_subnet.us-west-2b-public.id}"

    route_table_id = "${aws_route_table.us-west-2a-public.id}"
}


resource "aws_security_group" "sg" {
    name = "vpc_sg"
    description = "Allow traffic to pass to the public subnet from the internet"

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = -1
        cidr_blocks = ["0.0.0.0/0"]
    }
    vpc_id = "${aws_vpc.myapp.id}"

    tags {
        Name = "myapp-sg"
    }
}

resource "aws_security_group" "myapp_mysql_rds" {
  name = "web server"
  description = "Allow access to MySQL RDS"
  vpc_id = "${aws_vpc.myapp.id}"

  ingress {
      from_port = 3306
      to_port = 3306
      protocol = "tcp"
      cidr_blocks = ["${var.vpc_cidr}"]
  }

  egress {
      from_port = 1024
      to_port = 65535
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web01" {
  ami           = "${lookup(var.amis, var.aws_region)}"
  instance_type = "t2.micro"
  key_name = "${var.aws_key_name}"
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
  subnet_id = "${aws_subnet.us-west-2a-public.id}"
  associate_public_ip_address = true
  source_dest_check = false

  tags {
      Name = "terraform-instance-app-1 "
  }
}

resource "aws_instance" "web02" {
  ami           = "${lookup(var.amis, var.aws_region)}"
  instance_type = "t2.micro"
  key_name = "${var.aws_key_name}"
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
  subnet_id = "${aws_subnet.us-west-2b-public.id}"
  associate_public_ip_address = true
  source_dest_check = false

  tags {
      Name = "terraform-instance-app-2 "
  }
}

#Define an ELB to attaches to the two public subnets, add both web EC2 instances

resource "aws_elb" "web-elb" {
  name = "web-elb"
  
  subnets         = ["${aws_subnet.us-west-2a-public.id}","${aws_subnet.us-west-2b-public.id}"]
  security_groups = ["${aws_security_group.sg.id}"]

  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }


  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    target = "HTTP:80/"
    interval = 30
  }

  instances = ["${aws_instance.web01.id}","${aws_instance.web02.id}"]


  cross_zone_load_balancing = true
  idle_timeout = 400
  connection_draining = true
  connection_draining_timeout = 400

  tags {
    Name = "Web ELB"
  }
}

#Create the DB Subnet Group.

resource "aws_db_subnet_group" "myapp-db" {
    name = "main"
    description = "Our main group of subnets"
    subnet_ids = ["${aws_subnet.us-west-2a-public.id}", "${aws_subnet.us-west-2b-public.id}"]
    tags {
        Name = "MyApp DB subnet group"
    }
}

#Create the RDS Instance

resource "aws_db_instance" "web-rds-01" {
    identifier = "myappdb-rds"
    allocated_storage = 10
    engine = "mysql"
    engine_version = "5.6.27"
    instance_class = "db.t1.micro"
    name = "myappdb"
    username = "kuldeep"
    password = "kuldeep"
    vpc_security_group_ids = ["${aws_security_group.myapp_mysql_rds.id}"]
    db_subnet_group_name = "${aws_db_subnet_group.myapp-db.id}"
    parameter_group_name = "default.mysql5.6"
}
