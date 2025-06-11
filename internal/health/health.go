// Package health 提供应用程序健康检查功能
package health

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/go-redis/redis/v8"
	"github.com/nats-io/nats.go"
)

// Status 健康检查状态
type Status string

const (
	StatusHealthy   Status = "healthy"
	StatusUnhealthy Status = "unhealthy"
	StatusDegraded  Status = "degraded"
)

// CheckResult 单个检查结果
type CheckResult struct {
	Name      string                 `json:"name"`
	Status    Status                 `json:"status"`
	Message   string                 `json:"message,omitempty"`
	Timestamp time.Time              `json:"timestamp"`
	Duration  time.Duration          `json:"duration"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
}

// HealthResponse 健康检查响应
type HealthResponse struct {
	Status    Status                 `json:"status"`
	Timestamp time.Time              `json:"timestamp"`
	Version   string                 `json:"version,omitempty"`
	Checks    map[string]CheckResult `json:"checks"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
}

// Checker 健康检查接口
type Checker interface {
	Check(ctx context.Context) CheckResult
}

// Manager 健康检查管理器
type Manager struct {
	checkers map[string]Checker
	version  string
}

// NewManager 创建新的健康检查管理器
func NewManager(version string) *Manager {
	return &Manager{
		checkers: make(map[string]Checker),
		version:  version,
	}
}

// AddChecker 添加检查器
func (m *Manager) AddChecker(name string, checker Checker) {
	m.checkers[name] = checker
}

// Check 执行所有健康检查
func (m *Manager) Check(ctx context.Context) HealthResponse {
	start := time.Now()
	checks := make(map[string]CheckResult)
	overallStatus := StatusHealthy

	// 并发执行所有检查
	resultChan := make(chan struct {
		name   string
		result CheckResult
	}, len(m.checkers))

	for name, checker := range m.checkers {
		go func(n string, c Checker) {
			result := c.Check(ctx)
			resultChan <- struct {
				name   string
				result CheckResult
			}{name: n, result: result}
		}(name, checker)
	}

	// 收集结果
	for i := 0; i < len(m.checkers); i++ {
		select {
		case result := <-resultChan:
			checks[result.name] = result.result
			if result.result.Status == StatusUnhealthy {
				overallStatus = StatusUnhealthy
			} else if result.result.Status == StatusDegraded && overallStatus == StatusHealthy {
				overallStatus = StatusDegraded
			}
		case <-ctx.Done():
			overallStatus = StatusUnhealthy
			return HealthResponse{
				Status:    overallStatus,
				Timestamp: start,
				Version:   m.version,
				Checks:    checks,
			}
		}
	}

	return HealthResponse{
		Status:    overallStatus,
		Timestamp: start,
		Version:   m.version,
		Checks:    checks,
		Metadata: map[string]interface{}{
			"total_duration": time.Since(start),
			"checks_count":   len(checks),
		},
	}
}

// Handler 返回Gin处理函数
func (m *Manager) Handler() gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
		defer cancel()

		result := m.Check(ctx)

		// 根据状态设置HTTP状态码
		var statusCode int
		switch result.Status {
		case StatusHealthy:
			statusCode = http.StatusOK
		case StatusDegraded:
			statusCode = http.StatusOK // 降级状态仍返回200
		case StatusUnhealthy:
			statusCode = http.StatusServiceUnavailable
		default:
			statusCode = http.StatusInternalServerError
		}

		c.JSON(statusCode, result)
	}
}

// DatabaseChecker 数据库健康检查器
type DatabaseChecker struct {
	db *sql.DB
}

// NewDatabaseChecker 创建数据库检查器
func NewDatabaseChecker(db *sql.DB) *DatabaseChecker {
	return &DatabaseChecker{db: db}
}

