package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/nats-io/nats.go"
)

// MarketData 市场数据结构
type MarketData struct {
	Symbol    string    `json:"symbol"`
	Price     float64   `json:"price"`
	Volume    float64   `json:"volume"`
	Timestamp time.Time `json:"timestamp"`
	Type      string    `json:"type"`
}

// TradingSignal 交易信号结构
type TradingSignal struct {
	ID         string    `json:"id"`
	Action     string    `json:"action"`
	Symbol     string    `json:"symbol"`
	Price      float64   `json:"price"`
	Quantity   float64   `json:"quantity"`
	Timestamp  time.Time `json:"timestamp"`
	StrategyID string    `json:"strategy_id"`
}

const (
	natsURL = "nats://finovatex_user:finovatex_nats_password@localhost:4222"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run nats_client_example.go [publisher|subscriber|signal-publisher|signal-subscriber]")
		os.Exit(1)
	}

	mode := os.Args[1]

	// 连接到NATS
	conn, err := nats.Connect(natsURL,
		nats.Timeout(5*time.Second),
		nats.ReconnectWait(1*time.Second),
		nats.MaxReconnects(5),
		nats.DisconnectErrHandler(func(nc *nats.Conn, err error) {
			log.Printf("NATS disconnected: %v", err)
		}),
		nats.ReconnectHandler(func(nc *nats.Conn) {
			log.Printf("NATS reconnected to %v", nc.ConnectedUrl())
		}),
	)
	if err != nil {
		log.Fatalf("Failed to connect to NATS: %v", err)
	}
	defer conn.Close()

	log.Printf("Connected to NATS at %s", conn.ConnectedUrl())

	// 创建JetStream上下文
	js, err := conn.JetStream()
	if err != nil {
		log.Fatalf("Failed to create JetStream context: %v", err)
	}

	// 设置信号处理
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	switch mode {
	case "publisher":
		runMarketDataPublisher(js, sigChan)
	case "subscriber":
		runMarketDataSubscriber(js, sigChan)
	case "signal-publisher":
		runSignalPublisher(js, sigChan)
	case "signal-subscriber":
		runSignalSubscriber(js, sigChan)
	default:
		fmt.Println("Invalid mode. Use: publisher, subscriber, signal-publisher, or signal-subscriber")
		os.Exit(1)
	}
}

// runMarketDataPublisher 运行市场数据发布者
func runMarketDataPublisher(js nats.JetStreamContext, sigChan chan os.Signal) {
	log.Println("Starting market data publisher...")

	symbols := []string{"BTCUSDT", "ETHUSDT", "ADAUSDT", "DOTUSDT"}
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-sigChan:
			log.Println("Shutting down publisher...")
			return
		case <-ticker.C:
			// 为每个交易对发布价格数据
			for _, symbol := range symbols {
				marketData := MarketData{
					Symbol:    symbol,
					Price:     generateRandomPrice(symbol),
					Volume:    generateRandomVolume(),
					Timestamp: time.Now(),
					Type:      "price_update",
				}

				data, err := json.Marshal(marketData)
				if err != nil {
					log.Printf("Failed to marshal market data: %v", err)
					continue
				}

				subject := fmt.Sprintf("market.prices.%s", symbol)
				_, err = js.Publish(subject, data)
				if err != nil {
					log.Printf("Failed to publish to %s: %v", subject, err)
				} else {
					log.Printf("Published %s: $%.2f (Vol: %.4f)", symbol, marketData.Price, marketData.Volume)
				}
			}
		}
	}
}

// runMarketDataSubscriber 运行市场数据订阅者
func runMarketDataSubscriber(js nats.JetStreamContext, sigChan chan os.Signal) {
	log.Println("Starting market data subscriber...")

	// 创建消费者
	consumerName := fmt.Sprintf("market-data-consumer-%d", time.Now().Unix())
	sub, err := js.PullSubscribe("market.prices.*", consumerName, nats.BindStream("MARKET_DATA"))
	if err != nil {
		log.Fatalf("Failed to create subscription: %v", err)
	}
	defer sub.Unsubscribe()

	log.Printf("Subscribed to market.prices.* with consumer: %s", consumerName)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 启动消息处理协程
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			default:
				// 批量获取消息
				msgs, err := sub.Fetch(10, nats.Context(ctx))
				if err != nil {
					if ctx.Err() != nil {
						return
					}
					time.Sleep(100 * time.Millisecond)
					continue
				}

				for _, msg := range msgs {
					var marketData MarketData
					if err := json.Unmarshal(msg.Data, &marketData); err != nil {
						log.Printf("Failed to unmarshal message: %v", err)
						msg.Nak()
						continue
					}

					log.Printf("Received %s: $%.2f (Vol: %.4f) at %s",
						marketData.Symbol,
						marketData.Price,
						marketData.Volume,
						marketData.Timestamp.Format("15:04:05"))

					msg.Ack()
				}
			}
		}
	}()

	// 等待退出信号
	<-sigChan
	log.Println("Shutting down subscriber...")
	cancel()
}

