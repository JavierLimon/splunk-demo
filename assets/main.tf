# =======================================================================
# Vault Telemetry Lab (vtl)
#
# =======================================================================

terraform {
  required_version = ">= 0.13"
}

# -----------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------

variable "docker_host" {
  default = "unix:///var/run/docker.sock"
}

variable "splunk_version" {
  default = "8.1"
}

variable "telegraf_version" {
  default = "1.12.6"
}

variable "vault_version" {
  default = "1.6.0"
}

variable "fluentd_splunk_hec_version" {
  default = "0.0.2"
}

# -----------------------------------------------------------------------
# Global configuration
# -----------------------------------------------------------------------

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# -----------------------------------------------------------------------
# Provider configuration
# -----------------------------------------------------------------------

provider "docker" {
  host = var.docker_host
}

# -----------------------------------------------------------------------
# Custom network
# -----------------------------------------------------------------------
resource "docker_network" "vtl_network" {
  name       = "vtl-network"
  attachable = true
  ipam_config { subnet = "10.42.10.0/24" }
}

# -----------------------------------------------------------------------
# Splunk resources
# -----------------------------------------------------------------------

resource "docker_image" "splunk" {
  name         = "splunk/splunk:${var.splunk_version}"
  keep_locally = true
}

resource "docker_container" "splunk" {
  name  = "vtl-splunk"
  image = docker_image.splunk.latest
  env   = ["SPLUNK_START_ARGS=--accept-license", "SPLUNK_PASSWORD=vtl-password"]
  upload {
    content = (file("${path.cwd}/vtl/config/default.yml"))
    file    = "/tmp/defaults/default.yml"
  }
  ports {
    internal = "8000"
    external = "8000"
    protocol = "tcp"
  }
  networks_advanced {
    name         = "vtl-network"
    ipv4_address = "10.42.10.100"
  }
  /*provisioner "local-exec" {
    command = <<-EOT
    export splunk_ready=0
    while [ $splunk_ready = 0 ]
      do
        if docker ps -f name=vtl-splunk --format "{{.Status}}" \
        | grep -q '(healthy)'
            then
                export splunk_ready=1
                echo "Splunk is ready."
            else
                printf "cheking splunk is ready"
        fi
        sleep 5s
    done
  EOT
  }*/
}

# -----------------------------------------------------------------------
# Fluentd resources
# Uses @brianshumate's fluentd-splunk-hec image
# https://github.com/brianshumate/fluentd-splunk-hec
# -----------------------------------------------------------------------

resource "docker_image" "fluentd_splunk_hec" {
  name         = "brianshumate/fluentd-splunk-hec:${var.fluentd_splunk_hec_version}"
  keep_locally = true
}

resource "docker_container" "fluentd" {
  name  = "vtl-fluentd"
  image = docker_image.fluentd_splunk_hec.latest
  volumes {
    host_path      = "${path.cwd}/vault-audit-log"
    container_path = "/vault/logs"
  }
  volumes {
    host_path      = "${path.cwd}/vtl/config/fluent.conf"
    container_path = "/fluentd/etc/fluent.conf"
  }
  networks_advanced {
    name         = "vtl-network"
    ipv4_address = "10.42.10.101"
  }
}

# -----------------------------------------------------------------------
# Telegraf resources
# -----------------------------------------------------------------------

data "template_file" "telegraf_configuration" {
  template = file(
    "${path.cwd}/vtl/config/telegraf.conf",
  )
}

resource "docker_image" "telegraf" {
  name         = "telegraf:${var.telegraf_version}"
  keep_locally = true
}

resource "docker_container" "telegraf" {
  name  = "vtl-telegraf"
  image = docker_image.telegraf.latest
  networks_advanced {
    name         = "vtl-network"
    ipv4_address = "10.42.10.102"
  }
  upload {
    content = data.template_file.telegraf_configuration.rendered
    file    = "/etc/telegraf/telegraf.conf"
  }
}

# -----------------------------------------------------------------------
# Vault data and resources
# -----------------------------------------------------------------------

data "template_file" "vault_configuration" {
  template = (file("${path.cwd}/vtl/config/vault.hcl"))
}

resource "docker_image" "vault" {
  name         = "vault:${var.vault_version}"
  keep_locally = true
}

