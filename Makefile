PNPM ?= pnpm
CONFIGURATION ?= release
SIGN_IDENTITY ?= -
NOTARY_PROFILE ?= md2pngNotary
RELEASE_SUFFIX ?=
GH_HOST ?= github.com
GH_REPO ?=
PROJECT_URL ?=
MINIMUM_MACOS_VERSION := 14.0
TARGET_NAME := md2png
RESOURCE_BUNDLE_NAME := md2png_MD2PNG.bundle
APP_NAME := md2png
ARM64_BUILD_DIR := .build/arm64-apple-macosx/$(CONFIGURATION)
APP_DIR := dist/$(APP_NAME).app
CONTENTS := $(APP_DIR)/Contents
ICON_SOURCE := Assets/AppIcon/AppIcon.png
ICONSET_DIR := .build/AppIcon.iconset
APP_ICON := .build/AppIcon.icns
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
BUNDLE_IDENTIFIER ?= $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)
RELEASE_QUALIFIER := $(if $(strip $(RELEASE_SUFFIX)),-$(strip $(RELEASE_SUFFIX)),)
ARTIFACT_BASENAME := md2png-$(VERSION)-macOS-arm64$(RELEASE_QUALIFIER)
RELEASE_ZIP := dist/$(ARTIFACT_BASENAME).zip
RELEASE_DMG := dist/$(ARTIFACT_BASENAME).dmg
DMG_DIR := .build/dmg-root

SIGN_FLAGS := --force --sign "$(SIGN_IDENTITY)"
ifneq ($(SIGN_IDENTITY),-)
SIGN_FLAGS += --options runtime --timestamp
endif

.PHONY: bootstrap renderer icon test build app release package-dmg dmg notarize publish-release run clean

bootstrap:
	cd WebRenderer && $(PNPM) install --frozen-lockfile=false
	$(MAKE) renderer

renderer:
	cd WebRenderer && $(PNPM) run build

icon:
	rm -rf "$(ICONSET_DIR)"
	mkdir -p "$(ICONSET_DIR)"
	sips -z 16 16 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_16x16.png"
	sips -z 32 32 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_16x16@2x.png"
	sips -z 32 32 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_32x32.png"
	sips -z 64 64 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_32x32@2x.png"
	sips -z 128 128 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_128x128.png"
	sips -z 256 256 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_128x128@2x.png"
	sips -z 256 256 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_256x256.png"
	sips -z 512 512 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_256x256@2x.png"
	sips -z 512 512 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_512x512.png"
	sips -z 1024 1024 "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/icon_512x512@2x.png"
	iconutil -c icns "$(ICONSET_DIR)" -o "$(APP_ICON)"

test: renderer
	swift test

build: renderer
	swift build -c $(CONFIGURATION) --triple arm64-apple-macosx$(MINIMUM_MACOS_VERSION)

app: build icon
	rm -rf "$(APP_DIR)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(ARM64_BUILD_DIR)/$(TARGET_NAME)" "$(CONTENTS)/MacOS/$(TARGET_NAME)"
	cp Info.plist "$(CONTENTS)/Info.plist"
	@case "$(BUNDLE_IDENTIFIER)" in \
		""|*[!A-Za-z0-9.-]*) \
			echo "BUNDLE_IDENTIFIER must contain only letters, numbers, dots, and hyphens"; \
			exit 1 ;; \
		*) ;; \
	esac
	/usr/bin/plutil -replace CFBundleIdentifier -string "$(BUNDLE_IDENTIFIER)" "$(CONTENTS)/Info.plist"
	@if [ -n "$(PROJECT_URL)" ]; then \
		case "$(PROJECT_URL)" in \
			https://*) ;; \
			*) echo "PROJECT_URL must be an HTTPS URL"; exit 1 ;; \
		esac; \
		/usr/bin/plutil -insert MD2PNGProjectURL -string "$(PROJECT_URL)" "$(CONTENTS)/Info.plist"; \
	fi
	cp "$(APP_ICON)" "$(CONTENTS)/Resources/AppIcon.icns"
	cp -R "$(ARM64_BUILD_DIR)/$(RESOURCE_BUNDLE_NAME)" "$(CONTENTS)/Resources/"
	cp CHANGELOG.md "$(CONTENTS)/Resources/CHANGELOG.md"
	cp -R Examples "$(CONTENTS)/Resources/Examples"
	codesign $(SIGN_FLAGS) "$(APP_DIR)"
release: app
	rm -f "$(RELEASE_ZIP)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_DIR)" "$(RELEASE_ZIP)"
	codesign --verify --deep --strict --verbose=2 "$(APP_DIR)"
	test "$$(lipo -archs "$(CONTENTS)/MacOS/$(TARGET_NAME)")" = "arm64"

package-dmg:
	rm -rf "$(DMG_DIR)"
	mkdir -p "$(DMG_DIR)"
	ditto "$(APP_DIR)" "$(DMG_DIR)/$(APP_NAME).app"
	ln -s /Applications "$(DMG_DIR)/Applications"
	rm -f "$(RELEASE_DMG)"
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(DMG_DIR)" -ov -format UDZO "$(RELEASE_DMG)"
	hdiutil verify "$(RELEASE_DMG)"

dmg: release package-dmg

notarize: release
	@if [ "$(SIGN_IDENTITY)" = "-" ]; then \
		echo "SIGN_IDENTITY must be a Developer ID Application identity"; \
		exit 1; \
	fi
	xcrun notarytool submit "$(RELEASE_ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(APP_DIR)"
	xcrun stapler validate "$(APP_DIR)"
	rm -f "$(RELEASE_ZIP)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_DIR)" "$(RELEASE_ZIP)"
	$(MAKE) package-dmg RELEASE_SUFFIX="$(RELEASE_SUFFIX)"
	codesign --force --sign "$(SIGN_IDENTITY)" --timestamp "$(RELEASE_DMG)"
	codesign --verify --verbose=2 "$(RELEASE_DMG)"
	xcrun notarytool submit "$(RELEASE_DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(RELEASE_DMG)"
	xcrun stapler validate "$(RELEASE_DMG)"
	hdiutil verify "$(RELEASE_DMG)"
	spctl --assess --type execute --verbose=2 "$(APP_DIR)"
	spctl --assess --type open --context context:primary-signature --verbose=2 "$(RELEASE_DMG)"

publish-release:
	SIGN_IDENTITY="$(SIGN_IDENTITY)" \
	NOTARY_PROFILE="$(NOTARY_PROFILE)" \
	GH_HOST="$(GH_HOST)" \
	GH_REPO="$(GH_REPO)" \
	PROJECT_URL="$(PROJECT_URL)" \
	BUNDLE_IDENTIFIER="$(BUNDLE_IDENTIFIER)" \
	./scripts/publish-release.sh

run: app
	open "$(APP_DIR)"

clean:
	swift package clean
	rm -rf dist
