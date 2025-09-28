#!/bin/bash
set -e

# Mosquitto MQTT Broker Start Script for AmpBridge
# This script starts the Mosquitto MQTT broker for development/production use

# Configuration
MOSQUITTO_CONFIG="/home/mj/amp-bridge/mosquitto.conf"
MOSQUITTO_PID_FILE="/home/mj/amp-bridge/mosquitto.pid"
MOSQUITTO_LOG_FILE="/home/mj/amp-bridge/mosquitto.log"
MOSQUITTO_DATA_DIR="/home/mj/amp-bridge/mosquitto-data"

# Create data directory if it doesn't exist
mkdir -p "$MOSQUITTO_DATA_DIR"

# Check if Mosquitto is already running
if [ -f "$MOSQUITTO_PID_FILE" ]; then
    PID=$(cat "$MOSQUITTO_PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "Mosquitto is already running with PID $PID"
        exit 0
    else
        echo "Removing stale PID file"
        rm -f "$MOSQUITTO_PID_FILE"
    fi
fi

# Check if port 1885 is already in use
if ss -tuln | grep -q ":1885 "; then
    echo "Port 1885 is already in use. Please stop the existing service first."
    exit 1
fi

# Start Mosquitto
echo "Starting Mosquitto MQTT broker..."
echo "Config: $MOSQUITTO_CONFIG"
echo "Data directory: $MOSQUITTO_DATA_DIR"
echo "Log file: $MOSQUITTO_LOG_FILE"

# Start mosquitto in daemon mode
mosquitto -c "$MOSQUITTO_CONFIG" -d

# Wait a moment for Mosquitto to start
sleep 2

# Verify Mosquitto is running by checking the port
if ss -tuln | grep -q ":1885 "; then
    # Find the PID of the mosquitto process (get the one listening on port 1885)
    PID=$(ss -tulnp | grep ":1885 " | grep mosquitto | sed 's/.*pid=\([0-9]*\).*/\1/' | head -1)
    if [ -n "$PID" ]; then
        echo "✅ Mosquitto MQTT broker started successfully!"
        echo "   PID: $PID"
        echo "   Port: 1885"
        echo "   Config: $MOSQUITTO_CONFIG"
        echo "   Log: $MOSQUITTO_LOG_FILE"
        echo ""
        echo "To stop Mosquitto, run: ./stop-mosquitto.sh"
        # Create PID file for stop script
        echo "$PID" > "$MOSQUITTO_PID_FILE"
    else
        echo "❌ Failed to start Mosquitto MQTT broker"
        exit 1
    fi
else
    echo "❌ Failed to start Mosquitto MQTT broker (port not listening)"
    exit 1
fi
