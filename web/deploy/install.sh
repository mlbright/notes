#!/usr/bin/env bash
#
# install.sh — Set up the Notes app on an Ubuntu/Debian VPS.
#
# Usage:
#   sudo bash deploy/install.sh
#
# Prerequisites:
#   - Ubuntu 24.04+
#   - Root or sudo access
#   - Git, curl installed
#   - mise installed for the 'ubuntu' user with Ruby provisioned (see web/mise.toml)
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — edit these before running
# ---------------------------------------------------------------------------
APP_USER="notes"
APP_DIR="/opt/notes/web"
MISE_USER="ubuntu"
DOMAIN="notes.example.com"              # your real domain
SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  red "This script must be run as root (or with sudo)."
  exit 1
fi

green "==> Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq \
  build-essential git curl libssl-dev libreadline-dev zlib1g-dev \
  libsqlite3-dev libyaml-dev libffi-dev rsync

# ---------------------------------------------------------------------------
# Create application user
# ---------------------------------------------------------------------------
if ! id "$APP_USER" &>/dev/null; then
  green "==> Creating system user '$APP_USER'..."
  useradd --system --create-home --shell /usr/sbin/nologin "$APP_USER"
fi

# ---------------------------------------------------------------------------
# Locate Ruby installed by mise for the ubuntu user
# ---------------------------------------------------------------------------
if ! id "$MISE_USER" &>/dev/null; then
  red "Expected user '$MISE_USER' to exist with mise installed."
  exit 1
fi

green "==> Locating Ruby via mise (user: $MISE_USER)..."
RUBY_DIR="$(sudo -iu "$MISE_USER" -- mise where ruby 2>/dev/null || true)"
if [[ -z "$RUBY_DIR" || ! -x "$RUBY_DIR/bin/ruby" ]]; then
  red "Could not locate a mise-managed Ruby for user '$MISE_USER'."
  red "Install it first, e.g.: sudo -iu $MISE_USER mise install ruby"
  exit 1
fi
export PATH="$RUBY_DIR/bin:$PATH"
ruby -v

# ---------------------------------------------------------------------------
# Deploy application code
# ---------------------------------------------------------------------------
green "==> Deploying application to ${APP_DIR}..."
mkdir -p "$APP_DIR"
rsync -a --delete \
  --exclude='.git' \
  --exclude='storage/development.sqlite3' \
  --exclude='storage/test.sqlite3' \
  --exclude='tmp/cache' \
  --exclude='log/*.log' \
  --exclude='node_modules' \
  "${SOURCE_DIR}/" "${APP_DIR}/"

chown -R "$APP_USER":"$APP_USER" "$APP_DIR"

# ---------------------------------------------------------------------------
# Install gems
# ---------------------------------------------------------------------------
green "==> Installing Ruby gems..."
cd "$APP_DIR"
su -s /bin/bash "$APP_USER" -c "export PATH=$RUBY_DIR/bin:\$PATH && cd $APP_DIR && bundle config set --local deployment true && bundle config set --local without 'development test' && bundle install --jobs 4 --quiet"

# ---------------------------------------------------------------------------
# Rails credentials
# ---------------------------------------------------------------------------
if [[ ! -f "$APP_DIR/config/master.key" ]]; then
  yellow "WARNING: config/master.key is missing."
  yellow "Copy your master.key to $APP_DIR/config/master.key before starting the service."
  yellow "  scp config/master.key root@server:$APP_DIR/config/master.key"
  yellow "  chown $APP_USER:$APP_USER $APP_DIR/config/master.key"
  yellow "  chmod 600 $APP_DIR/config/master.key"
fi

# ---------------------------------------------------------------------------
# Prepare database and assets
# ---------------------------------------------------------------------------
green "==> Preparing database..."
su -s /bin/bash "$APP_USER" -c "export PATH=$RUBY_DIR/bin:\$PATH && cd $APP_DIR && RAILS_ENV=production bin/rails db:prepare"

green "==> Precompiling assets..."
su -s /bin/bash "$APP_USER" -c "export PATH=$RUBY_DIR/bin:\$PATH && cd $APP_DIR && RAILS_ENV=production bin/rails assets:precompile"

# ---------------------------------------------------------------------------
# Ensure writable directories
# ---------------------------------------------------------------------------
su -s /bin/bash "$APP_USER" -c "mkdir -p $APP_DIR/tmp/pids $APP_DIR/tmp/sockets $APP_DIR/log $APP_DIR/storage"

# ---------------------------------------------------------------------------
# Install systemd service
# ---------------------------------------------------------------------------
green "==> Installing systemd service..."
cp "$APP_DIR/deploy/notes-web.service" /etc/systemd/system/notes-web.service

# Create a drop-in override for OAuth credentials (if not already present).
# Operators fill in the real values after install.
OVERRIDE_DIR="/etc/systemd/system/notes-web.service.d"
if [[ ! -f "$OVERRIDE_DIR/oauth.conf" ]]; then
  green "==> Creating systemd OAuth credentials override..."
  mkdir -p "$OVERRIDE_DIR"
  cat > "$OVERRIDE_DIR/oauth.conf" <<'EOF'
# Google OAuth2 credentials for the Notes app.
# Replace the placeholder values and then run:
#   sudo systemctl daemon-reload && sudo systemctl restart notes-web
[Service]
Environment=GOOGLE_CLIENT_ID=changeme
Environment=GOOGLE_CLIENT_SECRET=changeme
EOF
  chmod 600 "$OVERRIDE_DIR/oauth.conf"
  yellow "NOTE: Edit $OVERRIDE_DIR/oauth.conf with your Google OAuth2 credentials."
fi

systemctl daemon-reload
systemctl enable notes-web.service

# Drop-in to point the service at the mise-managed Ruby detected above.
# Rewritten on every install so it stays in sync with the active Ruby.
green "==> Writing Ruby PATH override for systemd..."
cat > "$OVERRIDE_DIR/ruby-path.conf" <<EOF
[Service]
Environment=PATH=$RUBY_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
chmod 644 "$OVERRIDE_DIR/ruby-path.conf"
systemctl daemon-reload

# ---------------------------------------------------------------------------
# Start the app
# ---------------------------------------------------------------------------
green "==> Starting Notes app..."
systemctl start notes-web.service
systemctl status notes-web.service --no-pager

green ""
green "================================================================"
green "  Installation complete!"
green ""
green "  App:      https://${DOMAIN}"
green "  Service:  systemctl {start|stop|restart|status} notes-web"
green "  Logs:     journalctl -u notes-web -f"
green "  App logs: tail -f ${APP_DIR}/log/production.log"
green "================================================================"
