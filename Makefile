DEVDIR := $(shell xcode-select -p)
SWIFT_FORMAT := $(DEVDIR)/usr/bin/swift-format

# Command Line Tools ship Testing.framework outside the default search paths.
# With full Xcode these directories do not exist and no flags are added.
TEST_FRAMEWORKS := $(wildcard $(DEVDIR)/Library/Developer/Frameworks)
TEST_LIBS := $(wildcard $(DEVDIR)/Library/Developer/usr/lib)

TESTFLAGS :=
ifneq ($(TEST_FRAMEWORKS),)
TESTFLAGS += -Xswiftc -F -Xswiftc $(TEST_FRAMEWORKS) \
             -Xlinker -F -Xlinker $(TEST_FRAMEWORKS) \
             -Xlinker -rpath -Xlinker $(TEST_FRAMEWORKS)
endif
ifneq ($(TEST_LIBS),)
TESTFLAGS += -Xlinker -rpath -Xlinker $(TEST_LIBS)
endif

.PHONY: build test fmt fixtures clean

build:
	swift build

test:
	swift test $(TESTFLAGS)

fmt:
	$(SWIFT_FORMAT) format -i -r Sources Tests

fixtures:
	python3 Tools/embed-fixtures.py
	$(SWIFT_FORMAT) format -i Sources/CzechatorCore/Quality/QualityFixtures+Embedded.swift

clean:
	rm -rf .build build

# Single source of truth lives in Swift; the plist is stamped from it.
VERSION := $(shell sed -n 's/.*let version = "\(.*\)".*/\1/p' Sources/CzechatorCore/Version.swift)

APP := build/Czechator.app
BIN := $(APP)/Contents/MacOS/CzechatorApp

# The signing identity, taken from the keychain when a Developer ID is in it and
# ad-hoc otherwise. The fallback is not a nicety: CI runners hold no identity
# and `make app` has to work there too. Override with:
#   make app SIGN_ID="Developer ID Application: Name (TEAMID)"
#
# Which one is used matters beyond distribution. macOS keys the Accessibility
# permission and the Keychain ACL on the signature, and an ad-hoc one differs on
# every build, so both have to be granted again after every install. A Developer
# ID stays the same, and both survive.
#
# No secure timestamp: it is only needed for notarization, which this project
# does not do, and requiring it would break building offline.
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
             | sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' | head -1)
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := -
endif

ifeq ($(SIGN_ID),-)
SIGN_LABEL := ad-hoc
else
SIGN_LABEL := $(SIGN_ID)
endif

.PHONY: app install install-cli icon reset-accessibility

ICONSET_SRC := img/exports/AppIcon.appiconset

# The icon is rendered per size, each variant with its own padding, corner
# radius and shadow; rescaling one 1024 px artwork would throw that away and
# blur the 16 px one. iconutil wants @2x names, the export ships -2x, so the
# staging copy renames them — the exported set stays the single source.
icon:
	@if [ -d $(ICONSET_SRC) ]; then \
	  rm -rf build/Czechator.iconset; \
	  mkdir -p build/Czechator.iconset; \
	  for f in $(ICONSET_SRC)/icon_*.png; do \
	    cp "$$f" "build/Czechator.iconset/$$(basename $$f | sed 's/-2x/@2x/')"; \
	  done; \
	  iconutil --convert icns build/Czechator.iconset --output build/Czechator.icns; \
	  echo "ikona sestavena"; \
	else \
	  echo "$(ICONSET_SRC) chybi, bundle pojede s vychozi ikonou"; \
	fi

app: icon
	swift build -c release --product CzechatorApp
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/CzechatorApp $(BIN)
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" \
	  $(APP)/Contents/Info.plist
	@if [ -f build/Czechator.icns ]; then \
	  cp build/Czechator.icns $(APP)/Contents/Resources/Czechator.icns; \
	  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Czechator" \
	    $(APP)/Contents/Info.plist >/dev/null 2>&1 || true; \
	fi
	codesign --force --sign "$(SIGN_ID)" --timestamp=none $(APP)
	@echo "hotovo: $(APP) (verze $(VERSION), podpis: $(SIGN_LABEL))"

# One source of truth; the bundle identifier lives in the plist.
BUNDLE_ID := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist)

# An ad-hoc build makes macOS see a different application each time, so the
# previous Accessibility entry stays behind — listed and ticked, but pointing at
# a binary that no longer exists. The double tap then silently does nothing,
# with the settings window insisting the permission is granted. Clearing the
# record is what makes the next launch ask again properly.
#
# A Developer ID build does not produce that stale record, which is why
# `install` stops calling this once one is in use. It is still worth running by
# hand once after switching identity, to clear what the ad-hoc builds left.
#
# Only ever with the bundle identifier: `tccutil reset Accessibility` on its own
# would revoke it for every application on the machine.
reset-accessibility:
	@tccutil reset Accessibility $(BUNDLE_ID) >/dev/null 2>&1 \
	  && echo "Zpristupneni vynulovano pro $(BUNDLE_ID) — pri dalsim pouziti je potreba udelit znovu" \
	  || echo "Zpristupneni se nepodarilo vynulovat, odeberte $(BUNDLE_ID) v Nastaveni systemu rucne"

# Defaults to a user-owned directory, so installing never needs sudo.
# Override with: make install BINDIR=/usr/local/bin
BINDIR ?= $(HOME)/.local/bin

install: app install-cli
	rm -rf /Applications/Czechator.app
	cp -R $(APP) /Applications/Czechator.app
	@echo "nainstalovano do /Applications/Czechator.app"
ifeq ($(SIGN_ID),-)
	@$(MAKE) --no-print-directory reset-accessibility
else
	@echo "Podepsano jako $(SIGN_ID)"
	@echo "Zpristupneni i Klicenka prezijou dalsi buildy. Po zmene podpisu je"
	@echo "potreba udelit je jeste jednou; zbytek po ad-hoc buildech smaze"
	@echo "  make reset-accessibility"
endif

install-cli:
	swift build -c release --product czechator
	@mkdir -p $(BINDIR)
	cp .build/release/czechator $(BINDIR)/czechator
	codesign --force --sign "$(SIGN_ID)" --timestamp=none $(BINDIR)/czechator
	@echo "nainstalovano do $(BINDIR)/czechator (podpis: $(SIGN_LABEL))"
	@case ":$$PATH:" in \
	  *":$(BINDIR):"*) ;; \
	  *) echo "POZOR: $(BINDIR) neni v PATH, prikaz czechator nepujde spustit" ;; \
	esac
