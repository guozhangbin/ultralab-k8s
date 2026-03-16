# Kubernetes 部署与使用指南

## 1. 项目概述

本项目基于 DeepOps 和 Kubespray 实现 Kubernetes 集群的自动化部署，支持 GPU 节点管理和容器编排。

## 2. 环境准备

### 2.1 系统要求
- **操作系统**：Rocky Linux 9.7
- **网络**：所有节点之间网络互通
- **用户**：具有 sudo 权限的用户
- **Python**：3.9+ 版本

### 2.2 依赖安装
```bash
# 安装 Python 依赖
sudo /usr/bin/python3 -m pip install ansible jmespath

# 安装系统依赖
sudo dnf install -y git curl wget
```

## 3. 集群部署

### 3.1 配置 inventory

编辑 `config/inventory` 文件，添加节点信息：

```ini
[all]
master ansible_host=192.168.0.200 ansible_user=user
gpu01 ansible_host=192.168.0.201 ansible_user=user
gpu02 ansible_host=192.168.0.202 ansible_user=user

[kube-master]
master

[kube-node]
master
gpu01
gpu02

[etcd]
master

[k8s-cluster:children]
kube-master
kube-node
```

### 3.2 配置集群参数

编辑 `config/group_vars/k8s-cluster.yml` 文件：

```yaml
################################################################################
# Kube-Proxy Configuration
################################################################################
kube_proxy_deployed: true
kube_proxy_mode: iptables
kubeadm_init_phases_skip: []
calico_bpf_enabled: false

################################################################################
# DNS Configuration
################################################################################
kube_dns_domain: "deepops.local"
dns_domain: "deepops.local"

# Containerd registry mirrors for faster image pulls in China
# Using DaoCloud and aityp mirrors for docker.io
containerd_registries_mirrors:
  - prefix: docker.io
    mirrors:
      - host: https://docker.m.daocloud.io
        capabilities: ["pull", "resolve"]
        skip_verify: false
      - host: https://docker.aityp.com
        capabilities: ["pull", "resolve"]
        skip_verify: false
  - prefix: registry.k8s.io
    mirrors:
      - host: https://k8s.m.daocloud.io
        capabilities: ["pull","resolve"]
        skip_verify: false
      - host: https://docker.aityp.com
        capabilities: ["pull","resolve"]
        skip_verify: false

# 使用国内镜像下载 pause 镜像
pod_infra_image_repo: "k8s.m.daocloud.io/pause"
pod_infra_image_tag: "3.10"
```

### 3.3 执行部署

```bash
# 部署集群
cd /home/new/deepops && ansible-playbook -l k8s-cluster playbooks/k8s-cluster.yml -vvv

# 部署完成后验证
sudo /usr/local/bin/kubectl get nodes
sudo /usr/local/bin/kubectl get pods -n kube-system
```

## 4. 常见问题解决方案

### 4.1 证书错误

**问题**：浏览器访问 Dashboard 时显示证书警告

**解决方案**：
- 这是正常现象，因为 Kubernetes Dashboard 使用自签名证书
- 在浏览器中点击「高级」→「继续访问（不安全）」
- 或者使用 kubectl proxy 访问：
  ```bash
  sudo /usr/local/bin/kubectl proxy --port=8080
  # 访问 http://localhost:8080/api/v1/namespaces/kube-system/services/kubernetes-dashboard:https/proxy/
  ```

### 4.2 节点加入失败

**问题**：Worker 节点无法加入集群

**解决方案**：
1. 检查网络连接
2. 确保 CA 证书正确分发
3. 生成新的加入令牌：
   ```bash
   sudo /usr/local/bin/kubeadm token create --print-join-command
   ```

### 4.3 Pause 镜像拉取失败

**问题**：无法拉取 registry.k8s.io/pause:3.10 镜像

**解决方案**：
- 配置国内镜像源（已在配置文件中设置）
- 手动拉取并打标签：
  ```bash
  sudo /usr/local/bin/crictl pull k8s.m.daocloud.io/pause:3.10
  sudo /usr/local/bin/crictl image tag k8s.m.daocloud.io/pause:3.10 registry.k8s.io/pause:3.10
  ```

## 5. Kubernetes Dashboard

### 5.1 访问方式

**通过 NodePort 访问**：
- 地址：https://192.168.0.200:32099
- 需要绕过证书警告

