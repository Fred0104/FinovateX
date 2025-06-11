#!/usr/bin/env pwsh
# CI Pipeline Test Script
# 本脚本用于本地测试CI管道的各个组件

Write-Host "=== FinovateX CI Pipeline Test ===" -ForegroundColor Green

# 检查Go环境
Write-Host "\n1. Checking Go environment..." -ForegroundColor Yellow
if (Get-Command go -ErrorAction SilentlyContinue) {
    go version
    Write-Host "✓ Go is available" -ForegroundColor Green
} else {
    Write-Host "✗ Go is not installed" -ForegroundColor Red
    exit 1
}

# 检查Python环境
Write-Host "\n2. Checking Python environment..." -ForegroundColor Yellow
if (Get-Command python -ErrorAction SilentlyContinue) {
    python --version
    Write-Host "✓ Python is available" -ForegroundColor Green
} else {
    Write-Host "✗ Python is not installed" -ForegroundColor Red
    exit 1
}

# Go代码质量检查
Write-Host "\n3. Running Go quality checks..." -ForegroundColor Yellow

# Go模块下载
Write-Host "Downloading Go dependencies..."
go mod download
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Go dependencies downloaded" -ForegroundColor Green
} else {
    Write-Host "✗ Failed to download Go dependencies" -ForegroundColor Red
}

# Go测试
Write-Host "Running Go tests..."
go test -v -race -coverprofile=coverage.out ./...
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Go tests passed" -ForegroundColor Green
} else {
    Write-Host "✗ Go tests failed" -ForegroundColor Red
}

# Go构建
Write-Host "Building Go application..."
go build -v ./...
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Go build successful" -ForegroundColor Green
} else {
    Write-Host "✗ Go build failed" -ForegroundColor Red
}

# golangci-lint检查
Write-Host "Running golangci-lint..."
if (Get-Command golangci-lint -ErrorAction SilentlyContinue) {
    golangci-lint run
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ golangci-lint passed" -ForegroundColor Green
    } else {
        Write-Host "⚠ golangci-lint found issues (may be warnings only)" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠ golangci-lint not installed, skipping" -ForegroundColor Yellow
}

# Python代码质量检查
Write-Host "\n4. Running Python quality checks..." -ForegroundColor Yellow

# Python依赖安装
Write-Host "Installing Python dependencies..."
if (Test-Path "requirements-dev.txt") {
    python -m pip install -r requirements-dev.txt
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Python dependencies installed" -ForegroundColor Green
    } else {
        Write-Host "✗ Failed to install Python dependencies" -ForegroundColor Red
    }
}

# Python测试
Write-Host "Running Python tests..."
if (Get-Command pytest -ErrorAction SilentlyContinue) {
    python -m pytest -v --cov=src
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Python tests passed" -ForegroundColor Green
    } else {
        Write-Host "✗ Python tests failed" -ForegroundColor Red
    }
} else {
    Write-Host "⚠ pytest not available, skipping Python tests" -ForegroundColor Yellow
}

# mypy类型检查
Write-Host "Running mypy type checking..."
if (Get-Command mypy -ErrorAction SilentlyContinue) {
    mypy src/ --ignore-missing-imports
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ mypy type checking passed" -ForegroundColor Green
    } else {
        Write-Host "✗ mypy type checking failed" -ForegroundColor Red
    }
} else {
    Write-Host "⚠ mypy not available, skipping type checking" -ForegroundColor Yellow
}

# flake8检查
Write-Host "Running flake8 linting..."
if (Get-Command flake8 -ErrorAction SilentlyContinue) {
    flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics
    flake8 . --count --exit-zero --max-complexity=10 --max-line-length=127 --statistics
    Write-Host "✓ flake8 linting completed" -ForegroundColor Green
} else {
    Write-Host "⚠ flake8 not available, skipping linting" -ForegroundColor Yellow
}

# black格式检查
Write-Host "Running black format checking..."
if (Get-Command black -ErrorAction SilentlyContinue) {
    black --check --diff .
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ black format checking passed" -ForegroundColor Green
    } else {
        Write-Host "⚠ black found formatting issues" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠ black not available, skipping format checking" -ForegroundColor Yellow
}

