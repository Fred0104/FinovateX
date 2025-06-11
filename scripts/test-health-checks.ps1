# Service Health Check Validation Script
# Used to validate health check endpoints and status for all services

param(
    [switch]$Docker = $false,
    [string]$ComposeFile = "docker-compose.yml",
    [int]$Timeout = 30,
    [switch]$Verbose = $false,
    [switch]$Help = $false
)

# Display help information
function Show-Help {
    Write-Host "Service Health Check Validation Script" -ForegroundColor Green
    Write-Host "Usage: .\test-health-checks.ps1 [options]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Docker               Use Docker environment for testing"
    Write-Host "  -ComposeFile [file]   Specify docker-compose file path"
    Write-Host "  -Timeout [seconds]    Health check timeout (default 30 seconds)"
    Write-Host "  -Verbose              Show verbose output"
    Write-Host "  -Help                 Show this help information"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\test-health-checks.ps1 -Docker"
    Write-Host "  .\test-health-checks.ps1 -Docker -Verbose -Timeout 60"
}

# Service health check configuration
$ServiceHealthChecks = @{
    "postgres" = @{
        "name" = "PostgreSQL"
        "url" = "http://localhost:5432"
        "check_type" = "database"
        "test_command" = "pg_isready -h localhost -p 5432 -U finovatex_user"
    }
    "redis" = @{
        "name" = "Redis"
        "url" = "redis://localhost:6379"
        "check_type" = "redis"
        "test_command" = "redis-cli -h localhost -p 6379 -a finovatex_redis_password ping"
    }
    "nats" = @{
        "name" = "NATS"
        "url" = "http://localhost:8222/healthz"
        "check_type" = "http"
        "jetstream_url" = "http://localhost:8222/jsz"
    }
    "prometheus" = @{
        "name" = "Prometheus"
        "url" = "http://localhost:9090/-/healthy"
        "check_type" = "http"
        "ready_url" = "http://localhost:9090/-/ready"
    }
    "grafana" = @{
        "name" = "Grafana"
        "url" = "http://localhost:3000/api/health"
        "check_type" = "http"
    }
    "loki" = @{
        "name" = "Loki"
        "url" = "http://localhost:3100/ready"
        "check_type" = "http"
    }
}

