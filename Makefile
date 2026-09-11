# takt — build and run shortcuts.
#
# SPM's own sandbox cannot nest inside a sandboxed shell, so every swift
# invocation here passes --disable-sandbox. See CLAUDE.md.

SWIFT ?= swift
SWIFT_FLAGS ?= --disable-sandbox

DEBUG_BIN = $(shell $(SWIFT) build $(SWIFT_FLAGS) -c debug --show-bin-path)
RELEASE_BIN = $(shell $(SWIFT) build $(SWIFT_FLAGS) -c release --show-bin-path)

.PHONY: help build debug run prod build-prod test bounce kit clean

help:
	@echo "make build       debug build, no launch"
	@echo "make debug       debug build, then launch takt"
	@echo "make run         alias for debug"
	@echo "make build-prod  release build, no launch"
	@echo "make prod        release build, then launch takt"
	@echo "make test        run the test suite"
	@echo "make bounce      render seed patterns to preview/*.wav"
	@echo "make kit         re-bake the TAKT-1 kit WAVs"
	@echo "make clean       remove .build"

build:
	$(SWIFT) build $(SWIFT_FLAGS) -c debug

debug: build
	$(DEBUG_BIN)/takt

run: debug

build-prod:
	$(SWIFT) build $(SWIFT_FLAGS) -c release

prod: build-prod
	$(RELEASE_BIN)/takt

test:
	$(SWIFT) test $(SWIFT_FLAGS)

bounce:
	$(SWIFT) run $(SWIFT_FLAGS) takt-bounce

kit:
	$(SWIFT) run $(SWIFT_FLAGS) takt-render-kit

clean:
	rm -rf .build
