#!/bin/bash
# Installs streamdeckd for the current user on Linux (SteamOS or any systemd distribution).
#   ./install-linux.sh              # install or upgrade
#   ./install-linux.sh --uninstall  # remove everything this script installed
#
# Run it on the target machine as the user who logs in there (on SteamOS: deck), not as root.
# It looks for its files next to itself (after `scp build/linux/streamdeckd dist/linux/* scripts/install-linux.sh`)
# or in a repository checkout (build/linux/streamdeckd and dist/linux/).
# Only the udev rules and the uinput module setup use sudo.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
bin_dir="$HOME/.local/bin"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
rules=/etc/udev/rules.d/70-streamdeck.rules
modules=/etc/modules-load.d/streamdeck-uinput.conf

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not root; it asks for sudo when it needs it." >&2
    exit 1
fi

# First existing file among the candidates.
find_file() {
    for candidate in "$@"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return
        fi
    done
    echo "error: none of these exist: $*" >&2
    exit 1
}

if [[ "${1:-}" == "--uninstall" ]]; then
    systemctl --user disable --now streamdeckd.service 2>/dev/null || true
    rm -f "$unit_dir/streamdeckd.service" "$bin_dir/streamdeckd"
    systemctl --user daemon-reload
    sudo rm -f "$rules" "$modules"
    sudo udevadm control --reload
    echo "Removed streamdeckd. Your config in ~/.config/streamdeck is still there."
    exit 0
elif [[ $# -gt 0 ]]; then
    echo "usage: $0 [--uninstall]" >&2
    exit 2
fi

binary="$(find_file "$here/streamdeckd" "$here/../build/linux/streamdeckd")"
unit="$(find_file "$here/streamdeckd.service" "$here/../dist/linux/streamdeckd.service")"
rules_source="$(find_file "$here/70-streamdeck.rules" "$here/../dist/linux/70-streamdeck.rules")"
modules_source="$(find_file "$here/uinput.conf" "$here/../dist/linux/uinput.conf")"

echo "Installing the udev rules and the uinput module (needs sudo)..."
sudo install -m 0644 "$rules_source" "$rules"
sudo install -m 0644 "$modules_source" "$modules"
sudo modprobe uinput
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=hidraw
sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput

echo "Installing streamdeckd to $bin_dir..."
mkdir -p "$bin_dir" "$unit_dir"
# Install next to the old binary and rename, so a running daemon keeps its file until the restart.
install -m 0755 "$binary" "$bin_dir/.streamdeckd.new"
mv -f "$bin_dir/.streamdeckd.new" "$bin_dir/streamdeckd"
install -m 0644 "$unit" "$unit_dir/streamdeckd.service"

systemctl --user daemon-reload
systemctl --user enable streamdeckd.service
systemctl --user restart streamdeckd.service

echo
echo "Done. streamdeckd is running and starts at login."
echo "Config: ~/.config/streamdeck/config.yaml (saved changes apply within a second)"
echo "Logs:   journalctl --user -u streamdeckd -f"
