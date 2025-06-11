package tests

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/nats-io/nats.go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestApplicationIntegration 应用程序集成测试
func TestApplicationIntegration(t *testing.T) {
	t.Log("开始应用程序集成测试...")

	conn := setupNATSConnection(t)
	defer conn.Close()

	js := setupJetStream(t, conn)

	// 测试所有流的基本功能
	streams := []string{"MARKET_DATA", "TRADING_SIGNALS", "EXECUTION_EVENTS", "RISK_EVENTS", "SYSTEM_EVENTS"}
	for _, stream := range streams {
		t.Run(fmt.Sprintf("测试流_%s", stream), func(t *testing.T) {
			testStreamBasicFunctionality(t, js, stream)
		})
	}

	t.Log("✓ 应用程序集成测试完成")
}

// testStreamBasicFunctionality 测试流的基本功能
func testStreamBasicFunctionality(t *testing.T, js nats.JetStreamContext, streamName string) {
	// 验证流存在
	_, err := js.StreamInfo(streamName)
	require.NoError(t, err, "获取流信息失败")

	// 根据流类型选择合适的主题
	var subject string
	switch streamName {
	case "MARKET_DATA":
		subject = "finovatex.market.ticker.TESTBTC"
	case "TRADING_SIGNALS":
		subject = "finovatex.signal.test"
	case "EXECUTION_EVENTS":
		subject = "finovatex.execution.test"
	case "RISK_EVENTS":
		subject = "finovatex.risk.test"
	case "SYSTEM_EVENTS":
		subject = "finovatex.system.test"
	default:
		t.Fatalf("未知的流名称: %s", streamName)
	}

	// 创建消费者（在发布消息前创建，使用DeliverNew确保只接收新消息）
	testTime := time.Now()
	consumerName := fmt.Sprintf("test-consumer-%s-%d", streamName, testTime.UnixNano())
	consumer, err := js.PullSubscribe("", consumerName, nats.BindStream(streamName), nats.DeliverNew())
	require.NoError(t, err, "创建消费者失败")
	defer consumer.Unsubscribe()

	// 发布测试消息
	testMsg := TestMessage{
		ID:        fmt.Sprintf("test-%s-%d", streamName, testTime.Unix()),
		Type:      "integration_test",
		Symbol:    "BTCUSDT",
		Price:     50000.0,
		Volume:    1.0,
		Timestamp: testTime,
	}

	msgData, err := json.Marshal(testMsg)
	require.NoError(t, err)

	// 发布消息到流中
	pubAck, err := js.Publish(subject, msgData)
	if err != nil {
		t.Logf("发布消息失败 - 流: %s, 主题: %s, 错误: %v", streamName, subject, err)
	}
	require.NoError(t, err, "发布消息失败")
	t.Logf("消息已发布到 %s，序列号: %d", subject, pubAck.Sequence)

	// 接收并验证消息
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	msgs, err := consumer.Fetch(1, nats.Context(ctx))
	require.NoError(t, err, "获取消息失败")
	require.Len(t, msgs, 1, "应该接收到一条消息")

	var receivedMsg TestMessage
	err = json.Unmarshal(msgs[0].Data, &receivedMsg)
	require.NoError(t, err, "解析消息失败")

	// 调试信息
	t.Logf("发送的消息ID: %s", testMsg.ID)
	t.Logf("接收的消息ID: %s", receivedMsg.ID)
	metadata, _ := msgs[0].Metadata()
	if metadata != nil {
		t.Logf("消息序列号: %d", metadata.Sequence.Stream)
	}
	t.Logf("消息主题: %s", msgs[0].Subject)

	// 验证消息内容
	assert.Equal(t, testMsg.ID, receivedMsg.ID)
	assert.Equal(t, testMsg.Type, receivedMsg.Type)
	assert.Equal(t, testMsg.Symbol, receivedMsg.Symbol)
	assert.Equal(t, testMsg.Price, receivedMsg.Price)
	assert.Equal(t, testMsg.Volume, receivedMsg.Volume)

	msgs[0].Ack()
	t.Logf("✓ 流 %s 基本功能测试通过", streamName)
}

