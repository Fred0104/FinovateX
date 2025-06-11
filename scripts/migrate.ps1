#!/usr/bin/env pwsh
# 数据库迁移管理脚本
# 用于管理FinovateX项目的数据库迁移

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("up", "down", "create", "version", "force", "goto", "drop")]
    [string]$Action,
    
    [Parameter(Mandatory=$false)]
    [string]$Name = "",
    
    [Parameter(Mandatory=$false)]
    [int]$Steps = 1,
    
    [Parameter(Mandatory=$false)]
    [int]$Version = 0,
    
    [Parameter(Mandatory=$false)]
    [string]$DatabaseUrl = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$Docker = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help = $false
)

# 显示帮助信息
function Show-Help {
    Write-Host "FinovateX 数据库迁移管理脚本" -ForegroundColor Green
    Write-Host ""
    Write-Host "用法:" -ForegroundColor Yellow
    Write-Host "  .\scripts\migrate.ps1 -Action [action] [options]"
    Write-Host ""
    Write-Host "操作:" -ForegroundColor Yellow
    Write-Host "  up       - 应用所有待执行的迁移"
    Write-Host "  down     - 回滚指定数量的迁移 (默认: 1)"
    Write-Host "  create   - 创建新的迁移文件"
    Write-Host "  version  - 显示当前迁移版本"
    Write-Host "  force    - 强制设置迁移版本"
    Write-Host "  goto     - 迁移到指定版本"
    Write-Host "  drop     - 删除数据库中的所有内容"
    Write-Host ""
    Write-Host "选项:" -ForegroundColor Yellow
    Write-Host "  -Name [name]        创建迁移时的名称"
Write-Host "  -Steps [number]     回滚的步数 (默认: 1)"
Write-Host "  -Version [number]   目标版本号"
Write-Host "  -DatabaseUrl [url]  数据库连接字符串"
    Write-Host "  -Docker             使用Docker环境"
    Write-Host "  -Help               显示此帮助信息"
    Write-Host ""
    Write-Host "示例:" -ForegroundColor Yellow
    Write-Host "  .\scripts\migrate.ps1 -Action up"
    Write-Host "  .\scripts\migrate.ps1 -Action down -Steps 2"
    Write-Host "  .\scripts\migrate.ps1 -Action create -Name 'add_user_preferences'"
    Write-Host "  .\scripts\migrate.ps1 -Action version"
    Write-Host "  .\scripts\migrate.ps1 -Action goto -Version 3"
    Write-Host "  .\scripts\migrate.ps1 -Action up -Docker"
}

# 检查migrate工具是否安装
function Test-MigrateTool {
    if (-not (Get-Command migrate -ErrorAction SilentlyContinue)) {
        Write-Host "错误: migrate工具未安装" -ForegroundColor Red
        Write-Host "请安装golang-migrate:" -ForegroundColor Yellow
        Write-Host "  choco install migrate" -ForegroundColor Cyan
        Write-Host "  或者从 https://github.com/golang-migrate/migrate/releases 下载"
        exit 1
    }
}

