include project.env

current_rmq_ref     ?= $(RABBITMQ_BASE)

define PROJECT_APP_EXTRA_KEYS
    {broker_version_requirements, []}
endef


DEPS      = rabbit rabbitmq_management
TEST_DEPS = rabbitmq_ct_helpers rabbitmq_ct_client_helpers rabbitmq_stream_common

DEP_EARLY_PLUGINS = rabbit_common/mk/rabbitmq-early-plugin.mk
DEP_PLUGINS       = rabbit_common/mk/rabbitmq-plugin.mk

include rabbitmq-components.mk
include erlang.mk

# Set log directory to be under the current project root directory
# Otherwise, erlang.mk will set it to a weird path
CT_LOGS_DIR = $(CURDIR)/logs

# The packaging framework is currently private, and should be provided before building the package.
fw:
	@if [ ! -d "src/extension-framework" ]; then \
		echo "The Seventh-State Framework was not found. Please provide it in src/extension-framework." >&2; \
		exit 1; \
	fi

package: fw
	@echo "Building packages using Seventh-State framework..."
	rm -rf $(PWD)/dist/*
	$(MAKE) -C src/extension-framework build-linux build-docker MANIFEST=$(PWD)/package/manifest.yml OUTPUT_DIR=$(PWD)/dist
