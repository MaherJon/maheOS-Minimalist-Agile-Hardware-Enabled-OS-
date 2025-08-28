#!/bin/bash

# maheOS自动构建脚本
# 用于构建基于Linux 6.0.11内核和静态编译busybox的最小系统

set -euo pipefail

# 配置信息
BUILD_DIR="$HOME/maheOS-build"
LOG_FILE="$BUILD_DIR/build.log"
MAX_ATTEMPTS=5
RETRY_DELAY=300  # 5分钟
AUTO_FIX=true    # 是否自动修复错误

# 日志初始化函数
init_log() {
    local log_dir=$(dirname "$LOG_FILE")
    
    # 确保日志目录存在
    if [ ! -d "$log_dir" ]; then
        echo "$(date): INFO: 创建日志目录: $log_dir"
        mkdir -p "$log_dir" || {
            echo "$(date): ERROR: 无法创建日志目录: $log_dir" >&2
            return 1
        }
    fi
    
    # 创建或清空日志文件
    echo "$(date): INFO: 初始化日志文件: $LOG_FILE"
    echo "$(date): 开始构建maheOS" > "$LOG_FILE" || {
        echo "$(date): ERROR: 无法创建日志文件: $LOG_FILE" >&2
        return 1
    }
    
    return 0
}

# 日志函数
log_info() {
    local message="$1"
    echo "$(date): INFO: $message" >> "$LOG_FILE" 2>/dev/null || {
        echo "$(date): INFO: (日志文件写入失败) $message" >&2
    }
    echo "INFO: $message"
}

log_warning() {
    local message="$1"
    echo "$(date): WARNING: $message" >> "$LOG_FILE" 2>/dev/null || {
        echo "$(date): WARNING: (日志文件写入失败) $message" >&2
    }
    echo "WARNING: $message" >&2
}

log_error() {
    local message="$1"
    echo "$(date): ERROR: $message" >> "$LOG_FILE" 2>/dev/null || {
        echo "$(date): ERROR: (日志文件写入失败) $message" >&2
    }
    echo "ERROR: $message" >&2
}

# 检查命令执行结果
check_result() {
    local result=$1
    local cmd="$2"
    local error_handler="$3"
    
    if [ $result -ne 0 ]; then
        log_error "命令执行失败: $cmd"
        
        if [ "$AUTO_FIX" = true ]; then
            log_info "尝试自动修复..."
            if $error_handler; then
                log_info "修复成功，将重试命令"
                return 1  # 返回1表示需要重试
            else
                log_error "自动修复失败"
                return 2  # 返回2表示修复失败
            fi
        else
            log_error "自动修复已禁用，请手动修复问题"
            return 2
        fi
    fi
    
    return 0
}

# 创建目录（自动处理错误）
create_dir() {
    local dir_path="$1"
    local attempt=1
    
    while [ $attempt -le $MAX_ATTEMPTS ]; do
        log_info "尝试创建目录: $dir_path (尝试 $attempt/$MAX_ATTEMPTS)"
        
        if mkdir -p "$dir_path"; then
            log_info "目录 $dir_path 创建成功"
            return 0
        else
            log_error "创建目录失败: $dir_path"
            
            # 尝试修复权限问题
            if [ $attempt -lt $MAX_ATTEMPTS ]; then
                local parent_dir=$(dirname "$dir_path")
                log_warning "尝试修复父目录权限: $parent_dir"
                chmod -R u+w "$parent_dir" || true
                sleep 1
            fi
            
            attempt=$((attempt + 1))
        fi
    done
    
    log_error "无法创建目录: $dir_path"
    return 1
}