# Check if Docker is available
function Test-DockerAvailable {
    try {
        $null = docker --version 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

# Check if docker-compose is available
function Test-DockerComposeAvailable {
    try {
        $null = docker-compose --version 2>&1
        if ($LASTEXITCODE -eq 0) { return $true }
        
        $null = docker compose version 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

# Get Docker Compose command
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

# Wait for service to start
function Wait-ForService {
    param(
        [string]$ServiceName,
        [int]$TimeoutSeconds = 30
    )
    
    Write-Host "Waiting for service '$ServiceName' to start..." -ForegroundColor Yellow
    
    $startTime = Get-Date
    $timeout = $startTime.AddSeconds($TimeoutSeconds)
    
    while ((Get-Date) -lt $timeout) {
        try {
            if ($Docker) {
                $status = docker-compose ps $ServiceName --format json 2>&1 | ConvertFrom-Json
                if ($status.State -eq "running") {
                    Write-Host "[OK] Service '$ServiceName' started" -ForegroundColor Green
                    return $true
                }
            }
            else {
                # Non-Docker environment, assume service is started
                return $true
            }
        }
        catch {
            # Continue waiting
        }
        
        Start-Sleep -Seconds 2
    }
    
    Write-Host "[FAIL] Service '$ServiceName' startup timeout" -ForegroundColor Red
    return $false
}

# HTTP health check
function Test-HttpHealthCheck {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 10
    )
    
    try {
        $response = Invoke-WebRequest -Uri $Url -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 300
    }
    catch {
        if ($Verbose) {
            Write-Host "    HTTP check failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        return $false
    }
}

# Database health check
function Test-DatabaseHealthCheck {
    param(
        [string]$TestCommand
    )
    
    try {
        if ($Docker) {
            $result = docker-compose exec -T postgres $TestCommand 2>&1
        }
        else {
            $result = Invoke-Expression $TestCommand 2>&1
        }
        return $LASTEXITCODE -eq 0
    }
    catch {
        if ($Verbose) {
            Write-Host "    Database check failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        return $false
    }
}

# Redis health check
function Test-RedisHealthCheck {
    param(
        [string]$TestCommand
    )
    
    try {
        if ($Docker) {
            $result = docker-compose exec -T redis $TestCommand 2>&1
        }
        else {
            $result = Invoke-Expression $TestCommand 2>&1
        }
        return $result -match "PONG" -and $LASTEXITCODE -eq 0
    }
    catch {
        if ($Verbose) {
            Write-Host "    Redis check failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        return $false
    }
}

# Execute service health check
function Test-ServiceHealth {
    param(
        [string]$ServiceKey,
        [hashtable]$ServiceConfig
    )
    
    $serviceName = $ServiceConfig.name
    Write-Host "Checking service: $serviceName" -ForegroundColor Cyan
    
    $healthStatus = @{
        "service" = $serviceName
        "healthy" = $false
        "details" = @()
    }
    
    switch ($ServiceConfig.check_type) {
        "http" {
            # 主要健康检查URL
            $mainCheck = Test-HttpHealthCheck -Url $ServiceConfig.url -TimeoutSeconds $Timeout
            $healthStatus.details += "Main check: $(if ($mainCheck) {'[OK]'} else {'[FAIL]'})"
            
            # Additional check URLs (if exist)
            $additionalChecks = $true
            if ($ServiceConfig.ContainsKey("ready_url")) {
                $readyCheck = Test-HttpHealthCheck -Url $ServiceConfig.ready_url -TimeoutSeconds $Timeout
                $healthStatus.details += "Ready check: $(if ($readyCheck) {'[OK]'} else {'[FAIL]'})"
                $additionalChecks = $additionalChecks -and $readyCheck
            }
            
            if ($ServiceConfig.ContainsKey("jetstream_url")) {
                $jsCheck = Test-HttpHealthCheck -Url $ServiceConfig.jetstream_url -TimeoutSeconds $Timeout
                $healthStatus.details += "JetStream check: $(if ($jsCheck) {'[OK]'} else {'[FAIL]'})"
                $additionalChecks = $additionalChecks -and $jsCheck
            }
            
            $healthStatus.healthy = $mainCheck -and $additionalChecks
        }
        
        "database" {
            $dbCheck = Test-DatabaseHealthCheck -TestCommand $ServiceConfig.test_command
            $healthStatus.details += "Database connection: $(if ($dbCheck) {'[OK]'} else {'[FAIL]'})"
            $healthStatus.healthy = $dbCheck
        }
        
        "redis" {
            $redisCheck = Test-RedisHealthCheck -TestCommand $ServiceConfig.test_command
            $healthStatus.details += "Redis connection: $(if ($redisCheck) {'[OK]'} else {'[FAIL]'})"
            $healthStatus.healthy = $redisCheck
        }
    }
    
    # Display results
    $statusColor = if ($healthStatus.healthy) { "Green" } else { "Red" }
    $statusText = if ($healthStatus.healthy) { "Healthy" } else { "Unhealthy" }
    Write-Host "  Status: $statusText" -ForegroundColor $statusColor
    
    if ($Verbose -or -not $healthStatus.healthy) {
        foreach ($detail in $healthStatus.details) {
            Write-Host "    $detail" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    return $healthStatus
}

# Get Docker service status
function Get-DockerServiceStatus {
    if (-not $Docker) {
        return @()
    }
    
    try {
        $composeCmd = Get-DockerComposeCommand
        if (-not $composeCmd) {
            Write-Host "Docker Compose not available" -ForegroundColor Red
            return @()
        }
        
        $services = & $composeCmd.Split() ps --format json 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Unable to get Docker service status" -ForegroundColor Red
            return @()
        }
        
        return $services | ConvertFrom-Json
    }
    catch {
        Write-Host "Error getting Docker service status: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

# Main function
function Main {
    if ($Help) {
        Show-Help
        return
    }
    
    Write-Host "=== FinovateX Service Health Check Validation ===" -ForegroundColor Cyan
    Write-Host ""
    
    # 检查Docker环境（如果需要）
    if ($Docker) {
        if (-not (Test-DockerAvailable)) {
            Write-Host "Docker not available, please ensure Docker is installed and running" -ForegroundColor Red
            exit 1
        }
        
        if (-not (Test-DockerComposeAvailable)) {
            Write-Host "Docker Compose not available, please ensure Docker Compose is installed" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "Using Docker environment for testing" -ForegroundColor Yellow
        
        # Check compose file
        if (-not (Test-Path $ComposeFile)) {
            Write-Host "Docker Compose file does not exist: $ComposeFile" -ForegroundColor Red
            exit 1
        }
        
        # Get service status
        Write-Host "Getting Docker service status..." -ForegroundColor Yellow
        $dockerServices = Get-DockerServiceStatus
        
        if ($dockerServices.Count -gt 0) {
            Write-Host "Docker service status:" -ForegroundColor Cyan
            foreach ($service in $dockerServices) {
                $statusColor = switch ($service.State) {
                    "running" { "Green" }
                    "exited" { "Red" }
                    default { "Yellow" }
                }
                Write-Host "  $($service.Service): $($service.State)" -ForegroundColor $statusColor
            }
            Write-Host ""
        }
    }
    else {
        Write-Host "Using local environment for testing" -ForegroundColor Yellow
    }
    
    # Execute health checks
    $allResults = @()
    $healthyCount = 0
    
    foreach ($serviceKey in $ServiceHealthChecks.Keys) {
        $serviceConfig = $ServiceHealthChecks[$serviceKey]
        
        # If Docker environment, wait for service startup
        if ($Docker) {
            Wait-ForService -ServiceName $serviceKey -TimeoutSeconds $Timeout | Out-Null
        }
        
        $result = Test-ServiceHealth -ServiceKey $serviceKey -ServiceConfig $serviceConfig
        $allResults += $result
        
        if ($result.healthy) {
            $healthyCount++
        }
    }
    
    # Display summary
    Write-Host "=== Health Check Summary ===" -ForegroundColor Cyan
    Write-Host "Total services: $($allResults.Count)" -ForegroundColor White
    Write-Host "Healthy services: $healthyCount" -ForegroundColor Green
    Write-Host "Unhealthy services: $($allResults.Count - $healthyCount)" -ForegroundColor Red
    Write-Host ""
    
    # Display unhealthy services
    $unhealthyServices = $allResults | Where-Object { -not $_.healthy }
    if ($unhealthyServices.Count -gt 0) {
        Write-Host "Unhealthy services:" -ForegroundColor Red
        foreach ($service in $unhealthyServices) {
            Write-Host "  - $($service.service)" -ForegroundColor Red
        }
        Write-Host ""
    }
    
    # Return results
    if ($healthyCount -eq $allResults.Count) {
        Write-Host "[SUCCESS] All service health checks passed!" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "[ERROR] Some service health checks failed, please check service configuration and status." -ForegroundColor Red
        exit 1
    }
}

# Execute main function
Main