**通过 kubectl proxy 访问**：
- 启动代理：`sudo /usr/local/bin/kubectl proxy --port=8080`
- 地址：http://localhost:8080/api/v1/namespaces/kube-system/services/kubernetes-dashboard:https/proxy/
- 无需处理证书警告

### 5.2 登录 Token

```
eyJhbGciOiJSUzI1NiIsImtpZCI6IlRYTmR0YTU1Ry1xSXZWbXdpSWI2cUJLVFk4ek1LRVlsNUFjaHRNeXdxb2sifQ.eyJhdWQiOlsiaHR0cHM6Ly9rdWJlcm5ldGVzLmRlZmF1bHQuc3ZjLmRlZXBvcHMubG9jYWwiXSwiZXhwIjoxNzczMzk4Nzk2LCJpYXQiOjE3NzMzOTUxOTYsImlzcyI6Imh0dHBzOi8va3ViZXJuZXRlcy5kZWZhdWx0LnN2Yy5kZWVwb3BzLmxvY2FsIiwianRpIjoiNzE1NTIyOTEtYWE2ZC00NGViLWJhMGYtYzE1NTZhYzIzYTUxIiwia3ViZXJuZXRlcy5pbyI6eyJuYW1lc3BhY2UiOiJrdWJlLXN5c3RlbSIsInNlcnZpY2VhY2NvdW50Ijp7Im5hbWUiOiJhZG1pbi1kYXNoYm9hcmQiLCJ1aWQiOiI4NTE4YmQ2YS0zYWMwLTRlNTgtOTFmZC0wZGY2Y2ZiNjI5YzYifX0sIm5iZiI6MTc3MzM5NTE5Niwic3ViIjoic3lzdGVtOnNlcnZpY2VhY2NvdW50Omt1YmUtc3lzdGVtOmFkbWluLWRhc2hib2FyZCJ9.o2_eCp3yjA1w5lbwtxO92bYAbhkLMsqIVj2-5Oy59fr1uBX-YD_DYdDAQQ3A_Bl1pa0YM4uL37MXwU1OtwbqWnM1rMorZgtGRhdIpUhz36glxaXRh7KLbgbRiPp749waum0ylJxlR1OgC3UaJ_qQ6XErKapRUOSRcj4wJJB4a6mWVU3Zs427-E4QJ1TgJa2VNHxwTl7BbEqWTl7HCXLU1wLvuUzWZcl5Nn3Pd6u-XSoI2-FPWnerYQ7mnzq4zGN6PNW4kEL5s4jHZmEHj0aZZKUNaz0vTZXlKhCha2NzDUp2ntB8zkYR94biV3wdWUIy7tDumfG3U2sf8aCNLBk1oA
```

### 5.3 权限配置

Dashboard 使用 `admin-dashboard` 服务账户，已配置 cluster-admin 权限：

```bash
# 查看服务账户
sudo /usr/local/bin/kubectl get sa -n kube-system | grep admin-dashboard

# 查看集群角色绑定
sudo /usr/local/bin/kubectl get clusterrolebinding | grep admin-dashboard
```

### 5.4 语言设置

**设置 Dashboard 为中文**：

1. **登录 Dashboard** 后，点击右上角的用户头像
2. 在下拉菜单中选择「Settings」或「设置」
3. 在「Language」或「语言」选项中，选择「中文」或「Chinese」
4. 保存设置，页面会自动刷新为中文界面

**通过 URL 参数设置语言**：
```
https://localhost:32099/?lang=zh
```

**验证 Dashboard 版本**：
```bash
sudo /usr/local/bin/kubectl get deployment -n kube-system kubernetes-dashboard -o jsonpath='{.spec.template.spec.containers[0].image}'
```

> 注意：Kubernetes Dashboard 2.0+ 版本内置支持多语言，包括中文。

## 6. 集群管理

### 6.1 节点管理

```bash
# 查看节点状态
sudo /usr/local/bin/kubectl get nodes

# 查看节点详细信息
sudo /usr/local/bin/kubectl describe node gpu01

# 标记节点为不可调度
sudo /usr/local/bin/kubectl cordon gpu01

# 驱逐节点上的 Pod
sudo /usr/local/bin/kubectl drain gpu01 --ignore-daemonsets
```

### 6.2 资源管理

```bash
# 查看所有 Pod
sudo /usr/local/bin/kubectl get pods --all-namespaces

# 查看服务
sudo /usr/local/bin/kubectl get svc --all-namespaces

# 查看配置映射
sudo /usr/local/bin/kubectl get configmaps --all-namespaces
```