# 创建文件（自动处理错误）
create_file() {
    local file_path="$1"
    local content="$2"
    local attempt=1
    
    while [ $attempt -le $MAX_ATTEMPTS ]; do
        log_info "尝试创建文件: $file_path (尝试 $attempt/$MAX_ATTEMPTS)"
        
        # 确保目录存在
        local dir_path=$(dirname "$file_path")
        if [ ! -d "$dir_path" ]; then
            if ! create_dir "$dir_path"; then
                log_error "无法创建文件目录: $dir_path"
                return 1
            fi
        fi
        
        # 创建文件
        if [ -n "$content" ]; then
            echo "$content" > "$file_path"
        else
            touch "$file_path"
        fi
        
        if [ $? -eq 0 ]; then
            log_info "文件 $file_path 创建成功"
            return 0
        else
            log_error "创建文件失败: $file_path"
            
            # 尝试修复权限问题
            if [ $attempt -lt $MAX_ATTEMPTS ]; then
                chmod -R u+w "$dir_path" || true
                sleep 1
            fi
            
            attempt=$((attempt + 1))
        fi
    done
    
    log_error "无法创建文件: $file_path"
    return 1
}

# 安全执行命令 - 带自动重试和错误修复
safe_exec() {
    local cmd="$1"
    local error_handler="$2"
    local attempt=1
    
    log_info "执行命令: $cmd"
    
    while [ $attempt -le $MAX_ATTEMPTS ]; do
        log_info "尝试 $attempt/$MAX_ATTEMPTS"
        
        eval "$cmd"
        local result=$?
        
        if [ $result -eq 0 ]; then
            log_info "命令执行成功"
            return 0
        fi
        
        check_result $result "$cmd" "$error_handler"
        local check_result=$?
        
        if [ $check_result -eq 0 ]; then
            log_info "命令执行成功"
            return 0
        elif [ $check_result -eq 2 ]; then
            log_error "命令执行失败，无法修复"
            return 1
        fi
        
        # 准备重试
        attempt=$((attempt + 1))
        log_info "将在 $RETRY_DELAY 秒后重试..."
        sleep $RETRY_DELAY
    done
    
    log_error "命令执行失败，达到最大重试次数"
    return 1
}

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo "$(date): ERROR: 此脚本需要root权限运行" >&2
    echo "$(date): ERROR: 请使用 sudo 命令运行: sudo ./build_maheos.sh" >&2
    exit 1
fi

# 清理函数
clean_failed_build() {
    local component=$1
    local build_dir="$BUILD_DIR/build/$component"
    
    log_info "清理失败的$component构建产物"
    
    case "$component" in
        "kernel")
            if [ -d "$build_dir/linux-6.0.11" ]; then
                cd "$build_dir/linux-6.0.11"
                make clean || true
                cd "$BUILD_DIR"
            fi
            ;;
        "busybox")
            if [ -d "$build_dir/busybox-1.36.1" ]; then
                cd "$build_dir/busybox-1.36.1"
                make clean || true
                cd "$BUILD_DIR"
            fi
            ;;
        "rootfs")
            if [ -d "$BUILD_DIR/rootfs" ]; then
                find "$BUILD_DIR/rootfs" -mindepth 1 -delete || true
                mkdir -p "$BUILD_DIR/rootfs/{bin,sbin,etc,proc,sys,dev,mnt,home,lib,lib64,usr/{bin,sbin,lib,lib64},var/log}"
            fi
            ;;
        *)
            log_error "未知组件: $component"
            ;;
    esac
    
    log_info "$component构建产物清理完成"
}

# 完全清理函数
clean_all() {
    log_info "开始完全清理构建环境"
    
    # 停止可能正在运行的进程
    pkill -f "linux-6.0.11" || true
    pkill -f "busybox-1.36.1" || true
    
    # 删除构建目录
    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR" || true
    fi
    
    # 创建基本目录结构
    mkdir -p "$BUILD_DIR/sources"
    mkdir -p "$BUILD_DIR/build"
    mkdir -p "$BUILD_DIR/rootfs"
    
    log_info "构建环境已完全清理"
    echo "构建环境已完全清理"
}

# 错误处理函数
handle_error() {
    local error_code=$?
    local error_line=$1
    local error_command=$2
    
    log_error "第 $error_line 行: $error_command 失败，错误码 $error_code"
    
    # 根据错误发生的位置，确定需要清理的组件
    if [[ "$error_command" == *"build_kernel"* ]]; then
        clean_failed_build "kernel"
    elif [[ "$error_command" == *"build_busybox"* ]]; then
        clean_failed_build "busybox"
    elif [[ "$error_command" == *"configure_rootfs"* || "$error_command" == *"create_initramfs"* ]]; then
        clean_failed_build "rootfs"
    fi
    
    log_error "构建过程中出现错误，请查看 $LOG_FILE 获取详细信息"
    echo "构建过程中出现错误，请查看 $LOG_FILE 获取详细信息" >&2
    
    if [ "$AUTO_FIX" = true ]; then
        log_info "尝试继续构建..."
        return 1
    else
        exit $error_code
    fi
}

