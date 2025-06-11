"""FinovateX Trading Platform

A high-performance trading platform with real-time data processing,
risk management, and strategy execution capabilities.
"""

__version__ = "0.1.0"
__author__ = "FinovateX Team"
__email__ = "dev@finovatex.com"

# 导出主要模块
from .utils import logger, config

__all__ = [
    "logger",
    "config",
    "__version__",
]
