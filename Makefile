APP_NAME = Epithet Agent
BUNDLE_NAME = EpithetAgent.app
BUILD_DIR = .build
RELEASE_DIR = $(BUILD_DIR)/release
DEBUG_DIR = $(BUILD_DIR)/debug
BUNDLE_DIR = $(BUILD_DIR)/$(BUNDLE_NAME)

.PHONY: all build build-release bundle run clean

all: build

# Build debug version
build:
	swift build

# Build release version
build-release:
	swift build -c release

# Create .app bundle (debug)
bundle: build
	@echo "Creating app bundle..."
	@rm -rf "$(BUNDLE_DIR)"
	@mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_DIR)/Contents/Resources"
	@cp "$(DEBUG_DIR)/EpithetAgent" "$(BUNDLE_DIR)/Contents/MacOS/"
	@cp Resources/Info.plist "$(BUNDLE_DIR)/Contents/"
	@echo "Bundle created at $(BUNDLE_DIR)"

# Create .app bundle (release)
bundle-release: build-release
	@echo "Creating release app bundle..."
	@rm -rf "$(BUNDLE_DIR)"
	@mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_DIR)/Contents/Resources"
	@cp "$(RELEASE_DIR)/EpithetAgent" "$(BUNDLE_DIR)/Contents/MacOS/"
	@cp Resources/Info.plist "$(BUNDLE_DIR)/Contents/"
	@echo "Release bundle created at $(BUNDLE_DIR)"

# Run the app (debug, no bundle)
run: build
	$(DEBUG_DIR)/EpithetAgent

# Run the bundled app
run-bundle: bundle
	open "$(BUNDLE_DIR)"

# Clean build artifacts
clean:
	swift package clean
	rm -rf "$(BUNDLE_DIR)"

# Install to /Applications
install: bundle-release
	@echo "Installing to /Applications..."
	@rm -rf "/Applications/$(BUNDLE_NAME)"
	@cp -r "$(BUNDLE_DIR)" "/Applications/"
	@echo "Installed to /Applications/$(BUNDLE_NAME)"