# 注册错误处理
trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR

# 创建项目结构
create_project_structure() {
    log_info "创建项目结构"
    
    safe_exec "mkdir -p $BUILD_DIR/sources" "create_dir $BUILD_DIR/sources"
    safe_exec "mkdir -p $BUILD_DIR/build/kernel" "create_dir $BUILD_DIR/build/kernel"
    safe_exec "mkdir -p $BUILD_DIR/build/busybox" "create_dir $BUILD_DIR/build/busybox"
    safe_exec "mkdir -p $BUILD_DIR/rootfs" "create_dir $BUILD_DIR/rootfs"
    
    # 创建根文件系统目录结构
    local rootfs_dirs=(
        "bin" "sbin" "etc" "proc" "sys" "dev" "mnt" "home" 
        "lib" "lib64" "usr/bin" "usr/sbin" "usr/lib" "usr/lib64" 
        "var" "var/log"
    )
    
    for dir in "${rootfs_dirs[@]}"; do
        safe_exec "mkdir -p $BUILD_DIR/rootfs/$dir" "create_dir $BUILD_DIR/rootfs/$dir"
    done
    
    log_info "项目结构创建完成"
}

# 下载源码
download_sources() {
    log_info "开始下载源码"
    
    cd "$BUILD_DIR/sources"
    
    if [ ! -f "linux-6.0.11.tar.xz" ]; then
        safe_exec "wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.0.11.tar.xz" "create_dir $BUILD_DIR/sources"
    fi
    
    if [ ! -f "busybox-1.36.1.tar.bz2" ]; then
        safe_exec "wget https://busybox.net/downloads/busybox-1.36.1.tar.bz2" "create_dir $BUILD_DIR/sources"
    fi
    
    # 下载Xorg和其他必要组件
    if [ ! -f "xorg-minimal.tar.gz" ]; then
        log_warning "Xorg组件需要手动准备并放置在sources目录中"
    fi
    
    log_info "源码下载完成"
}

# 解压源码
extract_sources() {
    log_info "开始解压源码"
    
    cd "$BUILD_DIR/sources"
    
    if [ ! -d "linux-6.0.11" ]; then
        safe_exec "tar -xf linux-6.0.11.tar.xz" "create_dir $BUILD_DIR/sources"
    fi
    
    if [ ! -d "busybox-1.36.1" ]; then
        safe_exec "tar -xf busybox-1.36.1.tar.bz2" "create_dir $BUILD_DIR/sources"
    fi
    
    log_info "源码解压完成"
}