// runSignalPublisher 运行交易信号发布者
func runSignalPublisher(js nats.JetStreamContext, sigChan chan os.Signal) {
	log.Println("Starting trading signal publisher...")

	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	signalID := 1
	for {
		select {
		case <-sigChan:
			log.Println("Shutting down signal publisher...")
			return
		case <-ticker.C:
			// 生成随机交易信号
			signal := TradingSignal{
				ID:         fmt.Sprintf("signal-%d", signalID),
				Action:     generateRandomAction(),
				Symbol:     "BTCUSDT",
				Price:      generateRandomPrice("BTCUSDT"),
				Quantity:   0.1,
				Timestamp:  time.Now(),
				StrategyID: "example-strategy-001",
			}

			data, err := json.Marshal(signal)
			if err != nil {
				log.Printf("Failed to marshal signal: %v", err)
				continue
			}

			subject := fmt.Sprintf("signals.%s.%s", 
				map[string]string{"BUY": "buy", "SELL": "sell"}[signal.Action],
				signal.Symbol)

			_, err = js.Publish(subject, data)
			if err != nil {
				log.Printf("Failed to publish signal: %v", err)
			} else {
				log.Printf("Published signal: %s %s %.4f @ $%.2f",
					signal.Action, signal.Symbol, signal.Quantity, signal.Price)
			}

			signalID++
		}
	}
}

// runSignalSubscriber 运行交易信号订阅者
func runSignalSubscriber(js nats.JetStreamContext, sigChan chan os.Signal) {
	log.Println("Starting trading signal subscriber...")

	// 创建消费者
	consumerName := fmt.Sprintf("signal-consumer-%d", time.Now().Unix())
	sub, err := js.PullSubscribe("signals.*.*", consumerName, nats.BindStream("TRADING_SIGNALS"))
	if err != nil {
		log.Fatalf("Failed to create signal subscription: %v", err)
	}
	defer sub.Unsubscribe()

	log.Printf("Subscribed to signals.*.* with consumer: %s", consumerName)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 启动信号处理协程
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			default:
				// 获取交易信号
				msgs, err := sub.Fetch(5, nats.Context(ctx))
				if err != nil {
					if ctx.Err() != nil {
						return
					}
					time.Sleep(100 * time.Millisecond)
					continue
				}

				for _, msg := range msgs {
					var signal TradingSignal
					if err := json.Unmarshal(msg.Data, &signal); err != nil {
						log.Printf("Failed to unmarshal signal: %v", err)
						msg.Nak()
						continue
					}

					log.Printf("🚨 SIGNAL RECEIVED: %s %s %.4f @ $%.2f (Strategy: %s, ID: %s)",
						signal.Action,
						signal.Symbol,
						signal.Quantity,
						signal.Price,
						signal.StrategyID,
						signal.ID)

					// 模拟信号处理
					processTradingSignal(signal)

					msg.Ack()
				}
			}
		}
	}()

	// 等待退出信号
	<-sigChan
	log.Println("Shutting down signal subscriber...")
	cancel()
}

// 辅助函数
func generateRandomPrice(symbol string) float64 {
	basePrice := map[string]float64{
		"BTCUSDT": 45000.0,
		"ETHUSDT": 3000.0,
		"ADAUSDT": 0.5,
		"DOTUSDT": 8.0,
	}

	base := basePrice[symbol]
	if base == 0 {
		base = 100.0
	}

	// 添加±5%的随机波动
	variation := (float64(time.Now().UnixNano()%1000) - 500) / 10000.0
	return base * (1 + variation)
}

func generateRandomVolume() float64 {
	return float64(time.Now().UnixNano()%10000) / 10000.0
}

func generateRandomAction() string {
	if time.Now().UnixNano()%2 == 0 {
		return "BUY"
	}
	return "SELL"
}

func processTradingSignal(signal TradingSignal) {
	// 模拟信号处理逻辑
	log.Printf("  → Processing %s signal for %s...", signal.Action, signal.Symbol)
	
	// 模拟风险检查
	if signal.Quantity > 1.0 {
		log.Printf("  ⚠️  Risk check: Large quantity detected (%.4f)", signal.Quantity)
	}
	
	// 模拟执行延迟
	time.Sleep(50 * time.Millisecond)
	
	log.Printf("  ✅ Signal processed successfully")
}