# 服务启动优化脚本
# 按正确顺序启动服务并等待依赖服务就绪

param(
    [string]$ComposeFile = "docker-compose.yml",
    [switch]$Build = $false,
    [switch]$Pull = $false,
    [int]$Timeout = 120,
    [switch]$Verbose = $false,
    [switch]$Help = $false
)

# 显示帮助信息
function Show-Help {
    Write-Host "FinovateX 服务启动优化脚本" -ForegroundColor Green
    Write-Host "用法: .\start-services.ps1 [选项]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "选项:"
    Write-Host "  -ComposeFile [file]   指定docker-compose文件路径（默认: docker-compose.yml）"
    Write-Host "  -Build                构建镜像后启动"
    Write-Host "  -Pull                 拉取最新镜像后启动"
    Write-Host "  -Timeout [seconds]    服务启动超时时间（默认: 120秒）"
    Write-Host "  -Verbose              显示详细输出"
    Write-Host "  -Help                 显示此帮助信息"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  .\start-services.ps1"
    Write-Host "  .\start-services.ps1 -Build -Verbose"
    Write-Host "  .\start-services.ps1 -Pull -Timeout 180"
}

# 服务启动顺序和依赖配置
$ServiceStartupOrder = @(
    @{
        "name" = "postgres"
        "display_name" = "PostgreSQL数据库"
        "health_check" = "http://localhost:5432"
        "health_type" = "database"
        "wait_time" = 30
        "dependencies" = @()
    },
    @{
        "name" = "redis"
        "display_name" = "Redis缓存"
        "health_check" = "redis://localhost:6379"
        "health_type" = "redis"
        "wait_time" = 15
        "dependencies" = @()
    },
    @{
        "name" = "nats"
        "display_name" = "NATS消息队列"
        "health_check" = "http://localhost:8222/healthz"
        "health_type" = "http"
        "wait_time" = 20
        "dependencies" = @()
    },
    @{
        "name" = "prometheus"
        "display_name" = "Prometheus监控"
        "health_check" = "http://localhost:9090/-/healthy"
        "health_type" = "http"
        "wait_time" = 25
        "dependencies" = @()
    },
    @{
        "name" = "loki"
        "display_name" = "Loki日志聚合"
        "health_check" = "http://localhost:3100/ready"
        "health_type" = "http"
        "wait_time" = 20
        "dependencies" = @()
    },
    @{
        "name" = "grafana"
        "display_name" = "Grafana仪表板"
        "health_check" = "http://localhost:3000/api/health"
        "health_type" = "http"
        "wait_time" = 30
        "dependencies" = @("prometheus", "loki")
    },
    @{
        "name" = "promtail"
        "display_name" = "Promtail日志收集"
        "health_check" = "http://localhost:9080/ready"
        "health_type" = "http"
        "wait_time" = 15
        "dependencies" = @("loki")
    },
    @{
        "name" = "otel-collector"
        "display_name" = "OpenTelemetry收集器"
        "health_check" = "http://localhost:13133"
        "health_type" = "http"
        "wait_time" = 20
        "dependencies" = @("prometheus")
    },
    @{
        "name" = "node-exporter"
        "display_name" = "Node Exporter"
        "health_check" = "http://localhost:9100/metrics"
        "health_type" = "http"
        "wait_time" = 10
        "dependencies" = @()
    },
    @{
        "name" = "redis-exporter"
        "display_name" = "Redis Exporter"
        "health_check" = "http://localhost:9121/metrics"
        "health_type" = "http"
        "wait_time" = 10
        "dependencies" = @("redis")
    },
    @{
        "name" = "postgres-exporter"
        "display_name" = "Postgres Exporter"
        "health_check" = "http://localhost:9187/metrics"
        "health_type" = "http"
        "wait_time" = 10
        "dependencies" = @("postgres")
    }
)

# 检查Docker和Docker Compose
function Test-DockerEnvironment {
    try {
        $null = docker --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Docker不可用，请确保Docker已安装并运行" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "Docker不可用，请确保Docker已安装并运行" -ForegroundColor Red
        return $false
    }
    
    try {
        $null = docker-compose --version 2>&1
        if ($LASTEXITCODE -eq 0) { 
            return $true 
        }
        
        $null = docker compose version 2>&1
        if ($LASTEXITCODE -eq 0) { 
            return $true 
        }
        
        Write-Host "Docker Compose不可用，请确保Docker Compose已安装" -ForegroundColor Red
        return $false
    }
    catch {
        Write-Host "Docker Compose不可用，请确保Docker Compose已安装" -ForegroundColor Red
        return $false
    }
}

