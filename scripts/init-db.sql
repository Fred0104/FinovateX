-- FinovateX Database Initialization Script
-- This script sets up the basic database structure and enables TimescaleDB extension

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- Create schemas for different modules
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS trading;
CREATE SCHEMA IF NOT EXISTS strategy;
CREATE SCHEMA IF NOT EXISTS ai;
CREATE SCHEMA IF NOT EXISTS monitoring;

-- Set default search path
ALTER DATABASE finovatex SET search_path TO core, trading, strategy, ai, monitoring, public;

-- Create basic tables for system configuration
CREATE TABLE IF NOT EXISTS core.system_config (
    id SERIAL PRIMARY KEY,
    config_key VARCHAR(255) UNIQUE NOT NULL,
    config_value TEXT,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create table for exchange configurations
CREATE TABLE IF NOT EXISTS trading.exchanges (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    display_name VARCHAR(200),
    api_endpoint VARCHAR(500),
    is_active BOOLEAN DEFAULT true,
    config JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create table for trading pairs
CREATE TABLE IF NOT EXISTS trading.trading_pairs (
    id SERIAL PRIMARY KEY,
    exchange_id INTEGER REFERENCES trading.exchanges(id),
    symbol VARCHAR(50) NOT NULL,
    base_asset VARCHAR(20) NOT NULL,
    quote_asset VARCHAR(20) NOT NULL,
    is_active BOOLEAN DEFAULT true,
    min_quantity DECIMAL(20,8),
    max_quantity DECIMAL(20,8),
    tick_size DECIMAL(20,8),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(exchange_id, symbol)
);

-- Create hypertable for market data (time-series)
CREATE TABLE IF NOT EXISTS trading.market_data (
    time TIMESTAMPTZ NOT NULL,
    exchange_id INTEGER NOT NULL,
    symbol VARCHAR(50) NOT NULL,
    data_type VARCHAR(20) NOT NULL, -- 'kline', 'ticker', 'trade', 'orderbook'
    open_price DECIMAL(20,8),
    high_price DECIMAL(20,8),
    low_price DECIMAL(20,8),
    close_price DECIMAL(20,8),
    volume DECIMAL(20,8),
    quote_volume DECIMAL(20,8),
    trade_count INTEGER,
    raw_data JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Convert market_data to hypertable (TimescaleDB)
SELECT create_hypertable('trading.market_data', 'time', if_not_exists => TRUE);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_market_data_exchange_symbol_time 
    ON trading.market_data (exchange_id, symbol, time DESC);
CREATE INDEX IF NOT EXISTS idx_market_data_type_time 
    ON trading.market_data (data_type, time DESC);

-- Create table for strategies
CREATE TABLE IF NOT EXISTS strategy.strategies (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) UNIQUE NOT NULL,
    description TEXT,
    strategy_type VARCHAR(50) NOT NULL, -- 'python', 'visual', 'ai'
    status VARCHAR(20) DEFAULT 'inactive', -- 'active', 'inactive', 'paused', 'error'
    config JSONB,
    code TEXT,
    container_id VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert default system configurations
INSERT INTO core.system_config (config_key, config_value, description) VALUES
    ('system.version', '1.0.0', 'System version'),
    ('system.environment', 'development', 'Current environment'),
    ('data.retention_days', '365', 'Data retention period in days'),
    ('risk.max_position_size', '0.1', 'Maximum position size as percentage of portfolio')
ON CONFLICT (config_key) DO NOTHING;

-- Insert default exchange configurations
INSERT INTO trading.exchanges (name, display_name, api_endpoint, config) VALUES
    ('binance', 'Binance', 'https://api.binance.com', '{"testnet": false, "rate_limit": 1200}'),
    ('binance_testnet', 'Binance Testnet', 'https://testnet.binance.vision', '{"testnet": true, "rate_limit": 1200}')
ON CONFLICT (name) DO NOTHING;

-- Create user for application access (if needed)
-- Note: This user should have limited permissions in production
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'finovatex_app') THEN
        CREATE ROLE finovatex_app WITH LOGIN PASSWORD 'finovatex_app_password';
        GRANT CONNECT ON DATABASE finovatex TO finovatex_app;
        GRANT USAGE ON SCHEMA core, trading, strategy, ai, monitoring TO finovatex_app;
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA core, trading, strategy, ai, monitoring TO finovatex_app;
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA core, trading, strategy, ai, monitoring TO finovatex_app;
    END IF;
END
$$;

-- Log initialization completion
INSERT INTO core.system_config (config_key, config_value, description) VALUES
    ('db.initialized_at', NOW()::TEXT, 'Database initialization timestamp')
ON CONFLICT (config_key) DO UPDATE SET 
    config_value = NOW()::TEXT,
    updated_at = NOW();
