#!/bin/bash
set -e

# Navigate to the project root directory
cd "$(dirname "$0")/.."

echo "=================================================="
echo "Building Production Database Image"
echo "=================================================="

# Build the custom Docker image using the Dockerfile inside 18-prod/
docker build -t postgres:18 ./18-prod

echo "=================================================="
echo "Build Complete!"
echo "Your custom image has successfully overwritten the local 'postgres:18' tag."
echo "You can now run your company's docker-compose.yml without changing the image name!"
echo "=================================================="
