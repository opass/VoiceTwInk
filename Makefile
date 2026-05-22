# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build

# Where the built .app gets deployed. /Applications is the standard macOS app
# location (Spotlight / Launchpad index it, Dock-drag works naturally). On
# personal Macs the user is in the admin group so /Applications is writable
# without sudo; the fork explicitly does NOT keep an upstream commercial
# `/Applications/VoiceInk.app` (CLAUDE.md mission) so there's no collision.
INSTALL_DIR := /Applications

# Apple Development team ID for the local-signed build. Read from .local-team
# (gitignored) so personal identifiers don't end up in the public repo. Populate
# once with the output of `security find-identity -v -p codesigning`.
LOCAL_TEAM := $(shell cat .local-team 2>/dev/null | tr -d ' \r\n')

.PHONY: all clean whisper setup build local check healthcheck help dev run relaunch

# Default target
all: check build

# Development workflow — build + relaunch the running app so changes pick up
# without needing to manually quit + reopen.
dev: local relaunch

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" build

# Build for local use. The build itself is ad-hoc signed (so SPM dependencies
# happy), then we re-sign just the outer .app wrapper with the user's free
# Apple Development (Personal Team) cert. TCC matches the wrapper's designated
# requirement, which is stable across rebuilds → Microphone / Accessibility
# permissions persist instead of re-prompting every build.
local: check setup
	@if [ -z "$(LOCAL_TEAM)" ]; then \
		echo "Error: .local-team is missing or empty."; \
		echo "Find your team ID with:"; \
		echo "  security find-identity -v -p codesigning | grep 'Apple Development'"; \
		echo "Then write the 10-char ID to .local-team, e.g.:"; \
		echo "  echo 'XXXXXXXXXX' > .local-team"; \
		exit 1; \
	fi
	@IDENTITY_HASH=$$(security find-identity -v -p codesigning | grep "Apple Development" | grep "$(LOCAL_TEAM)" | head -1 | awk '{print $$2}'); \
	if [ -z "$$IDENTITY_HASH" ]; then \
		echo "Error: No 'Apple Development' cert found in keychain for team $(LOCAL_TEAM)."; \
		echo "Open Xcode → Settings → Accounts, sign in, and let it create the cert."; \
		exit 1; \
	fi
	@echo "Building VoiceInk (ad-hoc) for local use..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/VoiceInk.app" && \
	if [ -d "$$APP_PATH" ]; then \
		mkdir -p "$(INSTALL_DIR)"; \
		echo "Copying VoiceInk.app to $(INSTALL_DIR)..."; \
		rm -rf "$(INSTALL_DIR)/VoiceInk.app"; \
		ditto "$$APP_PATH" "$(INSTALL_DIR)/VoiceInk.app"; \
		xattr -cr "$(INSTALL_DIR)/VoiceInk.app"; \
		IDENTITY_HASH=$$(security find-identity -v -p codesigning | grep "Apple Development" | grep "$(LOCAL_TEAM)" | head -1 | awk '{print $$2}'); \
		echo "Re-signing wrapper .app with Apple Development team $(LOCAL_TEAM)..."; \
		codesign --force --sign "$$IDENTITY_HASH" \
			--entitlements "$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
			--timestamp=none --generate-entitlement-der \
			"$(INSTALL_DIR)/VoiceInk.app"; \
		for stale in "$$HOME/Downloads/VoiceInk.app" "$$HOME/Applications/VoiceInk.app"; do \
			if [ -d "$$stale" ] && [ "$$stale" != "$(INSTALL_DIR)/VoiceInk.app" ]; then \
				echo "Removing stale $$stale from older deploy location..."; \
				rm -rf "$$stale"; \
			fi; \
		done; \
		echo ""; \
		echo "Signature:"; \
		codesign -dvv "$(INSTALL_DIR)/VoiceInk.app" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier|Signature" | head -6; \
		echo ""; \
		echo "Build complete! App saved to: $(INSTALL_DIR)/VoiceInk.app"; \
		echo "Run with: open $(INSTALL_DIR)/VoiceInk.app"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built VoiceInk.app at $$APP_PATH"; \
		exit 1; \
	fi

# Quit any running instance and relaunch from $(INSTALL_DIR)/VoiceInk.app.
# Use after `make local` to pick up freshly built code without losing
# macOS Microphone / Accessibility permissions (stable signing means TCC
# sees the new build as the same app).
relaunch:
	@echo "Restarting VoiceInk..."
	@osascript -e 'quit app "VoiceInk"' 2>/dev/null || true
	@sleep 1
	@open "$(INSTALL_DIR)/VoiceInk.app"
	@echo "Launched $(INSTALL_DIR)/VoiceInk.app"

# Run application
run:
	@if [ -d "$(INSTALL_DIR)/VoiceInk.app" ]; then \
		echo "Opening $(INSTALL_DIR)/VoiceInk.app..."; \
		open "$(INSTALL_DIR)/VoiceInk.app"; \
	else \
		echo "Looking for VoiceInk.app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "VoiceInk.app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "VoiceInk.app not found. Please run 'make build' or 'make local' first."; \
			exit 1; \
		fi; \
	fi

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to VoiceInk project"
	@echo "  build              Build the VoiceInk Xcode project"
	@echo "  local              Build for local use (signed with your free Apple Development team — see .local-team)"
	@echo "  run                Launch the built VoiceInk app"
	@echo "  relaunch           Quit any running instance and relaunch from ~/Downloads/VoiceInk.app"
	@echo "  dev                Build then relaunch (daily-driver workflow)"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"