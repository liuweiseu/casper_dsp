#!/bin/sh
set -e

echo "Step 1: run prepare script"
python prepare_dump.py --dir ../rtl

echo "Step 2: run pytest"
if [ -n "$MODULE" ]; then
    echo "Filtering tests for module: $MODULE"
    pytest -v --log-cli-level=WARNING -k "$MODULE" test_runner.py
else
    pytest -v --log-cli-level=WARNING test_runner.py
fi