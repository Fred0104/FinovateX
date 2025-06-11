package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/finovatex/finovatex/internal/database"
)

func main() {
	if err := run(); err != nil {
		log.Fatalf("执行失败: %v", err)
	}
}

func run() error {
	// 解析命令行参数
	action := flag.String("action", "", "操作类型: up, down, version, goto, force, drop, create, info")
	steps := flag.Int("steps", 1, "down操作的步数")
	version := flag.Uint("version", 0, "goto或force操作的目标版本")
	forceVer := flag.Int("force", -1, "强制设置的版本号")
	migrationName := flag.String("name", "", "create操作的迁移文件名")
	migrationsDir := flag.String("dir", "./migrations", "迁移文件目录")
	flag.Parse()

	if *action == "" {
		return fmt.Errorf("请指定操作类型")
	}

	// 连接数据库
	config := database.LoadConfigFromEnv()
	db, err := database.Connect(config)
	if err != nil {
		return fmt.Errorf("数据库连接失败: %w", err)
	}
	defer func() {
		if db != nil {
			if closeErr := db.Close(); closeErr != nil {
				log.Printf("关闭数据库连接失败: %v", closeErr)
			}
		}
	}()

	// 构建postgres URL格式的连接字符串
	dbURL := fmt.Sprintf("postgres://%s:%s@%s:%d/%s?sslmode=%s",
		config.User, config.Password, config.Host, config.Port, config.DBName, config.SSLMode)
	
	// 创建迁移管理器
	mm, err := database.NewMigrationManager(dbURL, *migrationsDir)
	if err != nil {
		return fmt.Errorf("创建迁移管理器失败: %w", err)
	}
	defer func() {
		if closeErr := mm.Close(); closeErr != nil {
			log.Printf("关闭迁移管理器失败: %v", closeErr)
		}
	}()

	// 执行操作
	switch *action {
	case "up":
		return handleUp(mm)
	case "down":
		return handleDown(mm, *steps)
	case "version":
		return handleVersion(mm)
	case "goto":
		return handleGoto(mm, *version)
	case "force":
		return handleForce(mm, *forceVer)
	case "drop":
		return handleDrop(mm)
	case "create":
		return handleCreate(*migrationsDir, *migrationName)
	case "info":
		return handleInfo(mm)
	default:
		return fmt.Errorf("未知操作: %s", *action)
	}
}

// handleUp 处理up操作
func handleUp(mm *database.MigrationManager) error {
	if err := mm.Up(); err != nil {
		return fmt.Errorf("应用迁移失败: %w", err)
	}
	fmt.Println("操作完成")
	return nil
}

// handleDown 处理down操作
func handleDown(mm *database.MigrationManager, steps int) error {
	if err := mm.Down(steps); err != nil {
		return fmt.Errorf("回滚迁移失败: %w", err)
	}
	fmt.Println("操作完成")
	return nil
}

// handleVersion 处理version操作
func handleVersion(mm *database.MigrationManager) error {
	ver, dirty, err := mm.Version()
	if err != nil {
		return fmt.Errorf("获取版本失败: %w", err)
	}
	if dirty {
		fmt.Printf("当前版本: %d (脏状态)\n", ver)
	} else {
		fmt.Printf("当前版本: %d\n", ver)
	}
	return nil
}

// handleGoto 处理goto操作
func handleGoto(mm *database.MigrationManager, version uint) error {
	if version == 0 {
		return fmt.Errorf("goto操作需要指定版本号")
	}
	if err := mm.Goto(version); err != nil {
		return fmt.Errorf("迁移到版本 %d 失败: %w", version, err)
	}
	fmt.Println("操作完成")
	return nil
}

// handleForce 处理force操作
func handleForce(mm *database.MigrationManager, forceVer int) error {
	if err := mm.Force(forceVer); err != nil {
		return fmt.Errorf("强制设置版本失败: %w", err)
	}
	fmt.Println("操作完成")
	return nil
}

// handleDrop 处理drop操作
func handleDrop(mm *database.MigrationManager) error {
	fmt.Print("警告: 这将删除数据库中的所有内容！确认请输入 'yes': ")
	var confirm string
	if _, err := fmt.Scanln(&confirm); err != nil {
		log.Printf("读取用户输入失败: %v", err)
		return fmt.Errorf("读取用户输入失败: %w", err)
	}
	if confirm != "yes" {
		fmt.Println("操作已取消")
		return nil
	}
	if err := mm.Drop(); err != nil {
		return fmt.Errorf("删除数据库内容失败: %w", err)
	}
	fmt.Println("操作完成")
	return nil
}

// handleCreate 处理create操作
func handleCreate(migrationsDir, migrationName string) error {
	if migrationName == "" {
		return fmt.Errorf("create操作需要指定迁移文件名")
	}
	if err := createMigrationFiles(migrationsDir, migrationName); err != nil {
		return fmt.Errorf("创建迁移文件失败: %w", err)
	}
	fmt.Println("操作完成")
	return nil
}

// handleInfo 处理info操作
func handleInfo(mm *database.MigrationManager) error {
	info, err := mm.GetMigrationsInfo()
	if err != nil {
		return fmt.Errorf("获取迁移信息失败: %w", err)
	}
	fmt.Println("迁移信息:")
	for key, value := range info {
		fmt.Printf("  %s: %v\n", key, value)
	}
	return nil
}

// createMigrationFiles 创建新的迁移文件
func createMigrationFiles(migrationsDir, name string) error {
	// 确保迁移目录存在
	if err := os.MkdirAll(migrationsDir, 0750); err != nil {
		return fmt.Errorf("创建迁移目录失败: %w", err)
	}

	// 获取下一个版本号
	files, err := filepath.Glob(filepath.Join(migrationsDir, "*.up.sql"))
	if err != nil {
		return fmt.Errorf("扫描迁移文件失败: %w", err)
	}

	nextVersion := len(files) + 1
	versionStr := fmt.Sprintf("%06d", nextVersion)

	// 创建up文件
	upFile := filepath.Join(migrationsDir, fmt.Sprintf("%s_%s.up.sql", versionStr, name))
	if err := os.WriteFile(upFile, []byte("-- Add your up migration here\n"), 0600); err != nil {
		return fmt.Errorf("创建up文件失败: %w", err)
	}

	// 创建down文件
	downFile := filepath.Join(migrationsDir, fmt.Sprintf("%s_%s.down.sql", versionStr, name))
	if err := os.WriteFile(downFile, []byte("-- Add your down migration here\n"), 0600); err != nil {
		return fmt.Errorf("创建down文件失败: %w", err)
	}

	fmt.Printf("创建迁移文件:\n")
	fmt.Printf("  Up:   %s\n", upFile)
	fmt.Printf("  Down: %s\n", downFile)

	return nil
}
