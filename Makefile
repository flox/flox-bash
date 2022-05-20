.DEFAULT_GOAL = all
PKGNAME = flox
VERSION = 0.0.1
PREFIX ?= ./build
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
	lib/metadata.sh \
	lib/profileRegistry.jq \
	lib/registry.jq \
	lib/utils.sh
SHARE = \
	share/bash-completion/completions/flox \
	share/flox-smoke-and-mirrors/packages-all-libs.txt.gz share/flox-smoke-and-mirrors/packages-all.txt.gz
LINKBIN = # Add files to be linked to flox here

all: $(BIN) $(MAN)

.SUFFIXES: .md .sh

.md:
	pandoc -s -t man $< -o $@

.sh:
	-@rm -f $@
	sed \
	  -e 's%@@PREFIX@@%$(PREFIX)%' \
	  -e 's%@@VERSION@@%$(VERSION)%' \
	  -e 's%@@FLOXPATH@@%$(FLOXPATH)%' \
	  $< > $@
	chmod +x $@

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

$(PREFIX)/share/man/man1/%: %
	-@rm -f $@
	@mkdir -p $(@D)
	cp $< $@

.PHONY: install
install: $(addprefix $(PREFIX)/bin/,$(BIN)) \
         $(addprefix $(PREFIX)/share/man/man1/,$(MAN1)) \
         $(addprefix $(PREFIX)/,$(LIB) $(ETC) $(SHARE))

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
