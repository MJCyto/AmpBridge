#!/bin/bash

# Test script to send MQTT commands to set all zones to 10% volume
# This requires mosquitto_pub to be installed

MQTT_BROKER="192.168.1.233"
MQTT_PORT="1885"
BASE_TOPIC="ampbridge/zones"

echo "Setting all zones to 10% volume via MQTT..."
echo "MQTT Broker: ${MQTT_BROKER}:${MQTT_PORT}"
echo ""

# Set volume for zones 0-6 (based on your API response)
for zone in 0 1 2 3 4 5 6; do
    echo "Setting zone ${zone} to 10% volume..."
    mosquitto_pub -h ${MQTT_BROKER} -p ${MQTT_PORT} -t "${BASE_TOPIC}/${zone}/volume/set" -m "10"
    sleep 0.5  # Small delay between commands
done

echo ""
echo "MQTT volume commands sent!"
echo "Check your AmpBridge logs to see if the commands were received."
echo ""
echo "You can also monitor MQTT messages with:"
echo "mosquitto_sub -h ${MQTT_BROKER} -p ${MQTT_PORT} -t '${BASE_TOPIC}/#'"