### 6.3 日志查看

```bash
# 查看 Pod 日志
sudo /usr/local/bin/kubectl logs -n kube-system kubernetes-dashboard-5c5f5c64d-2h58d

# 查看容器日志
sudo /usr/local/bin/kubectl logs -n kube-system kubernetes-dashboard-5c5f5c64d-2h58d -c kubernetes-dashboard

# 实时查看日志
sudo /usr/local/bin/kubectl logs -n kube-system kubernetes-dashboard-5c5f5c64d-2h58d -f
```

## 7. 网络配置

### 7.1 Calico CNI

集群使用 Calico 作为网络插件，配置如下：
- CNI 类型：Calico
- 网络模式：BGP
- 网络 CIDR：10.233.0.0/16

### 7.2 DNS 配置

- 集群 DNS 域名：deepops.local
- DNS 服务：CoreDNS
- 本地 DNS 缓存：nodelocaldns

## 8. 存储配置

### 8.1 默认存储
- 使用 EmptyDir 作为临时存储
- 支持 HostPath 用于本地存储
- 可配置 PersistentVolume 和 PersistentVolumeClaim

### 8.2 存储类
```bash
# 查看存储类
sudo /usr/local/bin/kubectl get storageclass
```

## 9. 安全配置

### 9.1 RBAC 权限
- 使用基于角色的访问控制
- 为不同用户和服务账户配置最小权限

### 9.2 网络策略
- Calico 支持网络策略
- 可配置 Pod 间的网络访问控制

## 10. 监控与日志

### 10.1 集群监控
- 可集成 Prometheus 和 Grafana
- 监控节点和 Pod 资源使用情况

### 10.2 日志收集
- 可配置 EFK 栈（Elasticsearch, Fluentd, Kibana）
- 集中管理集群日志

## 11. 升级与维护

### 11.1 集群升级
- 使用 Kubespray 进行版本升级
- 遵循滚动更新策略

### 11.2 备份与恢复
- 定期备份 etcd 数据
- 制定灾难恢复计划

## 12. 常见操作示例

### 12.1 部署应用

```bash
# 创建 deployment
cat > nginx-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
EOF

sudo /usr/local/bin/kubectl apply -f nginx-deployment.yaml

# 暴露服务
sudo /usr/local/bin/kubectl expose deployment nginx --port=80 --type=NodePort
```

### 12.2 查看应用状态

```bash
# 查看 deployment
sudo /usr/local/bin/kubectl get deployment nginx

# 查看 Pod
sudo /usr/local/bin/kubectl get pods -l app=nginx

# 查看服务
sudo /usr/local/bin/kubectl get svc nginx
```

## 13. 故障排查

### 13.1 常见错误

| 错误信息 | 可能原因 | 解决方案 |
|---------|---------|--------|
| `no endpoints available for service` | 服务没有可用的 Pod | 检查 Pod 状态和标签选择器 |
| `SSL certificate problem: self-signed certificate` | 自签名证书警告 | 绕过证书警告或使用 kubectl proxy |
| `failed to pull image` | 镜像拉取失败 | 检查网络连接和镜像源配置 |
| `nodes is forbidden` | RBAC 权限问题 | 检查服务账户和角色绑定 |

### 13.2 诊断命令

```bash
# 检查集群状态
sudo /usr/local/bin/kubectl cluster-info

# 检查 API 服务器状态
sudo /usr/local/bin/kubectl get componentstatuses

# 检查节点事件
sudo /usr/local/bin/kubectl get events --sort-by=.lastTimestamp

# 检查 Pod 详细信息
sudo /usr/local/bin/kubectl describe pod -n kube-system kubernetes-dashboard-5c5f5c64d-2h58d
```

## 14. Ollama 集成测试

### 14.1 Ollama 安装与配置

Ollama 是一个本地运行大语言模型的工具，可以用于 Kubernetes 集群的智能测试和配置生成。

**安装 Ollama**：
```bash
# 检查 Ollama 是否已安装
ollama --version

# 启动 Ollama 服务
ollama serve
```

**查看可用模型**：
```bash
# 列出已安装的模型
curl http://localhost:11434/api/tags

# 示例输出：
# {
#   "models": [
#     {"name": "qwen3:4b", ...},
#     {"name": "llama3.2:latest", ...},
#     {"name": "glm-4.7-flash:latest", ...}
#   ]
# }
```