# 获取Docker Compose命令
function Get-DockerComposeCommand {
    try {
        $null = docker-compose --version 2>&1
        if ($LASTEXITCODE -eq 0) { return "docker-compose" }
        
        $null = docker compose version 2>&1
        if ($LASTEXITCODE -eq 0) { return "docker compose" }
    }
    catch {}
    
    return $null
}

# 检查服务健康状态
function Test-ServiceHealth {
    param(
        [hashtable]$ServiceConfig,
        [int]$TimeoutSeconds = 30
    )
    
    $serviceName = $ServiceConfig.name
    $healthType = $ServiceConfig.health_type
    $healthCheck = $ServiceConfig.health_check
    
    switch ($healthType) {
        "http" {
            try {
                $response = Invoke-WebRequest -Uri $healthCheck -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop
                return $response.StatusCode -ge 200 -and $response.StatusCode -lt 300
            }
            catch {
                if ($Verbose) {
                    Write-Host "    HTTP健康检查失败: $($_.Exception.Message)" -ForegroundColor Red
                }
                return $false
            }
        }
        
        "database" {
            try {
                $composeCmd = Get-DockerComposeCommand
                $result = & $composeCmd.Split() exec -T postgres pg_isready -h localhost -p 5432 -U finovatex_user 2>&1
                return $LASTEXITCODE -eq 0
            }
            catch {
                if ($Verbose) {
                    Write-Host "    数据库健康检查失败: $($_.Exception.Message)" -ForegroundColor Red
                }
                return $false
            }
        }
        
        "redis" {
            try {
                $composeCmd = Get-DockerComposeCommand
                $result = & $composeCmd.Split() exec -T redis redis-cli -a finovatex_redis_password ping 2>&1
                return $result -match "PONG" -and $LASTEXITCODE -eq 0
            }
            catch {
                if ($Verbose) {
                    Write-Host "    Redis健康检查失败: $($_.Exception.Message)" -ForegroundColor Red
                }
                return $false
            }
        }
        
        default {
            Write-Host "    未知的健康检查类型: $healthType" -ForegroundColor Yellow
            return $false
        }
    }
}

# 等待服务健康
function Wait-ForServiceHealth {
    param(
        [hashtable]$ServiceConfig,
        [int]$TimeoutSeconds = 60
    )
    
    $serviceName = $ServiceConfig.name
    $displayName = $ServiceConfig.display_name
    
    Write-Host "  等待 $displayName 健康检查..." -ForegroundColor Yellow
    
    $startTime = Get-Date
    $timeout = $startTime.AddSeconds($TimeoutSeconds)
    $checkInterval = 3
    
    while ((Get-Date) -lt $timeout) {
        if (Test-ServiceHealth -ServiceConfig $ServiceConfig -TimeoutSeconds 10) {
            Write-Host "  ✓ $displayName 健康检查通过" -ForegroundColor Green
            return $true
        }
        
        if ($Verbose) {
            Write-Host "    等待 $displayName 就绪..." -ForegroundColor Gray
        }
        
        Start-Sleep -Seconds $checkInterval
    }
    
    Write-Host "  ✗ $displayName 健康检查超时" -ForegroundColor Red
    return $false
}

# 启动单个服务
function Start-Service {
    param(
        [hashtable]$ServiceConfig
    )
    
    $serviceName = $ServiceConfig.name
    $displayName = $ServiceConfig.display_name
    $waitTime = $ServiceConfig.wait_time
    
    Write-Host "启动服务: $displayName" -ForegroundColor Cyan
    
    try {
        $composeCmd = Get-DockerComposeCommand
        
        # 启动服务
        $result = & $composeCmd.Split() up -d $serviceName 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ✗ 启动 $displayName 失败: $result" -ForegroundColor Red
            return $false
        }
        
        Write-Host "  ✓ $displayName 容器已启动" -ForegroundColor Green
        
        # 等待服务初始化
        if ($waitTime -gt 0) {
            Write-Host "  等待 $waitTime 秒进行服务初始化..." -ForegroundColor Yellow
            Start-Sleep -Seconds $waitTime
        }
        
        # 等待健康检查通过
        $healthResult = Wait-ForServiceHealth -ServiceConfig $ServiceConfig -TimeoutSeconds $Timeout
        
        if ($healthResult) {
            Write-Host "  🎉 $displayName 启动完成并通过健康检查" -ForegroundColor Green
        }
        else {
            Write-Host "  ⚠️ $displayName 启动完成但健康检查失败" -ForegroundColor Yellow
        }
        
        Write-Host ""
        return $healthResult
    }
    catch {
        Write-Host "  ✗ 启动 $displayName 时发生异常: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return $false
    }
}

# 检查依赖服务
function Test-ServiceDependencies {
    param(
        [hashtable]$ServiceConfig,
        [array]$StartedServices
    )
    
    $dependencies = $ServiceConfig.dependencies
    if ($dependencies.Count -eq 0) {
        return $true
    }
    
    foreach ($dependency in $dependencies) {
        if ($dependency -notin $StartedServices) {
            return $false
        }
    }
    
    return $true
}

