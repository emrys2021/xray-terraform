# xray-terraform

本项目受 [wulabing/V2Ray_ws-tls_bash_onekey](https://github.com/wulabing/V2Ray_ws-tls_bash_onekey) 和 [vaxilu/x-ui](https://github.com/vaxilu/x-ui) 启发。

x-ui 安装了 xray 内核和面板，但未包含 TLS 证书申请。本项目将 wulabing 脚本的证书申请逻辑移植过来，修复了若干兼容性问题，并在安装时自动初始化 x-ui 面板的 TLS 配置。结合 Terraform，可以一键在云平台上完成节点的创建与部署。

## 准备条件

**云平台 / 协议说明**

- 云平台以 [Vultr](https://www.vultr.com) 为示例，默认虚拟机配置为 1C1G
- 代理协议以 vless + ws + tls 为示例，TLS 需要注册域名
- 域名解析以阿里云云解析 DNS 为示例

**操作步骤**

1. 到 Vultr 获取个人 API key：Vultr 控制台 → Manage User → API Access
2. 到阿里云获取个人 API key：阿里云控制台 → 权限与安全 → AccessKey 管理 → 创建 AccessKey
3. 将获取到的 API key 填入 `terraform.tfvars`

## 安装 Terraform

**Windows（winget）**
```powershell
winget install HashiCorp.Terraform
```

**macOS（Homebrew）**
```shell
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

**Ubuntu / Debian**
```shell
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

其他平台参考[官方文档](https://developer.hashicorp.com/terraform/downloads)。

## 配置 terraform.tfvars

将以下内容填入 `terraform.tfvars`：

```hcl
# Vultr API key
vultr_api_key = "your-vultr-api-key"

# 阿里云 API key
aliyun_access_key = "your-aliyun-access-key"
aliyun_secret_key = "your-aliyun-secret-key"

# 阿里云 DNS 接入地域（通常保持默认）
aliyun_dns_region = "cn-beijing"

# 根域名，需已托管在上述阿里云账号的云解析 DNS 下
# 注意：域名必须归属于该阿里云账号，否则创建 DNS 记录会报 IncorrectDomainUser 错误
domain = "example.com"

# 节点配置
#   region:              Vultr 机房地区（ord=芝加哥 / sjc=硅谷 / nrt=东京）
#   os_id:               系统镜像（387=Ubuntu 20.04 / 2284=Ubuntu 24.04 / 2657=Ubuntu 25.10）
#   plan:                套餐型号（vc2-1c-1gb=1核1G / vc2-1c-2gb=1核2G）
#   cloud_init_template: 部署脚本（xray.yaml=仅x-ui含证书申请）
nodes = {
  share1 = { region = "ord", os_id = "2657", plan = "vc2-1c-1gb", cloud_init_template = "xray.yaml" }
}
```

## 快速开始

```shell
git clone https://github.com/emrys2021/xray-terraform.git
cd xray-terraform
terraform init
terraform plan
terraform apply
```