# 配置并编译内核
build_kernel() {
    log_info "开始配置和编译内核"
    
    cd "$BUILD_DIR/build/kernel"
    
    # 复制源码
    if [ ! -d "linux-6.0.11" ]; then
        safe_exec "cp -r $BUILD_DIR/sources/linux-6.0.11 ." "create_dir $BUILD_DIR/build/kernel"
    fi
    
    cd "linux-6.0.11"
    
    # 配置内核
    if [ ! -f ".config" ]; then
        safe_exec "make defconfig" "create_file .config"
        
        # 启用必要的内核选项
        sed -i 's/# CONFIG_SCSI is not set/CONFIG_SCSI=y/' .config
        sed -i 's/# CONFIG_SCSI_MOD is not set/CONFIG_SCSI_MOD=y/' .config
        sed -i 's/# CONFIG_SATA_AHCI is not set/CONFIG_SATA_AHCI=y/' .config
        sed -i 's/# CONFIG_EXT4_FS is not set/CONFIG_EXT4_FS=y/' .config
        sed -i 's/# CONFIG_FB_VESA is not set/CONFIG_FB_VESA=y/' .config
        sed -i 's/# CONFIG_DRM_VGA_ARB is not set/CONFIG_DRM_VGA_ARB=y/' .config
        # 启用桌面环境支持
        sed -i 's/# CONFIG_INPUT is not set/CONFIG_INPUT=y/' .config
        sed -i 's/# CONFIG_KEYBOARD is not set/CONFIG_KEYBOARD=y/' .config
        sed -i 's/# CONFIG_MOUSE is not set/CONFIG_MOUSE=y/' .config
        sed -i 's/# CONFIG_VT is not set/CONFIG_VT=y/' .config
        sed -i 's/# CONFIG_CONSOLE_TRANSLATIONS is not set/CONFIG_CONSOLE_TRANSLATIONS=y/' .config
        # 启用X窗口系统支持
        sed -i 's/# CONFIG_FBDEV is not set/CONFIG_FBDEV=y/' .config
        sed -i 's/# CONFIG_DRM is not set/CONFIG_DRM=y/' .config
    fi
    
    # 编译内核
    safe_exec "make -j$(nproc) bzImage modules" "create_dir $BUILD_DIR/build/kernel/linux-6.0.11"
    
    # 安装内核模块
    safe_exec "make modules_install INSTALL_MOD_PATH=$BUILD_DIR/rootfs" "create_dir $BUILD_DIR/rootfs/lib/modules"
    
    # 复制内核镜像
    safe_exec "cp arch/x86/boot/bzImage $BUILD_DIR/rootfs/bzImage" "create_dir $BUILD_DIR/rootfs"
    
    log_info "内核编译完成"
}

# 配置并编译busybox
build_busybox() {
    log_info "开始配置和编译busybox"
    
    cd "$BUILD_DIR/build/busybox"
    
    # 复制源码
    if [ ! -d "busybox-1.36.1" ]; then
        safe_exec "cp -r $BUILD_DIR/sources/busybox-1.36.1 ." "create_dir $BUILD_DIR/build/busybox"
    fi
    
    cd "busybox-1.36.1"
    
    # 配置busybox
    if [ ! -f ".config" ]; then
        safe_exec "make defconfig" "create_file .config"
        
        # 启用静态编译
        sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
        # 禁用tc模块
        sed -i 's/CONFIG_FEATURE_TC=y/# CONFIG_FEATURE_TC is not set/' .config
        # 启用基本X窗口系统支持
        sed -i 's/# CONFIG_XWM is not set/CONFIG_XWM=y/' .config
        sed -i 's/# CONFIG_XTERM is not set/CONFIG_XTERM=y/' .config
    fi
    
    # 编译busybox
    safe_exec "make -j$(nproc)" "create_dir $BUILD_DIR/build/busybox/busybox-1.36.1"
    
    # 安装busybox
    safe_exec "make install CONFIG_PREFIX=$BUILD_DIR/rootfs" "create_dir $BUILD_DIR/rootfs/bin"
    
    log_info "busybox编译完成"
}

