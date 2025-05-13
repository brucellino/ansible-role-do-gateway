# Create test instance on digital ocean in AMS3
terraform {
  required_version = ">= 1.1.0"
  # require vault and digital ocean providers
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.53.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = "4.8.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "2.5.3"
    }
  }
  backend "consul" {
    path = "do/test/ansible-role-do-gateway"
  }
}

variable "enable_gateway" {
  type        = bool
  description = "Enable the gateway"
  default     = false
}

variable "backends" {
  type        = number
  description = "Number of backends behind the gateway"
  default     = 0

}

data "vault_generic_secret" "do_token" {
  path = "digitalocean/tokens"
}

provider "digitalocean" {
  token = data.vault_generic_secret.do_token.data["terraform"]
}

data "digitalocean_vpc" "vpc" {
  name = "terraform-vpc-hah"
}

data "digitalocean_ssh_key" "test_instances" {
  name = "test-instances"
}

data "vault_generic_secret" "ssh_key" {
  path = "digitalocean/ssh_key"
}

data "digitalocean_image" "base_image" {
  slug = "ubuntu-21-10-x64"
}

resource "digitalocean_droplet" "gateway" {
  count         = var.enable_gateway ? 1 : 0
  name          = format("ansible-role-do-base-platform-test-instance-%s", formatdate("YYYY-MM-DD-hh-mm-ss", timestamp()))
  image         = data.digitalocean_image.base_image.id
  size          = "s-1vcpu-1gb"
  vpc_uuid      = data.digitalocean_vpc.vpc.id
  region        = "ams3"
  tags          = ["ansible-role", "consul", "test"]
  backups       = false
  monitoring    = false
  droplet_agent = true
  ssh_keys      = [data.digitalocean_ssh_key.test_instances.id]
}

resource "digitalocean_droplet" "backends" {
  count         = var.backends
  name          = format("ansible-role-do-backend-${count.index}-%s", formatdate("YYYY-MM-DD-hh-mm-ss", timestamp()))
  image         = data.digitalocean_image.base_image.id
  size          = "s-1vcpu-1gb"
  vpc_uuid      = data.digitalocean_vpc.vpc.id
  region        = "ams3"
  tags          = ["ansible-role", "consul", "test"]
  backups       = false
  monitoring    = false
  droplet_agent = true
  ssh_keys      = [data.digitalocean_ssh_key.test_instances.id]
}

# write the private key for Ansible later
resource "local_sensitive_file" "ssh_priv_key" {
  filename        = "ssh_priv_key"
  count           = var.enable_gateway ? 1 : 0
  content         = data.vault_generic_secret.ssh_key.data["private_key"]
  file_permission = "0400"
}

# Create the inventory for Ansible in a local file, templating the ip address of the test instance


output "gateway_ip" {
  value = digitalocean_droplet.gateway.*.ipv4_address
}
