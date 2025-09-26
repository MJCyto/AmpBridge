#!/bin/bash

# Start webpack in the background
echo "Starting webpack build process..."
cd assets && npm run watch &
WEBPACK_PID=$!

# Wait a moment for webpack to start
sleep 2

# Start Phoenix server
echo "Starting Phoenix server..."
cd .. && mix server

# When Phoenix server stops, kill webpack
echo "Stopping webpack..."
kill $WEBPACK_PID