# 配置根文件系统
configure_rootfs() {
    log_info "开始配置根文件系统"
    
    cd "$BUILD_DIR/rootfs"
    
    # 创建必要的设备节点
    safe_exec "mkdir -p dev" "create_dir $BUILD_DIR/rootfs/dev"
    
    # 使用更安全的方式创建设备节点
    local devices=(
        "null c 1 3"
        "zero c 1 5"
        "tty c 5 0"
        "console c 5 1"
        "tty0 c 4 0"
        "random c 1 8"
        "urandom c 1 9"
    )
    
    for device in "${devices[@]}"; do
        IFS=' ' read -r -a parts <<< "$device"
        device_name="${parts[0]}"
        device_type="${parts[1]}"
        major="${parts[2]}"
        minor="${parts[3]}"
        
        safe_exec "mknod -m 666 dev/$device_name $device_type $major $minor" "create_dir $BUILD_DIR/rootfs/dev"
    done
    
    # 创建init脚本
    local init_content='#!/bin/busybox sh

# 设置环境变量
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

# 挂载必要的文件系统
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
mount -t tmpfs none /run

# 配置网络
ifconfig lo 127.0.0.1 up
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# 创建必要的目录
mkdir -p /mnt /var/run /var/log

# 启动getty
echo "启动getty..."
setsid cttyhack setuidgid root /sbin/getty 38400 tty1

# 启动X窗口系统（如果可用）
if [ -x /usr/bin/X ]; then
    echo "启动X窗口系统..."
    setsid /usr/bin/X &
    sleep 2
    setsid setuidgid root xterm &
fi

# 启动shell
echo "启动shell..."
exec /bin/sh'

    safe_exec "echo '$init_content' > init" "create_file init"
    safe_exec "chmod +x init" "chmod +x init"
    
    # 创建fstab文件
    local fstab_content='# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults        0       0
sysfs           /sys            sysfs   defaults        0       0
devtmpfs        /dev            devtmpfs defaults        0       0
tmpfs           /run            tmpfs   defaults        0       0'

    safe_exec "mkdir -p etc" "create_dir $BUILD_DIR/rootfs/etc"
    safe_exec "echo '$fstab_content' > etc/fstab" "create_file etc/fstab"
    
    # 添加基本的bashrc
    local profile_content='# /etc/profile - 系统范围的环境变量和启动程序

# 设置PATH
PATH="/bin:/sbin:/usr/bin:/usr/sbin"
export PATH

# 设置PS1
PS1="[\u@\h \W]\$ "
export PS1

# 设置LANG
LANG=en_US.UTF-8
export LANG'

    safe_exec "echo '$profile_content' > etc/profile" "create_file etc/profile"
    
    log_info "根文件系统配置完成"
}

# 创建initramfs
create_initramfs() {
    log_info "开始创建initramfs"
    
    cd "$BUILD_DIR/rootfs"
    
    # 创建cpio归档
    safe_exec "find . | cpio -H newc -o | gzip > $BUILD_DIR/initramfs.cpio.gz" "create_dir $BUILD_DIR"
    
    log_info "initramfs创建完成"
}

# 修复mtools依赖
fix_mtools_dependency() {
    log_info "检测到缺少mtools依赖，尝试安装..."
    
    if command -v apt-get &> /dev/null; then
        safe_exec "sudo apt-get install -y mtools" "create_dir /var/cache/apt/archives"
        return $?
    elif command -v yum &> /dev/null; then
        safe_exec "sudo yum install -y mtools" "create_dir /var/cache/yum"
        return $?
    elif command -v dnf &> /dev/null; then
        safe_exec "sudo dnf install -y mtools" "create_dir /var/cache/dnf"
        return $?
    elif command -v pacman &> /dev/null; then
        safe_exec "sudo pacman -S --noconfirm mtools" "create_dir /var/cache/pacman/pkg"
        return $?
    else
        log_error "无法确定包管理器类型，请手动安装mtools"
        return 1
    fi
}

# 创建ISO镜像
create_iso_image() {
    log_info "开始创建ISO镜像"
    
    cd "$BUILD_DIR"
    
    safe_exec "mkdir -p iso/boot/grub" "create_dir $BUILD_DIR/iso/boot/grub"
    
    # 复制内核和initramfs
    safe_exec "cp initramfs.cpio.gz iso/boot/" "create_file iso/boot/initramfs.cpio.gz"
    safe_exec "cp rootfs/bzImage iso/boot/vmlinuz" "create_file iso/boot/vmlinuz"
    
    # 创建GRUB配置
    local grub_config_content='set default="0"
set timeout=5

insmod all_video
insmod gfxterm

menuentry "maheOS - Server" {
    set gfxpayload=keep
    linux /boot/vmlinuz root=/dev/sda1 ro quiet splash
    initrd /boot/initramfs.cpio.gz
}

menuentry "maheOS - text" {
    linux /boot/vmlinuz root=/dev/sda1 ro
    initrd /boot/initramfs.cpio.gz
}

menuentry "maheOS - tast" {
    linux /boot/vmlinuz root=/dev/sda1 ro debug
    initrd /boot/initramfs.cpio.gz
}'

    safe_exec "echo '$grub_config_content' > iso/boot/grub/grub.cfg" "create_file iso/boot/grub/grub.cfg"
    
    # 确定使用哪个GRUB命令
    GRUB_MKRESCUE=$(command -v grub-mkrescue || command -v grub2-mkrescue || command -v grub-mkisoimage)
    if [ -z "$GRUB_MKRESCUE" ]; then
        log_error "找不到合适的GRUB命令来创建ISO镜像"
        exit 1
    fi
    
    log_info "将使用 $GRUB_MKRESCUE 创建ISO镜像"
    
    # 检查mformat是否可用
    if ! command -v mformat &> /dev/null; then
        log_warning "缺少mformat工具，这是创建ISO镜像所必需的"
        if [ "$AUTO_FIX" = true ]; then
            log_info "尝试自动安装mtools包..."
            if ! fix_mtools_dependency; then
                log_error "无法自动安装mtools，请手动安装后重试"
                exit 1
            fi
        else
            log_error "请手动安装mtools包"
            exit 1
        fi
    fi
    
    # 创建ISO
    safe_exec "$GRUB_MKRESCUE -o maheOS.iso iso" "fix_mtools_dependency"
    
    log_info "ISO镜像创建完成: $BUILD_DIR/maheOS.iso"
}

