#-----compute/main.tf-----
#==========================
provider "aws" {
  region = var.region
}

#Get Linux AMI ID using SSM Parameter endpoint
#==============================================
data "aws_ssm_parameter" "webserver-ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

#Create key-pair for logging into EC2 
#======================================
resource "aws_key_pair" "aws-key" {
  key_name   = "jenkins"
  public_key = file(var.ssh_key_public)
}

#Create and bootstrap Jenkins Master Server
#===========================================
resource "aws_instance" "jenkins" {
  instance_type               = "t3.micro"
  ami                         = data.aws_ssm_parameter.webserver-ami.value
  tags = {
  Name = "jenkins_master_tf"
  }
  key_name                    = aws_key_pair.aws-key.key_name
  associate_public_ip_address = true
  vpc_security_group_ids      = [var.security_group]
  subnet_id                   = var.subnets

  connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key   = file(var.ssh_key_private)
      host        = self.public_ip
   }

  # Copy the file from local machine to EC2
  provisioner "file" {
    source      = "install_jenkins_and_docker.yaml"
    destination = "install_jenkins_and_docker.yaml"
  }

  # Execute a script on a remote resource
  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y && sudo amazon-linux-extras install ansible2 -y",
      "sleep 30s",
      "ansible-playbook install_jenkins_and_docker.yaml"
    ]
 }
}
