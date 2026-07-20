APP := Bopop
BIN := .build/release/$(APP)
DIST := dist/$(APP).app
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
	codesign --force --deep --sign - $(DIST)

run: app
	-killall $(APP) 2>/dev/null || true
	$(DIST)/Contents/MacOS/$(APP)

open: app
	open $(DIST)

clean:
	rm -rf .build dist

release:
	Support/release.sh
