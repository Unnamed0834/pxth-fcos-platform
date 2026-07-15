
PXTH_COMMON_DIR ?= ../..
DEPLOY_VM := $(PXTH_COMMON_DIR)/libs/modules/deploy/deploy.sh
CACHE_SH  := $(PXTH_COMMON_DIR)/libs/modules/cache/cache.sh
PACK_SH   := $(PXTH_COMMON_DIR)/libs/modules/pack/pack.sh

APPS := $(notdir $(wildcard $(CURDIR)/apps/*))

define module_header
	@echo "========================================"
	@echo "$(1)"
	@echo "========================================"
endef

define cache_target
.PHONY: $(1)-cache
$(1)-cache:
	$(call module_header,Module: Syncing $(1) Cache)
	@export APPS_DIR=$(CURDIR)/apps && \
	LOG_FILE=$(abspath /tmp/setup.log) REPO_ROOT=$(CURDIR) bash $(CACHE_SH) sync $(1)
	@echo "✓ $(1) cache synced"
endef

define pack_target
.PHONY: $(1)-pack
$(1)-pack: $(1)-cache
	$(call module_header,Module: Packing $(1) Disk)
	@export APPS_DIR=$(CURDIR)/apps && \
	LOG_FILE=$(abspath /tmp/setup.log) INFERENCE_ENGINE=$(or $(INFERENCE_ENGINE),llama-server) REPO_ROOT=$(CURDIR) bash $(PACK_SH) pack $(1)
	@echo "✓ $(1) disk packed"
endef

define vm_target
.PHONY: $(1)-vm
$(1)-vm:
	$(call module_header,Provisioning $(1))
	@export REPO_ROOT=$(CURDIR) && \
	export APPS_DIR=$(CURDIR)/apps && \
	export COMMON_VARS_DIR=$(CURDIR)/variables && \
	bash $(DEPLOY_VM) deploy $(1)
endef

define composite_target
.PHONY: $(1)
$(1):
	@$(MAKE) $(1)-cache
	@$(MAKE) $(1)-pack
	@$(MAKE) $(1)-vm
	$(call module_header,$(1) COMPLETE)
endef

$(foreach app,$(APPS),$(eval $(call cache_target,$(app))))
$(foreach app,$(APPS),$(eval $(call pack_target,$(app))))
$(foreach app,$(APPS),$(eval $(call vm_target,$(app))))
$(foreach app,$(APPS),$(eval $(call composite_target,$(app))))

validate:
	@echo "Validating $(notdir $(CURDIR)) declarative data..."
	@python3 -c 'import json,glob,sys; files=glob.glob("apps/*/*.json"); [json.load(open(f)) for f in files]; print("  OK: " + str(len(files)) + " JSON files parsed")'
	@echo "✓ validation passed"

validate-images:
	@if [ -f "$(PXTH_COMMON_DIR)/libs/scripts/ci/validate-images.py" ]; then \
	  APPS_DIR=$(CURDIR)/apps python3 "$(PXTH_COMMON_DIR)/libs/scripts/ci/validate-images.py"; \
	else \
	  echo "validate-images.py not found; skipping"; \
	fi

.PHONY: $(APPS) $(addsuffix -cache,$(APPS)) $(addsuffix -pack,$(APPS)) $(addsuffix -vm,$(APPS)) validate validate-images
