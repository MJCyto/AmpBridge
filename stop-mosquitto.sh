#!/bin/bash
set -e

# Mosquitto MQTT Broker Stop Script for AmpBridge
# This script stops the Mosquitto MQTT broker

# Configuration
MOSQUITTO_PID_FILE="/home/mj/amp-bridge/mosquitto.pid"

# Check if Mosquitto is running
if [ ! -f "$MOSQUITTO_PID_FILE" ]; then
    echo "Mosquitto is not running (no PID file found)"
    exit 0
fi

PID=$(cat "$MOSQUITTO_PID_FILE")

# Check if the process is actually running
if ! ps -p "$PID" > /dev/null 2>&1; then
    echo "Mosquitto process $PID is not running (stale PID file)"
    rm -f "$MOSQUITTO_PID_FILE"
    exit 0
fi

echo "Stopping Mosquitto MQTT broker (PID: $PID)..."

# Try graceful shutdown first
kill -TERM "$PID"

# Wait for graceful shutdown (up to 10 seconds)
for i in {1..10}; do
    if ! ps -p "$PID" > /dev/null 2>&1; then
        echo "✅ Mosquitto MQTT broker stopped gracefully"
        rm -f "$MOSQUITTO_PID_FILE"
        exit 0
    fi
    echo "Waiting for graceful shutdown... ($i/10)"
    sleep 1
done

# Force kill if graceful shutdown failed
echo "Graceful shutdown failed, forcing termination..."
kill -KILL "$PID"

# Wait a moment and verify
sleep 1
if ! ps -p "$PID" > /dev/null 2>&1; then
    echo "✅ Mosquitto MQTT broker stopped forcefully"
    rm -f "$MOSQUITTO_PID_FILE"
else
    echo "❌ Failed to stop Mosquitto MQTT broker"
    exit 1
fi
