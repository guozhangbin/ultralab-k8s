# Ultralab Kubernetes 项目

## 项目概述

本项目基于 DeepOps 和 Kubespray 实现 Kubernetes 集群的自动化部署，支持 GPU 节点管理、容器编排和 AI 辅助测试。

## 功能特性

- **自动化部署**：使用 Ansible 和 Kubespray 实现集群一键部署
- **GPU 支持**：支持 NVIDIA GPU 节点管理和调度
- **国内镜像加速**：配置了国内镜像源，解决镜像拉取超时问题
- **Kubernetes Dashboard**：内置 Dashboard 管理界面，支持中文
- **Ollama 集成**：使用本地大语言模型辅助集群测试和配置生成
- **远程桌面服务**：配置了 xrdp 远程桌面服务，方便远程管理
- **完整的监控与管理**：提供集群管理、故障排查和维护指南

## 环境要求

- **操作系统**：Rocky Linux 9.7
- **网络**：所有节点之间网络互通
- **用户**：具有 sudo 权限的用户
- **Python**：3.9+ 版本

## 快速开始

### 1. 环境准备

```bash
# 安装 Python 依赖
sudo /usr/bin/python3 -m pip install ansible jmespath

# 安装系统依赖
sudo dnf install -y git curl wget
```

### 2. 配置集群

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

### 3. 部署集群

```bash
# 部署集群
cd /home/new/deepops && ansible-playbook -l k8s-cluster playbooks/k8s-cluster.yml -vvv

# 部署完成后验证
sudo /usr/local/bin/kubectl get nodes
sudo /usr/local/bin/kubectl get pods -n kube-system
```

## 访问 Dashboard

### 通过 NodePort 访问
- 地址：https://192.168.0.200:32099
- 需要绕过证书警告

### 通过 kubectl proxy 访问
```bash
sudo /usr/local/bin/kubectl proxy --port=8080
# 访问 http://localhost:8080/api/v1/namespaces/kube-system/services/kubernetes-dashboard:https/proxy/
```

### 登录 Token
```
eyJhbGciOiJSUzI1NiIsImtpZCI6IlRYTmR0YTU1Ry1xSXZWbXdpSWI2cUJLVFk4ek1LRVlsNUFjaHRNeXdxb2sifQ.eyJhdWQiOlsiaHR0cHM6Ly9rdWJlcm5ldGVzLmRlZmF1bHQuc3ZjLmRlZXBvcHMubG9jYWwiXSwiZXhwIjoxNzczMzk4Nzk2LCJpYXQiOjE3NzMzOTUxOTYsImlzcyI6Imh0dHBzOi8va3ViZXJuZXRlcy5kZWZhdWx0LnN2Yy5kZWVwb3BzLmxvY2FsIiwianRpIjoiNzE1NTIyOTEtYWE2ZC00NGViLWJhMGYtYzE1NTZhYzIzYTUxIiwia3ViZXJuZXRlcy5pbyI6eyJuYW1lc3BhY2UiOiJrdWJlLXN5c3RlbSIsInNlcnZpY2VhY2NvdW50Ijp7Im5hbWUiOiJhZG1pbi1kYXNoYm9hcmQiLCJ1aWQiOiI4NTE4YmQ2YS0zYWMwLTRlNTgtOTFmZC0wZGY2Y2ZiNjI5YzYifX0sIm5iZiI6MTc3MzM5NTE5Niwic3ViIjoic3lzdGVtOnNlcnZpY2VhY2NvdW50Omt1YmUtc3lzdGVtOmFkbWluLWRhc2hib2FyZCJ9.o2_eCp3yjA1w5lbwtxO92bYAbhkLMsqIVj2-5Oy59fr1uBX-YD_DYdDAQQ3A_Bl1pa0YM4uL37MXwU1OtwbqWnM1rMorZgtGRhdIpUhz36glxaXRh7KLbgbRiPp749waum0ylJxlR1OgC3UaJ_qQ6XErKapRUOSRcj4wJJB4a6mWVU3Zs427-E4QJ1TgJa2VNHxwTl7BbEqWTl7HCXLU1wLvuUzWZcl5Nn3Pd6u-XSoI2-FPWnerYQ7mnzq4zGN6PNW4kEL5s4jHZmEHj0aZZKUNaz0vTZXlKhCha2NzDUp2ntB8zkYR94biV3wdWUIy7tDumfG3U2sf8aCNLBk1oA
```

## 使用 Ollama 测试

```bash
# 运行测试工具
./k8s-test-with-ollama.sh

# 菜单选项：
# 1. 检查 Kubernetes 集群状态
# 2. 使用 Ollama 分析集群状态
# 3. 使用 Ollama 生成 Kubernetes 测试配置
# 4. 退出
```

## 远程桌面访问

```bash
# 连接方法：
# Windows：远程桌面连接（Win+R 输入 mstsc），输入服务器 IP 192.168.0.200
# Linux：使用 Remmina 或其他 RDP 客户端
# macOS：使用 Microsoft Remote Desktop 应用
```

## 项目结构

```
./
├── ansible_k8s.md          # Kubernetes 部署与使用指南
├── access-dashboard.sh      # Dashboard 访问脚本
├── k8s-test-with-ollama.sh  # Ollama 集成测试脚本
├── config/                  # 集群配置文件
├── playbooks/               # Ansible playbooks
├── roles/                   # Ansible roles
└── submodules/              # 子模块（Kubespray 等）
```

## 文档

- **详细指南**：`ansible_k8s.md` - 完整的 Kubernetes 部署与使用指南
- **快速访问**：`access-dashboard.sh` - 快速访问 Kubernetes Dashboard
- **测试工具**：`k8s-test-with-ollama.sh` - 使用 Ollama 进行集群测试

## 故障排查

### 常见问题

| 错误信息 | 可能原因 | 解决方案 |
|---------|---------|--------|
| `no endpoints available for service` | 服务没有可用的 Pod | 检查 Pod 状态和标签选择器 |
| `SSL certificate problem: self-signed certificate` | 自签名证书警告 | 绕过证书警告或使用 kubectl proxy |
| `failed to pull image` | 镜像拉取失败 | 检查网络连接和镜像源配置 |
| `nodes is forbidden` | RBAC 权限问题 | 检查服务账户和角色绑定 |

### 诊断命令

```bash
# 检查集群状态
sudo /usr/local/bin/kubectl cluster-info

# 检查 API 服务器状态
sudo /usr/local/bin/kubectl get componentstatuses

# 检查节点事件
sudo /usr/local/bin/kubectl get events --sort-by=.lastTimestamp

# 检查 Pod 详细信息
sudo /usr/local/bin/kubectl describe pod -n kube-system <pod-name>
```

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个项目。

## 许可证

MIT License

## 联系方式

- **GitHub**：https://github.com/guozhangbin/ultralab-k8s

---

Made with ❤️ for Kubernetes 集群管理