package tests

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/nats-io/nats.go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestMessage 测试消息结构
type TestMessage struct {
	ID        string    `json:"id"`
	Type      string    `json:"type"`
	Symbol    string    `json:"symbol"`
	Price     float64   `json:"price"`
	Volume    float64   `json:"volume"`
	Timestamp time.Time `json:"timestamp"`
}

// TradingSignal 交易信号结构
type TradingSignal struct {
	ID        string    `json:"id"`
	Action    string    `json:"action"` // BUY, SELL
	Symbol    string    `json:"symbol"`
	Price     float64   `json:"price"`
	Quantity  float64   `json:"quantity"`
	Timestamp time.Time `json:"timestamp"`
	StrategyID string   `json:"strategy_id"`
}

const (
	// NATS连接配置
	natsURL      = "nats://finovatex_user:finovatex_nats_password@localhost:4222"
	testTimeout  = 30 * time.Second
	messageCount = 10
)

// setupNATSConnection 建立NATS连接
func setupNATSConnection(t *testing.T) *nats.Conn {
	conn, err := nats.Connect(natsURL,
		nats.Timeout(5*time.Second),
		nats.ReconnectWait(1*time.Second),
		nats.MaxReconnects(3),
	)
	require.NoError(t, err, "Failed to connect to NATS")
	require.True(t, conn.IsConnected(), "NATS connection should be active")
	return conn
}

// setupJetStream 设置JetStream上下文
func setupJetStream(t *testing.T, conn *nats.Conn) nats.JetStreamContext {
	js, err := conn.JetStream()
	require.NoError(t, err, "Failed to create JetStream context")
	return js
}

// TestNATSConnection 测试基本NATS连接
func TestNATSConnection(t *testing.T) {
	t.Log("Testing NATS connection...")
	
	conn := setupNATSConnection(t)
	defer conn.Close()
	
	// 测试连接状态
	assert.True(t, conn.IsConnected(), "NATS should be connected")
	assert.Equal(t, nats.CONNECTED, conn.Status(), "NATS status should be CONNECTED")
	
	t.Log("✓ NATS connection test passed")
}

// TestJetStreamStreams 测试JetStream流是否存在
func TestJetStreamStreams(t *testing.T) {
	t.Log("Testing JetStream streams...")
	
	conn := setupNATSConnection(t)
	defer conn.Close()
	
	js := setupJetStream(t, conn)
	
	// 检查预期的流（与init-nats-streams.ps1脚本中创建的流保持一致）
	expectedStreams := []string{
		"MARKET_DATA",
		"TRADING_SIGNALS", 
		"EXECUTION_EVENTS",
		"RISK_EVENTS",
		"SYSTEM_EVENTS",
	}
	
	for _, streamName := range expectedStreams {
		stream, err := js.StreamInfo(streamName)
		assert.NoError(t, err, "Stream %s should exist", streamName)
		if err == nil {
			assert.Equal(t, streamName, stream.Config.Name)
			t.Logf("✓ Stream %s exists with %d messages", streamName, stream.State.Msgs)
		}
	}
}

