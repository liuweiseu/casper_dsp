# Sourced by scripts/run-local-test.sh and scripts/run-module-test.sh.
#
# Chooses the simulation config and the test data for the test container:
#   1. --config FILE / --test-data DIR on the command line
#   2. else $CASPER_SIM_CONFIG / $CASPER_TEST_DATA in the host environment
#   3. else the defaults built into the image (tests/simulation.toml, test_data/)
# The two are chosen independently. A chosen file / directory is mounted
# read-only into the container (container/docker-compose.config.yml,
# container/docker-compose.testdata.yml), which points the tests at it.
#
# parse_test_paths "$@" sets:
#   COMPOSE_ARGS  docker compose -f arguments
#   REST_ARGS     the remaining (non-option) arguments

usage_test_paths() {
    cat <<USAGE
Options:
  --config FILE     simulation config to use instead of tests/simulation.toml
                    (default: \$CASPER_SIM_CONFIG if set)
  --test-data DIR   test data root, laid out exactly like test_data/
                    (default: \$CASPER_TEST_DATA if set)
  -h, --help        show this help
USAGE
}

parse_test_paths() {
    local config="" config_src="" data="" data_src=""
    REST_ARGS=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --config|--test-data)
                if [ $# -lt 2 ] || [ -z "$2" ]; then
                    echo "error: $1 needs a value" >&2; exit 1
                fi
                if [ "$1" = --config ]; then config="$2"; config_src="--config"
                else data="$2"; data_src="--test-data"; fi
                shift 2 ;;
            --config=*)    config="${1#*=}"; config_src="--config"; shift ;;
            --test-data=*) data="${1#*=}"; data_src="--test-data"; shift ;;
            -h|--help)     usage; exit 0 ;;
            --)            shift; REST_ARGS+=("$@"); break ;;
            -*)            echo "error: unknown option $1" >&2; usage >&2; exit 1 ;;
            *)             REST_ARGS+=("$1"); shift ;;
        esac
    done
    if [ -z "$config_src" ] && [ -n "${CASPER_SIM_CONFIG:-}" ]; then
        config="$CASPER_SIM_CONFIG"; config_src="CASPER_SIM_CONFIG"
    fi
    if [ -z "$data_src" ] && [ -n "${CASPER_TEST_DATA:-}" ]; then
        data="$CASPER_TEST_DATA"; data_src="CASPER_TEST_DATA"
    fi

    COMPOSE_ARGS=(-f container/docker-compose.local.yml)
    if [ -n "$config_src" ]; then
        if [ ! -f "$config" ]; then
            echo "error: simulation config not found: $config (from $config_src)" >&2; exit 1
        fi
        export HOST_SIM_CONFIG
        HOST_SIM_CONFIG="$(realpath "$config")"
        COMPOSE_ARGS+=(-f container/docker-compose.config.yml)
        echo "config   : $HOST_SIM_CONFIG (from $config_src)"
    else
        echo "config   : tests/simulation.toml (default)"
    fi
    if [ -n "$data_src" ]; then
        if [ ! -d "$data" ]; then
            echo "error: test data directory not found: $data (from $data_src)" >&2; exit 1
        fi
        export HOST_TEST_DATA
        HOST_TEST_DATA="$(realpath "$data")"
        COMPOSE_ARGS+=(-f container/docker-compose.testdata.yml)
        echo "test data: $HOST_TEST_DATA (from $data_src)"
    else
        echo "test data: test_data/ (default)"
    fi
}
