.PHONY: help test deps-lua test-lua format-lua lint-lua typecheck-lua
all: help
SHELL=bash

# Absolutely awesome: http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help: ## show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-24s\033[0m %s\n", $$1, $$2}'

test: test-lua ## run the specs (alias of test-lua)

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

lint-lua: ## lint the Lua sources with selene
	selene lua plugin spec

typecheck-lua: ## type check the Lua sources with lua-language-server
	lua-language-server --check=. --checklevel=Warning --logpath="$${TMPDIR:-/tmp}/php-namespace-refactor-luals"
