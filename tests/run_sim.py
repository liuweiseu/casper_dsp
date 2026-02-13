# run_sims.py
import tomllib
import subprocess
import os
from pathlib import Path

def run_all():
    # 1. 读取配置
    with open("simulation.toml", "rb") as f:
        config = tomllib.load(f)

    # 2. 遍历并执行
    for sim in config["simulations"]:
        target_dir = sim["dir"]
        top = sim["top"]
        
        print(f"\n>>> Starting: {top} in {target_dir}")
        
        # 3. 构造环境变量或直接调用 make
        env = os.environ.copy()
        env["TARGET_DIR"] = target_dir
        env["TOP"] = top
        
        # 直接调用你原本那个简单的 Makefile
        result = subprocess.run(
            ["make", "sim", f"TARGET_DIR={target_dir}", f"TOP={top}"],
            env=env
        )
        
        if result.returncode != 0:
            print(f"!!! Simulation {top} failed!")

if __name__ == "__main__":
    run_all()