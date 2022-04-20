.DEFAULT_GOAL = all
PKGNAME = flox
VERSION = 0.0.1
PREFIX ?= ./build
BIN = flox
MAN1 = $(addsuffix .1,$(BIN))
MAN = $(MAN1)
ETC = \
	etc/flox.toml \
	etc/nix/registry.json
LIB = \
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

# String to be prepended to flox flake uri.
FLOXPKGS_URI = floxpkgs
# FIXME
SYSTEM = x86_64-linux

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
	  -e 's%@@SYSTEM@@%$(SYSTEM)%' \
	  -e 's%@@FLOXPKGS_URI@@%$(FLOXPKGS_URI)%' \
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

$(PREFIX)/lib/%: lib/%
	-@rm -f $@
	@mkdir -p $(@D)
	sed \
	  -e 's%@@PREFIX@@%$(PREFIX)%' \
	  -e 's%@@FLOXPATH@@%$(FLOXPATH)%' \
	  -e 's%@@SYSTEM@@%$(SYSTEM)%' \
	  -e 's%@@FLOXPKGS_URI@@%$(FLOXPKGS_URI)%' \
	  $< > $@

$(PREFIX)/etc/nix/registry.json: etc/nix/registry.json
	-@rm -f $@
	@mkdir -p $(@D)
	sed \
	  -e 's%@@SYSTEM@@%$(SYSTEM)%' \
	  -e 's%@@FLOXPKGS_URI@@%$(FLOXPKGS_URI)%' \
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
