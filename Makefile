# Deployment for the Notes app.
#
# Production runs directly from this checkout: all state (SQLite databases,
# Active Storage blobs, secrets) lives inside this directory. The only
# artifacts outside it are the systemd units that `make install` generates
# from the templates in deploy/.
#
# Run make as the user that will own the service (normally your login user,
# not root). Recipes use sudo where system access is required.
#
#   make install    one-time (and after Ruby upgrades): apt deps + systemd units
#   make update     make the running service reflect the current working tree
#   make status     service + backup timer status
#   make logs       follow the service journal
#
# See deploy/DEPLOYMENT.md for the full runbook, including machine migration.

APP_DIR      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
WEB_DIR      := $(APP_DIR)/web
SERVICE_USER := $(shell id -un)
# Resolve from web/ so the app's pinned Ruby (web/mise.toml) wins over the
# root mise.toml.
RUBY_DIR     := $(shell cd $(WEB_DIR) && mise where ruby 2>/dev/null)
SYSTEMD_DIR  := /etc/systemd/system

# Substitutes template placeholders when generating systemd units.
RENDER = sed \
	-e 's|@APP_DIR@|$(APP_DIR)|g' \
	-e 's|@WEB_DIR@|$(WEB_DIR)|g' \
	-e 's|@RUBY_DIR@|$(RUBY_DIR)|g' \
	-e 's|@SERVICE_USER@|$(SERVICE_USER)|g'

.PHONY: install install-deps install-web install-backup update restart status logs check-ruby

install: install-deps install-web install-backup

check-ruby:
	@test -n "$(RUBY_DIR)" && test -x "$(RUBY_DIR)/bin/ruby" || { \
		echo "error: no mise-managed Ruby found (mise where ruby). Run: mise install ruby"; \
		exit 1; \
	}

install-deps:
	sudo apt-get update -qq
	sudo apt-get install -y -qq \
		build-essential git curl rsync sqlite3 libsqlite3-dev libvips \
		libssl-dev libreadline-dev zlib1g-dev libyaml-dev libffi-dev

install-web: check-ruby
	$(RENDER) deploy/notes-web.service.tmpl | sudo tee $(SYSTEMD_DIR)/notes-web.service >/dev/null
	sudo systemctl daemon-reload
	sudo systemctl enable notes-web.service
	@echo "Installed notes-web.service (WorkingDirectory=$(WEB_DIR), User=$(SERVICE_USER))"

install-backup:
	@test -f deploy/backup.env || \
		echo "WARNING: deploy/backup.env is missing — backups will fail until it exists (see deploy/backup.env.example)"
	$(RENDER) deploy/notes-backup.service.tmpl | sudo tee $(SYSTEMD_DIR)/notes-backup.service >/dev/null
	sudo install -m 644 deploy/notes-backup.timer $(SYSTEMD_DIR)/notes-backup.timer
	sudo systemctl daemon-reload
	sudo systemctl enable --now notes-backup.timer

# No git operations here by design: production runs whatever the working
# tree contains, and git is the operator's business.
update: check-ruby
	cd $(WEB_DIR) && PATH="$(RUBY_DIR)/bin:$$PATH" bundle install
	cd $(WEB_DIR) && PATH="$(RUBY_DIR)/bin:$$PATH" RAILS_ENV=production bin/rails db:prepare
	cd $(WEB_DIR) && PATH="$(RUBY_DIR)/bin:$$PATH" RAILS_ENV=production bin/rails assets:precompile
	sudo systemctl restart notes-web.service

restart:
	sudo systemctl restart notes-web.service

status:
	@systemctl status notes-web.service --no-pager || true
	@echo
	@systemctl list-timers notes-backup.timer --no-pager || true

logs:
	journalctl -u notes-web -f
