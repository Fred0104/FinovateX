// Package database 提供数据库连接和配置管理功能
package database

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"os"
	"strconv"
	"time"

	_ "github.com/lib/pq"
)

// Config 数据库配置
type Config struct {
	Host         string
	Port         int
	User         string
	Password     string
	DBName       string
	SSLMode      string
	MaxOpenConns int
	MaxIdleConns int
	MaxLifetime  time.Duration
}

// LoadConfigFromEnv 从环境变量加载数据库配置
func LoadConfigFromEnv() *Config {
	config := &Config{
		Host:         getEnvOrDefault("DB_HOST", "localhost"),
		Port:         getEnvIntOrDefault("DB_PORT", 5432),
		User:         getEnvOrDefault("DB_USER", "finovatex_user"),
		Password:     getEnvOrDefault("DB_PASSWORD", "finovatex_password"),
		DBName:       getEnvOrDefault("DB_NAME", "finovatex"),
		SSLMode:      getEnvOrDefault("DB_SSLMODE", "disable"),
		MaxOpenConns: getEnvIntOrDefault("DB_MAX_OPEN_CONNS", 25),
		MaxIdleConns: getEnvIntOrDefault("DB_MAX_IDLE_CONNS", 5),
		MaxLifetime:  time.Duration(getEnvIntOrDefault("DB_MAX_LIFETIME_MINUTES", 30)) * time.Minute,
	}

	return config
}

// DSN 生成数据库连接字符串
func (c *Config) DSN() string {
	return fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
		c.Host, c.Port, c.User, c.Password, c.DBName, c.SSLMode,
	)
}

// Connect 连接到数据库
func Connect(config *Config) (*sql.DB, error) {
	log.Printf("连接到数据库: %s:%d/%s", config.Host, config.Port, config.DBName)

	db, err := sql.Open("postgres", config.DSN())
	if err != nil {
		return nil, fmt.Errorf("打开数据库连接失败: %w", err)
	}

	// 配置连接池
	db.SetMaxOpenConns(config.MaxOpenConns)
	db.SetMaxIdleConns(config.MaxIdleConns)
	db.SetConnMaxLifetime(config.MaxLifetime)

	// 测试连接
	if err := db.Ping(); err != nil {
		if closeErr := db.Close(); closeErr != nil {
			log.Printf("关闭数据库连接时出错: %v", closeErr)
		}
		return nil, fmt.Errorf("数据库连接测试失败: %w", err)
	}

	log.Println("数据库连接成功")
	return db, nil
}

// HealthCheck 数据库健康检查
func HealthCheck(db *sql.DB) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := db.PingContext(ctx); err != nil {
		return fmt.Errorf("数据库健康检查失败: %w", err)
	}

	return nil
}

// GetStats 获取数据库连接池统计信息
func GetStats(db *sql.DB) map[string]interface{} {
	stats := db.Stats()
	return map[string]interface{}{
		"max_open_connections": stats.MaxOpenConnections,
		"open_connections":     stats.OpenConnections,
		"in_use":               stats.InUse,
		"idle":                 stats.Idle,
		"wait_count":           stats.WaitCount,
		"wait_duration":        stats.WaitDuration.String(),
		"max_idle_closed":      stats.MaxIdleClosed,
		"max_idle_time_closed": stats.MaxIdleTimeClosed,
		"max_lifetime_closed":  stats.MaxLifetimeClosed,
	}
}

// 辅助函数：获取环境变量或默认值
func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// 辅助函数：获取整数环境变量或默认值
func getEnvIntOrDefault(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
		log.Printf("警告: 环境变量 %s 的值 '%s' 不是有效整数，使用默认值 %d", key, value, defaultValue)
	}
	return defaultValue
}
