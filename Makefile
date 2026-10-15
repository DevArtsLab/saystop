SRC := Sources/saystop/main.swift
BUILD := build
MINOS := 12.0
BIN := $(BUILD)/saystop

.PHONY: all clean install uninstall release

all: $(BIN)

$(BUILD)/saystop-arm64: $(SRC)
	mkdir -p $(BUILD)
	swiftc -O -target arm64-apple-macosx$(MINOS) -o $@ $<

$(BUILD)/saystop-x86_64: $(SRC)
	mkdir -p $(BUILD)
	swiftc -O -target x86_64-apple-macosx$(MINOS) -o $@ $<

$(BIN): $(BUILD)/saystop-arm64 $(BUILD)/saystop-x86_64
	lipo -create -output $@ $^
	codesign -s - $@
	lipo -info $@

release: $(BIN)
	shasum -a 256 $(BIN) > $(BIN).sha256

install: $(BIN)
	@if [ -d /opt/homebrew/bin ] && [ -w /opt/homebrew/bin ]; then \
		cp $(BIN) /opt/homebrew/bin/saystop; \
		echo "installed /opt/homebrew/bin/saystop"; \
	elif [ -w /usr/local/bin ]; then \
		cp $(BIN) /usr/local/bin/saystop; \
		echo "installed /usr/local/bin/saystop"; \
	else \
		mkdir -p $(HOME)/.local/bin; \
		cp $(BIN) $(HOME)/.local/bin/saystop; \
		echo "installed $(HOME)/.local/bin/saystop"; \
	fi

uninstall:
	rm -f /opt/homebrew/bin/saystop /usr/local/bin/saystop $(HOME)/.local/bin/saystop

clean:
	rm -rf $(BUILD)