// Check 执行数据库健康检查
func (d *DatabaseChecker) Check(ctx context.Context) CheckResult {
	start := time.Now()
	result := CheckResult{
		Name:      "database",
		Timestamp: start,
	}

	// 检查数据库连接
	if err := d.db.PingContext(ctx); err != nil {
		result.Status = StatusUnhealthy
		result.Message = fmt.Sprintf("数据库连接失败: %v", err)
		result.Duration = time.Since(start)
		return result
	}

	// 获取连接池统计信息
	stats := d.db.Stats()
	result.Status = StatusHealthy
	result.Message = "数据库连接正常"
	result.Duration = time.Since(start)
	result.Metadata = map[string]interface{}{
		"open_connections": stats.OpenConnections,
		"in_use":           stats.InUse,
		"idle":             stats.Idle,
		"wait_count":       stats.WaitCount,
	}

	// 检查连接池是否健康
	if stats.OpenConnections >= stats.MaxOpenConnections {
		result.Status = StatusDegraded
		result.Message = "数据库连接池接近满载"
	}

	return result
}

// RedisChecker Redis健康检查器
type RedisChecker struct {
	client *redis.Client
}

// NewRedisChecker 创建Redis检查器
func NewRedisChecker(client *redis.Client) *RedisChecker {
	return &RedisChecker{client: client}
}

// Check 执行Redis健康检查
func (r *RedisChecker) Check(ctx context.Context) CheckResult {
	start := time.Now()
	result := CheckResult{
		Name:      "redis",
		Timestamp: start,
	}

	// 检查Redis连接
	pong, err := r.client.Ping(ctx).Result()
	if err != nil {
		result.Status = StatusUnhealthy
		result.Message = fmt.Sprintf("Redis连接失败: %v", err)
		result.Duration = time.Since(start)
		return result
	}

	// 获取Redis信息
	info, err := r.client.Info(ctx, "memory", "clients").Result()
	if err != nil {
		result.Status = StatusDegraded
		result.Message = "无法获取Redis信息"
	} else {
		result.Status = StatusHealthy
		result.Message = fmt.Sprintf("Redis连接正常: %s", pong)
		result.Metadata = map[string]interface{}{
			"info": info,
		}
	}

	result.Duration = time.Since(start)
	return result
}

// NATSChecker NATS健康检查器
type NATSChecker struct {
	conn *nats.Conn
}

// NewNATSChecker 创建NATS检查器
func NewNATSChecker(conn *nats.Conn) *NATSChecker {
	return &NATSChecker{conn: conn}
}

// Check 执行NATS健康检查
func (n *NATSChecker) Check(ctx context.Context) CheckResult {
	start := time.Now()
	result := CheckResult{
		Name:      "nats",
		Timestamp: start,
	}

	// 检查NATS连接状态
	if !n.conn.IsConnected() {
		result.Status = StatusUnhealthy
		result.Message = "NATS连接断开"
		result.Duration = time.Since(start)
		return result
	}

	// 检查服务器信息
	stats := n.conn.Stats()
	result.Status = StatusHealthy
	result.Message = "NATS连接正常"
	result.Duration = time.Since(start)
	result.Metadata = map[string]interface{}{
		"in_msgs":    stats.InMsgs,
		"out_msgs":   stats.OutMsgs,
		"in_bytes":   stats.InBytes,
		"out_bytes":  stats.OutBytes,
		"reconnects": stats.Reconnects,
	}

	// 如果重连次数过多，标记为降级
	if stats.Reconnects > 5 {
		result.Status = StatusDegraded
		result.Message = "NATS重连次数较多"
	}

	return result
}

// SimpleChecker 简单的健康检查器
type SimpleChecker struct {
	name    string
	checkFn func(ctx context.Context) (Status, string, map[string]interface{})
}

// NewSimpleChecker 创建简单检查器
func NewSimpleChecker(name string, checkFn func(ctx context.Context) (Status, string, map[string]interface{})) *SimpleChecker {
	return &SimpleChecker{
		name:    name,
		checkFn: checkFn,
	}
}

// Check 执行检查
func (s *SimpleChecker) Check(ctx context.Context) CheckResult {
	start := time.Now()
	status, message, metadata := s.checkFn(ctx)

	return CheckResult{
		Name:      s.name,
		Status:    status,
		Message:   message,
		Timestamp: start,
		Duration:  time.Since(start),
		Metadata:  metadata,
	}
}