# 解析命令行参数
case "${1-}" in
    --clean)
        clean_all
        exit 0
        ;;
    --help)
        echo "使用方法: $0 [--clean|--help|--no-auto-fix]"
        echo "  --clean: 完全清理构建环境"
        echo "  --help: 显示此帮助信息"
        echo "  --no-auto-fix: 禁用自动修复功能"
        exit 0
        ;;
    --no-auto-fix)
        AUTO_FIX=false
        ;;
    "")
        # 没有参数，继续正常构建流程
        ;;
    *)
        echo "未知参数: $1" >&2
        echo "使用方法: $0 [--clean|--help|--no-auto-fix]" >&2
        exit 1
        ;;
esac

# 初始化日志
if ! init_log; then
    echo "错误: 无法初始化日志系统，退出..." >&2
    exit 1
fi

# 主构建流程
main() {
    log_info "开始maheOS自动构建流程"
    
    # 检查依赖
    log_info "检查系统依赖"
    missing_deps=()
    
    # 检查基本依赖
    for cmd in wget tar make gcc g++ perl bison flex bc xz bzip2 mformat; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # 检查GRUB工具
    if ! command -v grub-mkrescue &> /dev/null && ! command -v grub2-mkrescue &> /dev/null && ! command -v grub-mkisoimage &> /dev/null; then
        missing_deps+=("grub-mkrescue")
    fi
    
    # 处理缺少的依赖
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "检测到缺少依赖: ${missing_deps[*]}"
        
        # 尝试自动安装依赖（仅适用于Debian/Ubuntu系统）
        if command -v apt-get &> /dev/null; then
            log_info "尝试自动安装缺少的依赖..."
            safe_exec "sudo apt-get update" "create_dir /var/lib/apt/lists"
            
            # 安装mtools
            if [[ " ${missing_deps[*]} " == *" mformat "* ]]; then
                safe_exec "sudo apt-get install -y mtools" "create_dir /var/cache/apt/archives"
            fi
            
            # 安装GRUB相关包
            if [[ " ${missing_deps[*]} " == *" grub-mkrescue "* ]]; then
                safe_exec "sudo apt-get install -y grub2-common grub-pc-bin" "create_dir /var/cache/apt/archives"
            fi
            
            # 安装其他依赖
            for dep in "${missing_deps[@]}"; do
                if [[ "$dep" != "mformat" && "$dep" != "grub-mkrescue" ]]; then
                    safe_exec "sudo apt-get install -y $dep" "create_dir /var/cache/apt/archives"
                fi
            done
            
            log_info "依赖安装完成"
        else
            log_error "请手动安装上述依赖"
            exit 1
        fi
    fi
    
    log_info "系统依赖检查完成"
    
    # 执行构建步骤
    create_project_structure
    download_sources
    extract_sources
    build_kernel
    build_busybox
    configure_rootfs
    create_initramfs
    create_iso_image
    
    log_info "maheOS构建成功！ISO镜像位于: $BUILD_DIR/maheOS.iso"
    echo "maheOS构建成功！ISO镜像位于: $BUILD_DIR/maheOS.iso"
}

# 执行主构建流程
main    