// TestMessagePublishSubscribe 消息发布订阅功能验证
func TestMessagePublishSubscribe(t *testing.T) {
	t.Log("开始消息发布订阅功能验证...")

	conn := setupNATSConnection(t)
	defer conn.Close()

	js := setupJetStream(t, conn)

	// 测试多种消息类型的发布订阅
	testCases := []struct {
		name    string
		stream  string
		subject string
	}{
		{"市场数据", "MARKET_DATA", "finovatex.market.ticker.TEST"},
		{"交易信号", "TRADING_SIGNALS", "finovatex.signal.test"},
		{"执行事件", "EXECUTION_EVENTS", "finovatex.execution.test"},
		{"风险事件", "RISK_EVENTS", "finovatex.risk.test"},
		{"系统事件", "SYSTEM_EVENTS", "finovatex.system.test"},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			testPublishSubscribeFlow(t, js, tc.stream, tc.subject)
		})
	}

	t.Log("✓ 消息发布订阅功能验证完成")
}

// testPublishSubscribeFlow 测试发布订阅流程
func testPublishSubscribeFlow(t *testing.T, js nats.JetStreamContext, streamName, subject string) {
	// 创建多个消费者
	consumerCount := 3
	consumers := make([]*nats.Subscription, consumerCount)
	receivedMessages := make([][]TestMessage, consumerCount)
	var wg sync.WaitGroup

	// 创建消费者
	for i := 0; i < consumerCount; i++ {
		consumerName := fmt.Sprintf("test-consumer-%s-%d-%d", streamName, i, time.Now().Unix())
		consumer, err := js.PullSubscribe(subject, consumerName, nats.BindStream(streamName))
		require.NoError(t, err, "创建消费者失败")
		defer consumer.Unsubscribe()
		consumers[i] = consumer
		receivedMessages[i] = make([]TestMessage, 0)
	}

	// 发布多条消息
	messageCount := 5
	sentMessages := make([]TestMessage, messageCount)

	for i := 0; i < messageCount; i++ {
		msg := TestMessage{
			ID:        fmt.Sprintf("msg-%d-%d", time.Now().Unix(), i),
			Type:      "test_message",
			Symbol:    "BTCUSDT",
			Price:     50000.0 + float64(i),
			Volume:    1.0 + float64(i)*0.1,
			Timestamp: time.Now(),
		}
		sentMessages[i] = msg

		msgData, err := json.Marshal(msg)
		require.NoError(t, err)

		_, err = js.Publish(subject, msgData)
		require.NoError(t, err, "发布消息失败")
	}

	// 每个消费者接收消息
	for i := 0; i < consumerCount; i++ {
		wg.Add(1)
		go func(consumerIndex int) {
			defer wg.Done()
			consumer := consumers[consumerIndex]

			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()

			for j := 0; j < messageCount; j++ {
				msgs, err := consumer.Fetch(1, nats.Context(ctx))
				if err != nil {
					t.Errorf("消费者 %d 获取消息失败: %v", consumerIndex, err)
					return
				}

				if len(msgs) > 0 {
					var receivedMsg TestMessage
					err = json.Unmarshal(msgs[0].Data, &receivedMsg)
					if err != nil {
						t.Errorf("消费者 %d 解析消息失败: %v", consumerIndex, err)
						return
					}
					receivedMessages[consumerIndex] = append(receivedMessages[consumerIndex], receivedMsg)
					msgs[0].Ack()
				}
			}
		}(i)
	}

	wg.Wait()

	// 验证每个消费者都收到了所有消息
	for i := 0; i < consumerCount; i++ {
		assert.Len(t, receivedMessages[i], messageCount, "消费者 %d 应该收到 %d 条消息", i, messageCount)
	}

	t.Logf("✓ %s 发布订阅流程测试通过", streamName)
}

// TestFailureRecovery 故障恢复机制测试
func TestFailureRecovery(t *testing.T) {
	t.Log("开始故障恢复机制测试...")

	conn := setupNATSConnection(t)
	defer conn.Close()

	js := setupJetStream(t, conn)

	// 测试连接中断后的恢复
	t.Run("连接恢复测试", func(t *testing.T) {
		testConnectionRecovery(t, js)
	})

	// 测试消息重试机制
	t.Run("消息重试测试", func(t *testing.T) {
		testMessageRetry(t, js)
	})

	// 测试消费者故障恢复
	t.Run("消费者故障恢复测试", func(t *testing.T) {
		testConsumerFailureRecovery(t, js)
	})

	t.Log("✓ 故障恢复机制测试完成")
}

