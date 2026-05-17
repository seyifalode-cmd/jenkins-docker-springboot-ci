# **Jenkins and Docker CI Server — AWS Infrastructure Automation**

Terraform and Ansible automation that provisions a production-ready Jenkins CI server on AWS EC2, pre-configured with Docker, Maven, and all dependencies required to run a Spring Boot containerization pipeline.

---

## Project at a Glance

| | |
|---|---|
| **Tools Used** | Terraform, Ansible, AWS EC2, Jenkins, Docker, Maven, Amazon Linux 2 |
| **Platform** | AWS (us-east-1, configurable) |
| **Languages** | HCL (Terraform), YAML (Ansible) |
| **What It Does** | Provisions a dedicated VPC, public subnet, security group, and EC2 instance, then bootstraps the instance with Jenkins, Docker, and Maven via an Ansible playbook — fully automated from `terraform apply` |

---

## The Problem This Project Solves

Standing up a Jenkins CI server that is genuinely ready to build and publish Docker images is not a one-command operation. It requires OS-level package management, Java installation, a signed Jenkins repository configuration, daemon management, user-group assignments so Jenkins can talk to Docker without root, and a working Maven installation with correctly set environment variables. When done manually, each of these steps is a source of configuration drift — the server works today but no one can reproduce it tomorrow.

This project encodes the entire server configuration as code. Terraform creates all the AWS networking and compute resources in a repeatable, version-controlled manner. The moment the EC2 instance is reachable over SSH, Terraform invokes a `remote-exec` provisioner that runs an Ansible playbook directly on the instance. By the time `terraform apply` completes, Jenkins is running on port 8080, Docker is running and accessible to the Jenkins process, Maven is installed globally, and the initial admin password has been printed to the Terraform output.

The result is a CI server that any team member can recreate from scratch in minutes using a single command, with no manual SSH sessions or undocumented configuration steps. It also establishes the networking foundation — a dedicated VPC, an Internet Gateway, and a precisely scoped security group — that isolates the CI workload from other AWS resources.

---

## Architecture

```
Local Machine (Terraform + SSH key)
        |
        | terraform apply
        v
+---------------------------+
|  AWS us-east-1            |
|  +---------------------+  |
|  |  VPC 10.0.0.0/16   |  |
|  |  +---------------+  |  |
|  |  | Public Subnet |  |  |
|  |  | 10.0.1.0/24   |  |  |
|  |  |               |  |  |
|  |  | +-----------+ |  |  |
|  |  | |  EC2      | |  |  |
|  |  | |  t3.micro | |  |  |
|  |  | |           | |  |  |
|  |  | | Jenkins   | |  |  |
|  |  | | :8080     | |  |  |
|  |  | |           | |  |  |
|  |  | | Docker    | |  |  |
|  |  | | Maven 3.9 | |  |  |
|  |  | +-----------+ |  |  |
|  |  +---------------+  |  |
|  |        |             |  |
|  |  Internet Gateway    |  |
|  +---------------------+  |
+---------------------------+
        |
Security Group allows:
  TCP/22   (SSH)
  TCP/80   (HTTP)
  TCP/8080 (Jenkins)
  TCP/1233 (Custom)
```

**Bootstrap flow (triggered automatically by Terraform provisioner)**

```
EC2 instance starts
      |
      v
sudo yum update -y
sudo amazon-linux-extras install ansible2 -y
      |
      v
ansible-playbook install_jenkins_and_docker.yaml
      |
      +-- Install wget, git, yum-utils
      +-- Install Java 17 (Amazon Corretto)
      +-- Add Jenkins yum repo + GPG key
      +-- Install and enable Jenkins service
      +-- Retrieve and print initial admin password
      +-- Install Docker, create docker group
      +-- Add jenkins user to docker group
      +-- Start and enable Docker service
      +-- Set docker.sock permissions
      +-- Download and install Apache Maven 3.9.12
      +-- Configure M2_HOME environment variable
```

---

## Repository Structure

```
jenkins-docker-springboot-ci/
├── main.tf                          # Root module: provider, vpc module, compute module
├── variables.tf                     # Root variable: AWS region (default: us-east-1)
├── outputs.tf                       # Outputs Jenkins public URL (http://<ip>:8080)
├── install_jenkins_and_docker.yaml  # Ansible playbook: full server bootstrap
└── modules/
    ├── vpc/
    │   ├── main.tf                  # VPC, IGW, route table, public subnet, security group
    │   ├── variables.tf             # Region variable
    │   └── outputs.tf              # Exports subnet ID, security group ID, subnet CIDR
    └── compute/
        ├── main.tf                  # EC2 instance, key pair, file/remote-exec provisioners
        ├── variables.tf             # Region, SSH key paths, subnet/SG references
        └── outputs.tf              # Exports instance ID and public IP
```

---

## Walkthrough

**Terraform provisions the network layer first**

The VPC module creates the `10.0.0.0/16` network, attaches an Internet Gateway, configures a public route table with a default route to the gateway, and creates a single public subnet in the first available availability zone. A security group is attached to the subnet permitting inbound SSH (22), HTTP (80), Jenkins (8080), and a custom application port (1233), with unrestricted outbound access.

**Terraform provisions the compute layer**

The compute module fetches the latest Amazon Linux 2 AMI via AWS Systems Manager Parameter Store, imports the local SSH public key as a named EC2 key pair, and launches a `t3.micro` instance into the public subnet. The instance receives a public IP automatically. Terraform connects over SSH and copies `install_jenkins_and_docker.yaml` to the instance, then executes it with Ansible.

**Ansible configures the server**

The playbook runs locally on the EC2 instance (hosts: localhost) with privilege escalation. It installs Jenkins from the official signed yum repository, waits for the service to initialize, and captures the auto-generated admin password. Docker is installed, the `docker` group is created, and the `jenkins` user is added to that group — enabling Jenkins to invoke Docker commands without sudo. Maven 3.9.12 is extracted to `/opt` and symlinked to `/usr/bin/mvn`, with `M2_HOME` written to `/etc/profile.d/maven.sh` for global availability.

---

## How to Reproduce

**Prerequisites**

- AWS CLI configured with credentials that have EC2, VPC, and SSM read permissions
- Terraform >= 0.15.5 installed locally
- An SSH key pair at `~/.ssh/id_ed25519` and `~/.ssh/id_ed25519.pub` (or update the defaults in `modules/compute/variables.tf`)

```bash
# 1. Clone the repository
git clone https://github.com/<your-username>/jenkins-docker-springboot-ci.git
cd jenkins-docker-springboot-ci

# 2. Initialize Terraform (downloads the AWS provider)
terraform init

# 3. Preview the resources that will be created
terraform plan

# 4. Apply — this provisions the VPC, subnet, security group, EC2 instance,
#    and runs the full Ansible bootstrap. Takes approximately 4-6 minutes.
terraform apply

# 5. When apply completes, Terraform prints the Jenkins URL:
#    Jenkins-Public-URL = "http://<public-ip>:8080"
#    The Ansible playbook also prints the initial admin password in the apply output.

# 6. Open the Jenkins URL in a browser and complete the setup wizard
#    using the printed initial admin password.

# 7. To destroy all resources when done:
terraform destroy
```

**Customising the region**

```bash
terraform apply -var="region=us-west-2"
```

**Customising SSH key paths**

Edit `modules/compute/variables.tf`:

```hcl
variable "ssh_key_public" {
  default = "/path/to/your/key.pub"
}

variable "ssh_key_private" {
  default = "/path/to/your/key"
}
```

---

*Oluwaseyi Michael Falode · Cybersecurity & Cloud Security Engineer · Toronto, ON*
