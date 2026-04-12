#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <module>"
    echo "  <module> is the dir/top identifier from simulation.toml"
    echo "  Examples:"
    echo "    $0 BasicModules/logical"
    echo "    $0 FlowControl/bus_create"
    echo "    $0 logical          # matches any module whose id contains 'logical'"
    exit 1
fi

MODULE="$1"
COMPOSE_FILE="container/docker-compose.local.yml"

echo "--- Building CI Environment ---"
docker compose -f $COMPOSE_FILE build

echo "--- Running test for module: $MODULE ---"
docker compose -f $COMPOSE_FILE run --rm \
    -e MODULE="$MODULE" \
    test-runner /bin/sh run_test.sh

echo "--- Done ---"
