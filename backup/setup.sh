#!/usr/bin/env bash
# Sets up daily restic backups on this machine. See README.md.
# Safe to run again: steps that are already done get skipped.
set -eu

here=$(dirname "$(realpath "$0")")
conf="$HOME/.config/restic"
mkdir -p "$conf" "$HOME/.config/systemd/user"

# Install restic
if ! command -v restic >/dev/null; then
    if command -v pacman >/dev/null; then
        sudo pacman -S --needed restic libnotify
    elif command -v dnf >/dev/null; then
        sudo dnf install -y restic libnotify
    else
        echo "Install restic, then run this again."
        exit 1
    fi
fi

# The password lives in a file so the timers can run without asking
if [ ! -f "$conf/password" ]; then
    read -rsp "restic password: " password; echo
    read -rsp "Same password again: " again; echo
    if [ "$password" != "$again" ]; then
        echo "The passwords don't match."
        exit 1
    fi
    touch "$conf/password"
    chmod 600 "$conf/password"
    printf '%s\n' "$password" > "$conf/password"
fi

# Where this machine's backups go
if [ ! -f "$conf/env" ]; then
    read -rp "Repository, for example sftp:storagebox:restic-laptop: " repo
    echo "RESTIC_REPOSITORY=$repo" > "$conf/env"
    echo "RESTIC_PASSWORD_FILE=$conf/password" >> "$conf/env"
fi

# What to back up, one folder per line
if [ ! -f "$conf/paths" ]; then
    read -rp "Folders to back up, separated by spaces [$HOME]: " folders
    for folder in ${folders:-$HOME}; do
        echo "$folder"
    done > "$conf/paths"
fi

# What to skip. Each machine gets its own copy of the starting list to edit.
if [ ! -f "$conf/excludes" ]; then
    cp "$here/excludes" "$conf/excludes"
fi

# Link the services and timers from this folder
ln -sf "$here"/systemd/* "$HOME/.config/systemd/user/"

# Check the repository. restic exits with code 10 when there is none at that location yet.
source "$conf/env"
export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE
if restic cat config >/dev/null 2>&1; then
    echo "Found the repository at $RESTIC_REPOSITORY."
elif [ $? -eq 10 ]; then
    read -rp "No repository at $RESTIC_REPOSITORY yet. Create it? [y/N] " answer
    if [ "$answer" != y ]; then
        echo "Fix the repository in $conf/env, then run this again."
        exit 1
    fi
    restic init
else
    echo "Can't open $RESTIC_REPOSITORY. Check the SSH access and the password in $conf/password."
    exit 1
fi

# Turn on the timers
systemctl --user daemon-reload
systemctl --user enable --now restic-backup.timer restic-maintenance.timer

echo
echo "Done. Backups run every day at 17:00."
echo "To start the first one now: systemctl --user start restic-backup.service"
echo "Keep a copy of the password somewhere other than this machine."
