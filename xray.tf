variable "nodes" {
  type = map(object({
    region              = string
    os_id               = string
    plan                = string
    cloud_init_template = string
  }))
}

variable "domain" {
  type        = string
  description = "根域名，用于 DNS 记录和 cloud-init 模板"
}

data "template_file" "cloudinit_template" {
  for_each = var.nodes
  template = file(each.value.cloud_init_template)

  vars = {
    node_name = each.key
    domain    = var.domain
  }
}

resource "vultr_instance" "v2ray_instance" {
  for_each = data.template_file.cloudinit_template
  plan     = var.nodes[each.key].plan

  region   = var.nodes[each.key].region
  os_id    = var.nodes[each.key].os_id

  user_data = each.value.rendered
}

resource "alicloud_alidns_record" "record" {
  for_each    = vultr_instance.v2ray_instance
  domain_name = var.domain
  rr          = each.key
  type        = "A"
  value       = each.value.main_ip
  status      = "ENABLE"
}

output "cloudinit_template_keys" {
  value = tomap({
    for k, instance in data.template_file.cloudinit_template : k => instance.id
  })
}

output "vultr_instance_keys" {
  value = tomap({
    for k, instance in vultr_instance.v2ray_instance : k => instance.id
  })
}