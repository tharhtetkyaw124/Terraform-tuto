
#Dont hard code credentials directly in the configuration file
#Provider needs to be installed in the machine with "terraform init" command in the terminal

#We need to use the terraform command "terraform init" 
#We'll use "terraform apply" to create and make changes
provider "aws" {
  #set as AWS Global user, using aws cli
  region = "us-east-2"
}

#declare variable, there is three ways to do it.
# 1)if we dont define a value for the variable, after terraform apply commnad it asking for in the terminal
# 2)we can define the value directli in the terminal with apply: terraform apply -var "<variable_name>=value"
#example: terraform apply -var "subnet_cdr_block=10.0.10.0/24"
# 3) Create the file "terraform.tfvars"
variable "vpc_cidr_block" {}
variable "subnet_cidr_block" {}
variable "avail_zone" {}
variable "env_prefix" {}
variable "my_ip" {}
variable "instance_type" {}
variable "public_key_location" {}

resource "aws_vpc" "myapp-vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "${var.env_prefix}-vpc"
  }
}

resource "aws_subnet" "myapp-subnet-1" {
  vpc_id            = aws_vpc.myapp-vpc.id
  cidr_block        = var.subnet_cidr_block
  availability_zone = var.avail_zone
  tags = {
    Name : "${var.env_prefix}-subnet-1"
  }
}

#Route table and gateway configuration and also subnet asociation
#route table, like a virtual router

#Create new route table
# resource "aws_route_table" "myapp-route-table" {
#   vpc_id = aws_vpc.myapp-vpc.id

#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_internet_gateway.myapp-igw.id
#   }
#   tags = {
#     Name : "${var.env_prefix}-rtb"
#   }
# }

#internet gateway, like a virtual modem
resource "aws_internet_gateway" "myapp-igw" {
  vpc_id = aws_vpc.myapp-vpc.id

  tags = {
    Name : "${var.env_prefix}-igw"
  }
}

# resource "aws_route_table_association" "a-rtb-subnet" {
#   subnet_id      = aws_subnet.myapp-subnet-1.id
#   route_table_id = aws_route_table.myapp-route-table.id
# }

#Use main Route Table
#work with the default route table that was created by default
# comment the follow resource above: 
# 1) aws_route_table_association
# 2) aws_route_table


resource "aws_default_route_table" "main-rtb" {
  #we can show the full attributes of a object with "terraform state show <<object-name>>}"
  default_route_table_id = aws_vpc.myapp-vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myapp-igw.id
  }
  tags = {
    Name : "${var.env_prefix}-main-rtb"
  }
}

#create security groupg
#rmenber, security groups are firewell in the cloud
# they are tow typoe, request tha come from browser and request from SSH
#so we need to open or configure those ports
#firewall rules :
# incoming trafic: 
#   1) incoming : ssh into EC2: open port 22
#   2) access from browser: open port 8080

#outgoing traffic:
# 1) installations
# 2) fetch Docker images

#use security group create for AWS by default 
resource "aws_default_security_group" "myapp-default-sg" {
  vpc_id = aws_vpc.myapp-vpc.id

  #for incoming traffic rules
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #for out traffic rules
  #we dont restric any port, becouse por 0, dont restrcin any protocol, becpuse -1
  egress {
    cidr_blocks     = ["0.0.0.0/0"]
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    prefix_list_ids = []
  }

  tags = {
    "Name" : "${var.env_prefix}-default-sg"
  }
}


#this will provide us an amazon-ami recenlty dynamically for create a EC2 
data "aws_ami" "latest-amazon-linux-image" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

#check in output the id from data
output "aws_ami_id" {
  value = data.aws_ami.latest-amazon-linux-image.id
}

# #create a EC2 instance
resource "aws_instance" "myapp-instance" {
  ami           = data.aws_ami.latest-amazon-linux-image.id
  instance_type = var.instance_type

  #if we do not explicite define these fields, TF will take default VPC  in aws
  subnet_id                   = aws_subnet.myapp-subnet-1.id
  vpc_security_group_ids      = [aws_default_security_group.myapp-default-sg.id]
  availability_zone           = var.avail_zone
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ssh-key.key_name

  tags = {
    Name = "${var.env_prefix}-ec2-server"
  }

  #entrypoint script / remenber that this will execute once at the begining of ec2 instance
  user_data = file("docker-script.sh")
}

#conect out ec2 instance throught out SSH key
resource "aws_key_pair" "ssh-key" {
  key_name   = "server-key"
  public_key = file(var.public_key_location)
}

#check the public ipf from ec2 instance
output "ec2_public_ip" {
  value = aws_instance.myapp-instance.public_ip
}

