.DEFAULT_GOAL = all
PKGNAME = flox
VERSION = 0.0.1
PREFIX ?= ./build
BIN = flox
MAN1 = $(addsuffix .1,$(BIN))
MAN = $(MAN1)
ETC = \
	etc/nix.conf \
	etc/nix/registry.json
LIBEXEC = \
	libexec/config.sh \
	libexec/builtpkgs/flake.nix \
	libexec/versions/flake.nix
SHARE = \
	share/bash-completion/completions/flox
LINKBIN = # Add files to be linked to flox here

all: $(BIN) $(MAN)

.SUFFIXES: .md .sh

.md:
	pandoc -s -t man $< -o $@

.sh:
	-@rm -f $@
	sed \
	  -e 's%@@PREFIX@@%$(PREFIX)%' \
	  -e 's%@@FLOXPATH@@%$(FLOXPATH)%' \
	  $< > $@
	chmod +x $@

$(PREFIX)/bin/%: %
	-@rm -f $@
	@mkdir -p $(@D)
	cp $< $@

$(PREFIX)/%: %
	-@rm -f $@
	@mkdir -p $(@D)
	cp $< $@

$(PREFIX)/etc/nix.conf: etc/nix.conf
	-@rm -f $@
	@mkdir -p $(@D)
	sed -e 's%@@PREFIX@@%$(PREFIX)%' $< > $@

$(PREFIX)/share/man/man1/%: %
	-@rm -f $@
	@mkdir -p $(@D)
	cp $< $@

.PHONY: install
install: $(addprefix $(PREFIX)/bin/,$(BIN)) $(addprefix $(PREFIX)/,$(LIBEXEC) $(ETC) $(SHARE))

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
