#!/bin/bash
set -e

usage() {
    echo "Usage: $0 [--config FILE] [--test-data DIR] <module>"
    echo "  <module> is the dir/top identifier from simulation.toml"
    echo "  Examples:"
    echo "    $0 BasicModules/logical"
    echo "    $0 FlowControl/bus_create"
    echo "    $0 logical          # matches any module whose id contains 'logical'"
    echo "    $0 --test-data /data/my_test_data FFTs/fft_direct"
    usage_test_paths
}

source "$(dirname "$0")/lib/test-paths.sh"
parse_test_paths "$@"
if [ ${#REST_ARGS[@]} -ne 1 ]; then
    usage; exit 1
fi

MODULE="${REST_ARGS[0]}"

echo "--- Building CI Environment ---"
docker compose "${COMPOSE_ARGS[@]}" build

echo "--- Running test for module: $MODULE ---"
docker compose "${COMPOSE_ARGS[@]}" run --rm \
    -e MODULE="$MODULE" \
    test-runner /bin/sh run_test.sh

echo "--- Done ---"
