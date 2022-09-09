.DEFAULT_GOAL = all
PKGNAME = flox
PREFIX ?= ./build

ifeq (,$(VERSION))
  $(error VERSION not defined - aborting build)
endif

# `nix show-config` does not work on Darwin, dies within a build:
#
#   libc++abi: terminating with uncaught exception of type nix::SysError: error: getting status of /System/Library/LaunchDaemons/com.apple.oahd.plist: Operation not permitted
#
# For now we'll just punt and fall back to (coreutils) `uname -s`.
#
# SYSTEM := $(shell nix --extra-experimental-features nix-command show-config | awk '/system = / {print $$NF}')
# CPU = $(firstword $(subst -, ,$(SYSTEM)))
# OS = $(lastword $(subst -, ,$(SYSTEM)))
OS := $(shell uname -s | tr A-Z a-z)

CFLAGS = \
	-DFLOXSH='"$(PREFIX)/libexec/flox/flox"' \
	-DSSL_CERT_FILE='"$(SSL_CERT_FILE)"'
ifeq ($(OS),linux)
  CFLAGS += -DLOCALE_ARCHIVE='"$(LOCALE_ARCHIVE)"'
endif
ifeq ($(OS),darwin)
  CFLAGS += \
	-DNIX_COREFOUNDATION_RPATH='"$(NIX_COREFOUNDATION_RPATH)"' \
	-DPATH_LOCALE='"$(PATH_LOCALE)"'
endif

BIN = flox
MAN1 = $(addsuffix .1,$(BIN))
MAN = $(MAN1)
ETC = \
	etc/flox.bashrc \
	etc/flox.profile \
	etc/flox.toml \
	etc/flox.zdotdir/.zlogin \
	etc/flox.zdotdir/.zlogout \
	etc/flox.zdotdir/.zprofile \
	etc/flox.zdotdir/.zshenv \
	etc/flox.zdotdir/.zshrc
LIB = \
	lib/bootstrap.sh \
	lib/init.sh \
	lib/manifest.jq \
	lib/manifestTOML.jq \
	lib/metadata.sh \
	lib/profileRegistry.jq \
	lib/registry.jq \
	lib/search.jq \
	lib/utils.sh
LIBEXEC = libexec/flox/flox
SHARE = share/bash-completion/completions/flox
LINKBIN = # Add files to be linked to flox here

SHFMT = shfmt --language-dialect bash

all: $(BIN) $(MAN)

.SUFFIXES: .md .sh

.md:
	pandoc -s -t man $< -o $@

$(PREFIX)/%: %
	-@rm -f $@
	@mkdir -p $(@D)
	cp $< $@

$(PREFIX)/bin/%: %
	-@rm -f $@
	@mkdir -p $(@D)
	cp $< $@

# This file is mastered in default.nix, passed by makeFlags.
$(PREFIX)/etc/flox.profile: $(FLOX_PROFILE)
	-@rm -f $@
	@mkdir -p $(@D)
	cp $< $@

$(PREFIX)/etc/%: etc/%
	-@rm -f $@
	@mkdir -p $(@D)
	sed \
	  -e 's%@@PREFIX@@%$(PREFIX)%' \
	  $< > $@

$(PREFIX)/lib/%: lib/%
	-@rm -f $@
	@mkdir -p $(@D)
	sed \
	  -e 's%@@PREFIX@@%$(PREFIX)%' \
	  -e 's%@@FLOXPATH@@%$(FLOXPATH)%' \
	  -e 's%@@SSL_CERT_FILE@@%$(SSL_CERT_FILE)%' \
	  $< > $@
	$(if $(filter %.sh,$@),$(SHFMT) $@ >/dev/null)

$(PREFIX)/libexec/flox/flox: flox.sh
	-@rm -f $@
	@mkdir -p $(@D)
	sed \
	  -e 's%@@PREFIX@@%$(PREFIX)%' \
	  -e 's%@@VERSION@@%$(VERSION)%' \
	  -e 's%@@FLOXPATH@@%$(FLOXPATH)%' \
	  $< > $@
	$(SHFMT) $@ >/dev/null
	chmod +x $@

$(PREFIX)/share/man/man1/%: %
	-@rm -f $@
	@mkdir -p $(@D)
	cp $< $@

.PHONY: install
install: $(addprefix $(PREFIX)/bin/,$(BIN)) \
         $(addprefix $(PREFIX)/share/man/man1/,$(MAN1)) \
         $(addprefix $(PREFIX)/,$(LIBEXEC) $(LIB) $(ETC) $(SHARE))

define LINK_template =
  $(PREFIX)/bin/$(link):
	mkdir -p $$(@D)
	ln -s flox $$@

  LINKS += $(PREFIX)/bin/$(link)
endef

$(foreach link,$(LINKBIN),$(eval $(call LINK_template)))
install: $(LINKS)

clean:
	-rm -f $(BIN) $(MAN)
