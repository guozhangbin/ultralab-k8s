# DeepOps Kubernetes (K8S) 集群部署指南

> **已验证环境**: Rocky Linux 9.8 / Kubespray v2.35.4 / NVIDIA Driver 580.167.08 / CUDA 13.0 / GPU Operator v26.3.1

## 目录

- [概述](#概述)
- [中国网络适配](#中国网络适配)
- [环境要求](#环境要求)
- [快速部署](#快速部署)
- [配置说明](#配置说明)
- [集群管理](#集群管理)
- [GPU 支持](#gpu-支持)
- [部署后验证](#部署后验证)
- [可选组件](#可选组件)
- [故障排查](#故障排查)

---

## 概述

DeepOps 基于 Kubespray 实现 Kubernetes 集群自动化部署，专为 NVIDIA GPU 环境优化。

### 核心特性

| 特性 | 说明 |
|------|------|
| Kubespray 集成 | 底层 K8S 部署引擎 |
| GPU Operator | 一键部署 GPU 驱动、设备插件、MIG 管理 |
| 容器运行时 | 默认 containerd（支持 Docker/cri-o） |
| 存储方案 | NFS Client Provisioner / Ceph / NetApp Trident |
| 监控日志 | Prometheus + Grafana + rsyslog |
| **中国网络优化** | ✅ 已全面适配中国镜像源 |

### 架构

```
控制节点 (kube_control_plane): API Server / Scheduler / Controller / etcd / Helm / NFS Server
工作节点 (kube_node): kubelet / containerd / NVIDIA GPU / NFS Client
```

---

## 中国网络适配 ⚠️

> **重要**: 本项目已针对中国大陆网络环境进行全面优化，以下为所有修改点汇总。

### 已修复的网络问题

| 组件 | 原始源 | 修复后源 | 问题原因 |
|------|--------|----------|----------|
| **NVIDIA 驱动/CUDA 仓库** | `nvidia.com/nvidia/cuda/` (错误路径) | `developer.download.nvidia.cn/compute/cuda/` | 路径不存在 + 域名不可达 |
| **NVIDIA DCGM 仓库** | `nvidia.com` | `developer.download.nvidia.cn/` | 国内无法访问 |
| **GPU Operator Helm 仓库** | `helm.ngc.nvidia.com/nvidia` (需认证) | `nvidia.github.io/gpu-operator` (公开) | NGC 需要认证且超时 |
| **Helm Stable 仓库** | `charts.helm.sh/stable` (已废弃) | 添加 ignore_errors | 2020年废弃，超时 |
| **Helm 超时问题** | `--wait` (5分钟超时) | `--timeout 30m` (30分钟) | 镜像拉取时间不足 |

### 修改的文件清单

```
roles/galaxy/nvidia.nvidia_driver/tasks/install-redhat.yml    # 硬编码 repo URL + 缓存清理
roles/nvidia_cuda/tasks/install-redhat.yml                    # 硬编码 repo URL
roles/nvidia_dcgm/tasks/install-redhat.yml                    # 硬编码 repo URL
roles/nvidia_cuda/defaults/main.yml                           # cuda-toolkit 包名修正
roles/nvidia-gpu-operator/defaults/main.yml                   # Helm 仓库改为 GitHub Pages
roles/nvidia-gpu-operator/tasks/k8s.yml                       # 超时时间 30m + repo 清理
roles/nfs-client-provisioner/tasks/main.yml                   # 超时时间 30m（--wait → --timeout）
playbooks/k8s-cluster.yml                                    # Helm stable ignore_errors
playbooks/nvidia-software/nvidia-cuda.yml                    # 运行前清理旧 repo
```

### 手动验证镜像源可用性

```bash
# 测试 CUDA 仓库（应在目标节点执行）
curl -sI "https://developer.download.nvidia.cn/compute/cuda/repos/rhel9/x86_64/repodata/repomd.xml" | head -5

# 测试 nvcr.io（GPU Operator 镜像源）
sudo podman pull nvcr.io/nvidia/k8s-device-plugin:latest

# 测试 GPU Operator Helm 仓库
helm repo add nvidia https://nvidia.github.io/gpu-operator && helm search repo nvidia/gpu-operator
```

---

## 环境要求

### 硬件要求

| 角色 | 最低配置 | 推荐配置 |
|------|----------|----------|
| 控制节点 | 2 CPU, 4GB RAM, 50GB | 4 CPU, 8GB RAM, 100GB SSD |
| 工作节点 | 2 CPU, 4GB RAM, 50GB | 4+ CPU, 16GB+ RAM, 100GB+ SSD |
| GPU 节点 | 同上 + NVIDIA GPU | A100/H100/H800 等 |

> etcd 节点数量必须为**奇数**（1, 3, 5...）

### 操作系统支持

| 系统 | 版本 | 支持状态 |
|------|------|----------|
| Ubuntu | 22.04 LTS, 24.04 LTS | 官方推荐 |
| Rocky Linux / RHEL | 8, 9 | 已验证 |
| DGX OS | 6, 7 | DGX 平台 |

### 网络端口

| 端口 | 用途 |
|------|------|
| 6443 | Kubernetes API Server |
| 2379-2380 | etcd 集群通信 |
| 10250 | kubelet API |
| 30000-32767 | NodePort 服务范围 |

---

## 快速部署

### 第一步：初始化控制节点

```bash
git clone https://github.com/NVIDIA/deepops.git
cd deepops
./scripts/setup.sh
```

### 第二步：配置 Inventory

编辑 `config/inventory`：

```ini
[all]
master     ansible_host=192.168.0.200
gpu01      ansible_host=192.168.0.201
gpu02      ansible_host=192.168.0.202

[kube_control_plane]
master

[etcd]
master

[kube_node]
gpu01
gpu02

[k8s_cluster:children]
kube_control_plane
kube_node

[all:vars]
ansible_user=new
ansible_ssh_private_key_file='~/.ssh/id_rsa'
```

### 第三步：修改 K8S 配置（可选）

编辑 `config/group_vars/k8s-cluster.yml`：

```yaml
container_manager: containerd
deepops_gpu_operator_enabled: true
gpu_operator_preinstalled_nvidia_software: true
k8s_gpu_mig_strategy: "mixed"
k8s_nfs_client_provisioner: true
kube_enable_rsyslog_server: true
```

### 第四步：验证连通性

```bash
ansible all -m raw -a "hostname"
```

### 第五步：部署集群

```bash
ansible-playbook playbooks/k8s-cluster.yml
```

如需密码认证添加 `-k -K` 参数。

### 第六步：验证

```bash
kubectl get nodes
export CLUSTER_VERIFY_EXPECTED_PODS=2
./scripts/k8s/verify_gpu.sh
kubectl get pods -A
```

**预期输出**:
```
NVIDIA-SMI 580.167.08     Driver Version: 580.167.08     CUDA Version: 13.0
GPU: NVIDIA GeForce GTX 1050 (2GB, Pascal)
1 / 1 GPU Jobs COMPLETED
```

---

## 部署后验证 ✅

集群部署完成后，按以下步骤逐一验证：

### 1. 节点状态

```bash
kubectl get nodes -o wide
# 预期: 所有节点 Status=Ready, ROLES 包含 control-plane / worker
```

### 2. GPU 资源识别

```bash
kubectl describe nodes | grep -A3 "nvidia.com/gpu"
# 预期: nvidia.com/gpu: 1 (或等于你的 GPU 数量)
```

### 3. GPU Operator 组件状态

```bash
kubectl get pods -n gpu-operator -o wide
```

**预期状态（所有 Running 或 Completed）**:

| Pod 名称 | 状态 | 说明 |
|----------|------|------|
| gpu-operator-* | Running | 控制器 |
| nvidia-device-plugin-daemonset-* | Running | 每个 GPU 节点一个 |
| nvidia-container-toolkit-daemonset-* | Running | 容器运行时集成 |
| gpu-feature-discovery-* | Running | GPU 特征发现 |
| nvidia-dcgm-exporter-* | Running | 监控导出器 |
| nvidia-operator-validator-* | Running | 验证器 |
| nvidia-cuda-validator-* | Completed | CUDA 验证通过 |

> ⚠️ **已知问题**: `node-feature-discovery-worker` 在非 master 节点上可能 CrashLoopBackOff，不影响 GPU 功能。

### 4. GPU 功能测试

```bash
# 方法一：DeepOps 内置脚本（推荐）
./scripts/k8s/verify_gpu.sh

# 方法二：手动测试
kubectl run gpu-test --image=nvidia/cuda:12.0.0-base-ubuntu22.04 --rm -it --restart=Never -- nvidia-smi

# 方法三：查看 GPU 标签
kubectl get nodes --show-labels | grep nvidia.com
```

### 5. StorageClass 检查（部署可选组件前必须）

```bash
kubectl get sc
# 如果没有输出，需要先部署 NFS:
ansible-playbook playbooks/k8s-cluster/nfs-client-provisioner.yml
```

### 6. 防火墙检查（kubelet 日志访问）

```bash
# 在所有工作节点上执行
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --reload

# 从 master 验证
kubectl logs <pod-name> -n <namespace>
```

---

## 配置说明

### 核心配置文件

| 文件 | 用途 |
|------|------|
| `config/inventory` | 定义集群节点和分组 |
| `config/group_vars/all.yml` | 全局变量（代理等） |
| `config/group_vars/k8s-cluster.yml` | K8S 专用配置 |

### GPU Operator 关键变量

位置: roles/nvidia-gpu-operator/defaults/main.yml

| 变量 | 默认值 | 说明 |
|------|--------|------|
| gpu_operator_chart_version | v26.3.1 | Helm Chart 版本 |
| gpu_operator_driver_version | 580.126.20 | NVIDIA 驱动版本 |
| gpu_operator_default_runtime | containerd | 容器运行时 |
| gpu_operator_enable_dcgm | false | DCGM 监控 |
| gpu_operator_enable_migmanager | true | MIG 管理 |

### K8S 集群关键变量

位置: config/group_vars/k8s-cluster.yml

| 变量 | 默认值 | 说明 |
|------|--------|------|
| container_manager | containerd | 容器运行时 |
| deepops_gpu_operator_enabled | true | 启用 GPU Operator |
| gpu_operator_preinstalled_nvidia_software | true | 使用主机预装驱动 |
| k8s_gpu_mig_strategy | mixed | MIG 策略 |
| k8s_nfs_client_provisioner | true | NFS 存储 |
| dashboard_enabled | true | Dashboard |
| kube_enable_rsyslog_server | true | 日志服务端 |

---

## 集群管理

### 添加节点

```bash
# 编辑 config/inventory 添加新节点后运行:
ansible-playbook submodules/kubespray/scale.yml
```

### 移除节点

```bash
ansible-playbook submodules/kubespray/remove-node.yml --extra-vars "node=主机名"
```

### 重置集群

```bash
ansible-playbook submodules/kubespray/reset.yml
```

### 远程访问

```bash
./scripts/k8s/setup_remote_k8s.sh
kubectl get nodes
```

---

## GPU 支持

### 部署流程

```
playbooks/k8s-cluster.yml
  |-- nvidia-software/nvidia-driver.yml     # 安装主机驱动
  |-- k8s-cluster/nvidia-gpu-operator.yml    # Helm 部署 GPU Operator
  |     |-- roles/nvidia-gpu-operator/
  |           |-- tasks/k8s.yml              # helm upgrade --install
  |-- 生成的 K8S 组件:
        |-- nvidia-device-plugin-daemonset   # GPU 设备分配
        |-- nvidia-container-toolkit-daemonset # 运行时集成
        |-- gpu-feature-discovery-daemonset  # 特征发现
        |-- nvidia-mig-manager               # MIG 管理
```

### 方案对比

| 特性 | GPU Operator（推荐） | 传统 Device Plugin |
|------|---------------------|-------------------|
| 部署方式 | Helm Chart 一键 | DaemonSet 手动 |
| 驱动管理 | 自动化容器 | 主机预装 |
| MIG 支持 | 内置 | 需手动配置 |
| Feature Discovery | 内置 GFD | 单独部署 |

### 验证 GPU

```bash
./scripts/k8s/verify_gpu.sh
kubectl describe nodes | grep nvidia.com/gpu
```

---

## 可选组件

| 组件 | 命令 | 访问地址 |
|------|------|----------|
| Dashboard | kubectl apply -f dashboard-nodeport.yaml | https://node:30444 |
| 监控栈 | helm install kube-prometheus-stack | Grafana :30200 / Prometheus :30500 / Alertmanager :30400 |
| NFS 存储 | playbooks/k8s-cluster/nfs-client-provisioner.yml | SC: nfs-client |
| Kubeflow | ./scripts/k8s/deploy_kubeflow.sh | 见文档 |
| Ingress | helm install ingress-nginx | HTTP :30080 / HTTPS :30443 |
| LoadBalancer | ./scripts/k8s/deploy_loadbalancer.sh | MetalLB |
| Ceph | ./scripts/k8s/deploy_rook.sh | 已废弃 |

### 监控栈地址

| 服务 | URL | 说明 |
|------|-----|------|
| Grafana | http://node:30200 | 用户: admin / 密码: deepops |
| Prometheus | http://node:30500 | Prometheus 监控面板 |
| Alertmanager | http://node:30400 | Alertmanager 告警面板 |

### Kubernetes Dashboard

#### 📋 访问方式（推荐：局域网 Port-Forward）

**访问地址**: `https://192.168.0.200:8443` (HTTPS)

> ⚠️ **重要**: NodePort 30444 可能因 kube-proxy 问题无法直接使用，推荐使用 Port-Forward 方式。

##### 方法一：Port-Forward（推荐，稳定可靠）

```bash
# 1. 使用 Screen 创建持久化端口转发
screen -dmS k8s-dashboard bash -c "kubectl port-forward svc/kubernetes-dashboard 8443:443 -n kubernetes-dashboard --address 0.0.0.0; exec bash"

# 2. 等待 3 秒让服务启动
sleep 3

# 3. 验证端口监听
ss -tlnp | grep 8443
# 输出: LISTEN 0  4096  0.0.0.0:8443  0.0.0.0:*  users:(("kubectl",pid=XXXX,fd=7))

# 4. 局域网任意机器浏览器访问
# https://192.168.0.200:8443
```

**Screen 管理命令**:
```bash
# 查看 Screen 会话
screen -ls

# 进入会话（查看日志）
screen -r k8s-dashboard

# 退出会话（Ctrl+A, D）
# 终止会话
screen -S k8s-dashboard -X quit
```

##### 方法二：NodePort 直接访问（需要 kube-proxy 正常工作）

```bash
# 检查 NodePort 是否监听
ss -tlnp | grep 30444

# 如果未监听，检查 kube-proxy
kubectl get pods -n kube-system | grep kube-proxy

# 访问地址: https://192.168.0.200:30444
```

##### 方法三：kubectl proxy（仅本机访问）

```bash
# 启动代理
kubectl proxy --port=8001 --address='127.0.0.1' --accept-hosts='^*$' &

# 本机浏览器访问
http://127.0.0.1:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

#### 🔐 登录认证（Token 方式）

**步骤 1**: 获取 Token

```bash
# 创建管理员 ServiceAccount（如果不存在）
kubectl create serviceaccount admin-user -n kubernetes-dashboard 2>/dev/null || true

# 创建 ClusterRoleBinding（授权管理员权限）
kubectl create clusterrolebinding admin-user-binding \
  --clusterrole=admin \
  --serviceaccount=kubernetes-dashboard:admin-user \
  2>/dev/null || true

# 生成 Token（有效期 365 天）
TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard --duration=8760h)

# 显示 Token
echo "$TOKEN"

# 复制完整 Token 到剪贴板或保存到文件
echo "$TOKEN" > /tmp/dashboard-token.txt
cat /tmp/dashboard-token.txt
```

**步骤 2**: 浏览器登录

1. 打开 `https://192.168.0.200:8443`
2. 选择 **"Token"** 登录选项
3. 将上面生成的完整 Token 粘贴到输入框
4. 点击 **"Sign in"** 按钮
5. ✅ 成功进入 Dashboard 主界面

#### 📊 Dashboard 功能模块

登录成功后，你可以看到以下功能：

| 模块 | 说明 |
|------|------|
| **集群概览** | 节点状态、资源使用率、Pod 数量 |
| **工作负载** | Deployments、Pods、ReplicaSets、DaemonSets |
| **服务与网络** | Services、Ingress、NetworkPolicies |
| **存储** | PersistentVolumes、PersistentVolumeClaims、StorageClasses |
| **配置** | ConfigMaps、Secrets |
| **命名空间管理** | 切换和创建命名空间 |

#### ⚠️ 常见问题排查

**问题 1: 403 Forbidden**

```bash
# 原因: 缺少 RBAC 权限
# 解决方案:
kubectl create clusterrolebinding admin-user-binding \
  --clusterrole=admin \
  --serviceaccount=kubernetes-dashboard:admin-user

# 验证权限
kubectl auth can-i create pods --all-namespaces \
  --as=system:serviceaccount:kubernetes-dashboard:admin-user
# 应输出: yes
```

**问题 2: Connection Refused（端口未监听）**

```bash
# 检查 port-forward 进程是否运行
ps aux | grep "port-forward.*kubernetes-dashboard"
ss -tlnp | grep 8443

# 如果未运行，重新启动
screen -dmS k8s-dashboard bash -c "kubectl port-forward svc/kubernetes-dashboard 8443:443 -n kubernetes-dashboard --address 0.0.0.0; exec bash"
sleep 3 && ss -tlnp | grep 8443
```

**问题 3: SSL 证书警告**

```bash
# 浏览器显示证书不安全是正常的（自签名证书）
# 选择"高级" → "继续前往 192.168.0.200(不安全)"
# 或使用 curl -k 忽略证书验证
curl -k https://192.168.0.200:8443
```

**问题 4: Token 过期**

```bash
# 默认 Token 有效期较短，建议使用 --duration=8760h (365天)
TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard --duration=8760h)
echo $TOKEN
```

#### 📁 相关文件

| 文件/资源 | 说明 |
|-----------|------|
| Dashboard Service | `kubernetes-dashboard` in namespace `kubernetes-dashboard` |
| Admin SA | `admin-user` in namespace `kubernetes-dashboard` |
| ClusterRoleBinding | `admin-user-binding` (cluster-admin 权限) |
| Deployment 文件 | `/home/new/deepops/dashboard-nodeport.yaml` |

#### 💡 最佳实践

1. **生产环境安全**: 使用 Ingress + HTTPS + RBAC 限制访问
2. **持久化 Token**: 设置较长的有效期（如 365 天）避免频繁重新登录
3. **Screen 管理**: 使用 screen/tmux 保持 port-forward 进程稳定运行
4. **防火墙规则**: 确保 8443 端口对局域网开放（当前 firewalld 已关闭，无需额外配置）
5. **定期轮换 Token**: 安全考虑下定期重新生成 Token

### Ingress Controller

| 项目 | 值 |
|------|-----|
| HTTP 端口 | node:30080 |
| HTTPS 端口 | node:30443 |
| 部署命令 | helm install ingress-nginx ingress-nginx/ingress-nginx -n deepops-ingress --create-namespace |

---

## 故障排查

### 常见问题（已验证）

#### 1. CUDA 仓库 404 错误

**症状**: `Failed to download metadata for repo 'cuda': Cannot download repomd.xml: 404`

**原因**: 旧配置使用了错误的路径 `/nvidia/cuda/`（不存在）

**解决方案**: 已修复为 `developer.download.nvidia.cn/compute/cuda/`。手动处理：

```bash
# 检查当前 repo 内容
cat /etc/yum.repos.d/cuda.repo

# 如果路径错误，清理后重新运行 playbook
sudo rm /etc/yum.repos.d/cuda.repo
sudo dnf clean all

# 或手动测试正确 URL
curl -sI "https://developer.download.nvidia.cn/compute/cuda/repos/rhel9/x86_64/repodata/repomd.xml"
```

#### 2. CUDA 包名不存在

**症状**: `No package cuda-toolkit-13-0-2 available.`

**原因**: 包名格式错误，特定版本包可能不存在

**解决方案**: 已改为通用包名 `cuda-toolkit`（自动安装最新版）

#### 3. Helm Stable 仓库超时

**症状**: `context deadline exceeded` for `charts.helm.sh/stable`

**原因**: Helm Stable 仓库已于 2020 年 11 月废弃，中国大陆无法访问

**解决方案**: 已在 playbook 中添加 `ignore_errors: yes`，不影响功能

#### 4. GPU Operator Helm 仓库超时

**症状**: `UPGRADE FAILED: context deadline exceeded`

**原因**: NGC 仓库 (`helm.ngc.nvidia.com`) 需要 API Key 认证且网络不稳定

**解决方案**: 已改为 GitHub Pages 公开仓库 (`nvidia.github.io/gpu-operator`)，无需认证

```bash
# 验证新仓库可用性
helm repo add nvidia https://nvidia.github.io/gpu-operator
helm search repo nvidia/gpu-operator
```

#### 5. Helm 安装超时（GPU Operator / NFS Client Provisioner）

**症状**: `Error: context deadline exceeded` 或 `UPGRADE FAILED: context deadline exceeded`

**原因**: DeepOps 默认使用 `--wait` 参数，超时仅 **5 分钟**。但 Helm Chart 需要拉取镜像：
- **GPU Operator**: 从 `nvcr.io` 拉取多个大容器（device-plugin、toolkit、validator 等）
- **NFS Client Provisioner**: 从 `registry.k8s.io` 拉取 `nfs-subdir-external-provisioner`

**解决方案**: 已将所有 Helm 命令从 `--wait` 改为 `--timeout 30m`（30 分钟）

**修改的文件**:
```
roles/nvidia-gpu-operator/tasks/k8s.yml              # 第 22 行
roles/nfs-client-provisioner/tasks/main.yml           # 第 14 行
```

如果仍然超时，可以手动预拉取镜像：

```bash
# GPU Operator 相关镜像（在所有节点执行）
sudo podman pull nvcr.io/nvidia/k8s-device-plugin:latest
sudo podman pull nvcr.io/nvidia/container-toolkit:latest

# NFS Client Provisioner 镜像
sudo podman pull registry.k8s.io/sig-storage/nfs-subdir-external-provisioner:v4.0.13
```

#### 6. Node Feature Discovery Worker 崩溃

**症状**: `node-feature-discovery-worker` 在 gpu01/gpu02 上 CrashLoopBackOff

**影响**: ❌ **无影响**——master 节点上的 NFD 正常工作，GPU 标签已正确识别

**原因**: kubelet 端口 (10250) 未开放或网络问题

**修复方法**:

```bash
# 在工作节点上开放防火墙
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --reload
```

#### 7. kubectl logs 无法获取日志

**症状**: `dial tcp <node-ip>:10250: connect: no route to host`

**原因**: 同上，kubelet API 端口未开放

**解决**: 见第 6 条

#### 8. 缺少 StorageClass

**症状**: `No storageclass found` when deploying monitoring/Kubeflow

**解决方案**:

```bash
# 部署 NFS Client Provisioner
ansible-playbook playbooks/k8s-cluster/nfs-client-provisioner.yml

# 验证
kubectl get sc
# 预期输出:
# NAME         PROVISIONER   RECLAIMPOLICY   VOLUMEBINDINGMODE
# nfs-client   nfs-client    Delete          Immediate
```

#### 9. firewall-cmd Python 错误

**症状**: `ModuleNotFoundError: No module named 'gi'`

**原因**: Rocky Linux 9 上 firewalld 的 Python 依赖缺失

**解决方案**: 不影响功能，可忽略或重装 python3-gobject

---

### 实时监控命令

```bash
# 监控 GPU Operator Pod 状态（推荐）
watch -n 5 'kubectl get pods -n gpu-operator -o wide'

# 查看 GPU Operator 控制器日志
kubectl logs -f -n gpu-operator -l app.kubernetes.io/name=gpu-operator

# 查看某个 Pod 的详细事件
kubectl describe pod <pod-name> -n gpu-operator | tail -30

# 查看集群事件
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# 查看 NVIDIA 相关资源
kubectl get all -n gpu-operator
```

### Playbook 执行调试

```bash
# 详细模式（显示每个任务详情）
ansible-playbook playbooks/k8s-cluster.yml -v

# 更详细（显示每个命令输出）
ansible-playbook playbooks/k8s-cluster.yml -vvv

# 只执行特定 tag（如只部署 GPU 相关）
ansible-playbook playbooks/k8s-cluster.yml --tags nvidia

# 只执行特定 tag（如只初始化引导）
ansible-playbook playbooks/k8s-cluster.yml --tags bootstrap

# 跳过特定 tag
ansible-playbook playbooks/k8s-cluster.yml --skip-tags nfs

# 限制目标主机
ansible-playbook playbooks/k8s-cluster.yml -l master,gpu01

# Dry Run（不实际执行变更）
ansible-playbook playbooks/k8s-cluster.yml --check
```

### K8S 常用排查命令

```bash
# 节点状态
kubectl get nodes -o wide

# 所有 Pod 状态（筛选非 Running）
kubectl get pods -A | grep -v Running

# GPU 资源分配
kubectl describe nodes | grep -i "nvidia.com/gpu"

# 容器运行时信息
crictl ps
crictl info

# 网络排查
kubectl run test-net --image=busybox --rm -it -- nslookup kubernetes.default
```

---

## 项目结构

```
deepops/
|-- playbooks/
|   |-- k8s-cluster.yml              # 主 playbook
|   |-- k8s-cluster/
|       |-- nvidia-gpu-operator.yml  # GPU Operator
|       |-- nfs-client-provisioner.yml
|       |-- container-registry.yml
|       |-- netapp-trident.yml
|-- roles/
|   |-- nvidia-gpu-operator/          # GPU Operator 角色
|   |-- nvidia_cuda/                  # CUDA Toolkit
|   |-- galaxy/nvidia.nvidia_driver/  # NVIDIA 驱动
|-- scripts/k8s/
|   |-- setup_remote_k8s.sh
|   |-- install_helm.sh
|   |-- verify_gpu.sh
|   |-- deploy_monitoring.sh
|   |-- deploy_dashboard_user.sh
|   |-- deploy_kubeflow.sh
|-- config.example/                    # 示例配置
|-- config/                            # 实际配置（setup.sh 生成）
|   |-- inventory
|   |-- group_vars/*.yml
|   |-- artifacts/                     # K8S 证书等
|-- docs/k8s-cluster/                  # 详细文档
```

---

## 相关链接

- [DeepOps README](README.md)
- [Kubespray 文档](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/getting-started.html)
- [官方详细指南](docs/k8s-cluster/README.md)

---

## 快速参考卡 📋

### 部署顺序

```
1. ./scripts/setup.sh                          # 初始化环境
2. 编辑 config/inventory                       # 配置节点
3. ansible-playbook playbooks/k8s-cluster.yml   # 部署 K8S + GPU（含 GPU Operator）
4. kubectl get nodes                            # 验证集群
5. ./scripts/k8s/verify_gpu.sh                 # 验证 GPU
6. kubectl get sc                               # 检查 StorageClass
   └─ 如无输出 → ansible-playbook playbooks/k8s-cluster/nfs-client-provisioner.yml
7. ./scripts/k8s/deploy_monitoring.sh           # 监控栈（需 StorageClass）
8. ./scripts/k8s/deploy_kubeflow.sh            # Kubeflow（需 StorageClass）
```

### 关键端口

| 端口 | 服务 | 必要性 |
|------|------|--------|
| 6443 | Kubernetes API Server | 必须 |
| 2379-2380 | etcd | 必须 |
| 10250 | kubelet | **必须**（日志访问） |
| 30200 | Grafana | 可选 |
| 30500 | Prometheus | 可选 |
| 30443 | Dashboard | 可选 |

### 常用命令速查

```bash
# 集群状态
kubectl get nodes -o wide
kubectl get pods -A
kubectl get sc

# GPU 相关
kubectl get pods -n gpu-operator -o wide
./scripts/k8s/verify_gpu.sh

# 日志查看
kubectl logs -f <pod> -n <namespace>
kubectl describe pod <pod> -n <namespace>

# 监控
watch -n 5 'kubectl get pods -n gpu-operator'
```

---

**文档版本**: 2026-06-25 v2 (基于实际部署验证，新增 Helm 超时修复)