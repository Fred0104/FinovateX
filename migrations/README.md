# Database Migrations

本目录包含FinovateX项目的数据库迁移文件。

## 迁移工具

我们使用 [golang-migrate](https://github.com/golang-migrate/migrate) 作为数据库迁移工具。

### 安装

```bash
# Windows (使用 Chocolatey)
choco install migrate

# 或者使用 Go 安装
go install -tags 'postgres' github.com/golang-migrate/migrate/v4/cmd/migrate@latest

# 或者下载预编译的二进制文件
# https://github.com/golang-migrate/migrate/releases
```

## 目录结构

```
migrations/
├── README.md                    # 本文件
├── 000001_initial_schema.up.sql   # 初始数据库架构
├── 000001_initial_schema.down.sql # 回滚初始架构
├── 000002_add_users_table.up.sql  # 添加用户表
├── 000002_add_users_table.down.sql # 回滚用户表
└── ...
```

## 命名约定

- 文件名格式：`{version}_{description}.{direction}.sql`
- `version`: 6位数字，从000001开始递增
- `description`: 简短的英文描述，使用下划线分隔
- `direction`: `up` (应用迁移) 或 `down` (回滚迁移)

## 常用命令

### 创建新迁移

```bash
# 创建新的迁移文件
migrate create -ext sql -dir migrations -seq add_users_table
```

### 应用迁移

```bash
# 应用所有待执行的迁移
migrate -path migrations -database "postgres://finovatex_user:finovatex_password@localhost:5432/finovatex?sslmode=disable" up

# 应用指定数量的迁移
migrate -path migrations -database "postgres://finovatex_user:finovatex_password@localhost:5432/finovatex?sslmode=disable" up 2

# 应用到指定版本
migrate -path migrations -database "postgres://finovatex_user:finovatex_password@localhost:5432/finovatex?sslmode=disable" goto 3
```

### 回滚迁移

```bash
# 回滚一个版本
migrate -path migrations -database "postgres://finovatex_user:finovatex_password@localhost:5432/finovatex?sslmode=disable" down 1

# 回滚到指定版本
migrate -path migrations -database "postgres://finovatex_user:finovatex_password@localhost:5432/finovatex?sslmode=disable" goto 1
```

### 查看状态

```bash
# 查看当前迁移状态
migrate -path migrations -database "postgres://finovatex_user:finovatex_password@localhost:5432/finovatex?sslmode=disable" version
```

### 强制设置版本（谨慎使用）

```bash
# 强制设置当前版本（不执行迁移）
migrate -path migrations -database "postgres://finovatex_user:finovatex_password@localhost:5432/finovatex?sslmode=disable" force 1
```

## 环境变量

为了简化命令，可以设置环境变量：

```bash
# Windows PowerShell
$env:DATABASE_URL = "postgres://finovatex_user:finovatex_password@localhost:5432/finovatex?sslmode=disable"

# 然后可以简化命令
migrate -path migrations -database $env:DATABASE_URL up
```

## 最佳实践

1. **总是创建 up 和 down 文件**：确保每个迁移都可以回滚
2. **测试迁移**：在开发环境中测试 up 和 down 迁移
3. **备份数据**：在生产环境应用迁移前备份数据库
4. **原子性操作**：每个迁移文件应该包含一个逻辑单元的变更
5. **不要修改已应用的迁移**：如果需要修改，创建新的迁移文件
6. **使用事务**：在迁移文件中使用 `BEGIN;` 和 `COMMIT;` 确保原子性

## Docker 环境中的使用

```bash
# 在 Docker 容器中运行迁移
docker run --rm -v "$(pwd)/migrations:/migrations" --network finovatex-network migrate/migrate \
  -path=/migrations/ \
  -database postgres://finovatex_user:finovatex_password@postgres:5432/finovatex?sslmode=disable \
  up
```

## 集成到应用程序

在 Go 应用程序中，可以使用 golang-migrate 库来程序化地管理迁移：

```go
import (
    "github.com/golang-migrate/migrate/v4"
    _ "github.com/golang-migrate/migrate/v4/database/postgres"
    _ "github.com/golang-migrate/migrate/v4/source/file"
)

func runMigrations(databaseURL string) error {
    m, err := migrate.New(
        "file://migrations",
        databaseURL,
    )
    if err != nil {
        return err
    }
    defer m.Close()
    
    if err := m.Up(); err != nil && err != migrate.ErrNoChange {
        return err
    }
    
    return nil
}
```