#!/bin/sh
set -e 

echo "Step 1: run prepare script"
python prepare_dump.py --dir ../rtl

echo "Step 2: run pytest"
pytest -v test_runner.py