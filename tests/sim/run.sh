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
         noctalia-greeter-session noctalia-greeter-apply-appearance dbus-run-session gsettings xdg-user-dirs-update; do
    ln -sf "$BIN/stub" "$BIN/$t"
done
export STUB_BIN="$BIN" STUB_LOG="$LOGF" STUB_REPO="$HERE/repo.txt"

FAKEDRM="$(mktemp -d)"; python3 "$HERE/make-drm.py" "$FAKEDRM"

for u in tester greeter _greetd; do id "$u" &>/dev/null || useradd -m "$u"; done
TH="$(getent passwd tester | cut -d: -f6)"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   $*"; }
bad()  {
    FAIL=$((FAIL + 1)); echo "  FAIL $*"
    [[ -n ${OUT:-} ]] && tail -n 8 <<< "$OUT" | sed 's/^/       | /'
}
check() { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }

reset() {
    rm -rf "$TH/.config" "$TH/.local/state/noctalia-installer" "$TH/Pictures/Wallpapers" "$TH/.face"
    rm -f "$BIN/paru" "$BIN/yay" /etc/modprobe.d/90-noctalia-nvidia.conf \
          /etc/nvidia/nvidia-application-profiles-rc.d/50-noctalia-niri-vram.json \
          /etc/systemd/logind.conf.d/10-noctalia-lid.conf
    mkdir -p /etc/greetd
    printf '[terminal]\nvt = 1\n\n[default_session]\ncommand = "agreety --cmd /bin/sh"\nuser = "_greetd"\n' > /etc/greetd/config.toml
    : > "$LOGF"
}
run() {  # run OS [args...] -> $OUT, $RC
    local os=$1; shift
    OUT="$(NOCTALIA_OS_RELEASE="$HERE/os/$os" NOCTALIA_TEST_DRM="${DRM:-/nonexistent}" PATH="$BIN:$PATH" \
           "$REPO/install.sh" --user=tester "$@" 2>&1 \
           | sed 's/\x1b\[[0-9;]*m//g')"
    RC=$?
}
no_errors() { ! grep -q '✗' <<< "$OUT"; }
called()    { grep -qF -- "$1" "$LOGF"; }

echo "== Arch, every compositor, every extra"
reset
NOCTALIA_TEST_LAPTOP=1 NOCTALIA_TEST_BT=1 NOCTALIA_TEST_NVIDIA=1 DRM="$FAKEDRM" \
    run arch --yes --no-tui --compositors=niri,hyprland,sway,scroll,mango,labwc,umbriel,kde \
        --aur-helper=paru --terminal=kitty --file-manager=thunar --browser=librewolf --layout=de,us --lid-fix \
        --variant=nodeadkeys, --switch-key=ctrl-shift --caps=escape --theme=tokyo-night --flathub
check "finishes without errors" no_errors
for f in niri/config.kdl hypr/hyprland.lua sway/config scroll/config mango/config.conf labwc/rc.xml \
         umbriel/config.toml autostart/noctalia.desktop noctalia/10-installer.toml noctalia/20-bar.toml noctalia/30-wallpaper.toml; do
    check "wrote $f" test -s "$TH/.config/$f"
