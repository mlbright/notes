# Deployment and development tasks for the Notes app. Run `make` (or
# `make help`) for the targets, variables, and examples.
#
# Production runs directly from this checkout: all state (SQLite databases,
# Active Storage blobs, secrets) lives inside this directory. The only
# artifacts outside it are the systemd units that `make install` generates
# from the templates in deploy/.
#
# Run make as the user that will own the service (normally your login user,
# not root). Recipes use sudo where system access is required.
#
# See deploy/DEPLOYMENT.md for the full runbook, including machine migration.

APP_DIR      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
WEB_DIR      := $(APP_DIR)/web
SERVICE_USER := $(shell id -un)
# Resolve from web/ so the app's pinned Ruby (web/mise.toml) wins over
# whatever mise picks elsewhere, e.g. a global Ruby.
RUBY_DIR     := $(shell cd $(WEB_DIR) && mise where ruby 2>/dev/null)
SYSTEMD_DIR  := /etc/systemd/system
# The Rust Port (ADR 0004), built in its own checkout, which serves this
# checkout's state in place of Rails once switched to (decision 14).
PORT_DIR     ?= $(abspath $(APP_DIR)/../notes-rust)
# The unit serving :3002: notes-port when it is enabled, else notes-web.
LIVE_UNIT     = $(shell systemctl is-enabled --quiet notes-port.service 2>/dev/null && echo notes-port || echo notes-web)
# Waits up to a minute for /up on :3002 (host authorization skips /up).
WAIT_UP       = for i in $$(seq 1 60); do curl -fs -o /dev/null http://127.0.0.1:3002/up && exit 0; sleep 1; done; exit 1
# Solid Queue jobs Rails has still to run (ready, claimed, scheduled or
# blocked; failed ones never run again unless retried by hand).
QUEUE_PENDING = sqlite3 "file:$(WEB_DIR)/storage/production_queue.sqlite3?mode=ro" \
	"SELECT (SELECT count(*) FROM solid_queue_ready_executions) + (SELECT count(*) FROM solid_queue_claimed_executions) + (SELECT count(*) FROM solid_queue_scheduled_executions) + (SELECT count(*) FROM solid_queue_blocked_executions)"
# Shell scripts (by extension or shebang), tracked or new, minus third-party
# agent skills. Deferred (=) so other targets don't need shfmt installed.
SHELL_SCRIPTS = $(shell git ls-files -z --cached --others --exclude-standard -- ':!.github/skills' | xargs -0 shfmt -f 2>/dev/null)

# Production Rails run outside the service, e.g. by `make update`. The service
# gets SECRET_KEY_BASE from web/.env (EnvironmentFile); pass just that key here
# rather than source the file. The shell expands it, so make never prints it.
PROD_RAILS = cd $(WEB_DIR) && PATH="$(RUBY_DIR)/bin:$$PATH" RAILS_ENV=production \
	SECRET_KEY_BASE="$$(sed -n 's/^SECRET_KEY_BASE=//p' .env | tail -n 1)" bin/rails

# Substitutes template placeholders when generating systemd units.
RENDER = sed \
	-e 's|@APP_DIR@|$(APP_DIR)|g' \
	-e 's|@WEB_DIR@|$(WEB_DIR)|g' \
	-e 's|@RUBY_DIR@|$(RUBY_DIR)|g' \
	-e 's|@PORT_DIR@|$(PORT_DIR)|g' \
	-e 's|@SERVICE_USER@|$(SERVICE_USER)|g'

.PHONY: help install install-deps install-web install-backup backup update restart status logs check-ruby check-secret-key-base lint format check-shell-tools check-port-pin build-port install-port switch-to-port switch-to-rails

.DEFAULT_GOAL := help