# 初始化NATS JetStream
function Initialize-NatsJetStream {
    Write-Host "初始化NATS JetStream..." -ForegroundColor Cyan
    
    $scriptPath = Join-Path (Split-Path -Parent $MyInvocation.ScriptName) "init-nats-streams.ps1"
    
    if (Test-Path $scriptPath) {
        try {
            & $scriptPath -Docker -Verbose:$Verbose
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ NATS JetStream初始化完成" -ForegroundColor Green
            }
            else {
                Write-Host "⚠️ NATS JetStream初始化失败" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "⚠️ NATS JetStream初始化异常: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "⚠️ NATS JetStream初始化脚本未找到" -ForegroundColor Yellow
    }
    
    Write-Host ""
}

# 主函数
function Main {
    if ($Help) {
        Show-Help
        return
    }
    
    Write-Host "=== FinovateX 服务启动优化 ===" -ForegroundColor Cyan
    Write-Host ""
    
    # 检查Docker环境
    if (-not (Test-DockerEnvironment)) {
        exit 1
    }
    
    # 检查compose文件
    if (-not (Test-Path $ComposeFile)) {
        Write-Host "Docker Compose文件不存在: $ComposeFile" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "使用Docker Compose文件: $ComposeFile" -ForegroundColor Yellow
    Write-Host "服务启动超时: $Timeout 秒" -ForegroundColor Yellow
    Write-Host ""
    
    $composeCmd = Get-DockerComposeCommand
    
    # 拉取镜像（如果需要）
    if ($Pull) {
        Write-Host "拉取最新镜像..." -ForegroundColor Yellow
        & $composeCmd.Split() pull
        Write-Host ""
    }
    
    # 构建镜像（如果需要）
    if ($Build) {
        Write-Host "构建镜像..." -ForegroundColor Yellow
        & $composeCmd.Split() build
        Write-Host ""
    }
    
    # 停止现有服务
    Write-Host "停止现有服务..." -ForegroundColor Yellow
    & $composeCmd.Split() down
    Write-Host ""
    
    # 按顺序启动服务
    $startedServices = @()
    $failedServices = @()
    
    foreach ($serviceConfig in $ServiceStartupOrder) {
        $serviceName = $serviceConfig.name
        
        # 检查依赖
        if (-not (Test-ServiceDependencies -ServiceConfig $serviceConfig -StartedServices $startedServices)) {
            Write-Host "服务 $serviceName 的依赖未满足，跳过启动" -ForegroundColor Yellow
            $failedServices += $serviceName
            continue
        }
        
        # 启动服务
        $success = Start-Service -ServiceConfig $serviceConfig
        
        if ($success) {
            $startedServices += $serviceName
        }
        else {
            $failedServices += $serviceName
        }
    }
    
    # 初始化NATS JetStream（如果NATS启动成功）
    if ("nats" -in $startedServices) {
        Initialize-NatsJetStream
    }
    
    # 显示启动结果
    Write-Host "=== 服务启动结果 ===" -ForegroundColor Cyan
    Write-Host "成功启动的服务 ($($startedServices.Count)):" -ForegroundColor Green
    foreach ($service in $startedServices) {
        $serviceConfig = $ServiceStartupOrder | Where-Object { $_.name -eq $service }
        Write-Host "  ✓ $($serviceConfig.display_name)" -ForegroundColor Green
    }
    
    if ($failedServices.Count -gt 0) {
        Write-Host "启动失败的服务 ($($failedServices.Count)):" -ForegroundColor Red
        foreach ($service in $failedServices) {
            $serviceConfig = $ServiceStartupOrder | Where-Object { $_.name -eq $service }
            Write-Host "  ✗ $($serviceConfig.display_name)" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    
    # 显示访问信息
    if ($startedServices.Count -gt 0) {
        Write-Host "=== 服务访问信息 ===" -ForegroundColor Cyan
        if ("grafana" -in $startedServices) {
            Write-Host "Grafana仪表板: http://localhost:3000 (admin/admin)" -ForegroundColor Green
        }
        if ("prometheus" -in $startedServices) {
            Write-Host "Prometheus监控: http://localhost:9090" -ForegroundColor Green
        }
        if ("nats" -in $startedServices) {
            Write-Host "NATS监控: http://localhost:8222" -ForegroundColor Green
        }
        Write-Host ""
    }
    
    # 返回结果
    if ($failedServices.Count -eq 0) {
        Write-Host "🎉 所有服务启动成功！" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "⚠️ 部分服务启动失败，请检查日志。" -ForegroundColor Yellow
        exit 1
    }
}

# 执行主函数
Main