resource "docker_container" "vault" {
  name     = "vtl-vault"
  image    = docker_image.vault.latest
  env      = ["SKIP_CHOWN", "VAULT_ADDR=http://127.0.0.1:8200"]
  command  = ["vault", "server", "-log-level=trace", "-config=/vault/config"]
  hostname = "vtl-vault"
  must_run = true
  capabilities {
    add = ["IPC_LOCK"]
  }
  healthcheck {
    test         = ["CMD", "vault", "status"]
    interval     = "10s"
    timeout      = "2s"
    start_period = "10s"
    retries      = 2
  }
  networks_advanced {
    name         = "vtl-network"
    ipv4_address = "10.42.10.103"
  }
  ports {
    internal = "8200"
    external = "8200"
    protocol = "tcp"
  }
  upload {
    content = data.template_file.vault_configuration.rendered
    file    = "/vault/config/main.hcl"
  }
  upload {
    content = (file("${path.cwd}/vtl/scripts/10secrets.sh"))
    file    = "/home/vault/10secrets.sh"
  }
  upload {
    content = (file("${path.cwd}/vtl/scripts/25secrets.sh"))
    file    = "/home/vault/25secrets.sh"
  }
  upload {
    content = (file("${path.cwd}/vtl/scripts/50secrets.sh"))
    file    = "/home/vault/50secrets.sh"
  }
  upload {
    content = (file("${path.cwd}/vtl/scripts/update10secrets.sh"))
    file    = "/home/vault/update10secrets.sh"
  }
  upload {
    content = (file("${path.cwd}/vtl/policies/sudo-policy.hcl"))
    file    = "/home/vault/sudo-policy.hcl"
  }
  upload {
    content = (file("${path.cwd}/vtl/scripts/10logins.sh"))
    file    = "/home/vault/10logins.sh"
  }
  upload {
    content = (file("${path.cwd}/vtl/scripts/25logins.sh"))
    file    = "/home/vault/25logins.sh"
  }
  upload {
    content = (file("${path.cwd}/vtl/scripts/50logins.sh"))
    file    = "/home/vault/50logins.sh"
  }
  upload {
    content = (file("${path.cwd}/vtl/scripts/200tokens.sh"))
    file    = "/home/vault/200tokens.sh"
  }
  volumes {
    host_path      = "${path.cwd}/vault-audit-log"
    container_path = "/vault/logs"
  }
  provisioner "local-exec" {
    command = <<-EOT
    echo "wait 10 seconds for vault be ready"
    sleep 10
    echo "install dependencies"
    docker container exec -i vtl-vault apk add util-linux
    echo "Making vault init"
    docker container exec -i vtl-vault vault operator init -key-shares=1 -key-threshold=1 | head -n3 | cat > .vault-init
    echo "Making unseal"
    docker container exec -i vtl-vault vault operator unseal $(grep 'Unseal Key 1'  .vault-init | awk '{print $NF}')
    echo "Making vault login"
    docker container exec -i vtl-vault vault login -no-print $(grep 'Initial Root Token' .vault-init | awk '{print $NF}')
    echo "Making lookup policies"
    docker container exec -i vtl-vault vault token lookup | grep policies
    echo "Activating audit log"
    docker container exec -i vtl-vault vault audit enable file file_path=/vault/logs/vault-audit.log
    echo "Generating vault data for splunk, this can take a while"
    echo "Enabling kv"
    docker container exec -i vtl-vault vault secrets enable -version=2 kv
    echo "generating 10 secrets"
    docker container exec -i vtl-vault sh /home/vault/10secrets.sh
    echo "wait 10 seconds"
    sleep 10
    echo "generating 25 secrets"
    docker container exec -i vtl-vault sh /home/vault/25secrets.sh
    echo "wait 10 seconds"
    sleep 10
    echo "generating 50 secrets"
    docker container exec -i vtl-vault sh /home/vault/50secrets.sh
    echo "wait 10 seconds"
    sleep 10
    echo "updating the first 10 secrets"
    docker container exec -i vtl-vault sh /home/vault/update10secrets.sh
    echo "creating sudo policy"
    docker container exec -i vtl-vault vault policy write sudo /home/vault/sudo-policy.hcl
    echo "enabling user pass auth method"
    docker container exec -i vtl-vault vault auth enable userpass
    echo "add a learner user with the password **vtl-password**."
    docker container exec -i vtl-vault vault write auth/userpass/users/learner password=vtl-password token_ttl=120m token_max_ttl=140m token_policies=sudo
    echo "login to Vault 10 times as the learner user."
    docker container exec -i vtl-vault sh /home/vault/10logins.sh
    echo "wait 10 seconds"
    sleep 10
    echo "login to Vault 25 times as the learner user."
    docker container exec -i vtl-vault sh /home/vault/25logins.sh
    echo "wait 10 seconds"
    sleep 10
    echo "login to Vault 50 times as the learner user."
    docker container exec -i vtl-vault sh /home/vault/50logins.sh
    echo "wait 10 seconds"
    sleep 10
    echo "creating 200 tokens."
    docker container exec -i vtl-vault sh /home/vault/200tokens.sh
    echo "Finish generating data for metrics"
  EOT
  }
}
output "link_info" {
  value     = "Please open this link on your browser to go to splunk"
}
output "link" {
  value     = "https://localhost:8000"
}
output "credentials" {
  value     = "Username: admin, password: vtl-password"
}
output "notes" {
  value     = "Afer opening the link in your browser, if you are on a mac and it says 'Your coonection is not private' click anyware in the screen and write 'thisisunsafe' to go to the login page"
}
output "cleaning" {
  value     = "After finish checking splunk app you can use the command 'terraform destroy -auto-approve' to cleanup the enviroment and destroy the docker containers"
}