APP := Bopop
BIN := .build/release/$(APP)
DIST := dist/$(APP).app

.PHONY: build test app run open clean

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(DIST)
	mkdir -p $(DIST)/Contents/MacOS
	cp $(BIN) $(DIST)/Contents/MacOS/$(APP)
	cp Support/Info.plist $(DIST)/Contents/Info.plist
	printf 'APPL????' > $(DIST)/Contents/PkgInfo
	codesign --force --sign - $(DIST)

run: app
	-killall $(APP) 2>/dev/null || true
	$(DIST)/Contents/MacOS/$(APP)

open: app
	open $(DIST)

clean:
	rm -rf .build dist
