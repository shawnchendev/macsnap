PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

.PHONY: all build check test install clean

all: build

build:
	swift build -c release

check: test

test:
	swift test

install: build
	mkdir -p $(BINDIR)
	install -m 755 .build/release/macsnap $(BINDIR)/macsnap
	@echo "macsnap installed to $(BINDIR)/macsnap"

clean:
	swift package clean