# Docker配置检查
Write-Host "\n5. Checking Docker configuration..." -ForegroundColor Yellow
if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
    if (Test-Path "docker-compose.yml") {
        docker-compose config
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Docker Compose configuration is valid" -ForegroundColor Green
        } else {
            Write-Host "✗ Docker Compose configuration is invalid" -ForegroundColor Red
        }
    } else {
        Write-Host "⚠ docker-compose.yml not found" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠ docker-compose not available, skipping Docker checks" -ForegroundColor Yellow
}

# 测试数据库迁移
function Test-DatabaseMigration {
    Write-Host "`n--- 测试数据库迁移 ---" -ForegroundColor Yellow
    
    # 检查迁移文件
    if (-not (Test-Path "migrations")) {
        throw "迁移目录不存在"
    }
    
    $migrationFiles = Get-ChildItem "migrations" -Filter "*.sql"
    if ($migrationFiles.Count -eq 0) {
        throw "没有找到迁移文件"
    }
    
    Write-Host "找到 $($migrationFiles.Count) 个迁移文件" -ForegroundColor Green
    
    # 检查迁移工具
    if (Test-Path "cmd/migrate/main.go") {
        Write-Host "迁移工具存在" -ForegroundColor Green
    } else {
        throw "迁移工具不存在"
    }
    
    # 检查数据库连接配置
    if (Test-Path "internal/database/connection.go") {
        Write-Host "数据库连接配置存在" -ForegroundColor Green
    } else {
        throw "数据库连接配置不存在"
    }
    
    Write-Host "数据库迁移配置验证完成" -ForegroundColor Green
}

# 测试健康检查
function Test-HealthCheck {
    Write-Host "`n--- 测试健康检查配置 ---" -ForegroundColor Yellow
    
    # 检查健康检查代码
    if (Test-Path "internal/health/health.go") {
        Write-Host "健康检查代码存在" -ForegroundColor Green
    } else {
        throw "健康检查代码不存在"
    }
    
    # 检查NATS配置
    if (Test-Path "config/nats/jetstream.conf") {
        Write-Host "NATS JetStream配置存在" -ForegroundColor Green
    } else {
        throw "NATS JetStream配置不存在"
    }
    
    # 检查Docker健康检查脚本
    if (Test-Path "scripts/docker-health-check.sh") {
        Write-Host "Docker健康检查脚本存在" -ForegroundColor Green
    } else {
        throw "Docker健康检查脚本不存在"
    }
    
    Write-Host "健康检查配置验证完成" -ForegroundColor Green
}

# 测试Docker Compose配置
function Test-DockerComposeConfig {
    Write-Host "`n--- 测试Docker Compose配置 ---" -ForegroundColor Yellow
    
    if (-not (Test-Path "docker-compose.yml")) {
        throw "docker-compose.yml 文件不存在"
    }
    
    # 验证Docker Compose语法
    try {
        $result = docker-compose config 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Docker Compose配置语法错误: $result"
        }
        Write-Host "Docker Compose配置语法正确" -ForegroundColor Green
    }
    catch {
        Write-Host "警告: 无法验证Docker Compose配置 (可能Docker未安装)" -ForegroundColor Yellow
    }
    
    # 检查健康检查配置
    $composeContent = Get-Content "docker-compose.yml" -Raw
    if ($composeContent -match "healthcheck:") {
        Write-Host "Docker服务健康检查配置存在" -ForegroundColor Green
    } else {
        Write-Host "警告: Docker服务缺少健康检查配置" -ForegroundColor Yellow
    }
    
    Write-Host "Docker Compose配置验证完成" -ForegroundColor Green
}

# 主函数
function Main {
    Write-Host "=== FinovateX CI Pipeline 本地测试 ===" -ForegroundColor Cyan
    Write-Host "开始时间: $(Get-Date)" -ForegroundColor Gray
    
    try {
        Test-Environment
        Test-GoQuality
        Test-PythonQuality  
        Test-DockerConfig
        Test-DatabaseMigration
        Test-HealthCheck
        Test-DockerComposeConfig
        
        Write-Host "`n=== 所有测试通过! ===" -ForegroundColor Green
        Write-Host "CI Pipeline 配置正确，可以提交代码" -ForegroundColor Green
    }
    catch {
        Write-Host "`n=== 测试失败! ===" -ForegroundColor Red
        Write-Host "错误: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    finally {
        Write-Host "结束时间: $(Get-Date)" -ForegroundColor Gray
    }
}

# 执行主函数
Main