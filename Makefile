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
