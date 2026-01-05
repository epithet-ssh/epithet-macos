APP_NAME = Epithet Agent
BUNDLE_NAME = EpithetAgent.app
BUILD_DIR = .build
RELEASE_DIR = $(BUILD_DIR)/release
DEBUG_DIR = $(BUILD_DIR)/debug
BUNDLE_DIR = $(BUILD_DIR)/$(BUNDLE_NAME)
DMG_NAME = EpithetAgent.dmg
DMG_PATH = $(BUILD_DIR)/$(DMG_NAME)
EPITHET_REPO = epithet-ssh/epithet

# Signing and notarization (optional - set these env vars for signed releases)
# DEVELOPER_ID - Signing identity, e.g., "Developer ID Application: Your Name (TEAMID)"
# APPLE_ID     - Your Apple ID email
# TEAM_ID      - Your Apple Developer Team ID
# APP_PASSWORD - App-specific password for notarytool

.PHONY: all build build-release bundle run clean fetch-epithet sign notarize dmg release

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

# Code sign the app bundle (requires DEVELOPER_ID)
sign: bundle-release
ifndef DEVELOPER_ID
	$(error DEVELOPER_ID is not set. Example: "Developer ID Application: Your Name (TEAMID)")
endif
	@echo "Signing embedded epithet binary..."
	@codesign --force --sign "$(DEVELOPER_ID)" \
		--options runtime \
		--timestamp \
		"$(BUNDLE_DIR)/Contents/Resources/epithet"
	@echo "Signing app bundle..."
	@codesign --force --verify --verbose \
		--sign "$(DEVELOPER_ID)" \
		--options runtime \
		--timestamp \
		"$(BUNDLE_DIR)"
	@echo "App bundle signed"

# Notarize the app (requires APPLE_ID, TEAM_ID, APP_PASSWORD)
notarize: sign
ifndef APPLE_ID
	$(error APPLE_ID is not set)
endif
ifndef TEAM_ID
	$(error TEAM_ID is not set)
endif
ifndef APP_PASSWORD
	$(error APP_PASSWORD is not set. Create an app-specific password at appleid.apple.com)
endif
	@echo "Creating ZIP for notarization..."
	@ditto -c -k --keepParent "$(BUNDLE_DIR)" "$(BUILD_DIR)/EpithetAgent.zip"
	@echo "Submitting for notarization (this may take a few minutes)..."
	@xcrun notarytool submit "$(BUILD_DIR)/EpithetAgent.zip" \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(TEAM_ID)" \
		--password "$(APP_PASSWORD)" \
		--wait
	@echo "Stapling notarization ticket..."
	@xcrun stapler staple "$(BUNDLE_DIR)"
	@rm "$(BUILD_DIR)/EpithetAgent.zip"
	@echo "Notarization complete"

# Create DMG (signed and notarized if credentials available)
dmg: bundle-release
	@echo "Creating DMG..."
	@rm -f "$(DMG_PATH)"
	@hdiutil create -volname "$(APP_NAME)" -srcfolder "$(BUNDLE_DIR)" \
		-ov -format UDZO "$(DMG_PATH)"
ifdef DEVELOPER_ID
	@echo "Signing DMG..."
	@codesign --sign "$(DEVELOPER_ID)" "$(DMG_PATH)"
ifdef APPLE_ID
ifdef TEAM_ID
ifdef APP_PASSWORD
	@echo "Notarizing DMG..."
	@xcrun notarytool submit "$(DMG_PATH)" \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(TEAM_ID)" \
		--password "$(APP_PASSWORD)" \
		--wait
	@xcrun stapler staple "$(DMG_PATH)"
endif
endif
endif
endif
	@echo "DMG created at $(DMG_PATH)"

# Create signed, notarized DMG (requires all credentials)
dmg-signed: notarize
	@echo "Creating DMG from notarized app..."
	@rm -f "$(DMG_PATH)"
	@hdiutil create -volname "$(APP_NAME)" -srcfolder "$(BUNDLE_DIR)" \
		-ov -format UDZO "$(DMG_PATH)"
	@codesign --sign "$(DEVELOPER_ID)" "$(DMG_PATH)"
	@echo "Notarizing DMG..."
	@xcrun notarytool submit "$(DMG_PATH)" \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(TEAM_ID)" \
		--password "$(APP_PASSWORD)" \
		--wait
	@xcrun stapler staple "$(DMG_PATH)"
	@echo "Signed DMG created at $(DMG_PATH)"

# Create GitHub release with signed DMG (requires VERSION)
release: dmg-signed
ifndef VERSION
	$(error VERSION is not set. Usage: make release VERSION=1.0.0)
endif
	@echo "Creating GitHub release v$(VERSION)..."
	@gh release create "v$(VERSION)" "$(DMG_PATH)" \
		--title "Epithet Agent v$(VERSION)" \
		--generate-notes
	@echo "Release v$(VERSION) published to GitHub"
