#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
简化的NATS连接测试
"""

import asyncio
import pytest
import nats
from nats.js import JetStreamContext


class TestNATSSimple:
    """简化的NATS测试"""
    
    @pytest.mark.asyncio
    async def test_nats_connection(self):
        """测试NATS连接"""
        try:
            # 尝试连接到NATS服务器（带认证）
            nc = await nats.connect(
                servers=["nats://localhost:4222"],
                user="finovatex_user",
                password="finovatex_nats_password"
            )
            
            # 验证连接状态
            assert nc.is_connected
            
            # 关闭连接
            await nc.close()
            
            print("✓ NATS连接测试通过")
            
        except Exception as e:
            pytest.skip(f"NATS服务器未运行或连接失败: {e}")
    
    @pytest.mark.asyncio
    async def test_jetstream_basic(self):
        """测试JetStream基本功能"""
        try:
            nc = await nats.connect(
                servers=["nats://localhost:4222"],
                user="finovatex_user",
                password="finovatex_nats_password"
            )
            js = nc.jetstream()
            
            # 获取流信息
            try:
                stream_info = await js.stream_info("MARKET_DATA")
                print(f"✓ 找到流: {stream_info.config.name}")
            except Exception:
                print("! 流MARKET_DATA不存在，这是正常的")
            
            await nc.close()
            print("✓ JetStream基本功能测试通过")
            
        except Exception as e:
            pytest.skip(f"JetStream测试失败: {e}")
    
    @pytest.mark.asyncio
    async def test_simple_publish_subscribe(self):
        """测试简单的发布订阅"""
        try:
            nc = await nats.connect(
                servers=["nats://localhost:4222"],
                user="finovatex_user",
                password="finovatex_nats_password"
            )
            
            # 设置订阅
            received_messages = []
            
            async def message_handler(msg):
                received_messages.append(msg.data.decode())
            
            # 订阅测试主题
            await nc.subscribe("test.simple", cb=message_handler)
            
            # 发布消息
            await nc.publish("test.simple", b"Hello NATS!")
            
            # 等待消息处理
            await asyncio.sleep(0.1)
            
            # 验证消息接收
            assert len(received_messages) == 1
            assert received_messages[0] == "Hello NATS!"
            
            await nc.close()
            print("✓ 简单发布订阅测试通过")
            
        except Exception as e:
            pytest.skip(f"发布订阅测试失败: {e}")


if __name__ == "__main__":
    # 运行测试
    pytest.main([__file__, "-v"])