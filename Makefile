# ===========================================================================
# ip-lookup-C  —  Binary Trie IP Lookup Engine
# ===========================================================================
#
# Targets:
#   make            Build the release binary (./iplookup)
#   make debug      Build with debug symbols and AddressSanitizer
#   make clean      Remove build artefacts
#   make docs       Generate Doxygen HTML documentation
#   make test       Run the smoke test script
#   make bench      Run the reproducible throughput benchmark (no external data)
#
# Usage after build:
#   ./iplookup rrc04 20211122
#
# ===========================================================================

CC      = gcc
TARGET  = iplookup

# Directories
SRC_DIR     = src
INC_DIR     = include
BUILD_DIR   = build
DATA_DIR    = data

SRCS    = $(wildcard $(SRC_DIR)/*.c)
OBJS    = $(patsubst $(SRC_DIR)/%.c, $(BUILD_DIR)/%.o, $(SRCS))

# Compiler flags
CFLAGS_COMMON = -Wall -Wextra -Wpedantic -I$(INC_DIR) -std=c11
CFLAGS_RELEASE = $(CFLAGS_COMMON) -O2
CFLAGS_DEBUG   = $(CFLAGS_COMMON) -g3 -O0 -fsanitize=address,undefined -fno-omit-frame-pointer

CFLAGS ?= $(CFLAGS_RELEASE)

# Link math library for clock() on some platforms
LDFLAGS =

# ===========================================================================
# Default target: release build
# ===========================================================================
.PHONY: all
all: $(DATA_DIR) $(BUILD_DIR) $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)
	@echo ""
	@echo "  Build complete →  ./$(TARGET)"
	@echo "  Usage: ./$(TARGET) <region> <date_tag>"
	@echo ""

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

# ===========================================================================
# Debug build
# ===========================================================================
.PHONY: debug
debug: CFLAGS = $(CFLAGS_DEBUG)
debug: clean all
	@echo "  Debug build complete (ASan + UBSan enabled)"

# ===========================================================================
# Utility targets
# ===========================================================================
$(DATA_DIR):
	mkdir -p $(DATA_DIR)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR) $(TARGET)
	@echo "  Cleaned."

.PHONY: docs
docs:
	doxygen Doxyfile
	@echo "  Docs generated → docs/html/index.html"

.PHONY: test
test:
	@bash scripts/smoke_test.sh

.PHONY: bench
bench: all
	@bash scripts/benchmark.sh

# ===========================================================================
# Dependency tracking (auto-generated .d files)
# ===========================================================================
-include $(OBJS:.o=.d)

$(BUILD_DIR)/%.d: $(SRC_DIR)/%.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -MM -MT $(BUILD_DIR)/$*.o $< > $@
