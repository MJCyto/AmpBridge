#!/bin/bash

# Test script for AmpBridge API endpoints
# Replace YOUR_SERVER_IP with your actual server IP address

SERVER_IP="192.168.1.233"
BASE_URL="http://${SERVER_IP}:4000/api"

echo "Testing AmpBridge API endpoints..."
echo "Server: ${BASE_URL}"
echo ""

# Test 1: Get all zones
echo "1. Getting all zones..."
curl -s "${BASE_URL}/zones" | jq '.'
echo ""

# Test 2: Get specific zone (zone 0)
echo "2. Getting zone 0..."
curl -s "${BASE_URL}/zones/0" | jq '.'
echo ""

# Test 3: Set zone 0 volume to 75%
echo "3. Setting zone 0 volume to 75%..."
curl -s -X POST "${BASE_URL}/zones/0/volume" \
  -H "Content-Type: application/json" \
  -d '{"volume": 75}' | jq '.'
echo ""

# Test 4: Toggle zone 0 mute
echo "4. Toggling zone 0 mute..."
curl -s -X POST "${BASE_URL}/zones/0/mute" | jq '.'
echo ""

# Test 5: Set zone 0 source
echo "5. Setting zone 0 source to 'Source 1'..."
curl -s -X POST "${BASE_URL}/zones/0/source" \
  -H "Content-Type: application/json" \
  -d '{"source": "Source 1"}' | jq '.'
echo ""

# Test 6: Get all zones again to see changes
echo "6. Getting all zones again to see changes..."
curl -s "${BASE_URL}/zones" | jq '.'
echo ""

echo "API testing complete!"
