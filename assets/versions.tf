terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
    template = {
      source = "hashicorp/template"
    }
  }
  required_version = ">= 0.13"
}