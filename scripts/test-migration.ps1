# 数据库迁移测试脚本
# 用于验证数据库迁移的完整性和正确性

param(
    [string]$DatabaseUrl = "",
    [switch]$Docker = $false,
    [switch]$Help = $false
)

# 显示帮助信息
function Show-Help {
    Write-Host "数据库迁移测试脚本" -ForegroundColor Green
    Write-Host "用法: .\test-migration.ps1 [选项]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "选项:"
    Write-Host "  -DatabaseUrl [url]    指定数据库连接URL"
    Write-Host "  -Docker               使用Docker环境的数据库"
    Write-Host "  -Help                 显示此帮助信息"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  .\test-migration.ps1 -Docker"
    Write-Host "  .\test-migration.ps1 -DatabaseUrl 'postgres://user:pass@localhost:5432/dbname?sslmode=disable'"
}

# 检查migrate工具是否存在
function Test-MigrateTool {
    try {
        $null = Get-Command "migrate" -ErrorAction Stop
        return $true
    }
    catch {
        Write-Error "migrate工具未找到。请先安装golang-migrate工具。"
        Write-Host "安装方法: go install -tags 'postgres' github.com/golang-migrate/migrate/v4/cmd/migrate@latest" -ForegroundColor Yellow
        return $false
    }
}

# 获取数据库连接URL
function Get-DatabaseUrl {
    if ($DatabaseUrl) {
        return $DatabaseUrl
    }
    
    if ($Docker) {
        return "postgres://finovatex_user:finovatex_password@localhost:5432/finovatex?sslmode=disable"
    }
    
    # 尝试从环境变量获取
    $envUrl = $env:DATABASE_URL
    if ($envUrl) {
        return $envUrl
    }
    
    # 默认本地数据库URL
    return "postgres://finovatex_user:finovatex_password@localhost:5432/finovatex?sslmode=disable"
}

# 获取迁移文件路径
function Get-MigrationsPath {
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    $projectRoot = Split-Path -Parent $scriptDir
    return Join-Path $projectRoot "migrations"
}

