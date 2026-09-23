CC ?= cc
PKG_CONFIG ?= pkg-config
TARGET := rk3588-hdmi-passthrough
TX_TARGET := hdmirxtest-tx-selftest
SRC := src/passthrough.c
TX_SRC := src/tx-selftest.c

CPPFLAGS += $(shell $(PKG_CONFIG) --cflags libdrm 2>/dev/null)
CFLAGS ?= -O2 -g
CFLAGS += -std=gnu11 -Wall -Wextra -Wpedantic
LDLIBS += $(shell $(PKG_CONFIG) --libs libdrm 2>/dev/null)

SHELL_SCRIPTS := \
	PiCycle.sh \
	TxTest.sh \
	setup.sh \
	scripts/pi-cycle.sh \
	scripts/run.sh \
	scripts/collect-tx-state.sh \
	scripts/tx-selftest-service.sh \
	scripts/install-deps.sh \
	scripts/prepare-monitor-edid.sh \
	scripts/check-monitor-identity.sh \
	scripts/verify-bridge-edid.sh \
	scripts/load-saved-edid.sh \
	scripts/restore-rx-edid.sh \
	scripts/collect-debug.sh \
	packaging/openrc/hdmirxtest-edid

.PHONY: all clean check

all: $(TARGET) $(TX_TARGET)

$(TARGET): $(SRC)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LDLIBS)

$(TX_TARGET): $(TX_SRC)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LDLIBS)

check:
	$(CC) $(CPPFLAGS) $(CFLAGS) -fsyntax-only $(SRC)
	$(CC) $(CPPFLAGS) $(CFLAGS) -fsyntax-only $(TX_SRC)
	python3 -m py_compile tools/clone-monitor-edid.py tests/test_edid_policy.py
	python3 tests/test_edid_policy.py
	python3 tools/clone-monitor-edid.py --input edid/recovery-source.bin --output /tmp/hdmirxtest-v1-check.bin --identity-mode isolated --max-width 1920 --max-height 1080 --max-refresh 60 --max-pixel-clock 600000000
	python3 tools/clone-monitor-edid.py --check /tmp/hdmirxtest-v1-check.bin --identity-mode isolated
	bash -n $(SHELL_SCRIPTS)

clean:
	rm -f $(TARGET) $(TX_TARGET)
	rm -rf tools/__pycache__
