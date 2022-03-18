.DEFAULT_GOAL = all
PKGNAME = flox
VERSION = 0.0.1
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

DASEL = $(shell which dasel)
ifeq (,$(DASEL))
  $(error dasel: command not found)
endif

NIX = $(shell which nix)
ifeq (,$(NIX))
  $(error nix: command not found)
endif

all: $(BIN) $(MAN)

.SUFFIXES: .md .sh

.md:
	pandoc -s -t man $< -o $@

.sh:
	sed \
	  -e 's%@@NIX@@%$(realpath $(NIX))%' \
	  -e 's%@@DASEL@@%$(realpath $(DASEL))%' \
	  -e 's%@@PREFIX@@%$(realpath $(PREFIX))%' \
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

$(PREFIX)/share/man/man1/%: %
	-@rm -f $@
	@mkdir -p $(@D)
	cp $< $@

$(PREFIX)/share/bash-completion/completions/%: %
	-@rm -f $@
	@mkdir -p $(@D)
	cp share/bash-completion/completions/flox $@

.PHONY: install
install: $(addprefix $(PREFIX)/bin/,$(BIN)) $(addprefix $(PREFIX)/,$(LIBEXEC) $(ETC)) $(addprefix $(PREFIX)/,$(SHARE))

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