# Lists the targets annotated with `## description`, grouped under the
# `##@ Section` lines, then variables and examples.
help:
	@echo 'Deployment and development tasks for the Notes app. Production runs'
	@echo 'from this checkout; see deploy/DEPLOYMENT.md for the full runbook.'
	@echo
	@echo 'Usage: make [TARGET ...] [VAR=value ...]'
	@awk 'BEGIN { FS = ":.*## " } \
		/^##@ / { printf "\n%s:\n", substr($$0, 5) } \
		/^[a-z-]+:.*## / { printf "  %-16s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo
	@echo 'Variables:'
	@echo '  AWS_PROFILE=NAME AWS CLI profile that provisions the S3 backup'
	@echo
	@echo 'Examples:'
	@echo '  make install AWS_PROFILE=prod  first install; provision backups as "prod"'
	@echo '  git pull && make update        deploy what is now in the working tree'
	@echo '  make status                    is notes-web up? when is the next backup?'
	@echo '  make format lint               fix script formatting, then lint'

##@ Setup

install: install-deps install-web install-backup ## install-deps + install-web + install-backup (idempotent)

check-ruby:
	@test -n "$(RUBY_DIR)" && test -x "$(RUBY_DIR)/bin/ruby" || { \
		echo "error: no mise-managed Ruby found (mise where ruby). Run: mise install ruby"; \
		exit 1; \
	}

check-secret-key-base:
	@grep -q '^SECRET_KEY_BASE=.' $(WEB_DIR)/.env 2>/dev/null || { \
		echo "error: SECRET_KEY_BASE is missing from web/.env (see deploy/DEPLOYMENT.md)"; \
		exit 1; \
	}

install-deps: ## Install apt packages (build tools, sqlite3, libvips, ...)
	sudo apt-get update -qq
	sudo apt-get install -y -qq \
		build-essential git curl rsync sqlite3 libsqlite3-dev libvips \
		libssl-dev libreadline-dev zlib1g-dev libyaml-dev libffi-dev

install-web: check-ruby ## Render + enable notes-web.service; re-run after Ruby upgrades
	$(RENDER) deploy/notes-web.service.tmpl | sudo tee $(SYSTEMD_DIR)/notes-web.service >/dev/null
	sudo systemctl daemon-reload
	sudo systemctl enable notes-web.service
	@echo "Installed notes-web.service (WorkingDirectory=$(WEB_DIR), User=$(SERVICE_USER))"

# Provisions S3 + IAM (as AWS_PROFILE, if set) and writes deploy/backup.env on
# first run (interactive); once backup.env exists (e.g. after a restore) it
# only installs the units.
install-backup: ## Provision S3 backup on first run; install its service + timer
	deploy/install-backup.sh $(if $(wildcard deploy/backup.env),--no-provision) $(if $(AWS_PROFILE),--admin-profile $(AWS_PROFILE))

##@ Operations

backup: ## Run a backup to S3 now
	sudo systemctl start notes-backup.service

# No git operations here by design: production runs whatever the working
# tree contains, and git is the operator's business.
update: check-ruby check-secret-key-base ## Deploy the working tree: bundle, migrate, assets, model, restart the live unit
	cd $(WEB_DIR) && PATH="$(RUBY_DIR)/bin:$$PATH" bundle install
	@# While the Port is live, Rails must not change the schema under it.
	@if [ "$(LIVE_UNIT)" = notes-port ]; then \
	  echo "The Port is live: not running db:prepare; refusing if migrations are pending"; \
	  $(PROD_RAILS) db:abort_if_pending_migrations; \
	else \
	  $(PROD_RAILS) db:prepare; \
	fi
	$(PROD_RAILS) assets:precompile
	$(PROD_RAILS) retrieval:install_model
	@if [ "$(LIVE_UNIT)" = notes-port ]; then $(MAKE) --no-print-directory build-port; fi
	sudo systemctl restart $(LIVE_UNIT).service

restart: ## Restart the live unit (notes-web or notes-port)
	sudo systemctl restart $(LIVE_UNIT).service

status: ## Show the live unit's status and the backup timer schedule
	@systemctl status $(LIVE_UNIT).service --no-pager || true
	@echo
	@systemctl list-timers notes-backup.timer --no-pager || true

logs: ## Follow the live unit's journal
	journalctl -u $(LIVE_UNIT) -f

##@ The Rust Port (ADR 0004)

