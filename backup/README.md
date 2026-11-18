# Backups

Daily encrypted backups of a Linux home folder to a Hetzner Storage Box, using restic and systemd timers.

## How it works

- restic compresses and encrypts files on the machine before uploading them. Hetzner only stores data it can't read, and nobody can read it without the password.
- `restic-backup.timer` starts a backup every day at 17:00. If the machine is off or asleep at that time, the backup runs as soon as it's back. Only new and changed files get uploaded.
- `restic-maintenance.timer` runs on Sundays at 18:00. It deletes old snapshots, keeping 7 daily, 4 weekly and 12 monthly ones, and checks a random 5% of the stored data for damage.
- If a job fails, a desktop notification says which one.
- Each backup includes lists of the installed pacman packages and Flatpak apps, saved to `~/.config/pkglist.txt` and `~/.config/flatpaks.txt`, so a new install can get the same apps back.
- Turn on automatic snapshots for the Storage Box in the Hetzner console. If someone gets into a machine and deletes the backups, those snapshots still have them.

## Tools

- [restic](https://restic.net) for the backups and the encryption
- systemd user timers for the schedule
- SSH on port 23 to reach the Storage Box over SFTP
- `notify-send` for the failure notifications

## Files

| File | Where | What it's for |
|---|---|---|
| `systemd/*` | this folder, linked to `~/.config/systemd/user/` | The two jobs, their timers and the notification |
| `excludes` | this folder | Starting list of folders to skip, copied to each machine |
| `env` | `~/.config/restic/` | Repository location and password file |
| `paths` | `~/.config/restic/` | Folders to back up, one per line |
| `excludes` | `~/.config/restic/` | This machine's list of folders to skip |
| `password` | `~/.config/restic/` | The restic password |

The files in `~/.config/restic/` belong to one machine and stay out of git. After editing a unit, run `systemctl --user daemon-reload`.

## Setting up a machine

1. Add the Storage Box to `~/.ssh/config`, with your Storage Box username in place of `uXXXXXX`:

   ```
   Host storagebox
       Hostname uXXXXXX.your-storagebox.de
       User uXXXXXX
       Port 23
       ServerAliveInterval 60
       ServerAliveCountMax 240
   ```

2. Copy your SSH key to the box. This asks for the Storage Box password.

   ```sh
   ssh-copy-id -s storagebox
   ```

3. Run `./setup.sh`. It installs restic, asks for the password, the repository and the folders to back up, and turns on the timers. Give each machine its own repository, for example `sftp:storagebox:restic-laptop`, so their snapshots don't get mixed up. Running it again is safe.

4. Write the password down on paper. Without it nobody can decrypt the backups, including you.

## Everyday use

To run restic by hand, export the two variables from `~/.config/restic/env` in your shell. In fish:

```fish
set -Ux RESTIC_REPOSITORY sftp:storagebox:restic-laptop
set -Ux RESTIC_PASSWORD_FILE ~/.config/restic/password
```

```sh
restic snapshots                         # list the backups
restic ls latest ~/Documents             # files in the latest backup
restic restore latest --target ~/restore --include ~/Documents
systemctl --user list-timers 'restic*'   # last and next runs
journalctl --user -u restic-backup       # what happened in each run
```

## Restoring a lost machine

You need the restic password and the Hetzner login. If the SSH key is gone too, reset the Storage Box password in the Hetzner console. Then follow steps 1 and 2 above, install restic, and run:

```fish
restic -r sftp:storagebox:restic-laptop restore latest --target /
paru -S --needed (cat ~/.config/pkglist.txt)
flatpak install (cut -f2 ~/.config/flatpaks.txt)
```

The restore brings back `~/.config/restic` as well, so running `./setup.sh` afterwards only turns the timers back on.
