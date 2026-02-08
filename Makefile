.PHONY: run build

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Linux)
    BUILD_FLAGS := -Xswiftc -static-stdlib -Xlinker -s
else ifeq ($(UNAME_S),Darwin)
    BUILD_FLAGS := -Xswiftc -parse-as-library
endif

BUILD_PATH := $(shell swift build -c release $(BUILD_FLAGS) --show-bin-path)

APP_NAME := SelfAuth
BIN_PATH := ./bin

run:
	swift run $(BUILD_FLAGS)

build:
	swift build -c release $(BUILD_FLAGS)
	mkdir -p $(BIN_PATH) && cp $(BUILD_PATH)/$(APP_NAME) $(BIN_PATH)/
