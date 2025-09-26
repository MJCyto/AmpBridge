#!/bin/bash
set -e

# Always ensure database is migrated and seeded
echo "Setting up database..."
/app/bin/amp_bridge eval "AmpBridge.Release.migrate()"
/app/bin/amp_bridge eval "AmpBridge.Release.seed()"
echo "Database setup complete!"

# Start MQTT broker in the background
echo "Starting MQTT broker (Mosquitto)..."
mosquitto -c /app/mosquitto.conf -d
echo "MQTT broker started on port 1885"

# Wait a moment for MQTT broker to fully start
sleep 2

# Start the application
echo "Starting AmpBridge application..."
/app/bin/amp_bridge start

# Wait for all services to be ready
echo "Waiting for services to initialize..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
  attempt=$((attempt + 1))
  echo "Health check attempt $attempt/$max_attempts..."
  
  if curl -f http://localhost:4000/api/health > /dev/null 2>&1; then
    echo "All services are ready!"
    break
  fi
  
  if [ $attempt -eq $max_attempts ]; then
    echo "Warning: Services may not be fully ready, but continuing..."
  else
    sleep 1
  fi
done

echo "AmpBridge is ready to accept requests."
