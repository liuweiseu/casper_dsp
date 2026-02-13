###############################################################################
# Cocotb + Verilator 高级仿真 Makefile
###############################################################################

# --- 基础配置 ---
SIM ?= verilator
TOPLEVEL_LANG ?= verilog

# 路径定义
RTL_ROOT = $(shell pwd)/../rtl
RESULTS_ROOT = $(shell pwd)/sim_results

# --- 接收参数 (可通过命令行覆盖) ---
# TARGET_DIR: RTL 子目录名 (例如: basic)
# TOP: 顶层模块名 (例如: adder)
TARGET_DIR ?= .
TOP ?= top

# --- 动态计算输出路径 ---
# 所有的仿真产物都会存放在 tests/sim_results/TARGET_DIR/TOP/ 下
# 使用 override 确保这些变量在 include 之后依然生效
override SIM_BUILD := $(RESULTS_ROOT)/$(TARGET_DIR)/$(TOP)

# --- 环境变量配置 ---
# 1. 禁用 Python 缓存文件夹 (__pycache__)
export PYTHONDONTWRITEBYTECODE := 1

# 2. 重定向 Cocotb 的测试结果 XML 文件
export COCOTB_RESULTS_FILE := $(SIM_BUILD)/results.xml

# 3. 确保 Python 能在 tests 目录下找到测试脚本
export PYTHONPATH := $(shell pwd):$(PYTHONPATH)

# --- 仿真器参数设置 ---
# 自动搜寻整个 RTL 目录下的所有 .v 文件，解决跨目录调用依赖
VERILOG_SOURCES = $(shell find $(RTL_ROOT) -name "*.v")

# 顶层配置
TOPLEVEL = $(TOP)
MODULE = test_$(TOP)

# Verilator 特定参数：开启波形，并强制指定波形路径
EXTRA_ARGS += --trace --trace-structs
PLUSARGS += --trace-file=$(SIM_BUILD)/dump.vcd

# --- 引入 Cocotb 核心规则 ---
include $(shell cocotb-config --makefiles)/Makefile.sim

# --- 自定义清理逻辑 ---
# 使用双冒号扩展 clean 目标
clean::
	@echo "Cleaning up simulation results..."
	rm -rf $(RESULTS_ROOT)
	rm -rf __pycache__
	rm -f results.xml dump.vcd

# 打印配置信息（调试用：make info）
info:
	@echo "RTL Root:      $(RTL_ROOT)"
	@echo "Target Dir:    $(TARGET_DIR)"
	@echo "Top Module:    $(TOP)"
	@echo "Sim Build:     $(SIM_BUILD)"
	@echo "Python Module: $(MODULE)"
	@echo "XML Result:    $(COCOTB_RESULTS_FILE)"
