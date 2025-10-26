#!/bin/bash

# Benchmark script for testing memory behavior
# Usage: ./benchmark.sh [num_requests] [delay_ms]
# Environment: Set STATS_PASSWORD if authentication is enabled

NUM_REQUESTS=${1:-100}
DELAY_MS=${2:-10}
HOST="http://0.0.0.0:4567"

# Try to load settings from .env file
if [ -f .env ]; then
  export $(grep "^STATS_PASSWORD=" .env | xargs)
fi

# Default test credentials (will cause OutboxWorker warnings, but that's okay for testing)
INFLUX_TOKEN=${INFLUX_TOKEN:-test-token}
INFLUX_BUCKET=${INFLUX_BUCKET:-test-bucket}
INFLUX_ORG=${INFLUX_ORG:-test-org}

echo "========================================="
echo "SOLECTRUS Ingest Benchmark"
echo "========================================="
echo "Requests: $NUM_REQUESTS"
echo "Delay: ${DELAY_MS}ms between requests"
echo "Target: $HOST"
echo "========================================="
echo ""

# Function to make GET requests to stats page
test_stats() {
  local count=$1
  local delay=$2
  local password=${STATS_PASSWORD:-password}

  echo "Testing GET / (stats page)..."
  for i in $(seq 1 $count); do
    curl -s -o /dev/null -w "Request $i: HTTP %{http_code} - %{time_total}s\n" \
      -H "Cookie: password=$password" \
      "$HOST/"
    sleep $(echo "scale=3; $delay/1000" | bc)
  done
}

# Function to make POST requests with sample data
test_write() {
  local count=$1
  local delay=$2

  echo "Testing POST /api/v2/write (with data)..."
  for i in $(seq 1 $count); do
    timestamp=$(($(date +%s) * 1000000000))
    data="sensor,location=test value=${i}i ${timestamp}"

    curl -s -o /dev/null -w "Request $i: HTTP %{http_code} - %{time_total}s\n" \
      -X POST \
      -H "Authorization: Token $INFLUX_TOKEN" \
      -H "Content-Type: text/plain" \
      --data "$data" \
      "$HOST/api/v2/write?bucket=$INFLUX_BUCKET&org=$INFLUX_ORG&precision=ns"

    sleep $(echo "scale=3; $delay/1000" | bc)
  done
}

# Function to show memory usage (macOS)
show_memory() {
  if pgrep -x "ingest" > /dev/null; then
    pid=$(pgrep -x "ingest")
    rss_kb=$(ps -o rss= -p $pid)
    rss_mb=$(echo "scale=2; $rss_kb/1024" | bc)
    echo "Current memory usage: ${rss_mb} MB (PID: $pid)"
  else
    echo "Process 'ingest' not running"
  fi
}

# Show initial memory
echo "Initial state:"
show_memory
echo ""

# Run benchmark
echo "Starting benchmark..."
echo ""

# Test stats page (GET requests)
test_stats $NUM_REQUESTS $DELAY_MS

echo ""
echo "========================================="
echo "Benchmark completed!"
echo "========================================="
echo ""

# Show final memory
echo "Final state:"
show_memory
echo ""

# Optional: Run write benchmark
read -p "Run POST /write benchmark? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo ""
  echo "Starting POST benchmark..."
  echo "Note: Using token=$INFLUX_TOKEN, bucket=$INFLUX_BUCKET, org=$INFLUX_ORG"
  echo "      Set INFLUX_TOKEN/INFLUX_BUCKET/INFLUX_ORG env vars for real credentials"
  echo ""
  test_write $NUM_REQUESTS $DELAY_MS
  echo ""
  echo "POST benchmark completed!"
  echo ""
  show_memory
  echo ""
fi

echo "Done!"
