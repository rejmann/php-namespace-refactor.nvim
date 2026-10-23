.PHONY: tests deps-lua test-lua format-lua
all: help
SHELL=bash

# Absolutely awesome: http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help: ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-24s\033[0m %s\n", $$1, $$2}'

setup: ## setup
	rm -rf .vscode-test dist node_modules out
	npm install
	npm run compile
	npm run compile-tests

test: ## run tests
	npm run test

pack-manual: setup ## package the extension manually
	npm run pack

ROCKS_DIR := .rocks
ROCKS_BIN := $(ROCKS_DIR)/bin

$(ROCKS_BIN)/busted:
	pipx run hererocks $(ROCKS_DIR) -l 5.1 -r latest --no-readline
	$(ROCKS_BIN)/luarocks install busted
	$(ROCKS_BIN)/luarocks install nlua

deps-lua: $(ROCKS_BIN)/busted ## install LuaJIT, busted and nlua locally in .rocks/

test-lua: deps-lua ## run the Lua specs with busted + nlua
	eval "$$($(ROCKS_BIN)/luarocks path)" && PATH="$(CURDIR)/$(ROCKS_BIN):$$PATH" busted

format-lua: ## format the Lua sources with stylua
	stylua lua plugin spec
