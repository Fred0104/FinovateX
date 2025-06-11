#!/bin/bash

# Docker 健康检查脚本
# 用于检查各个服务的健康状态

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查PostgreSQL健康状态
check_postgres() {
    log_info "检查PostgreSQL健康状态..."
    
    if docker exec finovatex-postgres pg_isready -U finovatex_user -d finovatex > /dev/null 2>&1; then
        log_info "PostgreSQL: 健康"
        return 0
    else
        log_error "PostgreSQL: 不健康"
        return 1
    fi
}

# 检查Redis健康状态
check_redis() {
    log_info "检查Redis健康状态..."
    
    if docker exec finovatex-redis redis-cli -a finovatex_redis_password ping > /dev/null 2>&1; then
        log_info "Redis: 健康"
        return 0
    else
        log_error "Redis: 不健康"
        return 1
    fi
}

# 检查NATS健康状态
check_nats() {
    log_info "检查NATS健康状态..."
    
    if docker exec finovatex-nats wget --no-verbose --tries=1 --spider http://localhost:8222/healthz > /dev/null 2>&1; then
        log_info "NATS: 健康"
        return 0
    else
        log_error "NATS: 不健康"
        return 1
    fi
}

# 检查Prometheus健康状态
check_prometheus() {
    log_info "检查Prometheus健康状态..."
    
    if docker exec finovatex-prometheus wget --no-verbose --tries=1 --spider http://localhost:9090/-/healthy > /dev/null 2>&1; then
        log_info "Prometheus: 健康"
        return 0
    else
        log_error "Prometheus: 不健康"
        return 1
    fi
}

# 检查Grafana健康状态
check_grafana() {
    log_info "检查Grafana健康状态..."
    
    if docker exec finovatex-grafana curl -f http://localhost:3000/api/health > /dev/null 2>&1; then
        log_info "Grafana: 健康"
        return 0
    else
        log_error "Grafana: 不健康"
        return 1
    fi
}

# 检查所有服务
check_all_services() {
    log_info "开始检查所有服务健康状态..."
    
    local failed_services=()
    
    # 检查各个服务
    check_postgres || failed_services+=("PostgreSQL")
    check_redis || failed_services+=("Redis")
    check_nats || failed_services+=("NATS")
    check_prometheus || failed_services+=("Prometheus")
    check_grafana || failed_services+=("Grafana")
    
    # 汇总结果
    if [ ${#failed_services[@]} -eq 0 ]; then
        log_info "所有服务健康检查通过！"
        return 0
    else
        log_error "以下服务健康检查失败: ${failed_services[*]}"
        return 1
    fi
}

# 等待服务启动
wait_for_services() {
    local max_attempts=30
    local attempt=1
    
    log_info "等待服务启动..."
    
    while [ $attempt -le $max_attempts ]; do
        log_info "尝试 $attempt/$max_attempts"
        
        if check_all_services; then
            log_info "所有服务已启动并健康！"
            return 0
        fi
        
        log_warn "等待服务启动... (${attempt}/${max_attempts})"
        sleep 10
        ((attempt++))
    done
    
    log_error "服务启动超时！"
    return 1
}

# 显示服务状态
show_service_status() {
    log_info "显示Docker Compose服务状态..."
    docker-compose ps
    
    log_info "显示服务健康状态..."
    docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
}

# 主函数
main() {
    case "${1:-check}" in
        "check")
            check_all_services
            ;;
        "wait")
            wait_for_services
            ;;
        "status")
            show_service_status
            ;;
        "postgres")
            check_postgres
            ;;
        "redis")
            check_redis
            ;;
        "nats")
            check_nats
            ;;
        "prometheus")
            check_prometheus
            ;;
        "grafana")
            check_grafana
            ;;
        "help")
            echo "用法: $0 [check|wait|status|postgres|redis|nats|prometheus|grafana|help]"
            echo "  check      - 检查所有服务健康状态（默认）"
            echo "  wait       - 等待所有服务启动并健康"
            echo "  status     - 显示服务状态"
            echo "  postgres   - 仅检查PostgreSQL"
            echo "  redis      - 仅检查Redis"
            echo "  nats       - 仅检查NATS"
            echo "  prometheus - 仅检查Prometheus"
            echo "  grafana    - 仅检查Grafana"
            echo "  help       - 显示此帮助信息"
            ;;
        *)
            log_error "未知命令: $1"
            echo "使用 '$0 help' 查看可用命令"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"