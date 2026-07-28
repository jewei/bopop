APP := Bopop
BIN := .build/release/$(APP)
DIST := dist/$(APP).app

# `run`/`open` override these so a build from source gets its own identity.
# UserDefaults, the login item, Sparkle's state and (via
# Storage.directoryName) Application Support are all keyed by bundle
# identifier, so a dev build stops sharing any of them with an installed
# Bopop. `app` keeps the release identity untouched — release.sh assembles
# its own bundle and never goes through these targets.
BUNDLE_ID ?= com.oneone.bopop
BUNDLE_NAME ?= Bopop
SPARKLE_FMWK := .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework

.PHONY: build test app run open clean release

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(DIST)
	mkdir -p $(DIST)/Contents/MacOS
	cp $(BIN) $(DIST)/Contents/MacOS/$(APP)
	cp Support/Info.plist $(DIST)/Contents/Info.plist
	mkdir -p $(DIST)/Contents/Resources
	cp Resources/AppIcon.icns $(DIST)/Contents/Resources/AppIcon.icns
	mkdir -p $(DIST)/Contents/Frameworks
	cp -R $(SPARKLE_FMWK) $(DIST)/Contents/Frameworks/
	printf 'APPL????' > $(DIST)/Contents/PkgInfo
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(BUNDLE_ID)" $(DIST)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleName $(BUNDLE_NAME)" $(DIST)/Contents/Info.plist
	codesign --force --deep --sign - $(DIST)

run: BUNDLE_ID = com.oneone.bopop.dev
run: BUNDLE_NAME = Bopop Dev
run: app
	-killall $(APP) 2>/dev/null || true
	$(DIST)/Contents/MacOS/$(APP)

open: BUNDLE_ID = com.oneone.bopop.dev
open: BUNDLE_NAME = Bopop Dev
open: app
	open $(DIST)

clean:
	rm -rf .build dist

release:
	Support/release.sh
