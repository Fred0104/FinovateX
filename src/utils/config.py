"""Configuration management for FinovateX platform."""

import os
from typing import Any, Dict, Optional
from pathlib import Path


class Config:
    """Configuration manager for the application."""

    def __init__(self, config_file: Optional[str] = None):
        """Initialize configuration.

        Args:
            config_file: Path to configuration file (optional)
        """
        self._config: Dict[str, Any] = {}
        self._load_defaults()

        if config_file and Path(config_file).exists():
            self._load_from_file(config_file)

        # 环境变量覆盖配置文件
        self._load_from_env()

    def _load_defaults(self) -> None:
        """Load default configuration values."""
        self._config = {
            "app": {
                "name": "finovatex",
                "version": "0.1.0",
                "debug": False,
                "port": 8080,
            },
            "database": {
                "host": "localhost",
                "port": 5432,
                "name": "finovatex",
                "user": "postgres",
                "password": "",
            },
            "redis": {
                "host": "localhost",
                "port": 6379,
                "db": 0,
            },
            "logging": {
                "level": "INFO",
                "format": (
                    "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
                ),
            },
            "monitoring": {
                "prometheus_port": 9090,
                "metrics_enabled": True,
            },
        }

    def _load_from_env(self) -> None:
        """Load configuration from environment variables."""
        # App配置
        if os.getenv("DEBUG"):
            self._config["app"]["debug"] = os.getenv("DEBUG", "false").lower() == "true"
        if os.getenv("PORT"):
            self._config["app"]["port"] = int(os.getenv("PORT", "8000"))

        # 数据库配置
        if os.getenv("DB_HOST"):
            self._config["database"]["host"] = os.getenv("DB_HOST")
        if os.getenv("DB_PORT"):
            self._config["database"]["port"] = int(os.getenv("DB_PORT", "5432"))
        if os.getenv("DB_NAME"):
            self._config["database"]["name"] = os.getenv("DB_NAME")
        if os.getenv("DB_USER"):
            self._config["database"]["user"] = os.getenv("DB_USER")
        if os.getenv("DB_PASSWORD"):
            self._config["database"]["password"] = os.getenv("DB_PASSWORD")

        # Redis配置
        if os.getenv("REDIS_HOST"):
            self._config["redis"]["host"] = os.getenv("REDIS_HOST")
        if os.getenv("REDIS_PORT"):
            self._config["redis"]["port"] = int(os.getenv("REDIS_PORT", "6379"))
        if os.getenv("REDIS_DB"):
            self._config["redis"]["db"] = int(os.getenv("REDIS_DB", "0"))

        # 日志配置
        if os.getenv("LOG_LEVEL"):
            self._config["logging"]["level"] = os.getenv("LOG_LEVEL")

    def _load_from_file(self, config_file: str) -> None:
        """Load configuration from file.

        Args:
            config_file: Path to configuration file
        """
        # 这里可以添加YAML/JSON配置文件加载逻辑
        pass

    def get(self, key: str, default: Any = None) -> Any:
        """Get configuration value by key.

        Args:
            key: Configuration key (supports dot notation, e.g., 'app.debug')
            default: Default value if key not found

        Returns:
            Configuration value
        """
        keys = key.split(".")
        value = self._config

        try:
            for k in keys:
                value = value[k]
            return value
        except (KeyError, TypeError):
            return default

    def set(self, key: str, value: Any) -> None:
        """Set configuration value.

        Args:
            key: Configuration key (supports dot notation)
            value: Value to set
        """
        keys = key.split(".")
        config = self._config

        for k in keys[:-1]:
            if k not in config:
                config[k] = {}
            config = config[k]

        config[keys[-1]] = value

    def to_dict(self) -> Dict[str, Any]:
        """Get all configuration as dictionary.

        Returns:
            Configuration dictionary
        """
        return self._config.copy()