// TestMarketDataPublishSubscribe 测试市场数据发布订阅
func TestMarketDataPublishSubscribe(t *testing.T) {
	t.Log("Testing market data publish/subscribe...")
	
	conn := setupNATSConnection(t)
	defer conn.Close()
	
	js := setupJetStream(t, conn)
	
	// 创建消费者
	consumerName := fmt.Sprintf("test-consumer-%d", time.Now().Unix())
	consumer, err := js.PullSubscribe("finovatex.market.ticker.BTCUSDT", consumerName, nats.BindStream("MARKET_DATA"))
	require.NoError(t, err, "Failed to create consumer")
	defer consumer.Unsubscribe()
	
	// 发布测试消息
	testMessages := make([]TestMessage, messageCount)
	for i := 0; i < messageCount; i++ {
		testMessages[i] = TestMessage{
			ID:        fmt.Sprintf("test-msg-%d", i),
			Type:      "price_update",
			Symbol:    "BTCUSDT",
			Price:     45000.0 + float64(i)*10,
			Volume:    1.5 + float64(i)*0.1,
			Timestamp: time.Now(),
		}
		
		msgData, err := json.Marshal(testMessages[i])
		require.NoError(t, err)
		
		_, err = js.Publish("finovatex.market.ticker.BTCUSDT", msgData)
		require.NoError(t, err, "Failed to publish message %d", i)
	}
	
	t.Logf("Published %d test messages", messageCount)
	
	// 订阅并验证消息
	ctx, cancel := context.WithTimeout(context.Background(), testTimeout)
	defer cancel()
	
	receivedCount := 0
	for receivedCount < messageCount {
		msgs, err := consumer.Fetch(messageCount, nats.Context(ctx))
		if err != nil {
			if ctx.Err() != nil {
				t.Fatalf("Timeout waiting for messages. Received %d/%d", receivedCount, messageCount)
			}
			continue
		}
		
		for _, msg := range msgs {
			var receivedMsg TestMessage
			err := json.Unmarshal(msg.Data, &receivedMsg)
			assert.NoError(t, err, "Failed to unmarshal message")
			
			// 验证消息内容
			assert.Equal(t, "BTCUSDT", receivedMsg.Symbol)
			assert.Equal(t, "price_update", receivedMsg.Type)
			assert.True(t, receivedMsg.Price >= 45000.0)
			
			msg.Ack()
			receivedCount++
			
			if receivedCount >= messageCount {
				break
			}
		}
	}
	
	assert.Equal(t, messageCount, receivedCount, "Should receive all published messages")
	t.Logf("✓ Successfully received %d messages", receivedCount)
}

// TestTradingSignalsFlow 测试交易信号流
func TestTradingSignalsFlow(t *testing.T) {
	t.Log("Testing trading signals flow...")
	
	conn := setupNATSConnection(t)
	defer conn.Close()
	
	js := setupJetStream(t, conn)
	
	// 检查TRADING_SIGNALS流的配置
	streamInfo, err := js.StreamInfo("TRADING_SIGNALS")
	require.NoError(t, err, "Failed to get TRADING_SIGNALS stream info")
	t.Logf("TRADING_SIGNALS stream subjects: %v", streamInfo.Config.Subjects)
	
	// 使用更通用的主题格式
	subject := "finovatex.signal.test"
	
	// 创建消费者
	consumerName := fmt.Sprintf("signal-consumer-%d", time.Now().Unix())
	consumer, err := js.PullSubscribe(subject, consumerName, nats.BindStream("TRADING_SIGNALS"))
	require.NoError(t, err, "Failed to create signal consumer")
	defer consumer.Unsubscribe()
	
	// 发布交易信号
	signal := TradingSignal{
		ID:         fmt.Sprintf("signal-%d", time.Now().Unix()),
		Action:     "BUY",
		Symbol:     "BTCUSDT",
		Price:      45000.0,
		Quantity:   0.1,
		Timestamp:  time.Now(),
		StrategyID: "test-strategy-001",
	}
	
	signalData, err := json.Marshal(signal)
	require.NoError(t, err)
	
	_, err = js.Publish(subject, signalData)
	require.NoError(t, err, "Failed to publish trading signal")
	
	t.Log("Published trading signal")
	
	// 接收并验证信号
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	
	msgs, err := consumer.Fetch(1, nats.Context(ctx))
	require.NoError(t, err, "Failed to fetch signal")
	require.Len(t, msgs, 1, "Should receive exactly one signal")
	
	var receivedSignal TradingSignal
	err = json.Unmarshal(msgs[0].Data, &receivedSignal)
	require.NoError(t, err, "Failed to unmarshal signal")
	
	// 验证信号内容
	assert.Equal(t, signal.Action, receivedSignal.Action)
	assert.Equal(t, signal.Symbol, receivedSignal.Symbol)
	assert.Equal(t, signal.Price, receivedSignal.Price)
	assert.Equal(t, signal.Quantity, receivedSignal.Quantity)
	assert.Equal(t, signal.StrategyID, receivedSignal.StrategyID)
	
	msgs[0].Ack()
	t.Log("✓ Trading signal flow test passed")
}

