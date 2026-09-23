CC ?= cc
PKG_CONFIG ?= pkg-config
TARGET := rk3588-hdmi-passthrough
SRC := src/passthrough.c

CPPFLAGS += $(shell $(PKG_CONFIG) --cflags libdrm 2>/dev/null)
CFLAGS ?= -O2 -g
CFLAGS += -std=gnu11 -Wall -Wextra -Wpedantic
LDLIBS += $(shell $(PKG_CONFIG) --libs libdrm 2>/dev/null)

SHELL_SCRIPTS := \
	scripts/run.sh \
	scripts/diagnose.sh \
	scripts/pi-update-and-diagnose.sh \
	scripts/pi-cycle.sh \
	scripts/collect-debug.sh \
	scripts/probe-240.sh \
	scripts/prepare-240.sh \
	scripts/prepare-monitor-edid.sh \
	scripts/verify-bridge-edid.sh \
	scripts/restore-rx-edid.sh \
	scripts/install-deps.sh \
	packaging/openrc/hdmirxtest-edid

.PHONY: all clean check

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LDLIBS)

check:
	$(CC) $(CPPFLAGS) $(CFLAGS) -fsyntax-only $(SRC)
	python3 -m py_compile tools/analyze.py tools/build-240-edid.py tools/clone-monitor-edid.py
	python3 tools/build-240-edid.py --check edid/rk1080p240.bin
	python3 tools/clone-monitor-edid.py --input edid/zowie-xl2546x-captured.bin --output /tmp/hdmirxtest-clone-check.bin
	bash -n $(SHELL_SCRIPTS)

clean:
	rm -f $(TARGET)
	rm -rf tools/__pycache__
