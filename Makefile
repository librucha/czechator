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

.PHONY: build test fmt clean

build:
	swift build

test:
	swift test $(TESTFLAGS)

fmt:
	$(SWIFT_FORMAT) format -i -r Sources Tests

clean:
	rm -rf .build build

APP := build/Czechator.app
BIN := $(APP)/Contents/MacOS/CzechatorApp

.PHONY: app install icon

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
	@if [ -f build/Czechator.icns ]; then \
	  cp build/Czechator.icns $(APP)/Contents/Resources/Czechator.icns; \
	  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Czechator" \
	    $(APP)/Contents/Info.plist >/dev/null 2>&1 || true; \
	fi
	codesign --force --sign - --timestamp=none $(APP)
	@echo "hotovo: $(APP)"

install: app
	rm -rf /Applications/Czechator.app
	cp -R $(APP) /Applications/Czechator.app
	@echo "nainstalovano do /Applications/Czechator.app"
