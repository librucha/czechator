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

# Optional: drop a 1024x1024 Resources/icon.png in and this produces the icns.
# A menu bar only app (LSUIElement) shows its icon just in Finder, so the
# default is acceptable and the bundle builds without one.
icon:
	@if [ -f Resources/icon.png ]; then \
	  rm -rf build/Czechator.iconset; \
	  mkdir -p build/Czechator.iconset; \
	  for size in 16 32 64 128 256 512; do \
	    sips -z $$size $$size Resources/icon.png \
	      --out build/Czechator.iconset/icon_$${size}x$${size}.png >/dev/null; \
	    sips -z $$((size*2)) $$((size*2)) Resources/icon.png \
	      --out build/Czechator.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	  done; \
	  iconutil --convert icns build/Czechator.iconset --output build/Czechator.icns; \
	  echo "ikona sestavena"; \
	else \
	  echo "Resources/icon.png chybi, bundle pojede s vychozi ikonou"; \
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