// TestMultipleConsumers 测试多消费者场景
func TestMultipleConsumers(t *testing.T) {
	t.Log("Testing multiple consumers...")
	
	conn := setupNATSConnection(t)
	defer conn.Close()
	
	js := setupJetStream(t, conn)
	
	// 创建多个消费者
	consumerCount := 3
	consumers := make([]*nats.Subscription, consumerCount)
	
	for i := 0; i < consumerCount; i++ {
		consumerName := fmt.Sprintf("multi-consumer-%d-%d", time.Now().Unix(), i)
		consumer, err := js.PullSubscribe("finovatex.market.trade.ETHUSDT", consumerName, nats.BindStream("MARKET_DATA"))
		require.NoError(t, err, "Failed to create consumer %d", i)
		consumers[i] = consumer
		defer consumer.Unsubscribe()
	}
	
	// 发布消息
	testMsg := TestMessage{
		ID:        fmt.Sprintf("multi-test-%d", time.Now().Unix()),
		Type:      "trade",
		Symbol:    "ETHUSDT",
		Price:     3000.0,
		Volume:    2.5,
		Timestamp: time.Now(),
	}
	
	msgData, err := json.Marshal(testMsg)
	require.NoError(t, err)
	
	_, err = js.Publish("finovatex.market.trade.ETHUSDT", msgData)
	require.NoError(t, err, "Failed to publish message for multiple consumers")
	
	t.Log("Published message for multiple consumers")
	
	// 验证所有消费者都能接收到消息
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	
	for i, consumer := range consumers {
		msgs, err := consumer.Fetch(1, nats.Context(ctx))
		assert.NoError(t, err, "Consumer %d should receive message", i)
		if len(msgs) > 0 {
			var receivedMsg TestMessage
			err = json.Unmarshal(msgs[0].Data, &receivedMsg)
			assert.NoError(t, err, "Consumer %d should unmarshal message", i)
			assert.Equal(t, testMsg.Symbol, receivedMsg.Symbol)
			msgs[0].Ack()
			t.Logf("✓ Consumer %d received message", i)
		}
	}
	
	t.Log("✓ Multiple consumers test passed")
}

// TestMessagePersistence 测试消息持久化
func TestMessagePersistence(t *testing.T) {
	t.Log("Testing message persistence...")
	
	conn := setupNATSConnection(t)
	defer conn.Close()
	
	js := setupJetStream(t, conn)
	
	// 发布消息到系统事件流
	systemMsg := map[string]interface{}{
		"event_type": "user_login",
		"user_id":    "test-user-123",
		"timestamp":  time.Now().Unix(),
		"ip_address": "192.168.1.100",
		"success":    true,
	}

	msgData, err := json.Marshal(systemMsg)
	require.NoError(t, err)

	_, err = js.Publish("finovatex.system.user_login", msgData)
	require.NoError(t, err, "Failed to publish system message")

	t.Log("Published system message")

	// 检查流状态
	streamInfo, err := js.StreamInfo("SYSTEM_EVENTS")
	require.NoError(t, err, "Failed to get system stream info")

	assert.True(t, streamInfo.State.Msgs > 0, "System stream should have messages")
	t.Logf("✓ System stream has %d messages", streamInfo.State.Msgs)

	// 创建消费者并验证消息仍然存在
	consumerName := fmt.Sprintf("system-consumer-%d", time.Now().Unix())
	consumer, err := js.PullSubscribe("finovatex.system.user_login", consumerName, nats.BindStream("SYSTEM_EVENTS"))
	require.NoError(t, err, "Failed to create system consumer")
	defer consumer.Unsubscribe()
	
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	
	msgs, err := consumer.Fetch(1, nats.Context(ctx))
	assert.NoError(t, err, "Should be able to fetch audit message")
	if len(msgs) > 0 {
		var receivedAudit map[string]interface{}
		err = json.Unmarshal(msgs[0].Data, &receivedAudit)
		assert.NoError(t, err, "Should unmarshal audit message")
		assert.Equal(t, "user_login", receivedAudit["event_type"])
		assert.Equal(t, "test-user-123", receivedAudit["user_id"])
		msgs[0].Ack()
		t.Log("✓ Message persistence verified")
	}
}

