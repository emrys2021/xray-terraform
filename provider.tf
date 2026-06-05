terraform {
  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "2.15.1"
    }
    alicloud = {
      source = "aliyun/alicloud"
    }
    template = {
      source = "hashicorp/template"
    }
  }
}

provider "vultr" {
  api_key = var.vultr_api_key
}

variable "vultr_api_key" {}

provider "alicloud" {
  access_key = var.aliyun_access_key
  secret_key = var.aliyun_secret_key
  region     = var.aliyun_dns_region
}

variable "aliyun_access_key" {
  type = string
}

variable "aliyun_secret_key" {
  type = string
}

variable "aliyun_dns_region" {
  type = string
}