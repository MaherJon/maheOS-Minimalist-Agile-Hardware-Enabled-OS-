#!/bin/bash

# 配置参数（与构建脚本保持一致）
PROJECT_NAME="maheOS"
PROJECT_DIR="$HOME/$PROJECT_NAME-build"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1${NC}"
}

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    log_error "请使用root权限运行（sudo）"
    exit 1
fi

# 显示清理选项
echo "请选择清理模式："
echo "1 - 完全清理（包括源码，重新构建时需要重新下载）"
echo "2 - 部分清理（保留源码，只删除编译产物）"
read -p "请输入选项（1/2）：" choice

case $choice in
    1)
        log_info "执行完全清理..."
        if [ -d "$PROJECT_DIR" ]; then
            rm -rf "$PROJECT_DIR"
            log_info "已删除整个项目目录: $PROJECT_DIR"
        else
            log_warn "项目目录不存在，无需清理"
        fi
        ;;
    2)
        log_info "执行部分清理..."
        # 只删除编译产物，保留源码
        directories=(
            "$PROJECT_DIR/build"
            "$PROJECT_DIR/rootfs"
            "$PROJECT_DIR/iso"
            "$PROJECT_DIR/*.iso"
        )
        
        for dir in "${directories[@]}"; do
            if [ -e "$dir" ]; then
                rm -rf "$dir"
                log_info "已清理: $dir"
            fi
        done
        
        # 重新创建必要的目录结构
        mkdir -p \
            "$PROJECT_DIR/build" \
            "$PROJECT_DIR/rootfs" \
            "$PROJECT_DIR/iso" \
            "$PROJECT_DIR/iso/boot/grub"
        log_info "已重建基础目录结构"
        ;;
    *)
        log_error "无效选项"
        exit 1
        ;;
esac

log_info "清理完成，可以重新运行构建脚本了"
