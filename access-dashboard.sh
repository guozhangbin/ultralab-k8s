#!/bin/bash

# Kubernetes Dashboard 访问脚本
# 解决 SSL 证书错误问题

echo "=== Kubernetes Dashboard 访问工具 ==="
echo ""
echo "1. 启动 kubectl proxy（推荐，无需证书验证）"
echo "2. 显示 Dashboard 访问信息"
echo "3. 退出"
echo ""

read -p "请选择操作 (1-3): " choice

echo ""

case $choice in
    1)
        echo "启动 kubectl proxy..."
        echo ""
        echo "访问地址: http://localhost:8080/api/v1/namespaces/kube-system/services/kubernetes-dashboard:https/proxy/"
        echo ""
        echo "按 Ctrl+C 停止代理"
        echo ""
        sudo /usr/local/bin/kubectl proxy --port=8080 --address=0.0.0.0
        ;;
    2)
        echo "=== Dashboard 访问信息 ==="
        echo ""
        echo "直接访问（需要绕过证书警告）:"
        echo "https://192.168.0.200:32099"
        echo ""
        echo "使用 kubectl proxy（推荐）:"
        echo "1. 运行: sudo /usr/local/bin/kubectl proxy --port=8080"
        echo "2. 访问: http://localhost:8080/api/v1/namespaces/kube-system/services/kubernetes-dashboard:https/proxy/"
        echo ""
        echo "=== 登录 Token ==="
        sudo /usr/local/bin/kubectl create token admin-dashboard -n kube-system --duration=8760h
        echo ""
        ;;
    3)
        echo "退出..."
        exit 0
        ;;
    *)
        echo "无效选择，请重新输入"
        ;;
esac