### 14.2 Kubernetes 测试工具

项目提供了 `k8s-test-with-ollama.sh` 脚本，集成了 Ollama 进行集群测试和配置生成。

**使用测试工具**：
```bash
# 运行测试工具
./k8s-test-with-ollama.sh

# 菜单选项：
# 1. 检查 Kubernetes 集群状态
# 2. 使用 Ollama 分析集群状态
# 3. 使用 Ollama 生成 Kubernetes 测试配置
# 4. 退出
```

**功能说明**：
- **集群状态检查**：查看节点、Pod、服务和集群信息
- **Ollama 分析**：使用 AI 分析集群状态并提供改进建议
- **配置生成**：使用 AI 生成 Kubernetes 部署配置文件

### 14.3 使用 Ollama 生成配置

**生成 Nginx 部署配置**：
```bash
# 使用 Ollama 生成配置
ollama run qwen3:4b "请生成一个简单的 Kubernetes 部署配置，包含 Nginx 应用，3 个副本，NodePort 服务"
```

**生成的配置示例**：
```yaml
# nginx-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: hub.c.163.com/library/nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30001
  selector:
    app: nginx
```

### 14.4 部署测试应用

**部署应用**：
```bash
# 应用配置
sudo /usr/local/bin/kubectl apply -f nginx-deployment.yaml

# 查看 Pod 状态
sudo /usr/local/bin/kubectl get pods -l app=nginx

# 查看服务状态
sudo /usr/local/bin/kubectl get svc nginx-service
```

**访问应用**：
- 通过 NodePort 访问：
  - http://192.168.0.200:30001（master 节点）
  - http://192.168.0.201:30001（gpu01 节点）
  - http://192.168.0.202:30001（gpu02 节点）

### 14.5 测试验证

**验证集群功能**：
```bash
# 检查节点状态
sudo /usr/local/bin/kubectl get nodes

# 检查应用 Pod
sudo /usr/local/bin/kubectl get pods -l app=nginx

# 检查服务端点
sudo /usr/local/bin/kubectl get endpoints nginx-service

# 测试服务访问
curl http://192.168.0.200:30001
```

**预期结果**：
- 所有节点处于 Ready 状态
- Nginx Pod 全部运行正常
- 服务端点正确指向 Pod
- 可以通过 NodePort 访问 Nginx 欢迎页面

### 14.6 常见问题

**Ollama 服务未运行**：
```bash
# 启动 Ollama 服务
ollama serve

# 检查服务状态
curl http://localhost:11434/api/tags
```

**镜像拉取失败**：
- 使用国内镜像源：`hub.c.163.com/library/nginx:latest`
- 或配置 containerd 镜像仓库镜像

**Pod 无法启动**：
```bash
# 查看 Pod 详细信息
sudo /usr/local/bin/kubectl describe pod <pod-name>

# 查看 Pod 日志
sudo /usr/local/bin/kubectl logs <pod-name>
```

## 15. 远程桌面服务

### 15.1 xrdp 安装与配置

**安装 xrdp**：
```bash
# 安装 xrdp 服务
sudo dnf install -y xrdp

# 启动并启用服务
sudo systemctl start xrdp
sudo systemctl enable xrdp

# 检查服务状态
sudo systemctl status xrdp
```

**连接方法**：
- **Windows**：使用「远程桌面连接」（Win+R 输入 `mstsc`），输入服务器 IP `192.168.0.200`
- **Linux**：使用 Remmina 或其他 RDP 客户端，协议选择 RDP
- **macOS**：使用 Microsoft Remote Desktop 应用

**注意事项**：
- 使用服务器的系统用户名和密码登录
- 确保网络连接正常，服务器防火墙允许 3389 端口访问

## 16. 总结

本指南提供了 Kubernetes 集群的完整部署和管理流程，包括：
- 环境准备和依赖安装
- 集群部署和配置
- 常见问题解决方案
- Dashboard 访问和使用（支持中文界面）
- 集群管理和监控
- Ollama 集成测试
- 远程桌面服务配置
- 故障排查和维护

通过本指南，您可以快速部署和管理 Kubernetes 集群，利用 Ollama 进行智能测试和配置生成，并通过远程桌面服务方便地管理服务器，充分利用容器编排、AI 辅助和远程管理的优势。