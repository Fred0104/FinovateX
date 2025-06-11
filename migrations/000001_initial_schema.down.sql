-- 回滚初始数据库架构迁移
-- 删除所有创建的表、索引、触发器和函数

BEGIN;

-- 删除触发器
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
DROP TRIGGER IF EXISTS update_user_roles_updated_at ON user_roles;
DROP TRIGGER IF EXISTS update_financial_products_updated_at ON financial_products;
DROP TRIGGER IF EXISTS update_portfolios_updated_at ON portfolios;
DROP TRIGGER IF EXISTS update_data_sources_updated_at ON data_sources;
DROP TRIGGER IF EXISTS update_system_config_updated_at ON system_config;

-- 删除触发器函数
DROP FUNCTION IF EXISTS update_updated_at_column();

-- 删除表（按依赖关系逆序删除）
DROP TABLE IF EXISTS audit_logs;
DROP TABLE IF EXISTS system_config;
DROP TABLE IF EXISTS sync_jobs;
DROP TABLE IF EXISTS data_sources;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS portfolio_holdings;
DROP TABLE IF EXISTS portfolios;
DROP TABLE IF EXISTS price_data;
DROP TABLE IF EXISTS financial_products;
DROP TABLE IF EXISTS user_role_assignments;
DROP TABLE IF EXISTS user_roles;
DROP TABLE IF EXISTS users;

-- 删除扩展（如果没有其他依赖）
-- 注意：只有在确定没有其他应用使用这些扩展时才删除
-- DROP EXTENSION IF EXISTS "timescaledb";
-- DROP EXTENSION IF EXISTS "uuid-ossp";

COMMIT;