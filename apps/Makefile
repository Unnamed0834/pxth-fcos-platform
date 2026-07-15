
APPS := node-a1 node-gs node-gw node-infr

.PHONY: all $(APPS) clean validate validate-images help

.DEFAULT_GOAL := help

help:
	@echo "Apps monorepo"
	@echo ""
	@echo "Targets:"
	@echo "  all                - cache, pack and provision every app"
	@echo "  <app>              - full cycle for one app (e.g. make node-a1)"
	@echo "  <app>-cache        - sync the artifact cache for one app"
	@echo "  <app>-pack         - build the OEM disk for one app"
	@echo "  <app>-vm           - provision VMs for one app"
	@echo "  validate           - validate declarative data for all apps"
	@echo "  validate-images    - optional image/manifest consistency check"
	@echo ""
	@echo "Apps: $(APPS)"

all: $(APPS)

$(APPS):
	$(MAKE) -C $@ $@

%-cache %-pack %-vm:
	$(MAKE) -C $* $@

validate:
	@set -e; for app in $(APPS); do \
	  echo "--- validating $$app ---"; \
	  $(MAKE) -C $$app validate; \
	done
	@echo "✓ all apps validated"

validate-images:
	@set -e; for app in $(APPS); do \
	  $(MAKE) -C $$app validate-images; \
	done

clean:
	@echo "No build artifacts are tracked."
