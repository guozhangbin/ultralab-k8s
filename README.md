# Kubernetes Dashboard 局域网访问指南

> **适用环境**: DeepOps K8S 集群 / Rocky Linux 9.x / Kubernetes Dashboard v2.7+
> **最后更新**: 2026-07-01

---

## 📋 目录

- [快速开始](#快速开始)
- [访问方式详解](#访问方式详解)
- [认证与授权](#认证与授权)
- [功能模块介绍](#功能模块介绍)
- [常见问题排查](#常见问题排查)
- [高级配置](#高级配置)
- [安全最佳实践](#安全最佳实践)

---

## 快速开始

### ✅ 一键启动脚本

```bash
#!/bin/bash
# 文件: start-dashboard.sh

echo "=== 启动 Kubernetes Dashboard 局域网访问 ==="

# 1. 创建管理员 ServiceAccount（如果不存在）
kubectl create serviceaccount admin-user -n kubernetes-dashboard 2>/dev/null || true

# 2. 授权管理员权限
kubectl create clusterrolebinding admin-user-binding \
  --clusterrole=admin \
  --serviceaccount=kubernetes-dashboard:admin-user \
  2>/dev/null || true

# 3. 使用 Screen 持久化 Port-Forward
screen -dmS k8s-dashboard bash -c "kubectl port-forward svc/kubernetes-dashboard 8443:443 -n kubernetes-dashboard --address 0.0.0.0; exec bash"

# 4. 等待服务启动
sleep 3

# 5. 验证端口监听
if ss -tlnp | grep -q ":8443"; then
    echo "✅ Dashboard 已启动"
    echo "📍 访问地址: https://192.168.0.200:8443"
    echo ""
    echo "=== 获取登录 Token ==="
    TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard --duration=8760h)
    echo "$TOKEN" > /tmp/dashboard-token.txt
    echo "Token 已保存到: /tmp/dashboard-token.txt"
    echo ""
    cat /tmp/dashboard-token.txt
else
    echo "❌ 启动失败，请检查日志"
    screen -r k8s-dashboard
fi
```

**使用方法**:
```bash
chmod +x start-dashboard.sh
./start-dashboard.sh
```

### 🚀 最快访问方式（3 步）

```bash
# Step 1: 启动端口转发
screen -dmS k8s-dashboard bash -c "kubectl port-forward svc/kubernetes-dashboard 8443:443 -n kubernetes-dashboard --address 0.0.0.0; exec bash"

# Step 2: 等待并验证
sleep 3 && ss -tlnp | grep 8443

# Step 3: 获取 Token 并访问浏览器
TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard --duration=8760h) && echo $TOKEN
# 浏览器打开: https://192.168.0.200:8443 → 选择 "Token" 登录
```

---

## 访问方式详解

### 方法一：Port-Forward + Screen（推荐 ⭐）

**优点**: 稳定可靠、支持局域网、进程持久化、易于管理

#### 前置条件

```bash
# 检查是否安装 screen
which screen || sudo dnf install -y screen

# 检查 Dashboard 服务状态
kubectl get svc kubernetes-dashboard -n kubernetes-dashboard
# 预期输出:
# NAME                   TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)         AGE
# kubernetes-dashboard   NodePort   10.233.61.211   <none>        443:30444/TCP   45h
```

#### 启动步骤

```bash
# 1. 创建 Screen 会话并运行 port-forward
screen -dmS k8s-dashboard bash -c "kubectl port-forward svc/kubernetes-dashboard 8443:443 -n kubernetes-dashboard --address 0.0.0.0; exec bash"

# 2. 等待 2-3 秒让服务初始化
sleep 3

# 3. 验证端口是否监听
ss -tlnp | grep 8443
# 成功输出示例:
# LISTEN 0      4096         0.0.0.0:8443       0.0.0.0:*    users:(("kubectl",pid=417421,fd=7))

# 4. 测试连接（从本机）
curl -k -I https://192.168.0.200:8443 | head -5
# 预期输出: HTTP/2 200
```

#### 访问地址

```
局域网任意机器浏览器访问: https://192.168.0.200:8443
```

> **注意**: 
> - `192.168.0.200` 是 Master 节点 IP（可通过 `hostname -I | awk '{print $1}'` 获取）
> - `8443` 是本地转发端口（映射到 Dashboard 的 443 端口）
> - 使用 HTTPS 协议（Dashboard 内部是 TLS 加密）

#### Screen 会话管理

```bash
# 查看所有 Screen 会话
screen -ls
# 输出示例:
# There is a screen on:
#     417420.k8s-dashboard    (Detached)

# 进入会话查看实时日志
screen -r k8s-dashboard

# 从会话中分离（不关闭）: 按 Ctrl+A, 然后 D

# 终止会话
screen -S k8s-dashboard -X quit

# 发送命令到会话（不进入）
screen -S k8s-dashboard -X stuff "echo 'test'\n"
```

#### 故障排查

**问题**: 端口未监听
```bash
# 检查进程是否存在
ps aux | grep "port-forward.*kubernetes-dashboard" | grep -v grep

# 如果不存在，重新启动
screen -dmS k8s-dashboard bash -c "kubectl port-forward svc/kubernetes-dashboard 8443:443 -n kubernetes-dashboard --address 0.0.0.0; exec bash"
sleep 3 && ss -tlnp | grep 8443
```

**问题**: 连接被拒绝
```bash
# 检查防火墙（当前环境 firewalld 已关闭）
sudo systemctl status firewalld

# 如果开启，需要开放 8443 端口
sudo firewall-cmd --permanent --add-port=8443/tcp
sudo firewall-cmd --reload
```

---

### 方法二：NodePort 直接访问

**优点**: 无需额外进程、原生 K8S 功能  
**缺点**: 依赖 kube-proxy 正常工作、可能存在网络问题

#### 检查 NodePort 是否可用

```bash
# 查看 Service 配置
kubectl get svc kubernetes-dashboard -n kubernetes-dashboard -o wide
# 输出:
# NAME                   TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)         AGE
# kubernetes-dashboard   NodePort   10.233.61.211   <none>        443:30444/TCP   45h

# 检查 Endpoints（Pod 是否正常）
kubectl get endpoints kubernetes-dashboard -n kubernetes-dashboard
# 预期输出:
# NAME                   ENDPOINTS            AGE
# kubernetes-dashboard   10.233.70.204:8443   45h

# 检查各节点端口监听情况
for ip in $(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'); do
    echo -n "Node $ip: "
    timeout 2 bash -c "echo >/dev/tcp/$ip/30444" 2>/dev/null && echo "✅ 开放" || echo "❌ 未监听"
done
```

#### 如果 NodePort 未监听（常见问题）

**原因分析**:

| 可能原因 | 检查方法 |
|----------|----------|
| kube-proxy 异常 | `kubectl get pods -n kube-system \| grep kube-proxy` |
| iptables 规则冲突 | `iptables -L -n \| head -20` |
| Pod 未运行 | `kubectl get pods -n kubernetes-dashboard` |
| External Traffic Policy | 检查 Service 配置 |

**解决方案**:

```bash
# 方案 A: 重启 kube-proxy（谨慎操作）
kubectl rollout restart daemonset/kube-proxy -n kube-system

# 方案 B: 改用 Port-Forward（推荐）
# 见方法一

# 方案 C: 修改 Service 为 LoadBalancer（如果有 MetalLB）
kubectl patch svc kubernetes-dashboard -n kubernetes-dashboard -p '{"spec":{"type":"LoadBalancer"}}'
```

#### 访问地址（如果 NodePort 可用）

```
https://<任意节点IP>:30444
例如: https://192.168.0.200:30444 或 https://192.168.0.201:30444
```

---

### 方法三：kubectl Proxy（仅本机访问）

**优点**: 无需额外配置、官方推荐  
**缺点**: 仅限本机 127.0.0.1 访问、不适合局域网共享

#### 启动步骤

```bash
# 后台运行 proxy
kubectl proxy --port=8001 --address='127.0.0.1' --accept-hosts='^*$' &

# 验证
curl http://127.0.0.1:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

#### 访问地址

```
http://127.0.0.1:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

> **注意**: 此方法只能在本机（Master 节点）的浏览器访问，其他机器无法连接。

---

## 认证与授权

### 🔐 登录方式对比

| 方式 | 适用场景 | 安全性 | 复杂度 |
|------|----------|--------|--------|
| **Token**（推荐）| 生产环境、自动化脚本 | ⭐⭐⭐⭐⭐ | 低 |
| Kubeconfig | 开发调试 | ⭐⭐⭐⭐ | 中 |

### Token 认证完整流程

#### Step 1: 创建 ServiceAccount（一次性操作）

```bash
# 查看是否已存在
kubectl get sa admin-user -n kubernetes-dashboard 2>/dev/null && echo "已存在" || kubectl create serviceaccount admin-user -n kubernetes-dashboard

# 验证创建成功
kubectl describe sa admin-user -n kubernetes-dashboard | head -15
# 输出应包含:
# Name:                admin-user
# Namespace:           kubernetes-dashboard
```

#### Step 2: 授予集群管理员权限（一次性操作）

```bash
# 创建 ClusterRoleBinding（绑定 admin 角色）
kubectl create clusterrolebinding admin-user-binding \
  --clusterrole=admin \
  --serviceaccount=kubernetes-dashboard:admin-user

# 验证权限
kubectl auth can-i create pods --all-namespaces \
  --as=system:serviceaccount:kubernetes-dashboard:admin-user
# 应输出: yes

# 测试更多权限
kubectl auth can-i '*' '*' --all-namespaces \
  --as=system:serviceaccount:kubernetes-dashboard:admin-user
# 应输出: yes
```

**RBAC 权限说明**:

```yaml
# ClusterRoleBinding 结构解析
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user-binding
subjects:
  - kind: ServiceAccount
    name: admin-user          # ServiceAccount 名称
    namespace: kubernetes-dashboard  # 所在命名空间
roleRef:
  kind: ClusterRole
  name: admin                 # 绑定角色: admin（拥有几乎所有权限）
  apiGroup: rbac.authorization.k8s.io
```

**可选角色列表**:

| 角色 | 权限范围 | 适用场景 |
|------|----------|----------|
| `cluster-admin` | 超级管理员（完全控制） | 生产环境管理员 |
| `admin` | 命名空间管理（除资源配额外） | **推荐 ✅** |
| `edit` | 读写资源（除 RBAC 和资源配额） | 开发人员 |
| `view` | 只读权限 | 只读监控 |

#### Step 3: 生成 Token（定期或首次登录时）

```bash
# 生成 Token（有效期 365 天 = 8760 小时）
TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard --duration=8760h)

# 显示 Token
echo "$TOKEN"

# 保存到文件（方便后续使用）
echo "$TOKEN" > /tmp/dashboard-token.txt
chmod 600 /tmp/dashboard-token.txt

# 查看保存的 Token
cat /tmp/dashboard-token.txt
```

**Token 有效期选项**:

| 时长 | 参数值 | 适用场景 |
|------|--------|----------|
| 1 小时 | 默认（不加参数） | 安全敏感环境 |
| 24 小时 | `--duration=24h` | 日常开发 |
| 7 天 | `--duration=168h` | 短期项目 |
| 30 天 | `--duration=720h` | 中期项目 |
| **365 天** | **`--duration=8760h`** | **推荐 ✅** |
| 不过期 | ❌ 不支持 | K8S 安全限制 |

#### Step 4: 浏览器登录

1. **打开 URL**: https://192.168.0.200:8443
2. **处理 SSL 警告**:
   - Chrome/Edge: 点击 "高级" → "继续前往 192.168.0.200(不安全)"
   - Firefox: 点击 "高级..." → "接受风险并继续"
3. **选择登录方式**: 点击 "Token" 选项卡
4. **粘贴 Token**: 将上面生成的完整 Token 粘贴到输入框
5. **登录**: 点击 "Sign in" 按钮
6. **成功**: 进入 Dashboard 主界面 🎉

#### Token 格式说明

> ⚠️ **安全提醒**: 
> - **不要**将真实 Token 提交到 Git 仓库或公开分享
> - Token 包含集群管理员权限，泄露会导致安全风险
> - 每次生成的 Token 都不同，请使用自己的 Token

**Token 结构示例**（仅展示格式，非真实 Token）:

```
eyJhbGciOiJSUzI1NiIsImtpZCI6Ij<...省略...>.eyJhdWQiOlsia3ViZXJuZXRlcz<...省略...>.<数字签名>
```

**Token 组成部分**:
```
Header.Payload.Signature

Header:     {"alg":"RS256","typ":"JWT","kid":"xxx"}        # 算法和类型
Payload:    {"sub":"system:serviceaccount:kubernetes-dashboard:admin-user", "exp":1814428500}  # 用户信息和过期时间
Signature:  XvXsk6XKv95dHEtz-Jp9T<...>                      # RSA 签名（防篡改）
```

**获取你的 Token**:
```bash
# 运行此命令生成你自己的 Token（不要使用他人的）
TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard --duration=8760h)
echo "$TOKEN"
# 复制输出的完整字符串到浏览器登录框
```

---

## 功能模块介绍

### 🎛️ Dashboard 主界面布局

登录成功后，你会看到以下主要区域：

```
┌─────────────────────────────────────────────────────────────┐
│  顶部导航栏: Overview │ Workloads │ Discovery │ Config ...  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  左侧边栏              │        主内容区                    │
│  ├─ Namespaces         │  ┌──────────────────────────┐     │
│  ├─ Cluster            │  │  集群概览卡片             │     │
│  │  └─ Nodes           │  │  • 节点数: 3             │     │
│  │  └─ Namespaces      │  │  • Pods: 25              │     │
│  ├─ Workloads          │  │  • CPU: 45%              │     │
│  │  └─ Deployments     │  │  • Memory: 60%           │     │
│  │  └─ Pods            │  └──────────────────────────┘     │
│  │  └─ ReplicaSets     │                                   │
│  ├─ Discovery          │  工作负载列表                     │
│  │  └─ Services        │  └──────────────────────────┘     │
│  │  └─ Ingresses       │                                   │
│  └─ Config             │                                   │
│     └─ ConfigMaps      │                                   │
│     └─ Secrets         │                                   │
└─────────────────────────────────────────────────────────────┘
```

### 核心功能模块详解

#### 1️⃣ Overview（概览）

**用途**: 集群整体健康状态一目了然

**展示信息**:
- 🖥️ **节点状态**: Ready / NotReady 数量
- 📦 **工作负载统计**: Deployments, Pods, ReplicaSets 数量
- 💾 **资源使用率**: CPU、Memory 实时图表
- 🔄 **最近事件**: Warning/Error 日志

**常用操作**:
- 点击节点名称查看详细信息
- 切换命名空间过滤显示内容
- 刷新按钮更新实时数据

#### 2️⃣ Workloads（工作负载）

**子菜单**:
| 子模块 | 说明 | 操作 |
|--------|------|------|
| **Deployments** | 无状态应用部署 | 创建、扩缩容、更新、回滚 |
| **StatefulSets** | 有状态应用（数据库等） | 创建、管理有序部署 |
| **DaemonSets** | 每个节点运行的 Pod（日志收集等） | 创建、更新 |
| **ReplicaSets** | Pod 副本控制器 | 查看（通常由 Deployment 管理）|
| **Jobs** | 一次性任务 | 创建、查看日志 |
| **CronJobs** | 定时任务 | 创建、编辑调度规则 |
| **Pods** | 最小部署单元 | **最常用** ✅ |

**Pods 管理（重点）**:

```bash
# Dashboard 中可以执行的操作:
# ✓ 查看 Pod 详情（容器状态、重启次数、事件）
# ✓ 查看实时日志（类似 kubectl logs -f）
# ✓ 执行命令（类似 kubectl exec -it）
# ✓ 编辑 YAML 配置
# ✓ 删除 Pod
# ✓ 查看关联的 Service、ConfigMap
```

**实际场景示例**:
```
场景 1: 应用报错排查
→ Workloads → Pods → 选择异常 Pod → Logs 标签页 → 查看错误日志

场景 2: 进入容器调试
→ Workloads → Pods → 选择 Pod → Exec 标签页 → 执行 shell 命令

场景 3: 查看资源使用
→ Workloads → Pods → Pod 详情 → Monitor 标签页 → CPU/Memory 图表
```

#### 3️⃣ Discovery（服务发现与网络）

**子菜单**:
| 子模块 | 说明 | 用途 |
|--------|------|------|
| **Services** | 服务暴露 | ClusterIP / NodePort / LoadBalancer |
| **Ingresses** | HTTP 路由 | 域名 → Service 映射 |
| **NetworkPolicies** | 网络策略 | Pod 间通信控制 |

**Services 操作示例**:
```
场景: 暴露 Nginx 应用到外部
1. Workloads → Deployments → 创建 nginx-deployment
2. Discovery → Services → Create → 选择 nginx-deployment
3. 类型选择: NodePort
4. 端口映射: 80:80
5. 通过 <NodeIP>:<NodePort> 访问
```

#### 4️⃣ Storage（存储）

**子菜单**:
| 子模块 | 说明 | 用途 |
|--------|------|------|
| **PersistentVolumes** | PV（存储卷）| 集群级别存储资源 |
| **PersistentVolumeClaims** | PVC（存储声明）| 应用申请存储 |
| **StorageClasses** | 存储类 | 动态供应策略（NFS/Ceph）|

**存储操作流程**:
```
1. Storage → StorageClasses → 查看可用存储类（如 nfs-client）
2. Storage → PersistentVolumeClaims → Create
   - 选择 StorageClass: nfs-client
   - 设置大小: 10Gi
   - 访问模式: ReadWriteOnce
3. 在 Deployment 中挂载 PVC
4. 数据持久化完成 ✅
```

#### 5️⃣ Config（配置管理）

**子菜单**:
| 子模块 | 说明 | 用途 |
|--------|------|------|
| **ConfigMaps** | 配置文件 | 环境变量、配置文件注入 |
| **Secrets** | 敏感数据 | 密码、证书、Token（Base64 编码）|

**Secrets 注意事项**:
- ⚠️ 不要在 Secret 中存储明文密码（Base64 可逆）
- ✅ 用于存储 TLS 证书、Docker Registry 凭据
- ✅ 使用 KMS 加密 etcd 中的 Secret 数据

#### 6️⃣ Namespace & Access Control

**Namespaces（命名空间）**:
- 逻辑隔离不同项目/团队
- 资源配额限制（Resource Quotas）
- 左上角下拉框快速切换

**Cluster Roles（集群角色）**:
- 查看 RBAC 配置
- 管理用户权限（需 cluster-admin 权限）
- **不建议**在 Dashboard 中修改 RBAC（易出错）

---

## 常见问题排查

### 问题 1: 403 Forbidden（禁止访问）

**症状**:
```
浏览器显示: Forbidden
curl 返回: HTTP/1.1 403 Forbidden
```

**原因分析**:
```
Timeline:
┌─────────────────────────────────────────────┐
│ 场景 A: 未提供 Token                         │
│ → Dashboard 要求身份验证                      │
│                                             │
│ 场景 B: 有 Token 但无权限                    │
│ → 缺少 ClusterRoleBinding                   │
│ → ServiceAccount 未绑定角色                  │
│                                             │
│ 场景 C: Token 过期或无效                     │
│ → Token 超过有效期限                          │
│ → Token 格式错误                             │
└─────────────────────────────────────────────┘
```

**解决方案**:

```bash
# Step 1: 验证 ServiceAccount 存在
kubectl get sa admin-user -n kubernetes-dashboard
# 如果不存在:
kubectl create serviceaccount admin-user -n kubernetes-dashboard

# Step 2: 创建/重建 ClusterRoleBinding
kubectl delete clusterrolebinding admin-user-binding 2>/dev/null || true
kubectl create clusterrolebinding admin-user-binding \
  --clusterrole=admin \
  --serviceaccount=kubernetes-dashboard:admin-user

# Step 3: 验证权限
kubectl auth can-i create pods --all-namespaces \
  --as=system:serviceaccount:kubernetes-dashboard:admin-user
# 必须输出: yes

# Step 4: 重新生成 Token
TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard --duration=8760h)
echo "新 Token: $TOKEN"

# Step 5: 用新 Token 重新登录
```

**验证清单**:
```bash
# 完整检查脚本
echo "=== 1. ServiceAccount ==="
kubectl get sa admin-user -n kubernetes-dashboard || echo "❌ 缺失"

echo "=== 2. ClusterRoleBinding ==="
kubectl get clusterrolebinding admin-user-binding || echo "❌ 缺失"

echo "=== 3. 权限测试 ==="
kubectl auth can-i create pods --all-namespaces \
  --as=system:serviceaccount:kubernetes-dashboard:admin-user || echo "❌ 无权限"

echo "=== 4. Token 有效性 ==="
TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard --duration=1h)
echo "测试 Token: ${TOKEN:0:50}..."
```

---

### 问题 2: Connection Refused（连接被拒绝）

**症状**:
```
curl: (7) Failed to connect to 192.168.0.200 port 8443: Connection refused
浏览器显示: 192.168.0.200 拒绝连接
```

**原因**: Port-Forward 进程未运行或已退出

**诊断步骤**:

```bash
# 1. 检查端口监听
ss -tlnp | grep 8443
# 如果无输出 → 进程未运行

# 2. 检查进程
ps aux | grep "port-forward.*kubernetes-dashboard" | grep -v grep
# 如果无输出 → 进程不存在

# 3. 检查 Screen 会话
screen -ls
# 如果没有 k8s-dashboard 会话 → Screen 已终止

# 4. 尝试手动运行（前台，查看错误信息）
kubectl port-forward svc/kubernetes-dashboard 8443:443 -n kubernetes-dashboard --address 0.0.0.0
# 观察是否有错误输出
```

**解决方案**:

```bash
# 方案 A: 重新启动 Screen（推荐）
screen -dmS k8s-dashboard bash -c "kubectl port-forward svc/kubernetes-dashboard 8443:443 -n kubernetes-dashboard --address 0.0.0.0; exec bash"
sleep 3 && ss -tlnp | grep 8443 && echo "✅ 重启成功"

# 方案 B: 使用 nohup（备选）
nohup kubectl port-forward svc/kubernetes-dashboard 8443:443 -n kubernetes-dashboard --address 0.0.0.0 > /tmp/k8s-dashboard.log 2>&1 &
sleep 3 && tail -f /tmp/k8s-dashboard.log

# 方案 C: 使用 systemd 服务（生产环境推荐）
# 创建 /etc/systemd/system/k8s-dashboard.service
cat > /etc/systemd/system/k8s-dashboard.service << 'EOF'
[Unit]
Description=Kubernetes Dashboard Port Forward
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/kubectl port-forward svc/kubernetes-dashboard 8443:443 -n kubernetes-dashboard --address 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable k8s-dashboard
systemctl start k8s-dashboard
systemctl status k8s-dashboard
```

**预防措施（自动重启脚本）**:

```bash
# 文件: /usr/local/bin/restart-dashboard.sh
#!/bin/bash
LOG_FILE="/var/log/dashboard-watchdog.log"

check_dashboard() {
    if ! ss -tlnp | grep -q ":8443"; then
        echo "$(date): Dashboard port not listening, restarting..." >> $LOG_FILE
        
        # 终止残留进程
        pkill -f "port-forward.*kubernetes-dashboard" 2>/dev/null || true
        
        # 重新启动
        screen -dmS k8s-dashboard bash -c "kubectl port-forward svc/kubernetes-dashboard 8443:443 -n kubernetes-dashboard --address 0.0.0.0; exec bash"
        
        sleep 3
        
        if ss -tlnp | grep -q ":8443"; then
            echo "$(date): Dashboard restarted successfully" >> $LOG_FILE
        else
            echo "$(date): Failed to restart Dashboard!" >> $LOG_FILE
        fi
    fi
}

# 每 60 秒检查一次
while true; do
    check_dashboard
    sleep 60
done
```

---

### 问题 3: SSL 证书不安全警告

**症状**:
```
Chrome: "您的连接不是私密连接"
Firefox: "警告: 潜在的安全风险"
curl: SSL certificate problem: self signed certificate
```

**原因**: Dashboard 使用自签名证书（Self-Signed Certificate）

**解决方案**:

**浏览器端**:
```
Chrome/Edge:
1. 点击 "高级"
2. 点击 "继续前往 192.168.0.200(不安全)"
3. （可选）将地址加入例外列表

Firefox:
1. 点击 "高级..."
2. 点击 "接受风险并继续"
3. 确认安全例外
```

**curl 命令行**:
```bash
# 忽略证书验证（测试用）
curl -k https://192.168.0.200:8443

# 显示证书信息
openssl s_client -connect 192.168.0.200:8443 -showcerts

# 添加到系统信任库（Linux）
echo -n | openssl s_client -connect 192.168.0.200:8443 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > /tmp/dashboard-ca.crt
sudo cp /tmp/dashboard-ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust extract
```

**说明**:
- ✅ **开发/测试环境**: 可以忽略此警告，直接继续访问
- ⚠️ **生产环境**: 建议替换为正式 CA 签发的证书（见高级配置章节）

---

### 问题 4: Token 过期或失效

**症状**:
```
Dashboard 提示: "Expired" 或 "Invalid token"
登录后立即跳转回登录页面
```

**原因**: Token 超过有效期（默认较短）

**诊断**:
```bash
# 解析 Token 过期时间（需要 jq 工具）
TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard --duration=1h)
echo $TOKEN | cut -d'.' -f2 | base64 -d 2>/dev/null | python3 -m json.tool | grep exp

# 或者使用在线工具解码 JWT
# https://jwt.io/
```

**解决方案**:

```bash
# 生成新 Token（延长有效期）
TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard --duration=8760h)
echo $TOKEN

# 更新浏览器中的 Token
```

**自动续期方案**:

```bash
# 文件: renew-token.sh（建议配合 cron 使用）
#!/bin/bash
TOKEN_FILE="/tmp/dashboard-token.txt"
MAX_AGE_DAYS=300  # 300 天后续期

# 检查 Token 文件是否存在和过期
if [ ! -f "$TOKEN_FILE" ] || [ $(find "$TOKEN_FILE" -mtime +$MAX_AGE_DAYS 2>/dev/null) ]; then
    echo "$(date): Renewing Dashboard Token..."
    
    # 生成新 Token
    NEW_TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard --duration=8760h)
    
    # 保存到文件
    echo "$NEW_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    
    echo "$(date): New Token saved to $TOKEN_FILE"
else
    echo "$(date): Token is still valid"
fi
```

**设置定时任务**:
```bash
# 编辑 crontab
crontab -e

# 添加以下行（每天凌晨 3 点检查一次）
0 3 * * * /path/to/renew-token.sh >> /var/log/token-renewal.log 2>&1
```

---

### 问题 5: 页面加载缓慢或超时

**症状**:
```
浏览器一直转圈加载
部分组件无法显示
API 调用超时
```

**可能原因及解决**:

| 原因 | 诊断 | 解决方案 |
|------|------|----------|
| **网络延迟** | `ping <master-ip>` | 检查网络连通性 |
| **Dashboard Pod 资源不足** | `kubectl top pod -n kubernetes-dashboard` | 增加 CPU/Memory 限制 |
| **etcd 压力大** | `kubectl get pods -n kube-system \| grep etcd` | 优化 etcd 性能 |
| **大量资源对象** | `kubectl get all -A \| wc -l` | 减少不必要的资源 |

**优化建议**:
```bash
# 1. 检查 Dashboard Pod 状态
kubectl describe pod -n kubernetes-dashboard -l app.kubernetes.io/name=kubernetes-dashboard

# 2. 查看资源使用
kubectl top pod -n kubernetes-dashboard

# 3. 如果资源不足，调整 Deployment
kubectl edit deployment kubernetes-dashboard -n kubernetes-dashboard
# 修改 resources.limits.cpu/memory

# 4. 清理无用资源（减少 API Server 压力）
kubectl delete deploy <unused-deployment> -n <namespace>
```

---

### 问题 6: 无法看到某些命名空间或资源

**症状**:
```
左侧命名空间下拉框缺少某些 ns
Workloads 列表为空
部分资源显示 "Forbidden"
```

**原因**: RBAC 权限不够精细

**解决方案**:

```bash
# 当前 admin 角色应该能看到所有资源
# 如果看不到，尝试使用 cluster-admin（更宽松）

kubectl delete clusterrolebinding admin-user-binding 2>/dev/null || true
kubectl create clusterrolebinding admin-user-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=kubernetes-dashboard:admin-user

# 重新登录 Dashboard
```

**自定义 Role（精细化权限）**:
```yaml
# custom-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: dashboard-custom
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "nodes", "namespaces"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dashboard-custom-binding
subjects:
  - kind: ServiceAccount
    name: admin-user
    namespace: kubernetes-dashboard
roleRef:
  kind: ClusterRole
  name: dashboard-custom
  apiGroup: rbac.authorization.k8s.io
```

---

## 高级配置

### 自定义 Dashboard 配置

#### 修改 Dashboard 参数

```bash
# 查看当前 Deployment 配置
kubectl get deployment kubernetes-dashboard -n kubernetes-dashboard -o yaml

# 编辑配置（如修改 args）
kubectl edit deployment kubernetes-dashboard -n kubernetes-dashboard
```

**常用参数**:

```yaml
spec:
  template:
    spec:
      containers:
      - args:
        - --namespace=kubernetes-dashboard  # 默认命名空间
        - --enable-skip-login               # 允许跳过登录（不安全）
        - --disable-settings-authorizer     # 禁用设置权限检查
        - --insecure-port=0                 # 禁用 HTTP（仅 HTTPS）
        - --tls-cert-file=tls.crt           # 自定义证书路径
        - --tls-key-file=tls.key            # 自定义密钥路径
```

#### 替换为正式 SSL 证书

**前置条件**: 拥有域名和 CA 签发的证书

```bash
# 1. 创建 TLS Secret
kubectl create secret tls dashboard-tls-cert \
  -n kubernetes-dashboard \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem

# 2. 修改 Deployment 挂载证书
kubectl patch deployment kubernetes-dashboard -n kubernetes-dashboard -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "kubernetes-dashboard",
          "volumeMounts": [{
            "name": "tls-cert",
            "mountPath": "/certs",
            "readOnly": true
          }]
        }],
        "volumes": [{
          "name": "tls-cert",
          "secret": {
            "secretName": "dashboard-tls-cert"
          }
        }]
      }
    }
  }
}'

# 3. 更新启动参数
kubectl set env deployment/kubernetes-dashboard -n kubernetes-dashboard \
  --containers="kubernetes-dashboard" \
  TLS_CERT_FILE=/certs/tls.crt \
  TLS_KEY_FILE=/certs/tls.key
```

**使用 Let's Encrypt 自动证书**（需要 Cert-Manager）:
```bash
# 安装 cert-manager
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.13.3 --set installCRDs=true

# 创建 Certificate 资源
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dashboard-cert
  namespace: kubernetes-dashboard
spec:
  dnsNames:
  - dashboard.yourdomain.com
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  secretName: dashboard-tls-cert
EOF
```

#### 配置 Ingress（推荐用于生产环境）

**优势**:
- ✅ 使用标准 80/443 端口
- ✅ 支持域名访问
- ✅ 自动 HTTPS（Let's Encrypt）
- ✅ 负载均衡和高可用

**Ingress 配置示例**:
```yaml
# dashboard-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubernetes-dashboard-ingress
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - dashboard.yourdomain.com
    secretName: dashboard-tls-cert
  rules:
  - host: dashboard.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard
            port:
              number: 443
```

**应用配置**:
```bash
kubectl apply -f dashboard-ingress.yaml

# 验证
kubectl get ingress -n kubernetes-dashboard
kubectl describe ingress kubernetes-dashboard-ingress -n kubernetes-dashboard
```

**访问地址**: `https://dashboard.yourdomain.com`

---

### 监控与日志

#### 查看 Dashboard 日志

```bash
# 实时查看 Dashboard Pod 日志
kubectl logs -f deployment/kubernetes-dashboard -n kubernetes-dashboard

# 查看特定容器的日志
kubectl logs -f deployment/kubernetes-dashboard -n kubernetes-dashboard -c kubernetes-dashboard

# 查看过去的日志（上次重启前）
kubectl logs -p deployment/kubernetes-dashboard -n kubernetes-dashboard
```

#### 集成 Prometheus 监控

```bash
# Dashboard 本身暴露 metrics 端点
# 通过 ServiceMonitor 收集指标

cat << EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
  labels:
    app: kubernetes-dashboard
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: kubernetes-dashboard
  endpoints:
  - port: https
    scheme: https
    tlsConfig:
      insecureSkipVerify: true
EOF
```

**Grafana Dashboard 导入**:
- 可以导入社区提供的 Kubernetes Dashboard Grafana 面板
- ID: `315` (Kubernetes cluster monitoring via Prometheus)

---

## 安全最佳实践

### ✅ 生产环境必做项

#### 1. 最小权限原则

```bash
# ❌ 错误: 使用 cluster-admin（过度授权）
kubectl create clusterrolebinding binding \
  --clusterrole=cluster-admin \
  --serviceaccount=ns:user

# ✅ 正确: 使用精确的角色
kubectl create rolebinding binding \
  --role=pod-reader \
  --serviceaccount=ns:user
```

#### 2. Token 安全管理

```bash
# ✅ 设置合理的有效期（不要过长）
TOKEN=$(kubectl create token user --duration=24h)

# ✅ 及时删除不再需要的 Token
kubectl delete secret <token-name>

# ✅ 不要将 Token 提交到 Git 仓库
# 添加 .gitignore 规则
echo "*.token" >> .gitignore
echo "/tmp/dashboard-token.txt" >> .gitignore
```

#### 3. 网络隔离

```bash
# ✅ 使用 NetworkPolicy 限制 Dashboard 访问来源
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dashboard-access-policy
  namespace: kubernetes-dashboard
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: kubernetes-dashboard
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: production
    - ipBlock:
        cidr: 192.168.0.0/16
        except:
        - 192.168.0.100/32  # 禁止特定 IP
    ports:
    - protocol: TCP
      port: 8443
EOF
```

#### 4. 审计日志

```bash
# 启用 K8S 审计日志（记录所有 API 调用）
# 编辑 /etc/kubernetes/manifests/kube-apiserver.yaml
# 添加:
--audit-log-path=/var/log/kubernetes/audit.log
--audit-policy-file=/etc/kubernetes/audit-policy.yaml

# 审计策略示例
cat > /etc/kubernetes/audit-policy.yaml << 'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
  users: ["system:serviceaccount:kubernetes-dashboard:admin-user"]
  verbs: ["create", "delete", "patch"]
  resources:
  - group: ""
    resources: ["secrets", "configmaps"]
EOF
```

#### 5. 定期轮换凭证

```bash
# 脚本: rotate-dashboard-secrets.sh
#!/bin/bash
NS="kubernetes-dashboard"
SA="admin-user"

# 1. 删除旧 Token Secret
kubectl delete secret $(kubectl get sa $SA -n $NS -o jsonpath='{.secrets[0].name}') -n $NS 2>/dev/null

# 2. 生成新 Token
NEW_TOKEN=$(kubectl create token $SA -n $NS --duration=8760h)

# 3. 保存新 Token
echo "$NEW_TOKEN" > /tmp/dashboard-token-new.txt
chmod 600 /tmp/dashboard-token-new.txt

echo "Token rotated successfully!"
echo "New Token saved to: /tmp/dashboard-token-new.txt"
```

**设置 Cron 任务**（每 90 天轮换一次）:
```bash
crontab -e
# 添加:
0 0 1 */3 * /path/to/rotate-dashboard-secrets.sh >> /var/log/token-rotation.log 2>&1
```

### ⚠️ 禁止事项

| 行为 | 风险等级 | 替代方案 |
|------|----------|----------|
| **使用 `--enable-skip-login`** | 🔴 极高 | 始终使用 Token/Kubeconfig 认证 |
| **暴露 Dashboard 到公网** | 🔴 极高 | VPN + Ingress + IP 白名单 |
| **使用默认自签名证书（生产）** | 🟡 高 | Let's Encrypt 或企业 CA 证书 |
| **授予 cluster-admin 给普通用户** | 🟡 高 | 创建自定义 Role |
| **在 Dashboard 中编辑 RBAC** | 🟡 中 | 使用 kubectl 或 GitOps |
| **禁用审计日志** | 🟡 中 | 始终启用审计 |

---

## 附录

### A. 快速参考卡片

```bash
# 🚀 一键启动 Dashboard（复制粘贴即可）
screen -dmS k8s-dashboard bash -c "kubectl port-forward svc/kubernetes-dashboard 8443:443 -n kubernetes-dashboard --address 0.0.0.0; exec bash"
sleep 3 && TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard --duration=8760h) && echo "✅ Dashboard: https://192.168.0.200:8443\nToken: $TOKEN"

# 🔄 重启 Dashboard
screen -S k8s-dashboard -X quit && screen -dmS k8s-dashboard bash -c "kubectl port-forward svc/kubernetes-dashboard 8443:443 -n kubernetes-dashboard --address 0.0.0.0; exec bash"

# 📊 检查状态
echo "=== 端口 ===" && ss -tlnp | grep 8443 && echo "=== 进程 ===" && ps aux | grep port-forward | grep -v grep && echo "=== Screen ===" && screen -ls

# 🛑 停止 Dashboard
screen -S k8s-dashboard -X quit

# 🔐 获取 Token
kubectl create token admin-user -n kubernetes-dashboard --duration=8760h
```

### B. 常用命令速查

| 操作 | 命令 |
|------|------|
| 查看 SA | `kubectl get sa -n kubernetes-dashboard` |
| 查看 CRB | `kubectl get clusterrolebinding \| grep admin-user` |
| 测试权限 | `kubectl auth can-i create pods --as=system:serviceaccount:kubernetes-dashboard:admin-user` |
| 查看 Pod | `kubectl get pods -n kubernetes-dashboard` |
| 查看日志 | `kubectl logs -f deployment/kubernetes-dashboard -n kubernetes-dashboard` |
| 查看 SVC | `kubectl get svc kubernetes-dashboard -n kubernetes-dashboard` |
| 查看 EP | `kubectl get ep kubernetes-dashboard -n kubernetes-dashboard` |
| 编辑部署 | `kubectl edit deployment kubernetes-dashboard -n kubernetes-dashboard` |
| 重启 Dashboard | `kubectl rollout restart deployment/kubernetes-dashboard -n kubernetes-dashboard` |

### C. 故障排除决策树

```
无法访问 Dashboard？
│
├─ 浏览器显示 "Connection Refused"？
│  └─ 是 → 检查 port-forward 进程（问题 2）
│
├─ 浏览器显示 "Forbidden"？
│  └─ 是 → 检查 RBAC 权限（问题 1）
│
├─ 浏览器显示 "SSL 证书不安全"？
│  └─ 是 → 这是正常的（问题 3），点击继续前往
│
├─ 浏览器显示 "Expired/Invalid token"？
│  └─ 是 → 重新生成 Token（问题 4）
│
└─ 页面加载很慢？
   └─ 是 → 检查资源使用和网络（问题 5）
```

### D. 相关资源链接

- **官方文档**: https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/
- **GitHub 仓库**: https://github.com/kubernetes/dashboard
- **版本发布**: https://github.com/kubernetes/dashboard/releases
- **RBAC 指南**: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- **Port-Forward 文档**: https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/

---

## 版本历史

| 日期 | 版本 | 作者 | 变更说明 |
|------|------|------|----------|
| 2026-07-01 | v1.0.0 | DeepOps Team | 初始版本，包含完整的局域网访问指南 |

---

## 反馈与贡献

如有问题或改进建议，请提交 Issue 或 Pull Request 至 DeepOps 仓库。

**祝使用愉快！🎉**