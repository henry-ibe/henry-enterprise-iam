#!/bin/bash
# Stop script for Phase 60 Employee Portal

echo "=== Phase 60: Stopping Employee Portal ==="
echo ""

docker-compose down

echo ""
echo "✅ All services stopped"
echo ""
echo "To remove volumes (WARNING: deletes all data):"
echo "  docker-compose down -v"
