#!/bin/bash
set -e

usage() {
    echo "Usage: $0 [--config FILE] [--test-data DIR]"
    echo "  Runs every test in the simulation config inside the test container."
    usage_test_paths
}

source "$(dirname "$0")/lib/test-paths.sh"
parse_test_paths "$@"
if [ ${#REST_ARGS[@]} -ne 0 ]; then
    echo "error: unexpected argument(s): ${REST_ARGS[*]}" >&2; usage >&2; exit 1
fi

echo "--- Building CI Environment ---"
# Build the test runner image
docker compose "${COMPOSE_ARGS[@]}" build

echo "--- Running CI Tests ---"
# 1. 'up': Starts the Test Runner
# 2. '--exit-code-from test_runner': If pytest fails, the script exits with error
# 3. '--abort-on-container-exit': Stops the container as soon as tests finish
docker compose "${COMPOSE_ARGS[@]}" up \
    --exit-code-from test-runner \
    --abort-on-container-exit

echo "--- Cleaning Up ---"
# Ensure all containers and networks are removed
docker compose "${COMPOSE_ARGS[@]}" down

echo "--- CASPER DSP CI Run Completed Successfully ---"