# 获取数据库连接字符串
function Get-DatabaseUrl {
    if ($DatabaseUrl -ne "") {
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
    
    # 默认本地数据库连接
    return "postgres://finovatex_user:finovatex_password@localhost:5432/finovatex?sslmode=disable"
}

# 获取迁移目录
function Get-MigrationsPath {
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    $projectRoot = Split-Path -Parent $scriptDir
    return Join-Path $projectRoot "migrations"
}

# 执行迁移命令
function Invoke-MigrateCommand {
    param(
        [string]$Command,
        [string]$DbUrl,
        [string]$MigrationsPath
    )
    
    Write-Host "执行命令: migrate -path $MigrationsPath -database $DbUrl $Command" -ForegroundColor Cyan
    
    try {
        $result = & migrate -path $MigrationsPath -database $DbUrl $Command.Split(' ')
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ 命令执行成功" -ForegroundColor Green
            if ($result) {
                Write-Host $result
            }
        } else {
            Write-Host "✗ 命令执行失败 (退出码: $LASTEXITCODE)" -ForegroundColor Red
            if ($result) {
                Write-Host $result -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "✗ 命令执行出错: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 创建新迁移
function New-Migration {
    param(
        [string]$Name,
        [string]$MigrationsPath
    )
    
    if ($Name -eq "") {
        Write-Host "错误: 创建迁移需要提供名称" -ForegroundColor Red
        Write-Host "用法: .\scripts\migrate.ps1 -Action create -Name 'migration_name'"
        exit 1
    }
    
    Write-Host "创建新迁移: $Name" -ForegroundColor Yellow
    
    try {
        & migrate create -ext sql -dir $MigrationsPath -seq $Name
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ 迁移文件创建成功" -ForegroundColor Green
            
            # 列出新创建的文件
            $files = Get-ChildItem -Path $MigrationsPath -Filter "*$Name*" | Sort-Object Name -Descending | Select-Object -First 2
            foreach ($file in $files) {
                Write-Host "  创建文件: $($file.Name)" -ForegroundColor Cyan
            }
        } else {
            Write-Host "✗ 迁移文件创建失败" -ForegroundColor Red
        }
    } catch {
        Write-Host "✗ 创建迁移出错: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 主函数
function Main {
    if ($Help) {
        Show-Help
        return
    }
    
    Write-Host "=== FinovateX 数据库迁移管理 ===" -ForegroundColor Green
    
    # 检查migrate工具
    Test-MigrateTool
    
    # 获取配置
    $dbUrl = Get-DatabaseUrl
    $migrationsPath = Get-MigrationsPath
    
    Write-Host "数据库URL: $($dbUrl -replace 'password=[^@]*', 'password=***')" -ForegroundColor Cyan
    Write-Host "迁移目录: $migrationsPath" -ForegroundColor Cyan
    Write-Host ""
    
    # 检查迁移目录是否存在
    if (-not (Test-Path $migrationsPath)) {
        Write-Host "错误: 迁移目录不存在: $migrationsPath" -ForegroundColor Red
        exit 1
    }
    
    # 执行相应操作
    switch ($Action.ToLower()) {
        "up" {
            Write-Host "应用所有待执行的迁移..." -ForegroundColor Yellow
            Invoke-MigrateCommand "up" $dbUrl $migrationsPath
        }
        "down" {
            Write-Host "回滚 $Steps 个迁移..." -ForegroundColor Yellow
            Invoke-MigrateCommand "down $Steps" $dbUrl $migrationsPath
        }
        "create" {
            New-Migration $Name $migrationsPath
        }
        "version" {
            Write-Host "查询当前迁移版本..." -ForegroundColor Yellow
            Invoke-MigrateCommand "version" $dbUrl $migrationsPath
        }
        "force" {
            if ($Version -eq 0) {
                Write-Host "错误: 强制设置版本需要提供版本号" -ForegroundColor Red
                Write-Host "用法: .\scripts\migrate.ps1 -Action force -Version [number]"
                exit 1
            }
            Write-Host "强制设置迁移版本为 $Version..." -ForegroundColor Yellow
            Write-Host "警告: 这是一个危险操作，不会执行实际的迁移!" -ForegroundColor Red
            Invoke-MigrateCommand "force $Version" $dbUrl $migrationsPath
        }
        "goto" {
            if ($Version -eq 0) {
                Write-Host "错误: 跳转到指定版本需要提供版本号" -ForegroundColor Red
                Write-Host "用法: .\scripts\migrate.ps1 -Action goto -Version [number]"
                exit 1
            }
            Write-Host "迁移到版本 $Version..." -ForegroundColor Yellow
            Invoke-MigrateCommand "goto $Version" $dbUrl $migrationsPath
        }
        "drop" {
            Write-Host "警告: 这将删除数据库中的所有内容!" -ForegroundColor Red
            $confirmation = Read-Host "确认删除所有数据? (输入 'YES' 确认)"
            if ($confirmation -eq "YES") {
                Write-Host "删除数据库内容..." -ForegroundColor Yellow
                Invoke-MigrateCommand "drop" $dbUrl $migrationsPath
            } else {
                Write-Host "操作已取消" -ForegroundColor Yellow
            }
        }
        default {
            Write-Host "错误: 未知操作 '$Action'" -ForegroundColor Red
            Show-Help
            exit 1
        }
    }
    
    Write-Host "\n=== 操作完成 ===" -ForegroundColor Green
}

# 执行主函数
Main