// TestPerformance 测试性能基准
func TestPerformance(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping performance test in short mode")
	}
	
	t.Log("Testing NATS performance...")
	
	conn := setupNATSConnection(t)
	defer conn.Close()
	
	js := setupJetStream(t, conn)
	
	// 性能测试参数
	perfMessageCount := 100
	subject := "finovatex.market.ticker.PERFORMANCE_TEST"
	

	
	// 测试发布性能
	start := time.Now()
	for i := 0; i < perfMessageCount; i++ {
		msg := TestMessage{
			ID:        fmt.Sprintf("perf-msg-%d", i),
			Type:      "price_update",
			Symbol:    "PERFORMANCE_TEST",
			Price:     float64(i),
			Volume:    1.0,
			Timestamp: time.Now(),
		}
		
		msgData, _ := json.Marshal(msg)
		_, err := js.Publish(subject, msgData)
		require.NoError(t, err)
	}
	publishDuration := time.Since(start)
	
	publishRate := float64(perfMessageCount) / publishDuration.Seconds()
	t.Logf("Published %d messages in %v (%.2f msg/sec)", perfMessageCount, publishDuration, publishRate)
	
	// 验证发布性能
	assert.True(t, publishRate > 10, "Publish rate should be > 10 msg/sec, got %.2f", publishRate)
	
	t.Log("✓ Performance test passed")
}

// TestErrorHandling 测试错误处理
func TestErrorHandling(t *testing.T) {
	t.Log("Testing error handling...")
	
	conn := setupNATSConnection(t)
	defer conn.Close()
	
	js := setupJetStream(t, conn)
	
	// 测试发布到不存在的流
	_, err := js.Publish("nonexistent.subject", []byte("test"))
	assert.Error(t, err, "Should fail to publish to non-existent stream")
	t.Log("✓ Correctly handled publish to non-existent stream")
	
	// 测试绑定到不存在的流
	_, err = js.PullSubscribe("invalid.subject", "test-consumer", nats.BindStream("NONEXISTENT_STREAM"))
	assert.Error(t, err, "Should fail to bind to non-existent stream")
	t.Log("✓ Correctly handled binding to non-existent stream")
	
	t.Log("✓ Error handling test passed")
}

// BenchmarkNATSPublish 发布性能基准测试
func BenchmarkNATSPublish(b *testing.B) {
	conn, err := nats.Connect(natsURL)
	if err != nil {
		b.Fatalf("Failed to connect to NATS: %v", err)
	}
	defer conn.Close()
	
	js, err := conn.JetStream()
	if err != nil {
		b.Fatalf("Failed to create JetStream context: %v", err)
	}
	
	msg := TestMessage{
		ID:        "benchmark-msg",
		Type:      "price_update",
		Symbol:    "BTCUSDT",
		Price:     45000.0,
		Volume:    1.0,
		Timestamp: time.Now(),
	}
	
	msgData, _ := json.Marshal(msg)
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := js.Publish("market.prices.BTCUSDT", msgData)
		if err != nil {
			b.Fatalf("Failed to publish: %v", err)
		}
	}
}