check-port-pin: ## Refuse if web/ differs from the Reference the Port was verified against
	@pin="$$(git -C $(PORT_DIR) ls-tree HEAD reference | awk '{print $$3}')"; \
	if [ -z "$$pin" ]; then echo "error: no reference pin in $(PORT_DIR)" >&2; exit 1; fi; \
	if ! git -C $(APP_DIR) diff --quiet "$$pin" -- web; then \
	  echo "error: web/ differs from $$pin, the Reference the Port was verified against; re-pin the Port and re-run Parity first" >&2; \
	  exit 1; \
	fi

build-port: check-port-pin ## Build the Port (release) in PORT_DIR
	cd $(PORT_DIR) && cargo build --release -p notes

install-port: build-port ## Build the Port and render notes-port.service (not enabled: see switch-to-port)
	$(RENDER) deploy/notes-port.service.tmpl | sudo tee $(SYSTEMD_DIR)/notes-port.service >/dev/null
	$(RENDER) deploy/notes-web.service.tmpl | sudo tee $(SYSTEMD_DIR)/notes-web.service >/dev/null
	sudo systemctl daemon-reload
	@echo "Installed notes-port.service (ExecStart=$(PORT_DIR)/target/release/notes); notes-web stays live"

switch-to-port: check-port-pin ## Stop Rails, refuse while its queue has work, start the Port and wait for /up
	@test -x $(PORT_DIR)/target/release/notes || { echo "error: no Port build; run make install-port" >&2; exit 1; }
	@test -f $(SYSTEMD_DIR)/notes-port.service || { echo "error: notes-port.service is not installed; run make install-port" >&2; exit 1; }
	sudo systemctl stop notes-web.service
	@# The Port does not run Solid Queue jobs: let Rails finish them first.
	@pending="$$($(QUEUE_PENDING))"; \
	if [ "$$pending" != 0 ]; then \
	  echo "error: Solid Queue still has $$pending job(s) to run; starting Rails again to finish them. Retry when they are done." >&2; \
	  sudo systemctl start notes-web.service; \
	  exit 1; \
	fi
	sudo systemctl disable notes-web.service
	sudo systemctl enable --now notes-port.service
	@if ! ($(WAIT_UP)); then \
	  echo "error: the Port did not answer /up; switching back to Rails" >&2; \
	  sudo systemctl disable --now notes-port.service; \
	  sudo systemctl enable --now notes-web.service; \
	  exit 1; \
	fi
	@echo "The Port is live on :3002 (notes-port.service); make switch-to-rails goes back"

switch-to-rails: ## Stop the Port, start Rails and wait for /up (refused past the Port's Point of No Return)
	@if grep -Eq '^[[:space:]]*rails_rollback[[:space:]]*=[[:space:]]*false' $(PORT_DIR)/migration.toml 2>/dev/null; then \
	  echo "error: the Port is past its Point of No Return (rails_rollback = false in $(PORT_DIR)/migration.toml): Rails cannot read its state" >&2; \
	  exit 1; \
	fi
	sudo systemctl disable --now notes-port.service
	sudo systemctl enable --now notes-web.service
	@($(WAIT_UP)) || { echo "error: Rails did not answer /up" >&2; exit 1; }
	@echo "Rails is live on :3002 (notes-web.service)"

##@ Development

# Style (2-space indent, indented case arms) comes from .editorconfig, so
# editors that run shfmt agree with these targets.
check-shell-tools:
	@command -v shellcheck >/dev/null || { echo "error: shellcheck not found (sudo apt install shellcheck)"; exit 1; }
	@command -v shfmt >/dev/null || { echo "error: shfmt not found (https://github.com/mvdan/sh, e.g. mise use -g shfmt)"; exit 1; }

lint: check-shell-tools ## ShellCheck + shfmt check of the shell scripts
	shellcheck $(SHELL_SCRIPTS)
	shfmt --diff $(SHELL_SCRIPTS)

format: check-shell-tools ## Format the shell scripts in place with shfmt
	shfmt --write $(SHELL_SCRIPTS)
