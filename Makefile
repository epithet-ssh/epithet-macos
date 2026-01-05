APP_NAME = Epithet Agent
BUNDLE_NAME = EpithetAgent.app
BUILD_DIR = .build
RELEASE_DIR = $(BUILD_DIR)/release
DEBUG_DIR = $(BUILD_DIR)/debug
BUNDLE_DIR = $(BUILD_DIR)/$(BUNDLE_NAME)
EPITHET_REPO = epithet-ssh/epithet

.PHONY: all build build-release bundle run clean fetch-epithet

all: build

# Fetch epithet binary from GitHub releases
Resources/epithet:
	@echo "Fetching latest epithet release..."
	@mkdir -p Resources
	@curl -sL "https://api.github.com/repos/$(EPITHET_REPO)/releases/latest" \
		| grep -o '"browser_download_url": *"[^"]*darwin_arm64[^"]*"' \
		| head -1 \
		| cut -d'"' -f4 \
		| xargs curl -sL -o Resources/epithet.tar.gz
	@tar -xzf Resources/epithet.tar.gz -C Resources
	@rm Resources/epithet.tar.gz
	@chmod +x Resources/epithet
	@echo "Epithet binary fetched to Resources/epithet"

fetch-epithet: Resources/epithet

# Build debug version
build: Resources/epithet
	swift build

# Build release version
build-release: Resources/epithet
	swift build -c release

# Create .app bundle (debug)
bundle: build
	@echo "Creating app bundle..."
	@rm -rf "$(BUNDLE_DIR)"
	@mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_DIR)/Contents/Resources"
	@cp "$(DEBUG_DIR)/EpithetAgent" "$(BUNDLE_DIR)/Contents/MacOS/"
	@cp Resources/Info.plist "$(BUNDLE_DIR)/Contents/"
	@cp Resources/epithet "$(BUNDLE_DIR)/Contents/Resources/"
	@cp Resources/AppIcon.icns "$(BUNDLE_DIR)/Contents/Resources/"
	@echo "Bundle created at $(BUNDLE_DIR)"

# Create .app bundle (release)
bundle-release: build-release
	@echo "Creating release app bundle..."
	@rm -rf "$(BUNDLE_DIR)"
	@mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	@mkdir -p "$(BUNDLE_DIR)/Contents/Resources"
	@cp "$(RELEASE_DIR)/EpithetAgent" "$(BUNDLE_DIR)/Contents/MacOS/"
	@cp Resources/Info.plist "$(BUNDLE_DIR)/Contents/"
	@cp Resources/epithet "$(BUNDLE_DIR)/Contents/Resources/"
	@cp Resources/AppIcon.icns "$(BUNDLE_DIR)/Contents/Resources/"
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
