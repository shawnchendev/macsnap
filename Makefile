PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
# Signing identity for the app bundle. Default ad-hoc (-): works, but every
# rebuild invalidates the Screen Recording grant (see README). For a stable
# signature: make app CODESIGN_IDENTITY="Apple Development: Name (TEAMID)"
CODESIGN_IDENTITY ?= -
export CODESIGN_IDENTITY

.PHONY: all build check test install clean app install-app

all: build

build:
	swift build -c release

check: test

test:
	swift test

install: build
	mkdir -p $(BINDIR)
	install -m 755 .build/release/opensnap $(BINDIR)/opensnap
	install -m 755 .build/release/opensnap-menubar $(BINDIR)/opensnap-menubar
	@echo "opensnap installed to $(BINDIR)/opensnap"
	@echo "opensnap-menubar installed to $(BINDIR)/opensnap-menubar"

# Double-clickable app bundle (menu-bar resident, no Dock icon).
# Pass CODESIGN_IDENTITY="Apple Development: Name (TEAMID)" for a stable
# signature (grants survive rebuilds); default is ad-hoc.
app:
	./packaging/make-app.sh

# Install the bundle into /Applications (may prompt for a password).
# rm -rf first: cp -R into an existing dir would nest Opensnap.app inside
# itself instead of replacing it.
install-app: app
	rm -rf /Applications/Opensnap.app
	cp -R dist/Opensnap.app /Applications/Opensnap.app
	@echo "Opensnap.app installed to /Applications/Opensnap.app"

clean:
	swift package clean
