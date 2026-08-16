PNPM ?= pnpm
NODE ?= node
CONFIGURATION ?= release
SIGN_IDENTITY ?= -
NOTARY_PROFILE ?= MDPNGNotary
NOTARY_KEYCHAIN ?=
RELEASE_SUFFIX ?=
GH_HOST ?= github.com
GH_REPO ?=
PROJECT_URL ?=
TEST_UPDATE_VERSION ?=
TEST_UPDATE_STATE ?=
BUMP ?=
RELEASE_DATE ?= $(shell TZ=Asia/Shanghai date +%F)
BASE_ROOT ?=
MINIMUM_MACOS_VERSION := 14.0
TARGET_NAME := md2png
RESOURCE_BUNDLE_NAME := md2png_MD2PNG.bundle
APP_NAME := md2png
ARM64_TRIPLE := arm64-apple-macosx$(MINIMUM_MACOS_VERSION)
ARM64_BUILD_DIR = $(shell swift build -c $(CONFIGURATION) --triple $(ARM64_TRIPLE) --show-bin-path)
ifeq ($(CONFIGURATION),debug)
APP_DIR := dist/debug/$(APP_NAME).app
DEBUG_APP_PREREQUISITE := debug-stop
else
APP_DIR := dist/$(APP_NAME).app
DEBUG_APP_PREREQUISITE :=
endif
CONTENTS := $(APP_DIR)/Contents
ICON_SOURCE := Assets/AppIcon/AppIcon.png
ICONSET_DIR := .build/AppIcon.iconset
APP_ICON := .build/AppIcon.icns
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
BUNDLE_IDENTIFIER ?= $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)
SOURCE_COMMIT ?= $(shell git rev-parse HEAD 2>/dev/null)
COVERAGE_DIR ?= .build/coverage
release_asset_field = $(shell "$(NODE)" scripts/release-assets.mjs field --version "$(VERSION)" --key "$(1)" --field "$(2)")
COVERAGE_JSON := $(COVERAGE_DIR)/$(call release_asset_field,coverageJson,name)
COVERAGE_MARKDOWN := $(COVERAGE_DIR)/$(call release_asset_field,coverageMarkdown,name)
RELEASE_QUALIFIER := $(if $(strip $(RELEASE_SUFFIX)),-$(strip $(RELEASE_SUFFIX)),)
ARTIFACT_BASENAME := md2png-$(VERSION)-macOS-arm64$(RELEASE_QUALIFIER)
ifeq ($(strip $(RELEASE_SUFFIX)),developer-id)
RELEASE_ZIP := $(call release_asset_field,releaseZip,sourcePath)
RELEASE_DMG := $(call release_asset_field,releaseDmg,sourcePath)
else
RELEASE_ZIP := dist/$(ARTIFACT_BASENAME).zip
RELEASE_DMG := dist/$(ARTIFACT_BASENAME).dmg
endif
DMG_DIR := .build/dmg-root

SIGN_FLAGS := --force --sign "$(SIGN_IDENTITY)"
NOTARY_KEYCHAIN_FLAG := $(if $(strip $(NOTARY_KEYCHAIN)),--keychain "$(strip $(NOTARY_KEYCHAIN))",)
ifneq ($(SIGN_IDENTITY),-)
SIGN_FLAGS += --options runtime --timestamp
endif

.PHONY: bootstrap renderer icon coverage-tool-test coverage coverage-validate release-asset-paths prepare-release validate-release-preparation test build debug-stop app verify-dist release package-dmg dmg notarize publish-release run clean

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