// testConnectionRecovery 测试连接恢复
func testConnectionRecovery(t *testing.T, js nats.JetStreamContext) {
	subject := "finovatex.system.test"
	consumerName := fmt.Sprintf("recovery-consumer-%d", time.Now().Unix())

	// 创建消费者
	consumer, err := js.PullSubscribe(subject, consumerName, nats.BindStream("SYSTEM_EVENTS"))
	require.NoError(t, err, "创建消费者失败")
	defer consumer.Unsubscribe()

	// 发布消息前测试
	msg1 := TestMessage{
		ID:        fmt.Sprintf("recovery-test-1-%d", time.Now().Unix()),
		Type:      "recovery_test",
		Symbol:    "ETHUSDT",
		Price:     3000.0,
		Volume:    2.0,
		Timestamp: time.Now(),
	}

	msgData, err := json.Marshal(msg1)
	require.NoError(t, err)

	_, err = js.Publish(subject, msgData)
	require.NoError(t, err, "发布消息失败")

	// 模拟短暂延迟（模拟网络问题）
	time.Sleep(100 * time.Millisecond)

	// 发布第二条消息
	msg2 := TestMessage{
		ID:        fmt.Sprintf("recovery-test-2-%d", time.Now().Unix()),
		Type:      "recovery_test",
		Symbol:    "ETHUSDT",
		Price:     3001.0,
		Volume:    2.1,
		Timestamp: time.Now(),
	}

	msgData2, err := json.Marshal(msg2)
	require.NoError(t, err)

	_, err = js.Publish(subject, msgData2)
	require.NoError(t, err, "发布第二条消息失败")

	// 验证两条消息都能正常接收
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	receivedCount := 0
	for receivedCount < 2 {
		msgs, err := consumer.Fetch(1, nats.Context(ctx))
		require.NoError(t, err, "获取消息失败")

		if len(msgs) > 0 {
			msgs[0].Ack()
			receivedCount++
		}
	}

	assert.Equal(t, 2, receivedCount, "应该接收到2条消息")
	t.Log("✓ 连接恢复测试通过")
}

// testMessageRetry 测试消息重试机制
func testMessageRetry(t *testing.T, js nats.JetStreamContext) {
	subject := "finovatex.system.test"
	consumerName := fmt.Sprintf("retry-consumer-%d", time.Now().Unix())

	// 创建消费者
	consumer, err := js.PullSubscribe(subject, consumerName, nats.BindStream("SYSTEM_EVENTS"))
	require.NoError(t, err, "创建消费者失败")
	defer consumer.Unsubscribe()

	// 发布测试消息
	msg := TestMessage{
		ID:        fmt.Sprintf("retry-test-%d", time.Now().Unix()),
		Type:      "retry_test",
		Symbol:    "ADAUSDT",
		Price:     1.5,
		Volume:    100.0,
		Timestamp: time.Now(),
	}

	msgData, err := json.Marshal(msg)
	require.NoError(t, err)

	_, err = js.Publish(subject, msgData)
	require.NoError(t, err, "发布消息失败")

	// 第一次接收但不确认（模拟处理失败）
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	msgs, err := consumer.Fetch(1, nats.Context(ctx))
	require.NoError(t, err, "第一次获取消息失败")
	require.Len(t, msgs, 1, "应该接收到一条消息")

	// 不确认消息，让它重新投递
	// msgs[0].Nak() // 可以显式NAK，但这里我们让它超时

	// 等待消息重新投递
	time.Sleep(2 * time.Second)

	// 第二次接收并确认
	ctx2, cancel2 := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel2()

	msgs2, err := consumer.Fetch(1, nats.Context(ctx2))
	require.NoError(t, err, "第二次获取消息失败")
	require.Len(t, msgs2, 1, "应该重新接收到消息")

	// 确认消息
	msgs2[0].Ack()

	t.Log("✓ 消息重试测试通过")
}

