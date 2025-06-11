"""Tests for utility modules."""

import pytest
import logging
from unittest.mock import patch, MagicMock

from src.utils.logger import get_logger, StructuredLogger
from src.utils.config import Config


class TestLogger:
    """Test logger utilities."""

    def test_get_logger_default(self):
        """Test getting logger with default settings."""
        logger = get_logger("test_logger")
        assert isinstance(logger, logging.Logger)
        assert logger.name == "test_logger"
        assert logger.level == logging.INFO

    def test_get_logger_with_level(self):
        """Test getting logger with specific level."""
        logger = get_logger("test_logger_debug", "DEBUG")
        assert logger.level == logging.DEBUG

    def test_structured_logger(self):
        """Test structured logger functionality."""
        with patch("src.utils.logger.get_logger") as mock_get_logger:
            mock_logger = MagicMock()
            mock_get_logger.return_value = mock_logger

            structured_logger = StructuredLogger("test")
            structured_logger.info("test message", user_id=123, action="login")

            mock_logger.info.assert_called_once_with(
                "test message | user_id=123 action=login"
            )

    def test_structured_logger_without_kwargs(self):
        """Test structured logger without extra data."""
        with patch("src.utils.logger.get_logger") as mock_get_logger:
            mock_logger = MagicMock()
            mock_get_logger.return_value = mock_logger

            structured_logger = StructuredLogger("test")
            structured_logger.info("simple message")

            mock_logger.info.assert_called_once_with("simple message")


class TestConfig:
    """Test configuration management."""

    def test_config_defaults(self):
        """Test default configuration values."""
        config = Config()
        assert config.get("app.name") == "finovatex"
        assert config.get("app.version") == "0.1.0"
        assert config.get("app.debug") is False
        assert config.get("app.port") == 8080

    def test_config_get_with_default(self):
        """Test getting configuration with default value."""
        config = Config()
        assert config.get("nonexistent.key", "default_value") == "default_value"

    def test_config_set_and_get(self):
        """Test setting and getting configuration values."""
        config = Config()
        config.set("test.key", "test_value")
        assert config.get("test.key") == "test_value"

    def test_config_nested_set(self):
        """Test setting nested configuration values."""
        config = Config()
        config.set("new.nested.key", "nested_value")
        assert config.get("new.nested.key") == "nested_value"

    @patch.dict(
        "os.environ",
        {"DEBUG": "true", "PORT": "9000", "DB_HOST": "test_host", "LOG_LEVEL": "DEBUG"},
    )
    def test_config_from_env(self):
        """Test loading configuration from environment variables."""
        config = Config()
        assert config.get("app.debug") is True
        assert config.get("app.port") == 9000
        assert config.get("database.host") == "test_host"
        assert config.get("logging.level") == "DEBUG"

    def test_config_to_dict(self):
        """Test converting configuration to dictionary."""
        config = Config()
        config_dict = config.to_dict()
        assert isinstance(config_dict, dict)
        assert "app" in config_dict
        assert "database" in config_dict
        assert "redis" in config_dict


class TestIntegration:
    """Integration tests for utility modules."""

    def test_logger_and_config_integration(self):
        """Test logger and config working together."""
        config = Config()
        log_level = config.get("logging.level")
        logger = get_logger("integration_test", log_level)

        assert isinstance(logger, logging.Logger)
        assert logger.level == getattr(logging, log_level)

    def test_structured_logger_with_config(self):
        """Test structured logger with configuration."""
        config = Config()
        config.set("app.name", "test_app")

        with patch("src.utils.logger.get_logger") as mock_get_logger:
            mock_logger = MagicMock()
            mock_get_logger.return_value = mock_logger

            structured_logger = StructuredLogger(config.get("app.name"))
            structured_logger.info(
                "Application started", version=config.get("app.version")
            )

            mock_logger.info.assert_called_once_with(
                "Application started | version=0.1.0"
            )