coverage-tool-test:
	$(NODE) --test scripts/tests/*.test.mjs

coverage: renderer coverage-tool-test
	swift test --enable-code-coverage
	@coverage_source="$$(swift test --show-codecov-path | tail -n 1)"; \
		test -s "$$coverage_source" || { echo "SwiftPM coverage JSON is missing or empty: $$coverage_source"; exit 1; }; \
		swift_version="$$(swift --version | sed -n '1p')"; \
		xcode_version="$$(xcodebuild -version | paste -s -d ' ' -)"; \
		$(NODE) scripts/coverage-report.mjs generate \
			--input "$$coverage_source" \
			--json "$(COVERAGE_JSON)" \
			--markdown "$(COVERAGE_MARKDOWN)" \
			--repo-root "$(CURDIR)" \
			--app-version "$(VERSION)" \
			--commit "$(SOURCE_COMMIT)" \
			--swift-version "$$swift_version" \
			--xcode-version "$$xcode_version"

coverage-validate:
	$(NODE) scripts/coverage-report.mjs validate \
		--report "$(COVERAGE_JSON)" \
		--app-version "$(VERSION)" \
		--commit "$(SOURCE_COMMIT)"

release-asset-paths:
	@printf 'coverageJson=%s\n' "$(COVERAGE_JSON)"
	@printf 'coverageMarkdown=%s\n' "$(COVERAGE_MARKDOWN)"
	@printf 'releaseZip=%s\n' "$(RELEASE_ZIP)"
	@printf 'releaseDmg=%s\n' "$(RELEASE_DMG)"

prepare-release:
	$(NODE) scripts/release-automation.mjs prepare \
		--bump "$(BUMP)" \
		--date "$(RELEASE_DATE)" \
		--repo-root "$(CURDIR)"

validate-release-preparation:
	$(NODE) scripts/release-automation.mjs validate-prepared \
		--bump "$(BUMP)" \
		--base-root "$(BASE_ROOT)" \
		--repo-root "$(CURDIR)"

test: renderer coverage-tool-test
	swift test

build: renderer
	swift build -c $(CONFIGURATION) --triple $(ARM64_TRIPLE)

debug-stop:
	$(NODE) scripts/debug-run.mjs stop \
		--repo-root "$(CURDIR)" \
		--app "$(APP_DIR)" \
		--executable "$(TARGET_NAME)"

app: build icon $(DEBUG_APP_PREREQUISITE)
	rm -rf "$(APP_DIR)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(ARM64_BUILD_DIR)/$(TARGET_NAME)" "$(CONTENTS)/MacOS/$(TARGET_NAME)"
	cp Info.plist "$(CONTENTS)/Info.plist"
	@effective_bundle_identifier="$(BUNDLE_IDENTIFIER)"; \
	debug_checkout_id=""; \
	if [ "$(CONFIGURATION)" = "debug" ]; then \
		debug_checkout_id="$$( $(NODE) scripts/debug-run.mjs identity --repo-root "$(CURDIR)" )" || exit $$?; \
		effective_bundle_identifier="$$( $(NODE) scripts/debug-run.mjs bundle-identifier --repo-root "$(CURDIR)" --base "$(BUNDLE_IDENTIFIER)" )" || exit $$?; \
	fi; \
	case "$$effective_bundle_identifier" in \
		""|*[!A-Za-z0-9.-]*) \
			echo "BUNDLE_IDENTIFIER must contain only letters, numbers, dots, and hyphens"; \
			exit 1 ;; \
		*) ;; \
	esac; \
	/usr/bin/plutil -replace CFBundleIdentifier -string "$$effective_bundle_identifier" "$(CONTENTS)/Info.plist"; \
	if [ -n "$$debug_checkout_id" ]; then \
		/usr/bin/plutil -insert MD2PNGDebugCheckoutID -string "$$debug_checkout_id" "$(CONTENTS)/Info.plist"; \
	fi
	@if [ -n "$(SOURCE_COMMIT)" ]; then \
		if ! /usr/bin/printf '%s\n' "$(SOURCE_COMMIT)" | /usr/bin/grep -Eq '^[0-9a-fA-F]{7,64}$$'; then \
			echo "SOURCE_COMMIT must contain 7 to 64 hexadecimal characters"; \
			exit 1; \
		fi; \
		/usr/bin/plutil -insert MD2PNGSourceCommit -string "$(SOURCE_COMMIT)" "$(CONTENTS)/Info.plist"; \
	fi
	@if [ -n "$(PROJECT_URL)" ]; then \
		case "$(PROJECT_URL)" in \
			https://*) ;; \
			*) echo "PROJECT_URL must be an HTTPS URL"; exit 1 ;; \
		esac; \
		/usr/bin/plutil -insert MD2PNGProjectURL -string "$(PROJECT_URL)" "$(CONTENTS)/Info.plist"; \
	fi
	@if [ -n "$(TEST_UPDATE_VERSION)" ]; then \
		if ! /usr/bin/printf '%s\n' "$(TEST_UPDATE_VERSION)" | /usr/bin/grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$$'; then \
			echo "TEST_UPDATE_VERSION must be a stable semantic version such as 0.0.0"; \
			exit 1; \
		fi; \
		/usr/bin/plutil -replace CFBundleShortVersionString -string "$(TEST_UPDATE_VERSION)" "$(CONTENTS)/Info.plist"; \
	fi
	@if [ -n "$(TEST_UPDATE_STATE)" ]; then \
		if [ "$(CONFIGURATION)" != "debug" ]; then \
			echo "TEST_UPDATE_STATE is only available for debug builds"; \
			exit 1; \
		fi; \
		case "$(TEST_UPDATE_STATE)" in \
			up-to-date|check-failed|download-failed|ready-to-install) ;; \
			*) echo "TEST_UPDATE_STATE must be up-to-date, check-failed, download-failed, or ready-to-install"; exit 1 ;; \
		esac; \
		/usr/bin/plutil -insert MD2PNGTestUpdateState -string "$(TEST_UPDATE_STATE)" "$(CONTENTS)/Info.plist"; \
	fi
	cp "$(APP_ICON)" "$(CONTENTS)/Resources/AppIcon.icns"
	cp -R "$(ARM64_BUILD_DIR)/$(RESOURCE_BUNDLE_NAME)" "$(CONTENTS)/Resources/"
	./scripts/release-notes.sh "$(VERSION)" ABOUT_CHANGELOG.md >/dev/null
	cp ABOUT_CHANGELOG.md "$(CONTENTS)/Resources/ABOUT_CHANGELOG.md"
	cp -R Examples "$(CONTENTS)/Resources/Examples"
	codesign $(SIGN_FLAGS) "$(APP_DIR)"

verify-dist: app
	codesign --verify --deep --strict --verbose=2 "$(APP_DIR)"
	test "$$(lipo -archs "$(CONTENTS)/MacOS/$(TARGET_NAME)")" = "arm64"
	"$(CONTENTS)/MacOS/$(TARGET_NAME)" --self-test

release: verify-dist
	rm -f "$(RELEASE_ZIP)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_DIR)" "$(RELEASE_ZIP)"

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
	xcrun notarytool submit "$(RELEASE_ZIP)" $(NOTARY_KEYCHAIN_FLAG) --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(APP_DIR)"
	xcrun stapler validate "$(APP_DIR)"
	rm -f "$(RELEASE_ZIP)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_DIR)" "$(RELEASE_ZIP)"
	$(MAKE) package-dmg RELEASE_SUFFIX="$(RELEASE_SUFFIX)"
	codesign --force --sign "$(SIGN_IDENTITY)" --timestamp "$(RELEASE_DMG)"
	codesign --verify --verbose=2 "$(RELEASE_DMG)"
	xcrun notarytool submit "$(RELEASE_DMG)" $(NOTARY_KEYCHAIN_FLAG) --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(RELEASE_DMG)"
	xcrun stapler validate "$(RELEASE_DMG)"
	hdiutil verify "$(RELEASE_DMG)"
	spctl --assess --type execute --verbose=2 "$(APP_DIR)"
	spctl --assess --type open --context context:primary-signature --verbose=2 "$(RELEASE_DMG)"

publish-release:
	@if [ -n "$(TEST_UPDATE_VERSION)" ] || [ -n "$(TEST_UPDATE_STATE)" ]; then \
		echo "TEST_UPDATE_VERSION and TEST_UPDATE_STATE are only for local app/run builds"; \
		exit 1; \
	fi
	SIGN_IDENTITY="$(SIGN_IDENTITY)" \
	NOTARY_PROFILE="$(NOTARY_PROFILE)" \
	GH_HOST="$(GH_HOST)" \
	GH_REPO="$(GH_REPO)" \
	PROJECT_URL="$(PROJECT_URL)" \
	BUNDLE_IDENTIFIER="$(BUNDLE_IDENTIFIER)" \
	./scripts/publish-release.sh

run: app
	@if [ "$(CONFIGURATION)" = "debug" ]; then \
		$(NODE) scripts/debug-run.mjs launch \
			--repo-root "$(CURDIR)" \
			--app "$(APP_DIR)" \
			--executable "$(TARGET_NAME)"; \
	else \
		open "$(APP_DIR)"; \
	fi

clean:
	swift package clean
	rm -rf dist