done
check "keyboard layout applied" grep -q 'layout "de,us"' "$TH/.config/niri/config.kdl"
check "keyboard variant applied" grep -q 'kb_variant = "nodeadkeys,"' "$TH/.config/hypr/hyprland.lua"
check "keyboard options applied" grep -q 'xkb_options "grp:ctrl_shift_toggle,caps:escape"' "$TH/.config/sway/config"
check "labwc keyboard options" grep -qx 'XKB_DEFAULT_OPTIONS=grp:ctrl_shift_toggle,caps:escape' "$TH/.config/labwc/environment"
check "niri display scale" grep -A2 'output "eDP-1"' "$TH/.config/niri/config.kdl" | grep -q 'scale 1.5'
check "hyprland highest refresh" grep -q 'mode = "1920x1080@144.001"' "$TH/.config/hypr/hyprland.lua"
check "mango monitor rule" grep -q 'monitor_rule=name:^eDP-1\$,width:2560,height:1600,refresh:1000,scale:1.5' "$TH/.config/mango/config.conf"
check "umbriel output" grep -q '^\[output.DP-2\]' "$TH/.config/umbriel/config.toml"
check "labwc wlr-randr" grep -q 'wlr-randr --output eDP-1 --scale 1.5' "$TH/.config/labwc/autostart"
check "theme file" grep -q 'builtin = "Tokyo-Night"' "$TH/.config/noctalia/40-theme.toml"
check "theme templates" grep -q '"niri", "hyprland".*"gtk3", "gtk4", "qt", "kitty"' "$TH/.config/noctalia/40-theme.toml"
check "qt6ct config" test -s "$TH/.config/qt6ct/qt6ct.conf"
check "gtk settings" grep -q 'gtk-application-prefer-dark-theme=1' "$TH/.config/gtk-3.0/settings.ini"
check "fontconfig" test -s "$TH/.config/fontconfig/conf.d/60-noctalia-fonts.conf"
check "flathub added" called '[flatpak] remote-add --if-not-exists flathub'
check "dark preference set" called "[gsettings] set org.gnome.desktop.interface color-scheme 'prefer-dark'"
check "configs pass the Umbriel/Noctalia TOML parse" python3 -c "import tomllib,sys;[tomllib.load(open(f,'rb')) for f in sys.argv[1:]]" \
    "$TH/.config/umbriel/config.toml" "$TH/.config/noctalia/40-theme.toml"
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
check "theme file removed" test ! -e "$TH/.config/noctalia/40-theme.toml"
check "app theme files removed" test ! -e "$TH/.config/qt6ct/qt6ct.conf"
check "gsettings set back" called "[gsettings] set org.gnome.desktop.interface color-scheme 'stub-old'"
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
check "Luciole is the default file manager on Arch" called 'luciole-git'
check "Noctalia's owl is the profile picture" cmp -s "$TH/.face" "$REPO/configs/avatar/noctalia.png"
check "Mod+E opens Luciole" grep -q 'spawn "luciole"' "$TH/.config/niri/config.kdl"
check "Luciole is the file picker on niri" grep -q '^org.freedesktop.impl.portal.FileChooser=luciole;gnome;gtk;' "$TH/.config/xdg-desktop-portal/niri-portals.conf"
run arch --yes --no-tui --compositors=niri --no-greeter --no-services          # a second run backs up our own file
run arch --uninstall --yes
check "original is back after two installs" grep -qx '// MINE' "$TH/.config/niri/config.kdl"
check "portal file removed" test ! -e "$TH/.config/xdg-desktop-portal/niri-portals.conf"

echo "== Without the app theme, Qt isn't pointed at qt6ct"
reset
run arch --yes --no-tui --compositors=niri,sway --no-greeter --no-services --no-app-theme --no-fonts --scale=none
check "no qt6ct in niri" bash -c "! grep -q QT_QPA_PLATFORMTHEME '$TH/.config/niri/config.kdl'"
check "sway env is empty" grep -qx 'set \$env env' "$TH/.config/sway/config"
check "no display blocks" bash -c "! grep -q '^output ' '$TH/.config/niri/config.kdl'"
check "templates without gtk/qt" bash -c "! grep -q gtk3 '$TH/.config/noctalia/40-theme.toml'"
run arch --uninstall --yes

echo "== A profile picture you already have stays"
reset
echo mine > "$TH/.face"; chown tester: "$TH/.face"
run arch --yes --no-tui --compositors=niri --no-greeter --no-services
check "keeps ~/.face" grep -qx mine "$TH/.face"
check "says so" grep -q 'Keeping your profile picture' <<< "$OUT"
rm -f "$TH/.face"

echo "== Dry run changes nothing"
reset
run arch --dry-run --yes --no-tui --compositors=niri,hyprland
check "exits cleanly" test "$RC" -eq 0
check "prints the plan" grep -q 'nothing has been changed' <<< "$OUT"
check "lists the niri config" grep -q 'niri/config.kdl' <<< "$OUT"
check "lists the theme" grep -q 'colour theme: Rose Pine' <<< "$OUT"
check "installs nothing" bash -c "! grep -qF '[pacman] -Syu' '$LOGF'"
check "writes nothing" test ! -e "$TH/.config/niri/config.kdl"

echo "== Every distribution"
# Gentoo looks packages up in the ebuild tree; give it a minimal fake one.
FAKE_PORTAGE=0
if [[ ! -d /var/db/repos ]]; then
    FAKE_PORTAGE=1
    for a in gui-apps/noctalia gui-wm/niri x11-terms/alacritty; do
        mkdir -p "/var/db/repos/gentoo/$a"; touch "/var/db/repos/gentoo/$a/${a#*/}-1.ebuild"
    done
fi
for os in fedora tumbleweed trixie resolute alpine chimera gentoo solus void nixos; do
    reset
    extra=("--compositors=niri,sway,labwc")
    # The stub repository only has niri there, and no file manager.
    [[ $os == gentoo || $os == void ]] && extra=("--compositors=niri" "--file-manager=none")
    run "$os" --yes --no-tui "${extra[@]}"
    check "$os: no errors" no_errors
    check "$os: niri config" test -s "$TH/.config/niri/config.kdl"
    [[ $os == fedora ]] && check "fedora: Nautilus (Luciole is AUR only)" grep -q 'spawn "nautilus"' "$TH/.config/niri/config.kdl"
done

[[ $FAKE_PORTAGE -eq 1 ]] && rm -rf /var/db/repos
[[ -n ${KEEP:-} ]] && { echo "$OUT" > /tmp/sim-last.txt; }
reset; rm -rf "$BIN" "$LOGF" "$FAKEDRM"
echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
