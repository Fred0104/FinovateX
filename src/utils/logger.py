"""Logging utilities for FinovateX platform."""

import logging
import sys
from typing import Any, Optional


def get_logger(name: str, level: Optional[str] = None) -> logging.Logger:
    """Get a configured logger instance.

    Args:
        name: Logger name
        level: Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)

    Returns:
        Configured logger instance
    """
    logger = logging.getLogger(name)

    # 避免重复添加handler
    if logger.handlers:
        return logger

    # 设置日志级别
    if level:
        logger.setLevel(getattr(logging, level.upper()))
    else:
        logger.setLevel(logging.INFO)

    # 创建控制台处理器
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.INFO)

    # 创建格式器
    formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    console_handler.setFormatter(formatter)

    # 添加处理器到logger
    logger.addHandler(console_handler)

    return logger


class StructuredLogger:
    """Structured logger for better log analysis."""

    def __init__(self, name: str):
        self.logger = get_logger(name)

    def info(self, message: str, **kwargs: Any) -> None:
        """Log info message with structured data."""
        extra_data = " ".join([f"{k}={v}" for k, v in kwargs.items()])
        if extra_data:
            self.logger.info(f"{message} | {extra_data}")
        else:
            self.logger.info(message)

    def error(self, message: str, **kwargs: Any) -> None:
        """Log error message with structured data."""
        extra_data = " ".join([f"{k}={v}" for k, v in kwargs.items()])
        if extra_data:
            self.logger.error(f"{message} | {extra_data}")
        else:
            self.logger.error(message)

    def warning(self, message: str, **kwargs: Any) -> None:
        """Log warning message with structured data."""
        extra_data = " ".join([f"{k}={v}" for k, v in kwargs.items()])
        if extra_data:
            self.logger.warning(f"{message} | {extra_data}")
        else:
            self.logger.warning(message)

    def debug(self, message: str, **kwargs: Any) -> None:
        """Log debug message with structured data."""
        extra_data = " ".join([f"{k}={v}" for k, v in kwargs.items()])
        if extra_data:
            self.logger.debug(f"{message} | {extra_data}")
        else:
            self.logger.debug(message)
