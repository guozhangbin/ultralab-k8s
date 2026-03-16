#!/bin/bash

# 检查 Kubernetes 集群状态
check_k8s_status() {
    echo "=== Kubernetes 集群状态检查 ==="
    echo ""
    
    # 节点状态
    echo "1. 节点状态:"
    sudo /usr/local/bin/kubectl get nodes
    echo ""
    
    # 系统 Pod 状态
    echo "2. 系统 Pod 状态:"
    sudo /usr/local/bin/kubectl get pods -n kube-system
    echo ""
    
    # 服务状态
    echo "3. 服务状态:"
    sudo /usr/local/bin/kubectl get svc -n kube-system
    echo ""
    
    # 集群信息
    echo "4. 集群信息:"
    sudo /usr/local/bin/kubectl cluster-info
    echo ""
}

# 使用 Ollama 分析集群状态
analyze_with_ollama() {
    echo "=== 使用 Ollama 分析集群状态 ==="
    echo ""
    
    # 收集集群信息
    k8s_info=$(sudo /usr/local/bin/kubectl get nodes && echo "\n---\n" && sudo /usr/local/bin/kubectl get pods -n kube-system && echo "\n---\n" && sudo /usr/local/bin/kubectl get svc -n kube-system && echo "\n---\n" && sudo /usr/local/bin/kubectl cluster-info)
    
    # 转义 JSON 特殊字符
    escaped_k8s_info=$(echo "$k8s_info" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    
    # 构建 Ollama 请求
    request_data=$(cat << EOF
{
  "model": "llama3.2",
  "prompt": "请分析以下 Kubernetes 集群状态信息，指出是否有异常，并提供改进建议：\\n\\n$escaped_k8s_info",
  "stream": false
}
EOF
    )
    
    # 发送请求到 Ollama
    response=$(curl -s -X POST http://localhost:11434/api/generate -H "Content-Type: application/json" -d "$request_data")
    
    # 提取和显示响应
    echo "Ollama 分析结果:"
    echo ""
    echo "$response"
    echo ""
    
    # 尝试提取响应内容
    if command -v jq &> /dev/null; then
        echo "使用 jq 提取响应:"
        echo ""
        echo $response | jq -r '.response // .error // "无法提取响应内容"'
        echo ""
    fi
}

# 生成 Kubernetes 测试配置
generate_k8s_config() {
    echo "=== 使用 Ollama 生成 Kubernetes 测试配置 ==="
    echo ""
    
    # 构建 Ollama 请求
    request_data=$(cat << EOF
{
  "model": "llama3.2",
  "prompt": "请生成一个 Kubernetes 部署配置文件，包含以下内容：\n1. 一个部署 3 个副本的 Nginx 应用\n2. 一个 NodePort 类型的服务，暴露 80 端口\n3. 适当的资源限制和健康检查\n4. 完整的 YAML 格式",
  "stream": false
}
EOF
    )
    
    # 发送请求到 Ollama
    response=$(curl -s -X POST http://localhost:11434/api/generate -H "Content-Type: application/json" -d "$request_data")
    
    # 提取和显示响应
    echo "Ollama 生成的 Kubernetes 配置:"
    echo ""
    echo "$response"
    echo ""
    
    # 尝试提取响应内容
    if command -v jq &> /dev/null; then
        echo "使用 jq 提取响应:"
        echo ""
        config_content=$(echo $response | jq -r '.response // .error // "无法提取响应内容"')
        echo "$config_content"
        echo ""
        
        # 保存配置到文件
        echo "$config_content" > nginx-test-deployment.yaml
        echo "配置已保存到 nginx-test-deployment.yaml"
        echo ""
    else
        echo "未安装 jq，无法提取响应内容"
        echo ""
    fi
}

# 主菜单
main() {
    echo "Kubernetes 测试工具 (使用 Ollama)"
    echo "================================"
    echo "1. 检查 Kubernetes 集群状态"
    echo "2. 使用 Ollama 分析集群状态"
    echo "3. 使用 Ollama 生成 Kubernetes 测试配置"
    echo "4. 退出"
    echo ""
    
    read -p "请选择操作 (1-4): " choice
    echo ""
    
    case $choice in
        1)
            check_k8s_status
            ;;
        2)
            analyze_with_ollama
            ;;
        3)
            generate_k8s_config
            ;;
        4)
            echo "退出..."
            exit 0
            ;;
        *)
            echo "无效选择，请重新输入"
            ;;
    esac
    
    echo ""
    read -p "按 Enter 键继续..."
    main
}

# 启动主菜单
main