#!/usr/bin/env bash
set -euo pipefail

# Multi-Python version test runner using Docker
# Usage: ./dev/test-versions.sh [OPTIONS] [VERSIONS...] [-- PYTEST_ARGS...]
#
# Options:
#   -r, --with-readonly    Include readonly e2e tests (auto-mounts auth)
#   -h, --help             Show this help
#
# Examples:
#   ./dev/test-versions.sh                    # All versions, unit+integration
#   ./dev/test-versions.sh 3.12 3.13          # Specific versions only
#   ./dev/test-versions.sh -r                 # Include readonly e2e tests
#   ./dev/test-versions.sh -- -k test_encoder # Pass pytest args

DEFAULT_VERSIONS="3.10 3.11 3.12 3.13 3.14"
VERSIONS=""
PYTEST_ARGS=""
WITH_READONLY=false
CONTAINER_PREFIX="pytest-$$"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

usage() {
    cat <<EOF
Multi-Python version test runner using Docker

Usage: $0 [OPTIONS] [VERSIONS...] [-- PYTEST_ARGS...]

Options:
  -r, --with-readonly    Include readonly e2e tests (auto-mounts auth)
  -h, --help             Show this help

Examples:
  $0                        # All versions (3.10-3.14), unit+integration
  $0 3.12 3.13              # Specific versions only
  $0 -r                     # Include readonly e2e tests
  $0 -- -k test_encoder     # Pass pytest args
  $0 -r 3.12 -- -k test_foo # Combine options
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--with-readonly)
            WITH_READONLY=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            PYTEST_ARGS="$*"
            break
            ;;
        3.1[0-9])
            VERSIONS="$VERSIONS $1"
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac
done

# Use default versions if none specified
VERSIONS="${VERSIONS:-$DEFAULT_VERSIONS}"
VERSIONS=$(echo "$VERSIONS" | xargs)  # Trim whitespace

# Set pytest command based on readonly flag
if [ "$WITH_READONLY" = true ]; then
    PYTEST_BASE="pytest -m 'readonly or not e2e'"
else
    PYTEST_BASE="pytest --ignore=tests/e2e"
fi

# Temp directory for logs
TMPDIR=$(mktemp -d)

cleanup() {
    # Kill any running containers
    for v in $VERSIONS; do
        docker kill "$CONTAINER_PREFIX-$v" 2>/dev/null || true
    done
    rm -rf "$TMPDIR"
}

trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

# Check Docker is running
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}Error: Docker daemon is not running${NC}" >&2
    exit 1
fi

# Check auth if readonly mode
if [ "$WITH_READONLY" = true ] && [ ! -d "$HOME/.notebooklm" ]; then
    echo -e "${RED}Error: No auth found at ~/.notebooklm. Run 'notebooklm login' first.${NC}" >&2
    exit 1
fi

echo "Testing Python versions: $VERSIONS"
echo "Pytest command: $PYTEST_BASE $PYTEST_ARGS"
echo ""

# Build volume mount args (using arrays for safety with spaces)
VOLUME_ARGS=(-v "$PWD:/src:ro")
if [ "$WITH_READONLY" = true ]; then
    VOLUME_ARGS+=(-v "$HOME/.notebooklm:/root/.notebooklm:ro")
    echo "Auth storage mounted for readonly e2e tests"
fi

# Pre-pull images
echo "Checking images..."
for v in $VERSIONS; do
    if ! docker image inspect "python:$v-slim" >/dev/null 2>&1; then
        echo -e "${YELLOW}Pulling python:$v-slim...${NC}"
        if ! docker pull -q "python:$v-slim"; then
            echo -e "${RED}Error: python:$v-slim not available${NC}" >&2
            exit 1
        fi
    fi
done

# Launch containers in parallel
echo ""
for v in $VERSIONS; do
    echo -e "${YELLOW}Starting Python $v...${NC}"
    (
        timeout 600 docker run --rm \
            --name "$CONTAINER_PREFIX-$v" \
            "${VOLUME_ARGS[@]}" \
            -v "notebooklm-pip-cache-$v:/root/.cache/pip" \
            -w /test \
            "python:$v-slim" \
            sh -c "cp -r /src/. . && rm -rf .git .venv __pycache__ .pytest_cache && pip install -q uv && uv pip install --system -e '.[dev]' -q && $PYTEST_BASE $PYTEST_ARGS" \
            > "$TMPDIR/$v.log" 2>&1
        echo $? > "$TMPDIR/$v.exit"
    ) &
done

# Wait for all containers
wait

# Print results
echo ""
echo "════════════════════════════════════════"
echo "                RESULTS                 "
echo "════════════════════════════════════════"

FAILED=0
for v in $VERSIONS; do
    # Handle missing exit file (killed before writing)
    if [ -f "$TMPDIR/$v.exit" ]; then
        exit_code=$(cat "$TMPDIR/$v.exit")
    else
        exit_code=137  # Killed
    fi

    # Extract pytest summary line
    summary=$(grep -E "passed|failed|error" "$TMPDIR/$v.log" 2>/dev/null | grep -E "^[0-9]|passed|failed" | tail -1 || echo "")

    if [ "$exit_code" -eq 0 ]; then
        printf "Python %-5s ${GREEN}PASS${NC}  %s\n" "$v:" "$summary"
    else
        printf "Python %-5s ${RED}FAIL${NC}  %s\n" "$v:" "$summary"
        echo "──────────────────────────────────────"
        tail -30 "$TMPDIR/$v.log"
        echo "──────────────────────────────────────"
        FAILED=1
    fi
done

echo "════════════════════════════════════════"

exit $FAILED
