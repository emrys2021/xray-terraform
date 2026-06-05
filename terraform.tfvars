vultr_api_key = ""

aliyun_access_key = ""

aliyun_secret_key = ""

aliyun_dns_region = "cn-beijing"
domain            = "example.com"

# 节点配置
#   region:              Vultr 机房地区（ord=芝加哥 / sjc=硅谷 / nrt=东京）
#   os_id:               系统镜像（387=Ubuntu 20.04 / 2284=Ubuntu 24.04 / 2657=Ubuntu 25.10）
#   plan:                套餐型号（vc2-1c-1gb=1核1G / vc2-1c-2gb=1核2G）
#   cloud_init_template: 部署脚本（xray.yaml=仅x-ui含证书申请 / v2ray.yaml=wulabing+x-ui）
nodes = {
  share1   = { region = "ord", os_id = "2657", plan = "vc2-1c-1gb", cloud_init_template = "xray.yaml" }
  share2   = { region = "ord", os_id = "2657", plan = "vc2-1c-1gb", cloud_init_template = "xray.yaml" }
}