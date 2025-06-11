# FinovateX - 量化交易平台

## 项目概述

FinovateX是一个高性能的量化交易平台，采用微服务架构，支持多种交易策略和风险管理功能。

## 技术栈

- **后端**: Go 1.21+ (Core Engine, API Gateway)
- **策略引擎**: Python 3.11+ (Strategy SDK, Backtesting)
- **数据库**: PostgreSQL + TimescaleDB, Redis
- **消息队列**: NATS JetStream
- **监控**: Prometheus + Grafana + Loki
- **容器化**: Docker + Docker Compose

## 开发环境设置

### 前置要求

- Go 1.21+
- Python 3.11+
- Docker & Docker Compose
- Git

### 安装依赖

```bash
# Go依赖
go mod download

# Python依赖
pip install -r requirements-dev.txt
```

### 运行测试

```bash
# Go测试
go test -v ./...

# Python测试
pytest -v --cov=src

# 代码质量检查
golangci-lint run
mypy src/
flake8 .
black --check .
```

### 启动服务

```bash
# 启动所有服务
docker-compose up -d

# 查看服务状态
docker-compose ps
```

## CI/CD 管道

项目使用GitHub Actions进行持续集成，包括：

- **代码质量检查**: golangci-lint, flake8, black, mypy
- **单元测试**: Go test, pytest
- **构建测试**: Docker Compose配置验证
- **覆盖率报告**: 自动生成测试覆盖率报告

## 项目结构

```
.
├── .github/workflows/     # CI/CD配置
├── config/               # 配置文件
├── src/                  # Python源码
├── tests/                # Python测试
├── main.go              # Go主程序
├── main_test.go         # Go测试
├── docker-compose.yml   # 容器编排
└── README.md           # 项目说明
```

## 代码质量标准

- Go代码必须通过golangci-lint检查
- Python代码必须通过flake8, black, mypy检查
- 单元测试覆盖率要求 > 80%
- 所有提交必须通过CI管道检查

## 贡献指南

1. Fork项目
2. 创建功能分支
3. 提交代码并确保通过所有检查
4. 创建Pull Request

## 许可证

本项目采用MIT许可证。