param(
    [string]$NatsUrl = "nats://localhost:4222",
    [string]$User = "finovatex_user",
    [string]$Password = "finovatex_nats_password",
    [switch]$Docker,
    [switch]$Help
)

if ($Help) {
    Write-Host "NATS JetStream Initialization Script" -ForegroundColor Green
    Write-Host "Usage: .\scripts\init-nats-streams.ps1 [options]" -ForegroundColor Yellow
    Write-Host "Options:"
    Write-Host "  -NatsUrl [url]      NATS server URL (default: nats://localhost:4222)"
    Write-Host "  -User [username]    NATS username (default: finovatex_user)"
    Write-Host "  -Password [pass]    NATS password"
    Write-Host "  -Docker             Use Docker environment"
    Write-Host "  -Help               Show this help message"
    exit 0
}

# Check nats CLI tool
$natsCmd = Get-Command nats -ErrorAction SilentlyContinue
if (-not $natsCmd) {
    Write-Host "Error: nats CLI tool not installed" -ForegroundColor Red
    Write-Host "Please install NATS CLI: go install github.com/nats-io/natscli/nats@latest" -ForegroundColor Yellow
    exit 1
}

Write-Host "FinovateX NATS JetStream Initialization" -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green

if ($Docker) {
    $NatsUrl = "nats://localhost:4222"
}

Write-Host "Connecting to NATS server: $NatsUrl" -ForegroundColor Yellow
Write-Host "Waiting for NATS service to start..." -ForegroundColor Yellow

$maxRetries = 30
$retryCount = 0

while ($retryCount -lt $maxRetries) {
    $retryCount++
    
    try {
        $testResult = & nats --server="nats://$User`:$Password@localhost:4222" account info 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "NATS service is ready" -ForegroundColor Green
            break
        }
    }
    catch {
        # Ignore errors and continue retrying
    }
    
    if ($retryCount -eq $maxRetries) {
        Write-Host "Error: NATS service failed to start within expected time" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Attempt $retryCount/$maxRetries - waiting for NATS service..." -ForegroundColor Gray
    Start-Sleep -Seconds 2
}

Write-Host "Starting to create JetStream streams and consumers..." -ForegroundColor Yellow

# Function to create streams
function Create-Stream {
    param(
        [string]$Name,
        [string[]]$Subjects,
        [string]$Description,
        [string]$MaxAge = "24h",
        [int]$MaxMsgs = 1000000,
        [string]$MaxBytes = "1GB"
    )
    
    Write-Host "Creating stream: $Name" -ForegroundColor Cyan
    $subjectsStr = $Subjects -join ","
    
    try {
        $result = & nats --server="nats://$User`:$Password@localhost:4222" stream add $Name --subjects=$subjectsStr --description="$Description" --max-age=$MaxAge --max-msgs=$MaxMsgs --max-bytes=$MaxBytes --defaults 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Stream '$Name' created successfully" -ForegroundColor Green
        } else {
            Write-Host "Failed to create stream '$Name'" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Error creating stream '$Name': $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to create consumers
function Create-Consumer {
    param(
        [string]$StreamName,
        [string]$ConsumerName,
        [string]$Description
    )
    
    Write-Host "Creating consumer: $ConsumerName" -ForegroundColor Cyan
    
    try {
        $result = & nats --server="nats://$User`:$Password@localhost:4222" consumer add $StreamName $ConsumerName --description="$Description" --defaults 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Consumer '$ConsumerName' created successfully" -ForegroundColor Green
        } else {
            Write-Host "Failed to create consumer '$ConsumerName'" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Error creating consumer '$ConsumerName': $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Create market data stream
$marketDataSubjects = @("finovatex.market.kline.*", "finovatex.market.ticker.*", "finovatex.market.depth.*", "finovatex.market.trade.*")
Create-Stream -Name "MARKET_DATA" -Subjects $marketDataSubjects -Description "Market data stream" -MaxAge "7d" -MaxMsgs 10000000 -MaxBytes "10GB"

# Create trading signals stream
$signalSubjects = @("finovatex.signal.*")
Create-Stream -Name "TRADING_SIGNALS" -Subjects $signalSubjects -Description "Trading signals stream" -MaxAge "30d" -MaxMsgs 1000000 -MaxBytes "1GB"

# Create execution events stream
$executionSubjects = @("finovatex.execution.*")
Create-Stream -Name "EXECUTION_EVENTS" -Subjects $executionSubjects -Description "Execution events stream" -MaxAge "90d" -MaxMsgs 5000000 -MaxBytes "5GB"

# Create risk events stream
$riskSubjects = @("finovatex.risk.*")
Create-Stream -Name "RISK_EVENTS" -Subjects $riskSubjects -Description "Risk events stream" -MaxAge "365d" -MaxMsgs 1000000 -MaxBytes "1GB"

# Create system events stream
$systemSubjects = @("finovatex.system.*")
Create-Stream -Name "SYSTEM_EVENTS" -Subjects $systemSubjects -Description "System events stream" -MaxAge "30d" -MaxMsgs 1000000 -MaxBytes "1GB"

Write-Host "Creating consumers..." -ForegroundColor Yellow

# Create consumers for market data stream
Create-Consumer -StreamName "MARKET_DATA" -ConsumerName "strategy-engine" -Description "Strategy engine consumer"
Create-Consumer -StreamName "MARKET_DATA" -ConsumerName "data-persistence" -Description "Data persistence consumer"

# Create consumers for trading signals stream
Create-Consumer -StreamName "TRADING_SIGNALS" -ConsumerName "execution-engine" -Description "Execution engine consumer"
Create-Consumer -StreamName "TRADING_SIGNALS" -ConsumerName "risk-engine" -Description "Risk engine consumer"

# Create consumers for execution events stream
Create-Consumer -StreamName "EXECUTION_EVENTS" -ConsumerName "account-manager" -Description "Account manager consumer"
Create-Consumer -StreamName "EXECUTION_EVENTS" -ConsumerName "audit-logger" -Description "Audit logger consumer"

# Create consumers for risk events stream
Create-Consumer -StreamName "RISK_EVENTS" -ConsumerName "alert-manager" -Description "Alert manager consumer"
Create-Consumer -StreamName "RISK_EVENTS" -ConsumerName "compliance-monitor" -Description "Compliance monitor consumer"

# Create consumers for system events stream
Create-Consumer -StreamName "SYSTEM_EVENTS" -ConsumerName "monitoring" -Description "Monitoring system consumer"

Write-Host "Verifying JetStream configuration..." -ForegroundColor Yellow
Write-Host "Current stream list:" -ForegroundColor Cyan

try {
    & nats --server="nats://$User`:$Password@localhost:4222" stream list
}
catch {
    Write-Host "Error getting stream list" -ForegroundColor Red
}

Write-Host "NATS JetStream initialization completed!" -ForegroundColor Green