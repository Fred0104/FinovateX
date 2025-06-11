"""Utility modules for FinovateX platform."""

from .logger import get_logger
from .config import Config

# 创建默认实例
logger = get_logger("finovatex")
config = Config()

__all__ = [
    "get_logger",
    "logger",
    "Config",
    "config",
]
