#!/usr/bin/env bash
# End-to-end runs of install.sh against stubbed package managers and
# fake os-release files. Needs root (it creates test users and edits
# /etc/greetd). Run on a throwaway machine or CI runner:
#   sudo tests/sim/run.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo $0)"; exit 1; }

# Open to the test user: AUR helpers are "built" (linked here) as that user.
BIN="$(mktemp -d)"; LOGF="$(mktemp)"; chmod 777 "$BIN"; chmod 666 "$LOGF"
install -m 755 "$HERE/stub" "$BIN/stub"
for t in pacman dnf zypper apt-get apt-cache dpkg xbps-install xbps-query apk emerge emaint eselect portageq eopkg \
         flatpak curl wget git makepkg systemctl systemd-tmpfiles niri sway scroll mango noctalia \
         noctalia-greeter-session noctalia-greeter-apply-appearance; do
    ln -sf "$BIN/stub" "$BIN/$t"
done
export STUB_BIN="$BIN" STUB_LOG="$LOGF" STUB_REPO="$HERE/repo.txt"

for u in tester greeter _greetd; do id "$u" &>/dev/null || useradd -m "$u"; done
TH="$(getent passwd tester | cut -d: -f6)"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   $*"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL $*"; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }

reset() {
    rm -rf "$TH/.config" "$TH/.local/state/noctalia-installer" "$TH/Pictures/Wallpapers"
    rm -f "$BIN/paru" "$BIN/yay" /etc/modprobe.d/90-noctalia-nvidia.conf \
          /etc/nvidia/nvidia-application-profiles-rc.d/50-noctalia-niri-vram.json \
          /etc/systemd/logind.conf.d/10-noctalia-lid.conf
    mkdir -p /etc/greetd
    printf '[terminal]\nvt = 1\n\n[default_session]\ncommand = "agreety --cmd /bin/sh"\nuser = "_greetd"\n' > /etc/greetd/config.toml
    : > "$LOGF"
}
run() {  # run OS [args...] -> $OUT, $RC
    local os=$1; shift
    OUT="$(NOCTALIA_OS_RELEASE="$HERE/os/$os" PATH="$BIN:$PATH" "$REPO/install.sh" --user=tester "$@" 2>&1 \
           | sed 's/\x1b\[[0-9;]*m//g')"
    RC=$?
}
no_errors() { ! grep -q '✗' <<< "$OUT"; }
called()    { grep -qF -- "$1" "$LOGF"; }

echo "== Arch, every compositor, every extra"
reset
NOCTALIA_TEST_LAPTOP=1 NOCTALIA_TEST_BT=1 NOCTALIA_TEST_NVIDIA=1 \
    run arch --yes --no-tui --compositors=niri,hyprland,sway,scroll,mango,labwc,umbriel,kde \
        --aur-helper=paru --terminal=kitty --file-manager=thunar --browser=librewolf --layout=de --lid-fix
check "finishes without errors" no_errors
for f in niri/config.kdl hypr/hyprland.lua sway/config scroll/config mango/config.conf labwc/rc.xml \
         umbriel/config.toml autostart/noctalia.desktop noctalia/10-installer.toml noctalia/20-bar.toml noctalia/30-wallpaper.toml; do
    check "wrote $f" test -s "$TH/.config/$f"
done
check "keyboard layout applied" grep -q 'layout "de"' "$TH/.config/niri/config.kdl"
check "terminal applied" grep -q 'kitty' "$TH/.config/hypr/hyprland.lua"
check "greetd points at the greeter" grep -q 'noctalia-greeter-session' /etc/greetd/config.toml
check "NetworkManager enabled" called '[systemctl] enable NetworkManager.service'
check "bluetooth enabled" called '[systemctl] enable bluetooth.service'
check "power profiles enabled" called '[systemctl] enable power-profiles-daemon.service'
check "NVIDIA modeset file" test -s /etc/modprobe.d/90-noctalia-nvidia.conf
check "niri VRAM profile" test -s /etc/nvidia/nvidia-application-profiles-rc.d/50-noctalia-niri-vram.json
M="$TH/.local/state/noctalia-installer/manifest"
check "install record written" test -s "$M"
check "record owned by the user" test "$(stat -c %U "$M")" = tester

echo "== Uninstall undoes it"
: > "$LOGF"
run arch --uninstall --yes
check "finishes without errors" no_errors
check "configs removed" test ! -e "$TH/.config/niri/config.kdl"
check "wallpapers removed" test ! -e "$TH/Pictures/Wallpapers/noctalia-moonrise.jpg"
check "greetd config restored" grep -q 'agreety' /etc/greetd/config.toml
check "NVIDIA files removed" test ! -e /etc/modprobe.d/90-noctalia-nvidia.conf
check "lid file removed" test ! -e /etc/systemd/logind.conf.d/10-noctalia-lid.conf
check "services disabled" called '[systemctl] disable bluetooth.service'
check "record retired" test ! -e "$M"

echo "== Uninstall restores a config that existed before"
reset
mkdir -p "$TH/.config/niri"; echo "// MINE" > "$TH/.config/niri/config.kdl"; chown -R tester: "$TH/.config"
run arch --yes --no-tui --compositors=niri --no-greeter --no-services
check "installed over it" grep -q 'noctalia' "$TH/.config/niri/config.kdl"
run arch --yes --no-tui --compositors=niri --no-greeter --no-services          # a second run backs up our own file
run arch --uninstall --yes
check "original is back after two installs" grep -qx '// MINE' "$TH/.config/niri/config.kdl"

echo "== Dry run changes nothing"
reset
run arch --dry-run --yes --no-tui --compositors=niri,hyprland
check "exits cleanly" test "$RC" -eq 0
check "prints the plan" grep -q 'nothing has been changed' <<< "$OUT"
check "lists the niri config" grep -q 'niri/config.kdl' <<< "$OUT"
check "installs nothing" bash -c "! grep -qF '[pacman] -Syu' '$LOGF'"
check "writes nothing" test ! -e "$TH/.config/niri/config.kdl"

echo "== Every distribution"
for os in fedora tumbleweed trixie resolute alpine chimera gentoo solus void nixos; do
    reset
    extra=("--compositors=niri,sway,labwc")
    # The stub repository only has niri there, and no file manager.
    [[ $os == gentoo || $os == void ]] && extra=("--compositors=niri" "--file-manager=none")
    run "$os" --yes --no-tui "${extra[@]}"
    check "$os: no errors" no_errors
    check "$os: niri config" test -s "$TH/.config/niri/config.kdl"
done

[[ -n ${KEEP:-} ]] && { echo "$OUT" > /tmp/sim-last.txt; }
reset; rm -rf "$BIN" "$LOGF"
echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
