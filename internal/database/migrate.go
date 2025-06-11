package database

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	_ "github.com/lib/pq"
)

// MigrationManager 数据库迁移管理器
type MigrationManager struct {
	db            *sql.DB
	migrate       *migrate.Migrate
	migrationsDir string
}

// NewMigrationManager 创建新的迁移管理器
func NewMigrationManager(dbURL, migrationsDir string) (*MigrationManager, error) {
	// 获取绝对路径
	absPath, err := filepath.Abs(migrationsDir)
	if err != nil {
		return nil, fmt.Errorf("获取绝对路径失败: %w", err)
	}

	// 构建源URL - 根据golang-migrate文档，使用相对路径格式
	var sourceURL string
	// 获取相对于当前工作目录的路径
	wd, err := os.Getwd()
	if err != nil {
		return nil, fmt.Errorf("获取工作目录失败: %w", err)
	}
	relPath, err := filepath.Rel(wd, absPath)
	if err != nil {
		return nil, fmt.Errorf("计算相对路径失败: %w", err)
	}
	// 转换为Unix风格路径并使用file://前缀
	unixPath := filepath.ToSlash(relPath)
	sourceURL = "file://" + unixPath

	// 添加调试日志
	log.Printf("迁移源URL: %s", sourceURL)

	// 创建迁移实例
	m, err := migrate.New(sourceURL, dbURL)
	if err != nil {
		return nil, fmt.Errorf("创建迁移实例失败: %w", err)
	}

	return &MigrationManager{migrate: m}, nil
}

// Up 应用所有待执行的迁移
func (mm *MigrationManager) Up() error {
	log.Println("开始应用数据库迁移...")

	err := mm.migrate.Up()
	if err != nil && err != migrate.ErrNoChange {
		return fmt.Errorf("应用迁移失败: %w", err)
	}

	if err == migrate.ErrNoChange {
		log.Println("没有待应用的迁移")
	} else {
		log.Println("数据库迁移应用成功")
	}

	return nil
}

// Down 回滚指定数量的迁移
func (mm *MigrationManager) Down(steps int) error {
	log.Printf("开始回滚 %d 个迁移...", steps)

	for i := 0; i < steps; i++ {
		err := mm.migrate.Steps(-1)
		if err != nil {
			if err == migrate.ErrNoChange {
				log.Println("没有可回滚的迁移")
				break
			}
			return fmt.Errorf("回滚迁移失败: %w", err)
		}
	}

	log.Printf("成功回滚迁移")
	return nil
}

// Version 获取当前迁移版本
func (mm *MigrationManager) Version() (version uint, dirty bool, err error) {
	version, dirty, err = mm.migrate.Version()
	if err != nil {
		if err == migrate.ErrNilVersion {
			return 0, false, nil
		}
		return 0, false, fmt.Errorf("获取迁移版本失败: %w", err)
	}

	return version, dirty, nil
}

// Goto 迁移到指定版本
func (mm *MigrationManager) Goto(version uint) error {
	log.Printf("迁移到版本 %d...", version)

	err := mm.migrate.Migrate(version)
	if err != nil && err != migrate.ErrNoChange {
		return fmt.Errorf("迁移到版本 %d 失败: %w", version, err)
	}

	if err == migrate.ErrNoChange {
		log.Printf("已经是版本 %d，无需迁移", version)
	} else {
		log.Printf("成功迁移到版本 %d", version)
	}

	return nil
}

// Force 强制设置迁移版本（危险操作）
func (mm *MigrationManager) Force(version int) error {
	log.Printf("警告: 强制设置迁移版本为 %d（这不会执行实际的迁移）", version)

	err := mm.migrate.Force(version)
	if err != nil {
		return fmt.Errorf("强制设置版本失败: %w", err)
	}

	log.Printf("成功强制设置版本为 %d", version)
	return nil
}

// Drop 删除数据库中的所有内容（危险操作）
func (mm *MigrationManager) Drop() error {
	log.Println("警告: 删除数据库中的所有内容...")

	err := mm.migrate.Drop()
	if err != nil {
		return fmt.Errorf("删除数据库内容失败: %w", err)
	}

	log.Println("成功删除数据库内容")
	return nil
}

// Close 关闭迁移管理器
func (mm *MigrationManager) Close() error {
	sourceErr, dbErr := mm.migrate.Close()
	if sourceErr != nil {
		return fmt.Errorf("关闭迁移源失败: %w", sourceErr)
	}
	if dbErr != nil {
		return fmt.Errorf("关闭数据库连接失败: %w", dbErr)
	}
	return nil
}

// GetMigrationsInfo 获取迁移信息
func (mm *MigrationManager) GetMigrationsInfo() (map[string]interface{}, error) {
	version, dirty, err := mm.Version()
	if err != nil {
		return nil, err
	}

	// 扫描迁移目录获取可用的迁移文件
	files, err := filepath.Glob(filepath.Join(mm.migrationsDir, "*.sql"))
	if err != nil {
		return nil, fmt.Errorf("扫描迁移文件失败: %w", err)
	}

	info := map[string]interface{}{
		"current_version": version,
		"is_dirty":        dirty,
		"migrations_dir":  mm.migrationsDir,
		"available_files": len(files),
		"migration_files": files,
	}

	return info, nil
}

// ValidateConnection 验证数据库连接
func (mm *MigrationManager) ValidateConnection() error {
	err := mm.db.Ping()
	if err != nil {
		return fmt.Errorf("数据库连接验证失败: %w", err)
	}

	log.Println("数据库连接验证成功")
	return nil
}
