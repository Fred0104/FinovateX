#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
应用程序集成测试模块

包含以下测试功能：
1. 应用程序集成测试
2. 消息发布订阅功能验证
3. 故障恢复机制测试
4. 性能基准测试
"""

import asyncio
import json
import time
import uuid
from datetime import datetime
from typing import Dict, List, Any
from unittest.mock import patch, MagicMock

import pytest
import nats
from nats.js import JetStreamContext

from src.utils.logger import get_logger
from src.utils.config import Config


class TestMessage:
    """测试消息类"""
    
    def __init__(self, msg_id: str = None, msg_type: str = "test", 
                 payload: str = "", timestamp: datetime = None):
        self.id = msg_id or str(uuid.uuid4())
        self.type = msg_type
        self.payload = payload
        self.timestamp = timestamp or datetime.now()
    
    def to_dict(self) -> Dict[str, Any]:
        """转换为字典"""
        return {
            "id": self.id,
            "type": self.type,
            "payload": self.payload,
            "timestamp": self.timestamp.isoformat()
        }
    
    def to_json(self) -> str:
        """转换为JSON字符串"""
        return json.dumps(self.to_dict())
    
    @classmethod
    def from_json(cls, json_str: str) -> 'TestMessage':
        """从JSON字符串创建实例"""
        data = json.loads(json_str)
        return cls(
            msg_id=data["id"],
            msg_type=data["type"],
            payload=data["payload"],
            timestamp=datetime.fromisoformat(data["timestamp"])
        )


class NATSTestHelper:
    """NATS测试辅助类"""
    
    def __init__(self):
        self.nc = None
        self.js = None
        self.logger = get_logger("nats_test_helper")
    
    async def connect(self, servers: List[str] = None) -> None:
        """连接到NATS服务器"""
        if servers is None:
            servers = ["nats://localhost:4222"]
        
        try:
            self.nc = await nats.connect(servers=servers)
            self.js = self.nc.jetstream()
            self.logger.info("成功连接到NATS服务器")
        except Exception as e:
            self.logger.error(f"连接NATS服务器失败: {e}")
            raise
    
    async def disconnect(self) -> None:
        """断开NATS连接"""
        if self.nc:
            await self.nc.close()
            self.logger.info("已断开NATS连接")
    
    async def publish_message(self, subject: str, message: TestMessage) -> None:
        """发布消息"""
        if not self.js:
            raise RuntimeError("JetStream未初始化")
        
        try:
            await self.js.publish(subject, message.to_json().encode())
            self.logger.debug(f"消息已发布到主题 {subject}: {message.id}")
        except Exception as e:
            self.logger.error(f"发布消息失败: {e}")
            raise
    
    async def subscribe_messages(self, subject: str, stream: str, 
                               consumer: str, count: int = 1) -> List[TestMessage]:
        """订阅消息"""
        if not self.js:
            raise RuntimeError("JetStream未初始化")
        
        try:
            # 创建拉取订阅
            psub = await self.js.pull_subscribe(subject, consumer, stream=stream)
            
            messages = []
            for _ in range(count):
                try:
                    msgs = await psub.fetch(1, timeout=5.0)
                    if msgs:
                        msg_data = msgs[0].data.decode()
                        test_msg = TestMessage.from_json(msg_data)
                        messages.append(test_msg)
                        await msgs[0].ack()
                        self.logger.debug(f"接收到消息: {test_msg.id}")
                except Exception as e:
                    self.logger.warning(f"获取消息超时或失败: {e}")
                    break
            
            return messages
        except Exception as e:
            self.logger.error(f"订阅消息失败: {e}")
            raise
    
    async def get_stream_info(self, stream_name: str) -> Dict[str, Any]:
        """获取流信息"""
        if not self.js:
            raise RuntimeError("JetStream未初始化")
        
        try:
            stream_info = await self.js.stream_info(stream_name)
            return {
                "name": stream_info.config.name,
                "subjects": stream_info.config.subjects,
                "messages": stream_info.state.messages,
                "bytes": stream_info.state.bytes
            }
        except Exception as e:
            self.logger.error(f"获取流信息失败: {e}")
            raise


@pytest.fixture(scope="function")
async def nats_helper():
    """NATS测试辅助器fixture"""
    helper = NATSTestHelper()
    try:
        await helper.connect([
            "nats://finovatex_user:finovatex_nats_password@localhost:4222"
        ])
        yield helper
    finally:
        await helper.disconnect()


class TestApplicationIntegration:
    """应用程序集成测试"""
    
    @pytest.mark.asyncio
    async def test_all_streams_basic_functionality(self, nats_helper: NATSTestHelper):
        """测试所有流的基本功能"""
        streams = [
            ("MARKET_DATA", "finovatex.market.test"),
            ("TRADING_SIGNALS", "finovatex.signal.test"),
            ("EXECUTION_EVENTS", "finovatex.execution.test"),
            ("RISK_EVENTS", "finovatex.risk.test"),
            ("SYSTEM_EVENTS", "finovatex.system.test")
        ]
        
        for stream_name, subject in streams:
            await self._test_stream_functionality(nats_helper, stream_name, subject)
    
    async def _test_stream_functionality(self, helper: NATSTestHelper, 
                                       stream_name: str, subject: str):
        """测试单个流的功能"""
        # 获取流信息
        stream_info = await helper.get_stream_info(stream_name)
        assert stream_info["name"] == stream_name
        
        # 创建测试消息
        test_msg = TestMessage(
            msg_type="integration_test",
            payload=f"测试消息用于流 {stream_name}"
        )
        
        # 发布消息
        await helper.publish_message(subject, test_msg)
        
        # 订阅并验证消息
        consumer_name = f"test-consumer-{stream_name}-{int(time.time())}"
        received_messages = await helper.subscribe_messages(
            subject, stream_name, consumer_name, 1
        )
        
        assert len(received_messages) == 1
        received_msg = received_messages[0]
        assert received_msg.id == test_msg.id
        assert received_msg.type == test_msg.type
        assert received_msg.payload == test_msg.payload
        
        helper.logger.info(f"✓ 流 {stream_name} 基本功能测试通过")


class TestMessagePublishSubscribe:
    """消息发布订阅功能验证"""
    
    @pytest.mark.asyncio
    async def test_multiple_message_types(self, nats_helper: NATSTestHelper):
        """测试多种消息类型的发布订阅"""
        test_cases = [
            ("市场数据", "MARKET_DATA", "finovatex.market.ticker.TEST"),
            ("交易信号", "TRADING_SIGNALS", "finovatex.signal.buy.TEST"),
            ("执行事件", "EXECUTION_EVENTS", "finovatex.execution.order.TEST"),
            ("风险事件", "RISK_EVENTS", "finovatex.risk.alert.TEST"),
            ("系统事件", "SYSTEM_EVENTS", "finovatex.system.startup.TEST")
        ]
        
        for name, stream, subject in test_cases:
            await self._test_publish_subscribe_flow(nats_helper, name, stream, subject)
    
    async def _test_publish_subscribe_flow(self, helper: NATSTestHelper,
                                         name: str, stream: str, subject: str):
        """测试发布订阅流程"""
        # 发布多条消息
        message_count = 5
        sent_messages = []
        
        for i in range(message_count):
            msg = TestMessage(
                msg_type="test_message",
                payload=f"测试消息 {i} 用于 {name}"
            )
            sent_messages.append(msg)
            await helper.publish_message(subject, msg)
        
        # 创建多个消费者
        consumer_count = 3
        tasks = []
        
        for i in range(consumer_count):
            consumer_name = f"test-consumer-{stream}-{i}-{int(time.time())}"
            task = asyncio.create_task(
                helper.subscribe_messages(subject, stream, consumer_name, message_count)
            )
            tasks.append(task)
        
        # 等待所有消费者完成
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # 验证结果
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                pytest.fail(f"消费者 {i} 失败: {result}")
            else:
                assert len(result) == message_count, f"消费者 {i} 应该收到 {message_count} 条消息"
        
        helper.logger.info(f"✓ {name} 发布订阅流程测试通过")
    
    @pytest.mark.asyncio
    async def test_message_ordering(self, nats_helper: NATSTestHelper):
        """测试消息顺序"""
        subject = "finovatex.system.ordering.test"
        stream = "SYSTEM_EVENTS"
        consumer_name = f"ordering-consumer-{int(time.time())}"
        
        # 发布有序消息
        message_count = 10
        for i in range(message_count):
            msg = TestMessage(
                msg_id=f"order-{i:03d}",
                msg_type="ordering_test",
                payload=f"有序消息 {i}"
            )
            await nats_helper.publish_message(subject, msg)
            # 小延迟确保顺序
            await asyncio.sleep(0.01)
        
        # 接收消息并验证顺序
        received_messages = await nats_helper.subscribe_messages(
            subject, stream, consumer_name, message_count
        )
        
        assert len(received_messages) == message_count
        
        for i, msg in enumerate(received_messages):
            expected_id = f"order-{i:03d}"
            assert msg.id == expected_id, f"消息顺序错误，期望 {expected_id}，实际 {msg.id}"
        
        nats_helper.logger.info("✓ 消息顺序测试通过")


class TestFailureRecovery:
    """故障恢复机制测试"""
    
    @pytest.mark.asyncio
    async def test_connection_recovery(self, nats_helper: NATSTestHelper):
        """测试连接恢复"""
        subject = "finovatex.system.recovery.test"
        stream = "SYSTEM_EVENTS"
        
        # 发布消息前测试
        msg1 = TestMessage(
            msg_type="recovery_test",
            payload="恢复测试消息 1"
        )
        await nats_helper.publish_message(subject, msg1)
        
        # 模拟短暂延迟（模拟网络问题）
        await asyncio.sleep(0.1)
        
        # 发布第二条消息
        msg2 = TestMessage(
            msg_type="recovery_test",
            payload="恢复测试消息 2"
        )
        await nats_helper.publish_message(subject, msg2)
        
        # 验证两条消息都能正常接收
        consumer_name = f"recovery-consumer-{int(time.time())}"
        received_messages = await nats_helper.subscribe_messages(
            subject, stream, consumer_name, 2
        )
        
        assert len(received_messages) == 2
        nats_helper.logger.info("✓ 连接恢复测试通过")
    
    @pytest.mark.asyncio
    async def test_message_retry(self, nats_helper: NATSTestHelper):
        """测试消息重试机制"""
        subject = "finovatex.system.retry.test"
        stream = "SYSTEM_EVENTS"
        consumer_name = f"retry-consumer-{int(time.time())}"
        
        # 发布测试消息
        msg = TestMessage(
            msg_type="retry_test",
            payload="重试测试消息"
        )
        await nats_helper.publish_message(subject, msg)
        
        # 创建订阅但模拟处理失败（不确认消息）
        psub = await nats_helper.js.pull_subscribe(subject, consumer_name, stream=stream)
        
        # 第一次获取消息但不确认
        msgs = await psub.fetch(1, timeout=5.0)
        assert len(msgs) == 1
        received_msg1 = TestMessage.from_json(msgs[0].data.decode())
        assert received_msg1.id == msg.id
        
        # 不确认消息，让它重新投递
        # 等待重新投递
        await asyncio.sleep(2)
        
        # 第二次获取消息并确认
        msgs2 = await psub.fetch(1, timeout=5.0)
        assert len(msgs2) == 1
        received_msg2 = TestMessage.from_json(msgs2[0].data.decode())
        assert received_msg2.id == msg.id
        
        # 确认消息
        await msgs2[0].ack()
        
        nats_helper.logger.info("✓ 消息重试测试通过")
    
    @pytest.mark.asyncio
    async def test_consumer_failure_recovery(self, nats_helper: NATSTestHelper):
        """测试消费者故障恢复"""
        subject = "finovatex.system.consumer.recovery.test"
        stream = "SYSTEM_EVENTS"
        consumer_name = f"consumer-recovery-{int(time.time())}"
        
        # 创建第一个消费者
        psub1 = await nats_helper.js.pull_subscribe(subject, consumer_name, stream=stream)
        
        # 发布消息
        msg = TestMessage(
            msg_type="consumer_recovery_test",
            payload="消费者恢复测试消息"
        )
        await nats_helper.publish_message(subject, msg)
        
        # 模拟消费者故障（取消订阅）
        await psub1.unsubscribe()
        
        # 创建新的消费者（使用相同的消费者名称）
        psub2 = await nats_helper.js.pull_subscribe(subject, consumer_name, stream=stream)
        
        # 验证新消费者能够接收消息
        msgs = await psub2.fetch(1, timeout=5.0)
        assert len(msgs) == 1
        
        received_msg = TestMessage.from_json(msgs[0].data.decode())
        assert received_msg.id == msg.id
        
        await msgs[0].ack()
        await psub2.unsubscribe()
        
        nats_helper.logger.info("✓ 消费者故障恢复测试通过")


class TestPerformanceBenchmarks:
    """性能基准测试"""
    
    @pytest.mark.asyncio
    @pytest.mark.benchmark
    async def test_message_throughput(self, nats_helper: NATSTestHelper):
        """测试消息吞吐量"""
        subject = "finovatex.market.benchmark.throughput"
        message_count = 1000
        
        # 准备测试消息
        msg = TestMessage(
            msg_type="benchmark",
            payload="性能测试消息"
        )
        
        # 测量发布性能
        start_time = time.time()
        
        tasks = []
        for i in range(message_count):
            task = asyncio.create_task(
                nats_helper.publish_message(subject, msg)
            )
            tasks.append(task)
        
        await asyncio.gather(*tasks)
        
        end_time = time.time()
        duration = end_time - start_time
        throughput = message_count / duration
        
        nats_helper.logger.info(f"消息吞吐量: {throughput:.2f} 消息/秒")
        nats_helper.logger.info(f"总时间: {duration:.3f} 秒")
        
        # 断言吞吐量达到最低要求（例如：1000消息/秒）
        assert throughput > 1000, f"吞吐量 {throughput:.2f} 低于要求的 1000 消息/秒"
    
    @pytest.mark.asyncio
    @pytest.mark.benchmark
    async def test_message_latency(self, nats_helper: NATSTestHelper):
        """测试消息延迟"""
        subject = "finovatex.market.benchmark.latency"
        stream = "MARKET_DATA"
        consumer_name = f"latency-benchmark-{int(time.time())}"
        test_count = 100
        
        latencies = []
        
        for i in range(test_count):
            # 记录发送时间
            start_time = time.time()
            
            # 发布消息
            msg = TestMessage(
                msg_id=f"latency-test-{i}",
                msg_type="latency_benchmark",
                payload="延迟测试消息"
            )
            
            await nats_helper.publish_message(subject, msg)
            
            # 接收消息
            received_messages = await nats_helper.subscribe_messages(
                subject, stream, f"{consumer_name}-{i}", 1
            )
            
            end_time = time.time()
            latency = (end_time - start_time) * 1000  # 转换为毫秒
            latencies.append(latency)
            
            assert len(received_messages) == 1
            assert received_messages[0].id == msg.id
        
        # 计算统计信息
        avg_latency = sum(latencies) / len(latencies)
        max_latency = max(latencies)
        min_latency = min(latencies)
        
        nats_helper.logger.info(f"平均延迟: {avg_latency:.2f} ms")
        nats_helper.logger.info(f"最大延迟: {max_latency:.2f} ms")
        nats_helper.logger.info(f"最小延迟: {min_latency:.2f} ms")
        
        # 断言平均延迟在可接受范围内（例如：< 50ms）
        assert avg_latency < 50, f"平均延迟 {avg_latency:.2f}ms 超过要求的 50ms"
    
    @pytest.mark.asyncio
    @pytest.mark.benchmark
    async def test_concurrent_consumers(self, nats_helper: NATSTestHelper):
        """测试并发消费者性能"""
        subject = "finovatex.system.benchmark.concurrent"
        stream = "SYSTEM_EVENTS"
        consumer_count = 10
        messages_per_consumer = 100
        
        # 发布消息
        total_messages = consumer_count * messages_per_consumer
        for i in range(total_messages):
            msg = TestMessage(
                msg_id=f"concurrent-{i}",
                msg_type="concurrent_benchmark",
                payload=f"并发测试消息 {i}"
            )
            await nats_helper.publish_message(subject, msg)
        
        # 创建并发消费者
        start_time = time.time()
        
        tasks = []
        for i in range(consumer_count):
            consumer_name = f"concurrent-consumer-{i}-{int(time.time())}"
            task = asyncio.create_task(
                nats_helper.subscribe_messages(
                    subject, stream, consumer_name, messages_per_consumer
                )
            )
            tasks.append(task)
        
        results = await asyncio.gather(*tasks)
        
        end_time = time.time()
        duration = end_time - start_time
        
        # 验证所有消费者都收到了预期数量的消息
        total_received = sum(len(result) for result in results)
        
        nats_helper.logger.info(f"并发消费者测试完成")
        nats_helper.logger.info(f"消费者数量: {consumer_count}")
        nats_helper.logger.info(f"总消息数: {total_messages}")
        nats_helper.logger.info(f"接收消息数: {total_received}")
        nats_helper.logger.info(f"总时间: {duration:.3f} 秒")
        nats_helper.logger.info(f"处理速度: {total_received/duration:.2f} 消息/秒")
        
        assert total_received == total_messages, f"接收消息数 {total_received} 不等于发送消息数 {total_messages}"


class TestSystemIntegration:
    """系统集成测试"""
    
    @pytest.mark.asyncio
    async def test_end_to_end_workflow(self, nats_helper: NATSTestHelper):
        """测试端到端工作流"""
        # 模拟完整的交易流程
        
        # 1. 市场数据
        market_data_msg = TestMessage(
            msg_type="market_data",
            payload=json.dumps({
                "symbol": "BTCUSDT",
                "price": 45000.0,
                "volume": 1.5,
                "timestamp": datetime.now().isoformat()
            })
        )
        await nats_helper.publish_message("finovatex.market.ticker.BTCUSDT", market_data_msg)
        
        # 2. 交易信号
        signal_msg = TestMessage(
            msg_type="trading_signal",
            payload=json.dumps({
                "action": "BUY",
                "symbol": "BTCUSDT",
                "price": 45000.0,
                "quantity": 0.1,
                "strategy_id": "test-strategy"
            })
        )
        await nats_helper.publish_message("finovatex.signal.buy.BTCUSDT", signal_msg)
        
        # 3. 执行事件
        execution_msg = TestMessage(
            msg_type="execution_event",
            payload=json.dumps({
                "order_id": "order-123",
                "status": "FILLED",
                "symbol": "BTCUSDT",
                "executed_price": 45000.0,
                "executed_quantity": 0.1
            })
        )
        await nats_helper.publish_message("finovatex.execution.order.BTCUSDT", execution_msg)
        
        # 4. 系统事件
        system_msg = TestMessage(
            msg_type="system_event",
            payload=json.dumps({
                "event_type": "order_completed",
                "order_id": "order-123",
                "timestamp": datetime.now().isoformat()
            })
        )
        await nats_helper.publish_message("finovatex.system.order.completed", system_msg)
        
        # 验证所有消息都能正常处理
        test_cases = [
            ("finovatex.market.ticker.BTCUSDT", "MARKET_DATA", market_data_msg),
            ("finovatex.signal.buy.BTCUSDT", "TRADING_SIGNALS", signal_msg),
            ("finovatex.execution.order.BTCUSDT", "EXECUTION_EVENTS", execution_msg),
            ("finovatex.system.order.completed", "SYSTEM_EVENTS", system_msg)
        ]
        
        for subject, stream, sent_msg in test_cases:
            consumer_name = f"e2e-consumer-{stream}-{int(time.time())}"
            received_messages = await nats_helper.subscribe_messages(
                subject, stream, consumer_name, 1
            )
            
            assert len(received_messages) == 1
            received_msg = received_messages[0]
            assert received_msg.id == sent_msg.id
            assert received_msg.type == sent_msg.type
        
        nats_helper.logger.info("✓ 端到端工作流测试通过")
    
    @pytest.mark.asyncio
    async def test_system_health_check(self, nats_helper: NATSTestHelper):
        """测试系统健康检查"""
        # 检查所有流的状态
        streams = ["MARKET_DATA", "TRADING_SIGNALS", "EXECUTION_EVENTS", "RISK_EVENTS", "SYSTEM_EVENTS"]
        
        for stream_name in streams:
            stream_info = await nats_helper.get_stream_info(stream_name)
            assert stream_info["name"] == stream_name
            assert isinstance(stream_info["messages"], int)
            assert isinstance(stream_info["bytes"], int)
            nats_helper.logger.info(f"流 {stream_name} 状态正常: {stream_info['messages']} 消息")
        
        nats_helper.logger.info("✓ 系统健康检查通过")


if __name__ == "__main__":
    # 运行测试
    pytest.main([
        __file__,
        "-v",
        "--tb=short",
        "-m", "not benchmark"  # 默认不运行基准测试
    ])