// testConsumerFailureRecovery 测试消费者故障恢复
func testConsumerFailureRecovery(t *testing.T, js nats.JetStreamContext) {
	subject := "finovatex.system.test"
	consumerName := fmt.Sprintf("consumer-recovery-%d", time.Now().Unix())

	// 创建第一个消费者
	consumer1, err := js.PullSubscribe(subject, consumerName, nats.BindStream("SYSTEM_EVENTS"))
	require.NoError(t, err, "创建第一个消费者失败")

	// 发布消息
	msg := TestMessage{
		ID:        fmt.Sprintf("consumer-recovery-test-%d", time.Now().Unix()),
		Type:      "consumer_recovery_test",
		Symbol:    "DOTUSDT",
		Price:     25.0,
		Volume:    10.0,
		Timestamp: time.Now(),
	}

	msgData, err := json.Marshal(msg)
	require.NoError(t, err)

	_, err = js.Publish(subject, msgData)
	require.NoError(t, err, "发布消息失败")

	// 模拟消费者故障（关闭连接）
	consumer1.Unsubscribe()

	// 创建新的消费者（使用相同的消费者名称）
	consumer2, err := js.PullSubscribe(subject, consumerName, nats.BindStream("SYSTEM_EVENTS"))
	require.NoError(t, err, "创建恢复消费者失败")
	defer consumer2.Unsubscribe()

	// 验证新消费者能够接收消息
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	msgs, err := consumer2.Fetch(1, nats.Context(ctx))
	require.NoError(t, err, "恢复消费者获取消息失败")
	require.Len(t, msgs, 1, "恢复消费者应该接收到消息")

	msgs[0].Ack()

	t.Log("✓ 消费者故障恢复测试通过")
}

// BenchmarkMessageThroughput 性能基准测试 - 消息吞吐量
func BenchmarkMessageThroughput(b *testing.B) {
	conn := setupNATSConnectionForBenchmark(b)
	defer conn.Close()

	js := setupJetStreamForBenchmark(b, conn)
	subject := "finovatex.market.benchmark.throughput"

	// 准备测试消息
	msg := TestMessage{
		ID:        "benchmark-msg",
		Type:      "benchmark",
		Symbol:    "BNBUSDT",
		Price:     400.0,
		Volume:    5.0,
		Timestamp: time.Now(),
	}

	msgData, err := json.Marshal(msg)
	if err != nil {
		b.Fatalf("序列化消息失败: %v", err)
	}

	b.ResetTimer()
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			_, err := js.Publish(subject, msgData)
			if err != nil {
				b.Errorf("发布消息失败: %v", err)
			}
		}
	})
}

// BenchmarkMessageLatency 性能基准测试 - 消息延迟
func BenchmarkMessageLatency(b *testing.B) {
	conn := setupNATSConnectionForBenchmark(b)
	defer conn.Close()

	js := setupJetStreamForBenchmark(b, conn)
	subject := "finovatex.market.benchmark.latency"
	consumerName := fmt.Sprintf("latency-benchmark-%d", time.Now().Unix())

	// 创建消费者
	consumer, err := js.PullSubscribe(subject, consumerName, nats.BindStream("MARKET_DATA"))
	if err != nil {
		b.Fatalf("创建消费者失败: %v", err)
	}
	defer consumer.Unsubscribe()

	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		// 记录发送时间
		start := time.Now()

		// 发布消息
		msg := TestMessage{
			ID:        fmt.Sprintf("latency-test-%d", i),
			Type:      "latency_benchmark",
			Symbol:    "SOLUSDT",
			Price:     200.0,
			Volume:    3.0,
			Timestamp: start,
		}

		msgData, err := json.Marshal(msg)
		if err != nil {
			b.Fatalf("序列化消息失败: %v", err)
		}

		_, err = js.Publish(subject, msgData)
		if err != nil {
			b.Fatalf("发布消息失败: %v", err)
		}

		// 接收消息
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		msgs, err := consumer.Fetch(1, nats.Context(ctx))
		cancel()

		if err != nil {
			b.Fatalf("接收消息失败: %v", err)
		}

		if len(msgs) > 0 {
			// 计算延迟
			latency := time.Since(start)
			b.Logf("消息延迟: %v", latency)
			msgs[0].Ack()
		}
	}
}

// setupNATSConnectionForBenchmark 为基准测试设置NATS连接
func setupNATSConnectionForBenchmark(b *testing.B) *nats.Conn {
	conn, err := nats.Connect("nats://localhost:4222")
	if err != nil {
		b.Fatalf("连接NATS失败: %v", err)
	}
	return conn
}

// setupJetStreamForBenchmark 为基准测试设置JetStream
func setupJetStreamForBenchmark(b *testing.B, conn *nats.Conn) nats.JetStreamContext {
	js, err := conn.JetStream()
	if err != nil {
		b.Fatalf("创建JetStream上下文失败: %v", err)
	}
	return js
}