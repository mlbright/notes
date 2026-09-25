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
# Resolve from web/ so the app's pinned Ruby (web/mise.toml) wins over the
# root mise.toml.
RUBY_DIR     := $(shell cd $(WEB_DIR) && mise where ruby 2>/dev/null)
SYSTEMD_DIR  := /etc/systemd/system
# Shell scripts (by extension or shebang), tracked or new, minus third-party
# agent skills. Deferred (=) so other targets don't need shfmt installed.
SHELL_SCRIPTS = $(shell git ls-files -z --cached --others --exclude-standard -- ':!.github/skills' | xargs -0 shfmt -f 2>/dev/null)

# Substitutes template placeholders when generating systemd units.
RENDER = sed \
	-e 's|@APP_DIR@|$(APP_DIR)|g' \
	-e 's|@WEB_DIR@|$(WEB_DIR)|g' \
	-e 's|@RUBY_DIR@|$(RUBY_DIR)|g' \
	-e 's|@SERVICE_USER@|$(SERVICE_USER)|g'

.PHONY: help install install-deps install-web install-backup backup update restart status logs check-ruby lint format check-shell-tools

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
update: check-ruby ## Deploy the working tree: bundle, migrate, assets, restart
	cd $(WEB_DIR) && PATH="$(RUBY_DIR)/bin:$$PATH" bundle install
	cd $(WEB_DIR) && PATH="$(RUBY_DIR)/bin:$$PATH" RAILS_ENV=production bin/rails db:prepare
	cd $(WEB_DIR) && PATH="$(RUBY_DIR)/bin:$$PATH" RAILS_ENV=production bin/rails assets:precompile
	sudo systemctl restart notes-web.service

restart: ## Restart notes-web
	sudo systemctl restart notes-web.service

status: ## Show notes-web status and the backup timer schedule
	@systemctl status notes-web.service --no-pager || true
	@echo
	@systemctl list-timers notes-backup.timer --no-pager || true

logs: ## Follow the notes-web journal
	journalctl -u notes-web -f

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