# 测试数据库连接
function Test-DatabaseConnection {
    param([string]$DbUrl)
    
    Write-Host "测试数据库连接..." -ForegroundColor Yellow
    
    try {
        # 使用psql测试连接（如果可用）
        if (Get-Command "psql" -ErrorAction SilentlyContinue) {
            $result = psql $DbUrl -c "SELECT 1;" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✓ 数据库连接成功" -ForegroundColor Green
                return $true
            }
        }
        
        # 使用migrate工具测试连接
        $migrationsPath = Get-MigrationsPath
        $result = migrate -path $migrationsPath -database $DbUrl version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ 数据库连接成功" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "✗ 数据库连接失败: $result" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ 数据库连接测试失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 获取当前迁移版本
function Get-CurrentMigrationVersion {
    param([string]$DbUrl)
    
    $migrationsPath = Get-MigrationsPath
    try {
        $result = migrate -path $migrationsPath -database $DbUrl version 2>&1
        if ($LASTEXITCODE -eq 0) {
            # 解析版本号
            if ($result -match "(\d+)") {
                return [int]$matches[1]
            }
        }
        return $null
    }
    catch {
        return $null
    }
}

# 测试迁移up操作
function Test-MigrationUp {
    param([string]$DbUrl)
    
    Write-Host "测试迁移UP操作..." -ForegroundColor Yellow
    
    $migrationsPath = Get-MigrationsPath
    try {
        $result = migrate -path $migrationsPath -database $DbUrl up 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ 迁移UP操作成功" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "✗ 迁移UP操作失败: $result" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ 迁移UP操作异常: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 测试迁移down操作
function Test-MigrationDown {
    param([string]$DbUrl, [int]$Steps = 1)
    
    Write-Host "测试迁移DOWN操作 (回退 $Steps 步)..." -ForegroundColor Yellow
    
    $migrationsPath = Get-MigrationsPath
    try {
        $result = migrate -path $migrationsPath -database $DbUrl down $Steps 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ 迁移DOWN操作成功" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "✗ 迁移DOWN操作失败: $result" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ 迁移DOWN操作异常: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 验证数据库模式
function Test-DatabaseSchema {
    param([string]$DbUrl)
    
    Write-Host "验证数据库模式..." -ForegroundColor Yellow
    
    # 检查必要的表是否存在
    $requiredTables = @(
        "users",
        "roles", 
        "financial_products",
        "price_data",
        "portfolios",
        "holdings",
        "schema_migrations"
    )
    
    $allTablesExist = $true
    
    foreach ($table in $requiredTables) {
        try {
            if (Get-Command "psql" -ErrorAction SilentlyContinue) {
                $result = psql $DbUrl -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = '$table');" -t 2>&1
                if ($result -match "t") {
                    Write-Host "  ✓ 表 '$table' 存在" -ForegroundColor Green
                }
                else {
                    Write-Host "  ✗ 表 '$table' 不存在" -ForegroundColor Red
                    $allTablesExist = $false
                }
            }
            else {
                Write-Host "  ? 无法验证表 '$table' (psql不可用)" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "  ✗ 验证表 '$table' 时出错: $($_.Exception.Message)" -ForegroundColor Red
            $allTablesExist = $false
        }
    }
    
    return $allTablesExist
}

# 主函数
function Main {
    if ($Help) {
        Show-Help
        return
    }
    
    Write-Host "=== FinovateX 数据库迁移测试 ===" -ForegroundColor Cyan
    Write-Host ""
    
    # 检查migrate工具
    if (-not (Test-MigrateTool)) {
        exit 1
    }
    
    # 获取数据库URL
    $dbUrl = Get-DatabaseUrl
    Write-Host "使用数据库URL: $($dbUrl -replace 'password=[^@]*', 'password=***')" -ForegroundColor Cyan
    Write-Host ""
    
    # 测试数据库连接
    if (-not (Test-DatabaseConnection -DbUrl $dbUrl)) {
        Write-Host "数据库连接失败，请检查数据库服务是否运行" -ForegroundColor Red
        exit 1
    }
    
    # 获取当前版本
    $currentVersion = Get-CurrentMigrationVersion -DbUrl $dbUrl
    if ($currentVersion -ne $null) {
        Write-Host "当前迁移版本: $currentVersion" -ForegroundColor Cyan
    }
    else {
        Write-Host "当前迁移版本: 未知或无迁移" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # 测试迁移操作
    $testResults = @()
    
    # 测试UP操作
    $upResult = Test-MigrationUp -DbUrl $dbUrl
    $testResults += @{Name="Migration UP"; Result=$upResult}
    
    # 验证数据库模式
    $schemaResult = Test-DatabaseSchema -DbUrl $dbUrl
    $testResults += @{Name="Database Schema"; Result=$schemaResult}
    
    # 测试DOWN操作（如果有迁移的话）
    $newVersion = Get-CurrentMigrationVersion -DbUrl $dbUrl
    if ($newVersion -gt 0) {
        $downResult = Test-MigrationDown -DbUrl $dbUrl -Steps 1
        $testResults += @{Name="Migration DOWN"; Result=$downResult}
        
        # 重新应用迁移
        if ($downResult) {
            Write-Host "重新应用迁移..." -ForegroundColor Yellow
            $reupResult = Test-MigrationUp -DbUrl $dbUrl
            $testResults += @{Name="Migration Re-UP"; Result=$reupResult}
        }
    }
    
    # 显示测试结果摘要
    Write-Host ""
    Write-Host "=== 测试结果摘要 ===" -ForegroundColor Cyan
    $allPassed = $true
    foreach ($test in $testResults) {
        $status = if ($test.Result) { "✓ 通过" } else { "✗ 失败" }
        $color = if ($test.Result) { "Green" } else { "Red" }
        Write-Host "  $($test.Name): $status" -ForegroundColor $color
        if (-not $test.Result) {
            $allPassed = $false
        }
    }
    
    Write-Host ""
    if ($allPassed) {
        Write-Host "🎉 所有测试通过！数据库迁移工作正常。" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "❌ 部分测试失败，请检查数据库迁移配置。" -ForegroundColor Red
        exit 1
    }
}

# 执行主函数
Main