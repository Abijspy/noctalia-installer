# Contributing

Thanks for helping. This file explains how the repository fits together, how to test a change, and how releases work.

## How the configs fit together

- **`configs/niri/config.kdl` is the reference.** Every other compositor's config mirrors it as far as that compositor allows: the same gaps, corners, border colours, shadow, blur, input settings, key scheme, and the rule that opens Noctalia settings full size (maximized, not fullscreen). When you change something in the niri config, carry it over to the others, or say in your pull request why it can't be.
- **`install.sh` rewrites a few words in each config**, so keep them as they are:
  - `alacritty`, `nautilus` and `firefox` are replaced by the terminal, file manager and browser the user picks;
  - the `us` keyboard layout (`layout "us"`, `kb_layout = "us"`, `xkb_layout "us"`, `xkb_rules_layout=us`, `layout = "us"`) is replaced by theirs.

  `tests/check-configs.py` fails if one of these goes missing.
- **Mango** uses Mango 0.18's option names; `install.sh` translates them back for older Mango (`mango_legacy_names`). Add any newly used renamed option to that list.
- **Sway**: `configs/sway/swayfx-effects` is appended only when SwayFX is installed. Plain Sway rejects those commands.
- **Noctalia** settings live in `configs/noctalia/`. They are merged with the user's own files, so only set what the preset needs.

## Testing a change

```bash
bash -n install.sh && shellcheck -S warning install.sh
pip install lupa ckdl
python3 tests/check-configs.py                        # parsing, placeholders, settings rule
git clone --depth 1 https://github.com/mangowm/mango.git /tmp/mango
git clone --depth 1 https://github.com/noctalia-dev/umbriel.git /tmp/umbriel
python3 tests/check-configs.py --mango-src /tmp/mango --umbriel-src /tmp/umbriel
sudo tests/sim/run.sh                                 # throwaway machine or VM only
```

`tests/sim/run.sh` runs `install.sh` end to end against stubbed package managers and fake `os-release` files for every supported distribution. It runs the install, the uninstall, a dry run and a reinstall over an existing config. It needs root because it creates test users and edits `/etc/greetd`, so run it in a VM or container, not on your desktop.

GitHub Actions runs all of this on every push and pull request, plus `niri validate` and `sway -C` with the real tools in an Arch container, and again weekly to catch upstream compositor changes.

Nothing here replaces logging in. If you change a compositor's config, please try it on that compositor and say so in the pull request, ideally with a screenshot.

## Installer conventions

- Every change the installer makes to the system goes through a function that records it (`place_user_file`, `enable_service`, `rec ...`), so `--uninstall` can undo it. Add a matching case to `do_uninstall` for anything new.
- Anything the installer would do must also be listed by `print_plan` (`--dry-run`).
- New choices need a flag, a place in the TUI (usually the Extras checklist), a line on the Review screen, and a row in the README's options table.
- Steps run in a background subshell during the TUI install, so results needed later come back through files in `$TMP_DIR`.

## Releases

The README's install command points at a tag, and a tagged `install.sh` downloads configs from that same tag (`REPO_REF`), so users always get a script and configs that were tested together.

To release:

```bash
tools/release.sh 1.1.0          # sets VERSION, updates the README links, commits, tags
git push origin main v1.1.0
```

The `release` check fails if the tag, `VERSION` in `install.sh` and the README's install command disagree.
