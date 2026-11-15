#!/usr/bin/env bash
# =====================================================================
#  Noctalia v5 desktop installer for Linux
#  https://github.com/Abijspy/noctalia-installer
#
#  Sets up Noctalia on any compositor it supports: niri, Hyprland,
#  Sway, Scroll, Mango, Labwc, Umbriel and KDE Plasma, on every
#  distribution Noctalia packages for: Arch, Fedora, openSUSE,
#  Debian/Ubuntu, Void, Alpine Edge, Chimera, Gentoo and Solus
#  (configs only on NixOS, Guix and others). Full-screen installer in
#  Noctalia's colors; works from a bare TTY, even as root. On Arch it
#  can install yay or paru.
#
#  Usage:
#    ./install.sh                     # TUI installer (default)
#    ./install.sh --no-tui            # plain text prompts
#    ./install.sh --yes               # no prompts, accept defaults
#
#  Options (also preset the TUI choices):
#    --compositors=niri,hyprland      # niri hyprland sway scroll mango labwc umbriel kde
#    --aur-helper=auto|paru|yay|none  # auto: keep an installed one, else paru if needed
#    --user=NAME                      # user to set up (when run as root)
#    --terminal=alacritty|kitty|foot|ghostty|wezterm
#    --file-manager=nautilus|dolphin|thunar|nemo|caja|pcmanfm|pcmanfm-qt|
#                   cosmic-files|krusader|doublecmd|yazi|ranger|lf|nnn|mc|none
#    --browser=firefox|librewolf|brave|mullvad|tor|ungoogled|zen|chromium|none
#    --layout=us                      # keyboard layout(s), e.g. us,de
#    --no-apps                        # skip file manager and browser
#    --no-greeter                     # skip Noctalia Greeter + greetd
#    --lid-fix                        # lock before suspend on lid close
#    --stock-bar                      # keep Noctalia's default bar (no bar preset)
#    --wallpaper=moonrise|aurora|dunes|waves|nebula|orbit|none
#                                     # bundled wallpaper to use (none: Noctalia's own)
#    --no-services                    # don't enable NetworkManager, Bluetooth, power profiles
#    --no-nvidia-fix                  # don't apply the NVIDIA tweaks (modeset, niri VRAM)
#    --dry-run                        # show what would be installed and written; change nothing
#    --uninstall                      # undo what this installer did (restores your backups)
#    --version                        # print the installer version
#
#  Straight from GitHub (a tagged release, so the script and its
#  configs always match):
#    curl -fsSL https://raw.githubusercontent.com/Abijspy/noctalia-installer/v1.0.0/install.sh | bash
# =====================================================================
set -euo pipefail

VERSION="1.0.0"
# Configs come from the same release as this script. Override with
# NOCTALIA_INSTALLER_REF=main to test unreleased changes.
REPO_REF="${NOCTALIA_INSTALLER_REF:-v$VERSION}"
REPO_RAW="https://raw.githubusercontent.com/Abijspy/noctalia-installer/$REPO_REF"
GREETD_CONF="/etc/greetd/config.toml"
LOG="/tmp/noctalia-niri-install.log"

# ---------- defaults ----------
ASSUME_YES=0
NO_TUI=0
INSTALL_APPS=1
INSTALL_GREETER=1
LID_FIX=0
TYPE_TO_LAUNCH=1
POLKIT_AGENT=1
BAR_PRESET=1
WALLPAPER="moonrise"
SWITCH_DM=1
TARGET_USER=""
NEW_USER_PASS=""
CREATE_USER=0
TERM_APP="alacritty"
FM_APP="nautilus"
BROWSER_APP="firefox"
KB_LAYOUT="us"
COMPOSITORS="niri"
COMPS_FROM_FLAG=0
AUR_HELPER="auto"
SERVICES=1
NVIDIA_FIX=1
DRY_RUN=0
UNINSTALL=0

usage() { awk 'NR > 2 && /^# =====/ { exit } NR > 2' "${BASH_SOURCE[0]:-$0}" 2>/dev/null | sed 's/^# \{0,1\}//'; }

for arg in "$@"; do
    case "$arg" in
        -y|--yes)          ASSUME_YES=1 ;;
        --no-tui)          NO_TUI=1 ;;
        --no-apps)         INSTALL_APPS=0 ;;
        --no-greeter)      INSTALL_GREETER=0 ;;
        --lid-fix)         LID_FIX=1 ;;
        --stock-bar)       BAR_PRESET=0 ;;
        --wallpaper=*)     WALLPAPER="${arg#*=}" ;;
        --user=*)          TARGET_USER="${arg#*=}" ;;
        --terminal=*)      TERM_APP="${arg#*=}" ;;
        --file-manager=*)  FM_APP="${arg#*=}" ;;
        --browser=*)       BROWSER_APP="${arg#*=}" ;;
        --layout=*)        KB_LAYOUT="${arg#*=}" ;;
        --compositors=*)   COMPOSITORS="${arg#*=}"; COMPS_FROM_FLAG=1 ;;
        --aur-helper=*)    AUR_HELPER="${arg#*=}" ;;
        --no-services)     SERVICES=0 ;;
        --no-nvidia-fix)   NVIDIA_FIX=0 ;;
        --dry-run)         DRY_RUN=1 ;;
        --uninstall)       UNINSTALL=1 ;;
        --version)         echo "noctalia-installer $VERSION"; exit 0 ;;
        -h|--help)         usage; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)"; exit 1 ;;
    esac
done

check_opt() {  # check_opt name value allowed...
    local name="$1" val="$2"; shift 2
    local a; for a in "$@"; do [[ $val == "$a" ]] && return 0; done
    echo "Invalid --$name=$val (allowed: $*)"; exit 1
}
check_opt terminal     "$TERM_APP"    alacritty kitty foot ghostty wezterm
check_opt file-manager "$FM_APP"      nautilus dolphin thunar nemo caja pcmanfm pcmanfm-qt cosmic-files krusader doublecmd yazi ranger lf nnn mc none
check_opt browser      "$BROWSER_APP" firefox librewolf brave mullvad tor ungoogled zen chromium none
[[ $KB_LAYOUT =~ ^[a-z]{2,}(,[a-z]{2,})*$ ]] || { echo "Invalid --layout=$KB_LAYOUT (e.g. us or us,de)"; exit 1; }
check_opt aur-helper   "$AUR_HELPER"  auto paru yay none
check_opt wallpaper    "$WALLPAPER"   moonrise aurora dunes waves nebula orbit none
WALLPAPERS_ON=1; [[ $WALLPAPER == none ]] && { WALLPAPERS_ON=0; WALLPAPER=moonrise; }

# Bundled wallpapers (configs/wallpapers/noctalia-<id>.jpg): id | description
WALLPAPER_TABLE=(
    "moonrise|crescent moon over deep navy"
    "aurora|mint and lavender aurora"
    "dunes|layered hills under a low moon"
    "waves|flowing lavender lines"
    "nebula|soft colour clouds"
    "orbit|minimal concentric rings"
)

# ---------- compositors Noctalia supports ----------
# id | name | repo packages | AUR packages | start command | description (no commas)
COMP_TABLE=(
    "niri|niri|niri xwayland-satellite xdg-desktop-portal-gnome||niri-session|scrollable tiling · blur · overview"
    "hyprland|Hyprland|hyprland xdg-desktop-portal-hyprland xorg-xwayland||start-hyprland|dynamic tiling · Lua config"
    "sway|Sway|sway xdg-desktop-portal-wlr xorg-xwayland||sway|i3-style tiling"
    "scroll|Scroll|xdg-desktop-portal-wlr xorg-xwayland|sway-scroll|scroll|Sway with a scrolling layout"
    "mango|Mango|mangowm xdg-desktop-portal-wlr xorg-xwayland||mango|dwl-based tiling with tags"
    "labwc|Labwc|labwc xdg-desktop-portal-wlr xorg-xwayland||labwc|stacking · Openbox-like"
    "umbriel|Umbriel||umbriel-git|umbriel|Noctalia's own compositor"
    "kde|KDE Plasma|plasma-desktop xdg-desktop-portal-kde||startplasma-wayland|full desktop · fewer Noctalia features"
)
comp_field() {  # comp_field ID FIELD_NUMBER
    local row
    for row in "${COMP_TABLE[@]}"; do
        [[ ${row%%|*} == "$1" ]] && { cut -d'|' -f"$2" <<< "$row"; return 0; }
    done
    return 1
}
COMPS=()
IFS=, read -ra COMPS <<< "$COMPOSITORS"
(( ${#COMPS[@]} > 0 )) || { echo "--compositors needs at least one compositor"; exit 1; }
for c in "${COMPS[@]}"; do
    comp_field "$c" 1 >/dev/null || { echo "Unknown compositor '$c' (use: niri hyprland sway scroll mango labwc umbriel kde)"; exit 1; }
done

has_comp()      { local c; for c in "${COMPS[@]}"; do [[ $c == "$1" ]] && return 0; done; return 1; }
needs_aur()     { local c; for c in "${COMPS[@]}"; do [[ -n $(comp_aur_pkgs "$c") ]] && return 0; done; return 1; }
aur_comp_names() { local c n=(); for c in "${COMPS[@]}"; do [[ -n $(comp_aur_pkgs "$c") ]] && n+=("$(comp_field "$c" 2)"); done; local IFS=/; echo "${n[*]}"; }
comp_names()    { local c n=(); for c in "${COMPS[@]}"; do n+=("$(comp_field "$c" 2)"); done; local IFS=,; echo "${n[*]}" | sed 's/,/, /g'; }
# Lid lock is wired up only in configs that can bind the lid switch.
lid_supported() { local c; for c in "${COMPS[@]}"; do case $c in niri|sway|scroll) ;; *) return 1 ;; esac; done; return 0; }

# ---------- browsers ----------
# id | name | description | Arch repo pkg | Arch AUR pkg | native pkg elsewhere | binaries to look for | Flathub id
BROWSER_TABLE=(
    "firefox|Firefox|Mozilla|firefox||firefox|firefox firefox-bin|org.mozilla.firefox"
    "librewolf|LibreWolf|Firefox fork with privacy defaults||librewolf-bin|librewolf|librewolf|io.gitlab.librewolf-community"
    "brave|Brave|Chromium with ad and tracker blocking||brave-bin|brave-browser|brave brave-browser|com.brave.Browser"
    "mullvad|Mullvad Browser|anti-fingerprinting, no Tor||mullvad-browser-bin|mullvad-browser|mullvad-browser|net.mullvad.MullvadBrowser"
    "tor|Tor Browser|browses over the Tor network|torbrowser-launcher||torbrowser-launcher|torbrowser-launcher|org.torproject.torbrowser-launcher"
    "ungoogled|Ungoogled Chromium|Chromium without Google services||ungoogled-chromium-bin|ungoogled-chromium|ungoogled-chromium chromium|io.github.ungoogled_software.ungoogled_chromium"
    "zen|Zen Browser|Firefox-based · vertical tabs||zen-browser-bin|zen-browser|zen-browser zen|app.zen_browser.zen"
    "chromium|Chromium|open-source Chrome|chromium||chromium|chromium chromium-browser|org.chromium.Chromium"
)
browser_field() {  # browser_field ID FIELD_NUMBER
    local row
    for row in "${BROWSER_TABLE[@]}"; do
        [[ ${row%%|*} == "$1" ]] && { cut -d'|' -f"$2" <<< "$row"; return 0; }
    done
    return 1
}
# ---------- file managers ----------
# id | name | description | kind (gui/tui) | package names to try | Gentoo atom | command
FM_TABLE=(
    "nautilus|Nautilus|GNOME Files|gui|nautilus|gnome-base/nautilus|nautilus"
    "dolphin|Dolphin|KDE · tabs and split view|gui|dolphin|kde-apps/dolphin|dolphin"
    "thunar|Thunar|Xfce · lightweight|gui|thunar Thunar|xfce-base/thunar|thunar"
    "nemo|Nemo|Cinnamon · dual pane|gui|nemo|gnome-extra/nemo|nemo"
    "caja|Caja|MATE · classic|gui|caja|mate-base/caja|caja"
    "pcmanfm|PCManFM|LXDE · very light GTK|gui|pcmanfm pcmanfm-gtk3|x11-misc/pcmanfm|pcmanfm"
    "pcmanfm-qt|PCManFM-Qt|LXQt · very light Qt|gui|pcmanfm-qt|lxqt-base/pcmanfm-qt|pcmanfm-qt"
    "cosmic-files|COSMIC Files|COSMIC · written in Rust|gui|cosmic-files|cosmic-base/cosmic-files|cosmic-files"
    "krusader|Krusader|twin panel · for power users|gui|krusader|kde-misc/krusader|krusader"
    "doublecmd|Double Commander|twin panel · Total Commander-like|gui|doublecmd-qt6 doublecmd-qt doublecmd-gtk doublecmd-gtk2 doublecmd|app-misc/doublecmd|doublecmd"
    "yazi|Yazi|terminal · fast · image previews|tui|yazi|app-misc/yazi|yazi"
    "ranger|ranger|terminal · vim keys|tui|ranger|app-misc/ranger|ranger"
    "lf|lf|terminal · minimal|tui|lf|app-misc/lf|lf"
    "nnn|nnn|terminal · tiny and fast|tui|nnn|app-misc/nnn|nnn"
    "mc|Midnight Commander|terminal · twin panel|tui|mc|app-misc/mc|mc"
)
fm_field() {  # fm_field ID FIELD_NUMBER
    local row
    for row in "${FM_TABLE[@]}"; do
        [[ ${row%%|*} == "$1" ]] && { cut -d'|' -f"$2" <<< "$row"; return 0; }
    done
    return 1
}
# How each terminal runs a program: terminal file managers open inside it.
term_exec() {  # term_exec TERMINAL -> launch prefix
    case $1 in
        alacritty) echo "alacritty -e" ;; ghostty) echo "ghostty -e" ;;
        wezterm)   echo "wezterm start --" ;; *) echo "$1" ;;   # kitty, foot take the command directly
    esac
}
fm_command() {  # what Mod+E runs
    local c; c="$(fm_field "$FM_APP" 7)"
    if [[ $(fm_field "$FM_APP" 4) == tui ]]; then echo "$(term_exec "$TERM_APP") $c"; else echo "$c"; fi
}
declare -A FM_PKG   # id -> package that's available here ("" = none)
fm_scan() {  # look up every file manager's package once
    [[ ${FM_SCANNED:-0} -eq 1 ]] && return 0
    FM_SCANNED=1
    local row id cands c
    for row in "${FM_TABLE[@]}"; do
        id=${row%%|*}
        if [[ $FAMILY == gentoo ]]; then cands="$(fm_field "$id" 6)"; else cands="$(fm_field "$id" 5)"; fi
        FM_PKG[$id]=""
        if [[ $CONFIGS_ONLY -eq 1 ]]; then FM_PKG[$id]=${cands%% *}; continue; fi
        for c in $cands; do pm_has "$c" && { FM_PKG[$id]=$c; break; }; done
    done
    true   # a missing last candidate must not end the script under set -e
}

FLATPAK_BIN=/var/lib/flatpak/exports/bin
BROWSER_CMD=""   # what Mod+B runs; set once the browser is installed

EXISTING_HELPER=""
for h in paru yay; do command -v "$h" >/dev/null && { EXISTING_HELPER=$h; break; }; done
default_helper() {
    [[ $FAMILY == arch ]] || { echo none; return; }
    if [[ -n $EXISTING_HELPER ]]; then echo "$EXISTING_HELPER"
    elif needs_aur; then echo paru
    else echo none; fi
}

# =====================================================================
#  Distribution support
#  Noctalia packages: https://docs.noctalia.dev/noctalia/getting-started/installation/
# =====================================================================
# For testing: NOCTALIA_OS_RELEASE=/path/to/os-release overrides detection.
OS_RELEASE_FILE="${NOCTALIA_OS_RELEASE:-/etc/os-release}"
osval() {  # osval KEY — read a value from os-release without sourcing it
    [[ -r $OS_RELEASE_FILE ]] || return 0
    sed -n "s/^$1=//p" "$OS_RELEASE_FILE" | head -n1 | sed 's/^["'\'']//; s/["'\'']$//'
}
OS_ID="$(osval ID)"; OS_LIKE="$(osval ID_LIKE)"; OS_NAME="$(osval PRETTY_NAME)"
[[ -z $OS_NAME ]] && OS_NAME="$(osval NAME)"; [[ -z $OS_NAME ]] && OS_NAME="Linux"
OS_VERSION_ID="$(osval VERSION_ID)"; OS_CODENAME="$(osval VERSION_CODENAME)"; OS_UBUNTU_CODENAME="$(osval UBUNTU_CODENAME)"

# FAMILY: arch fedora opensuse debian void alpine chimera gentoo solus,
# or "configs" (NixOS, Guix, anything else): write configs only.
FAMILY=configs; FAMILY_NOTE=""
case " $OS_ID $OS_LIKE " in
    *" nixos "*)                FAMILY_NOTE="NixOS is configured declaratively: add noctalia and your compositor to your Nix config." ;;
    *" guix "*)                 FAMILY_NOTE="Guix: install the noctalia-shell package (gnu packages window-management) or the noctalia channel." ;;
    *" arch "*|*" archlinux "*) FAMILY=arch ;;
    *" chimera "*)              FAMILY=chimera ;;
    *" alpine "*)               FAMILY=alpine ;;
    *" void "*)                 FAMILY=void ;;
    *" gentoo "*)               FAMILY=gentoo ;;
    *" solus "*)                FAMILY=solus ;;
    *" rhel "*|*" centos "*)    FAMILY_NOTE="$OS_NAME has no Noctalia packages; install Noctalia manually (see its docs)." ;;
    *" fedora "*)               FAMILY=fedora ;;
    *" suse "*|*" opensuse "*|*opensuse-*) FAMILY=opensuse ;;
    *" debian "*|*" ubuntu "*)  FAMILY=debian ;;
    *)                          FAMILY_NOTE="$OS_NAME isn't one of the distributions Noctalia packages for." ;;
esac

# Release checks for the Noctalia repositories.
DEB_SUITE=""
if [[ $FAMILY == debian ]]; then
    case "${OS_UBUNTU_CODENAME:-$OS_CODENAME}" in
        trixie)        DEB_SUITE=trixie ;;
        sid|forky)     DEB_SUITE=unstable ;;
        resolute)      DEB_SUITE=resolute ;;
        stonking)      DEB_SUITE=stonking ;;
        *) FAMILY=configs
           FAMILY_NOTE="Noctalia's APT repository covers Debian 13 (trixie), Debian sid, and Ubuntu 26.04 / 26.10; this is ${OS_CODENAME:-an unknown release}." ;;
    esac
    [[ $(dpkg --print-architecture 2>/dev/null) =~ ^(amd64|arm64)$ ]] || { [[ $FAMILY == debian ]] && FAMILY=configs && FAMILY_NOTE="Noctalia's APT repository has amd64 and arm64 packages only."; }
fi
if [[ $FAMILY == fedora && ${OS_VERSION_ID%%.*} =~ ^[0-9]+$ && ${OS_VERSION_ID%%.*} -lt 44 ]]; then
    FAMILY=configs; FAMILY_NOTE="Noctalia is in Fedora's repositories from Fedora 44."
fi
SUSE_FLAVOR=""
if [[ $FAMILY == opensuse ]]; then
    case $OS_ID in
        opensuse-tumbleweed) SUSE_FLAVOR=Tumbleweed ;;
        opensuse-slowroll)   SUSE_FLAVOR=Slowroll ;;
        opensuse-leap)       SUSE_FLAVOR=Leap ;;
        *)                   SUSE_FLAVOR=Tumbleweed ;;
    esac
    if [[ $SUSE_FLAVOR == Leap && ${OS_VERSION_ID%%.*} -lt 16 ]]; then FAMILY=configs; FAMILY_NOTE="Noctalia needs openSUSE Tumbleweed, Slowroll or Leap 16."; fi
fi
if [[ $FAMILY == alpine && $OS_VERSION_ID != *_alpha* ]]; then
    FAMILY=configs; FAMILY_NOTE="Noctalia's Alpine packages are for Alpine Edge."
fi

case $FAMILY in
    arch) FAMILY_LABEL="Arch Linux" ;; fedora) FAMILY_LABEL="Fedora" ;; opensuse) FAMILY_LABEL="openSUSE $SUSE_FLAVOR" ;;
    debian) FAMILY_LABEL="$OS_NAME" ;; void) FAMILY_LABEL="Void Linux" ;; alpine) FAMILY_LABEL="Alpine Edge" ;;
    chimera) FAMILY_LABEL="Chimera Linux" ;; gentoo) FAMILY_LABEL="Gentoo" ;; solus) FAMILY_LABEL="Solus" ;;
    *) FAMILY_LABEL="$OS_NAME" ;;
esac
CONFIGS_ONLY=0; [[ $FAMILY == configs ]] && CONFIGS_ONLY=1
HAS_SYSTEMD=0; [[ -d /run/systemd/system ]] && HAS_SYSTEMD=1
# Only Arch has the AUR; the greeter is packaged for these systemd distros.
GREETER_DISTRO=0; case $FAMILY in arch|fedora|opensuse|debian) GREETER_DISTRO=1 ;; esac
[[ $FAMILY == opensuse && $SUSE_FLAVOR == Leap ]] && GREETER_DISTRO=0
[[ $HAS_SYSTEMD -eq 1 ]] || GREETER_DISTRO=0

# ---------- package names per distribution ----------
# pkgs GENERIC -> this distribution's package name(s); empty = not packaged.
pkgs() {
    local g=$1
    if [[ $FAMILY == gentoo ]]; then
        case $g in
            noctalia) echo gui-apps/noctalia ;;          polkit) echo sys-auth/polkit ;;
            keyring) echo gnome-base/gnome-keyring ;;    portal-gtk) echo sys-apps/xdg-desktop-portal-gtk ;;
            audio) echo "media-video/pipewire media-video/wireplumber" ;;
            media) echo "media-sound/playerctl app-misc/brightnessctl" ;;
            fonts) echo "media-fonts/noto media-fonts/noto-emoji" ;;
            sudo) echo app-admin/sudo ;;                 curl) echo net-misc/curl ;;
            alacritty) echo x11-terms/alacritty ;;       kitty) echo x11-terms/kitty ;;
            foot) echo gui-apps/foot ;;                  ghostty) echo x11-terms/ghostty ;;
            wezterm) echo x11-terms/wezterm ;;           nautilus) echo gnome-base/nautilus ;;
            thunar) echo xfce-base/thunar ;;             dolphin) echo kde-apps/dolphin ;;
            nemo) echo gnome-extra/nemo ;;               firefox) echo www-client/firefox-bin ;;
            chromium) echo www-client/chromium ;;
            *) echo "" ;;
        esac
        return
    fi
    case "$FAMILY:$g" in
        *:noctalia)        echo noctalia ;;
        *:greeter)         [[ $GREETER_DISTRO -eq 1 ]] && echo noctalia-greeter ;;
        debian:polkit)     echo polkitd ;;
        *:polkit)          echo polkit ;;
        *:keyring)         echo gnome-keyring ;;
        *:portal-gtk)      echo xdg-desktop-portal-gtk ;;
        fedora:audio|opensuse:audio) echo "pipewire wireplumber pipewire-pulseaudio" ;;
        void:audio|chimera:audio|solus:audio) echo "pipewire wireplumber" ;;
        *:audio)           echo "pipewire wireplumber pipewire-pulse" ;;
        *:media)           echo "playerctl brightnessctl" ;;
        arch:fonts)        echo "noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd" ;;
        fedora:fonts)      echo "google-noto-sans-fonts google-noto-color-emoji-fonts jetbrains-mono-fonts" ;;
        opensuse:fonts)    echo "google-noto-sans-fonts noto-coloremoji-fonts jetbrains-mono-fonts" ;;
        debian:fonts)      echo "fonts-noto-core fonts-noto-color-emoji fonts-jetbrains-mono" ;;
        void:fonts)        echo "noto-fonts-ttf noto-fonts-emoji" ;;
        alpine:fonts|chimera:fonts) echo "font-noto font-noto-emoji" ;;
        solus:fonts)       echo "noto-sans-ttf noto-emoji" ;;
        *:sudo)            echo sudo ;;
        *:curl)            echo curl ;;
        arch:networkmanager) echo networkmanager ;;
        debian:networkmanager) echo network-manager ;;
        *:networkmanager)  echo NetworkManager ;;
        arch:bluetooth)    echo "bluez bluez-utils" ;;
        *:bluetooth)       echo bluez ;;
        *:power)           echo power-profiles-daemon ;;
        *)                 echo "$g" ;;   # apps share their names across distributions
    esac
}

# Compositor packages: main package first, then portals / Xwayland.
comp_repo_pkgs() {
    local id=$1
    if [[ $FAMILY == arch ]]; then comp_field "$id" 3; return; fi
    case "$FAMILY:$id" in
        fedora:niri|opensuse:niri)   echo "niri xwayland-satellite xdg-desktop-portal-gnome" ;;
        *:niri)
            case $FAMILY in gentoo) echo gui-wm/niri ;; *) echo "niri xdg-desktop-portal-gnome" ;; esac ;;
        void:hyprland)               echo "" ;;
        gentoo:hyprland)             echo "gui-wm/hyprland gui-libs/xdg-desktop-portal-hyprland" ;;
        *:hyprland)                  echo "hyprland xdg-desktop-portal-hyprland" ;;
        gentoo:sway)                 echo "gui-wm/sway gui-libs/xdg-desktop-portal-wlr" ;;
        *:sway)                      echo "sway xdg-desktop-portal-wlr" ;;
        gentoo:labwc)                echo "gui-wm/labwc gui-libs/xdg-desktop-portal-wlr" ;;
        *:labwc)                     echo "labwc xdg-desktop-portal-wlr" ;;
        debian:umbriel)              echo "umbriel xdg-desktop-portal-umbriel" ;;
        fedora:umbriel)              echo "umbriel-nightly" ;;
        opensuse:umbriel)            [[ $SUSE_FLAVOR != Leap ]] && echo "umbriel-git" ;;
        fedora:kde)                  echo "plasma-desktop xdg-desktop-portal-kde" ;;
        opensuse:kde)                echo "plasma6-workspace xdg-desktop-portal-kde" ;;
        debian:kde)                  echo "plasma-desktop xdg-desktop-portal-kde" ;;
        void:kde)                    echo "kde-plasma xdg-desktop-portal-kde" ;;
        alpine:kde|chimera:kde|solus:kde) echo "plasma-desktop" ;;
        gentoo:kde)                  echo "kde-plasma/plasma-meta" ;;
        *)                           echo "" ;;   # scroll, mango: not packaged outside Arch
    esac
}
comp_aur_pkgs() { [[ $FAMILY == arch ]] && comp_field "$1" 4; true; }

# Packages that come from a repository the installer adds, so they can't
# be looked up before the install starts.
from_added_repo() {
    case "$FAMILY:$1" in
        debian:noctalia|debian:noctalia-greeter|debian:umbriel|debian:xdg-desktop-portal-umbriel) return 0 ;;
        fedora:noctalia-greeter|fedora:umbriel-nightly|opensuse:umbriel-git) return 0 ;;
        void:noctalia|alpine:noctalia|chimera:noctalia|gentoo:gui-apps/noctalia) return 0 ;;
    esac
    return 1
}

# Where a browser will come from here: repo, aur or flatpak.
browser_source() {  # browser_source ID
    local id=$1 native aur
    [[ $id == none ]] && { echo none; return; }
    if [[ $FAMILY == arch ]]; then
        native="$(browser_field "$id" 4)"; aur="$(browser_field "$id" 5)"
        if [[ -n $native ]] && pm_has "$native"; then echo repo; return; fi
        if [[ -n $aur && $AUR_HELPER != none && $AUR_HELPER != auto ]]; then echo aur; return; fi
        if [[ -n $aur && $AUR_HELPER == auto && -n $EXISTING_HELPER ]]; then echo aur; return; fi
        echo flatpak; return
    fi
    native="$(browser_field "$id" 6)"
    [[ $FAMILY == gentoo ]] && native="$(pkgs "$id")"   # Gentoo atoms: only Firefox and Chromium
    if [[ -n $native ]] && pm_has "$native"; then echo repo; return; fi
    echo flatpak
}

# ---------- package manager ----------
pm_has() {  # pm_has PKG — is it in the configured repositories?
    local p=$1
    case $FAMILY in
        arch)     pacman -Si "$p" &>/dev/null ;;
        fedora)   [[ -n $(dnf -q repoquery --available "$p" 2>/dev/null) ]] ;;
        opensuse) zypper -n -q search -x -t package "$p" &>/dev/null ;;
        debian)   apt-cache show "$p" &>/dev/null ;;
        void)     xbps-query -R "$p" &>/dev/null ;;
        alpine|chimera) [[ -n $(apk search -x "$p" 2>/dev/null) ]] ;;
        gentoo)   compgen -G "/var/db/repos/*/$p/*.ebuild" >/dev/null ;;
        solus)    eopkg info "$p" &>/dev/null ;;
        *)        return 1 ;;
    esac
}
pkg_ok() { from_added_repo "$1" || pm_has "$1"; }

pm_install() {  # pm_install PKG...
    case $FAMILY in
        arch)     as_root pacman -Syu --needed --noconfirm "$@" ;;
        fedora)   as_root dnf install -y "$@" ;;
        opensuse) as_root zypper -n --gpg-auto-import-keys install --auto-agree-with-licenses "$@" ;;
        debian)   as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        void)     as_root xbps-install -Sy "$@" ;;
        alpine|chimera) as_root apk add "$@" ;;
        gentoo)   as_root emerge --noreplace --ask=n "$@" ;;
        solus)    as_root eopkg install -y "$@" ;;
    esac
}

pm_refresh() {
    case $FAMILY in
        opensuse) as_root zypper -n --gpg-auto-import-keys refresh ;;
        debian)   as_root apt-get update ;;
        # "yes" accepts the new repository key; run it in sh so its SIGPIPE
        # exit (once xbps is done) isn't seen by our pipefail.
        void)     as_root sh -c 'yes | xbps-install -S' ;;
        alpine|chimera) as_root apk update ;;
        solus)    as_root eopkg update-repo ;;
        *)        true ;;
    esac
}

download() {  # download URL DEST
    if command -v curl >/dev/null; then curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null; then wget -qO "$2" "$1"
    else die "Need curl or wget to download $1"; fi
}

# Add the Noctalia (and related) repositories, as Noctalia's docs describe.
setup_repos() {
    local t="$TMP_DIR/repo"; mkdir -p "$t"
    case $FAMILY in
        debian)
            command -v curl >/dev/null || pm_install curl ca-certificates
            download https://pkg.noctalia.dev/deb/nickh-archive-keyring.deb "$t/keyring.deb"
            as_root dpkg -i "$t/keyring.deb"
            download "https://pkg.noctalia.dev/deb/noctalia-$DEB_SUITE.sources" "$t/noctalia.sources"
            as_root install -m 644 "$t/noctalia.sources" "/etc/apt/sources.list.d/noctalia-$DEB_SUITE.sources"
            if [[ $DEB_SUITE == trixie ]] && ! grep -rqs 'trixie-backports' /etc/apt/sources.list /etc/apt/sources.list.d/; then
                printf 'Types: deb\nURIs: http://deb.debian.org/debian\nSuites: trixie-backports\nComponents: main\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\n' \
                    | as_root tee /etc/apt/sources.list.d/debian-trixie-backports.sources >/dev/null
            fi
            ok "Added Noctalia's APT repository ($DEB_SUITE)" ;;
        fedora)
            if [[ $INSTALL_GREETER -eq 1 ]] || has_comp umbriel; then
                # Terra carries noctalia-greeter and Umbriel for Fedora.
                as_root dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
                ok "Added the Terra repository"
            fi ;;
        opensuse)
            if has_comp umbriel; then
                as_root zypper -n addrepo --refresh --name 'Noctalia Project' \
                    "https://download.opensuse.org/repositories/home:neifua:Noctalia/openSUSE_${SUSE_FLAVOR}/home:neifua:Noctalia.repo" || true
                ok "Added the Noctalia OBS repository"
            fi ;;
        void)
            echo 'repository=https://universalrepo.pages.dev/void' | as_root tee /etc/xbps.d/10-universalrepository.conf >/dev/null
            ok "Added the UniversalRepository for Void" ;;
        alpine)
            download https://downloads.sourceforge.net/project/universalrepository/alpine/universalrepository.rsa.pub "$t/universalrepository.rsa.pub"
            as_root install -m 644 "$t/universalrepository.rsa.pub" /etc/apk/keys/
            grep -qs 'universalrepository/alpine/community' /etc/apk/repositories \
                || echo 'https://downloads.sourceforge.net/project/universalrepository/alpine/community' | as_root tee -a /etc/apk/repositories >/dev/null
            ok "Added the UniversalRepository for Alpine" ;;
        chimera)
            as_root apk add chimera-repo-user
            ok "Enabled Chimera's user repository" ;;
        gentoo)
            as_root emerge --noreplace --ask=n app-eselect/eselect-repository
            as_root eselect repository enable guru || true
            as_root emaint sync -r guru
            as_root mkdir -p /etc/portage/package.accept_keywords
            echo "gui-apps/noctalia ~$(portageq envvar ARCH 2>/dev/null || echo amd64)" \
                | as_root tee /etc/portage/package.accept_keywords/noctalia >/dev/null
            ok "Enabled the GURU overlay for Noctalia" ;;
    esac
    pm_refresh
}

# ---------- plain output helpers ----------
c_blue=$'\e[1;34m'; c_green=$'\e[1;32m'; c_yellow=$'\e[1;33m'; c_red=$'\e[1;31m'; c_off=$'\e[0m'
WARN_FILE="$(mktemp)"
TMP_DIR="$(mktemp -d)"
STATE="$TMP_DIR/state"
UI=plain
INSTALL_STARTED=0

info() { printf '%s==>%s %s\n' "$c_blue" "$c_off" "$*"; }
ok()   { printf '%s ✓ %s %s\n' "$c_green" "$c_off" "$*"; }
warn() { printf '%s !  %s %s\n' "$c_yellow" "$c_off" "$*"; echo "$*" >> "$WARN_FILE"; }
die()  { printf '%s ✗  %s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

SUDOERS_TMP="/etc/sudoers.d/99-noctalia-installer-tmp"
cleanup() {
    [[ $UI == tui ]] && ui_restore
    [[ $EUID -eq 0 && -f $SUDOERS_TMP ]] && rm -f "$SUDOERS_TMP"
    rm -rf "$TMP_DIR" "$WARN_FILE"
    [[ -n ${KEEPALIVE_PID:-} ]] && kill "$KEEPALIVE_PID" 2>/dev/null
    true
}
trap cleanup EXIT

# ---------- environment checks ----------
if [[ $CONFIGS_ONLY -eq 0 ]]; then
    case $FAMILY in
        arch) PM=pacman ;; fedora) PM=dnf ;; opensuse) PM=zypper ;; debian) PM=apt-get ;;
        void) PM=xbps-install ;; alpine|chimera) PM=apk ;; gentoo) PM=emerge ;; solus) PM=eopkg ;;
    esac
    command -v "$PM" >/dev/null || die "$FAMILY_LABEL detected, but $PM is missing."
fi
[[ $AUR_HELPER != auto && $AUR_HELPER != none && $FAMILY != arch ]] && die "--aur-helper is only for Arch Linux (the AUR)."

if [[ $EUID -eq 0 ]]; then
    IS_ROOT=1; SUDO=()
elif [[ $CONFIGS_ONLY -eq 1 ]]; then
    IS_ROOT=0; SUDO=(false)   # configs-only: nothing needs root
else
    IS_ROOT=0; SUDO=(sudo)
    if ! command -v sudo >/dev/null; then
        if command -v doas >/dev/null; then die "Run this installer as root: doas $0"
        else die "sudo is not installed. Run this installer as root instead (it can create your user)."; fi
    fi
fi

IS_LAPTOP=0
compgen -G "/sys/class/power_supply/BAT*" >/dev/null && IS_LAPTOP=1
HAS_BT=0
compgen -G "/sys/class/bluetooth/hci*" >/dev/null && HAS_BT=1
# NVIDIA: a card (PCI vendor 0x10de, display class 0x03xxxx), and whether
# NVIDIA's own driver is loaded (nouveau needs none of the tweaks).
NVIDIA_GPU=0; NVIDIA_DRIVER=0
for _d in /sys/bus/pci/devices/*; do
    [[ $(cat "$_d/vendor" 2>/dev/null) == 0x10de && $(cat "$_d/class" 2>/dev/null) == 0x03* ]] && NVIDIA_GPU=1
done
[[ -e /proc/driver/nvidia/version || -d /sys/module/nvidia_drm ]] && NVIDIA_DRIVER=1
# Test hooks (tests/sim): pretend to be different hardware.
IS_LAPTOP=${NOCTALIA_TEST_LAPTOP:-$IS_LAPTOP}; HAS_BT=${NOCTALIA_TEST_BT:-$HAS_BT}
NVIDIA_DRIVER=${NOCTALIA_TEST_NVIDIA:-$NVIDIA_DRIVER}; [[ $NVIDIA_DRIVER -eq 1 ]] && NVIDIA_GPU=1
# Desktop services (NetworkManager, Bluetooth, power profiles) are enabled
# on the systemd distributions the installer fully supports.
SERVICES_DISTRO=0
[[ $HAS_SYSTEMD -eq 1 && $CONFIGS_ONLY -eq 0 ]] && case $FAMILY in arch|fedora|opensuse|debian) SERVICES_DISTRO=1 ;; esac
[[ $SERVICES_DISTRO -eq 1 ]] || SERVICES=0
[[ $NVIDIA_DRIVER -eq 1 && $CONFIGS_ONLY -eq 0 ]] || NVIDIA_FIX=0

CURRENT_DM="$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" 2>/dev/null || true)"
[[ $CURRENT_DM == "display-manager.service" || $CURRENT_DM == "greetd.service" ]] && CURRENT_DM=""

HAVE_TTY=0
{ : </dev/tty >/dev/tty; } 2>/dev/null && HAVE_TTY=1

if [[ $IS_ROOT -eq 0 && $CONFIGS_ONLY -eq 0 && $DRY_RUN -eq 0 ]]; then
    if [[ $UNINSTALL -eq 1 ]]; then info "Administrator rights are needed to undo system changes."
    else info "Administrator rights are needed to install packages."; fi
    sudo -v </dev/tty || die "sudo authentication failed."
    ( while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 45; done ) 2>/dev/null &
    KEEPALIVE_PID=$!
fi

# Which compositors can be installed here (checked once, before the UI).
declare -A COMP_OK COMP_WHY
check_comp_availability() {
    local row id pk aur main
    for row in "${COMP_TABLE[@]}"; do
        id=${row%%|*}
        if [[ $CONFIGS_ONLY -eq 1 ]]; then COMP_OK[$id]=1; continue; fi
        pk="$(comp_repo_pkgs "$id")"; aur="$(comp_aur_pkgs "$id")"
        main=${pk%% *}
        if [[ -n $aur ]]; then COMP_OK[$id]=1
        elif [[ -z $main ]]; then COMP_OK[$id]=0; COMP_WHY[$id]="not packaged for $FAMILY_LABEL"
        elif pkg_ok "$main"; then COMP_OK[$id]=1
        else COMP_OK[$id]=0; COMP_WHY[$id]="$main isn't in your repositories"; fi
    done
}

# =====================================================================
#  Noctalia theme
#  Colors from Noctalia's built-in "Noctalia" palette.
# =====================================================================
#            role        hex     console slot
THEME=(      surface    070722  0
             error      fd4663  1
             tertiary   9bfece  2
             primary    fff59b  3
             dim        7c80b4  4
             secondary  a9aefe  5
             outline    21215f  6
             text       f3edf7  7 )

IS_CONSOLE=0
[[ ${TERM:-} == linux ]] && IS_CONSOLE=1

declare -A HEX SLOT
for ((i = 0; i < ${#THEME[@]}; i += 3)); do
    HEX[${THEME[i]}]=${THEME[i+1]}; SLOT[${THEME[i]}]=${THEME[i+2]}
done

fg() { if [[ $IS_CONSOLE -eq 1 ]]; then printf '\e[3%dm' "${SLOT[$1]}"
       else local h=${HEX[$1]}; printf '\e[38;2;%d;%d;%dm' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"; fi; }
bg() { if [[ $IS_CONSOLE -eq 1 ]]; then printf '\e[4%dm' "${SLOT[$1]}"
       else local h=${HEX[$1]}; printf '\e[48;2;%d;%d;%dm' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"; fi; }

R=$'\e[0m'; B=$'\e[1m'; EL=$'\e[K'

setup_theme() {
    P="$(fg primary)"; S="$(fg secondary)"; T="$(fg tertiary)"; E="$(fg error)"
    D="$(fg dim)"; O="$(fg outline)"; X="$(fg text)"
    BP="$(bg primary)"; BS="$(bg secondary)"; BO="$(bg outline)"; ON="$(fg surface)"

    if [[ $IS_CONSOLE -eq 1 ]]; then
        # The kernel console's font only has CP437-style glyphs.
        SYM_DONE="√"; SYM_CUR="►"; SYM_TODO="·"; SYM_BUL="•"; SYM_FAIL="x"
        SYM_ARROW="»"; SYM_MOON=""; SYM_ON="■"; SYM_OFF="·"
        BX=(┌ ┐ └ ┘ ─ │); SPIN=('|' '/' '-' '\'); BAR_ON="█"; BAR_OFF="░"
        # Repaint the console palette with Noctalia (bright slots = same colors,
        # since the console shows bold text in the bright slot).
        local i role
        for role in surface error tertiary primary dim secondary outline text; do
            i=${SLOT[$role]}
            printf '\e]P%X%s\e]P%X%s' "$i" "${HEX[$role]}" "$((i + 8))" "${HEX[$role]}" >/dev/tty
        done
    else
        SYM_DONE="✓"; SYM_CUR="●"; SYM_TODO="○"; SYM_BUL="•"; SYM_FAIL="✗"
        SYM_ARROW="›"; SYM_MOON="☾ "; SYM_ON="◉"; SYM_OFF="○"
        BX=(╭ ╮ ╰ ╯ ─ │); SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); BAR_ON="━"; BAR_OFF="━"
        # Ask xterm-compatible terminals to use Noctalia's surface/text colors.
        printf '\e]11;#%s\a\e]10;#%s\a' "${HEX[surface]}" "${HEX[text]}" >/dev/tty
    fi
}

ui_restore() {
    printf '\e[0m\e[?25h' >/dev/tty 2>/dev/null || true
    if [[ $IS_CONSOLE -eq 1 ]]; then printf '\e]R' >/dev/tty 2>/dev/null || true
    else printf '\e]110\a\e]111\a' >/dev/tty 2>/dev/null || true; fi
    printf '\e[H\e[2J' >/dev/tty 2>/dev/null || true
}

# ---------- drawing primitives ----------
COLS=80; ROWS=24
out()  { printf '%s' "$*" >/dev/tty; }
at()   { printf '\e[%d;%dH' "$1" "$2" >/dev/tty; }
cls()  { printf '\e[0m\e[H\e[2J' >/dev/tty; }
vlen() { local s; s="$(printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g')"; echo "${#s}"; }
rep()  { local s="" i; for ((i = 0; i < $2; i++)); do s+="$1"; done; printf '%s' "$s"; }
pill() { printf '%s%s%s %s %s' "$2" "${3:-$ON}" "$B" "$1" "$R"; }   # pill TEXT BG_ESC [FG_ESC]

# Step tracker shown under the header.
STEPS=()
build_steps() {
    STEPS=(Welcome)
    [[ $IS_ROOT -eq 1 ]] && STEPS+=(User)
    STEPS+=(Desktop Extras Apps Keyboard Review Install)
}

header() {  # header CURRENT_STEP_NAME
    local cur="$1" line="" name state seen=0 GAP="  " total=0
    for name in "${STEPS[@]}"; do total=$(( total + ${#name} + 4 )); done
    (( total > COLS - 4 )) && GAP=" "   # tighten the tracker on narrow screens
    at 2 3; out "${P}${B}${SYM_MOON}noctalia${R} ${S}${B}desktop${R}"
    local right="installer · ${FAMILY_LABEL}"
    (( ${#right} > COLS / 2 )) && right="${right:0:$(( COLS / 2 - 3 ))}..."
    at 2 $(( COLS - ${#right} - 2 )); out "${D}${right}${R}"
    at 3 3; out "${O}$(rep "─" $(( COLS - 4 )))${R}"
    for name in "${STEPS[@]}"; do
        if [[ $name == "$cur" ]]; then state=cur; seen=1
        elif [[ $seen -eq 0 ]]; then state="done"   # also: every step when $cur isn't a step
        else state=todo; fi
        case $state in
            done) line+="${T}${SYM_DONE}${R} ${D}${name}${R}${GAP}" ;;
            cur)  line+="${P}${SYM_CUR}${R} ${X}${B}${name}${R}${GAP}" ;;
            todo) line+="${O}${SYM_TODO}${R} ${D}${name}${R}${GAP}" ;;
        esac
    done
    at 4 3; out "$line"
}

footer() {  # footer "key" "label" ["key" "label" ...]
    local line=""
    while (( $# )); do line+="${P}${B}$1${R} ${D}$2${R}    "; shift 2; done
    out $'\e7'; at "$ROWS" 3; out "$line"; out $'\e8'   # save/restore cursor
}

screen() {  # screen STEP "Title" "Subtitle"
    cls; header "$1"
    at 6 3; out "${X}${B}$2${R}"
    [[ -n ${3:-} ]] && { at 7 3; out "${D}$3${R}"; }
    at 9 1
}

card() {  # card ROW "line" "line" ...   (outline border, 2-col padding)
    local row=$1; shift
    local w=$(( COLS - 6 )) l pad
    at "$row" 3; out "${O}${BX[0]}$(rep "${BX[4]}" $(( w - 2 )))${BX[1]}${R}"
    for l in "$@"; do
        row=$((row + 1)); pad=$(( w - 4 - $(vlen "$l") )); (( pad < 0 )) && pad=0
        at "$row" 3; out "${O}${BX[5]}${R} ${l}$(rep " " "$pad") ${O}${BX[5]}${R}"
    done
    row=$((row + 1))
    at "$row" 3; out "${O}${BX[2]}$(rep "${BX[4]}" $(( w - 2 )))${BX[3]}${R}"
}

err_line() { at 8 3; out "${E}${SYM_FAIL} $1${R}"; }

# ---------- keyboard input ----------
# Prints one of: up down left right home end enter esc space tab backspace
# delete other, or "char:X" for a printable character.
read_key() {
    local k r1="" r2="" r3=""
    IFS= read -rsn1 k </dev/tty || { echo esc; return; }
    case $k in
        $'\e')
            IFS= read -rsn1 -t 0.05 r1 </dev/tty || { echo esc; return; }   # lone Esc
            if [[ $r1 == "[" || $r1 == "O" ]]; then
                IFS= read -rsn1 -t 0.05 r2 </dev/tty || true
                case $r2 in
                    A) echo up ;; B) echo down ;; C) echo right ;; D) echo left ;;
                    H) echo home ;; F) echo end ;;
                    [0-9])
                        IFS= read -rsn1 -t 0.05 r3 </dev/tty || true
                        case "$r2$r3" in
                            1~|7~) echo home ;; 4~|8~) echo end ;; 3~) echo delete ;;
                            *) while IFS= read -rsn1 -t 0.01 _ </dev/tty; do :; done; echo other ;;
                        esac ;;
                    *) echo other ;;
                esac
            else
                echo other
            fi ;;
        "")              echo enter ;;
        " ")             echo space ;;
        $'\t')           echo tab ;;
        $'\x7f'|$'\b')   echo backspace ;;
        *)               printf 'char:%s\n' "$k" ;;
    esac
}

cancelled() {
    ui_restore; UI=plain   # UI=plain: the exit trap must not clear the screen again
    echo "Installer cancelled. No changes were made to your system configuration."
    exit 0
}

hide_cursor() { printf '\e[?25l' >/dev/tty; }
show_cursor() { printf '\e[?25h' >/dev/tty; }

# Key hints, with Backspace shown the way the console font can draw it.
BKSP_KEY="⌫"
nav_footer() {  # nav_footer [extra key label ...] — adds move / back / quit
    local extra=("$@")
    footer "↑↓" "move" "${extra[@]}" "$BKSP_KEY" "back" "esc" "quit"
}

# Info screens: Enter continues, Backspace goes back (returns 2), Esc quits.
press_continue() {  # press_continue ROW [label] [allow_back=1]
    local allow_back=${3:-1}
    at "$1" 3; out "$(pill "${2:-Continue}" "$BP")"
    if [[ $INSTALL_STARTED -eq 1 ]]; then footer "enter" "continue"
    elif [[ $allow_back -eq 1 ]]; then footer "enter" "continue" "$BKSP_KEY" "back" "esc" "quit"
    else footer "enter" "continue" "esc" "quit"; fi
    hide_cursor
    while true; do
        case "$(read_key)" in
            enter) show_cursor; return 0 ;;
            esc)   show_cursor; [[ $INSTALL_STARTED -eq 0 ]] && cancelled; return 0 ;;
            backspace|left) [[ $INSTALL_STARTED -eq 0 && $allow_back -eq 1 ]] && { show_cursor; return 2; } ;;
        esac
    done
}

# ---------- list widgets ----------
# Items are "name|description|value". The choice is left in ANSWER.
#   return 0 = chosen, 2 = back (Backspace / ←); Esc quits the installer.
ANSWER=""
fit() {  # fit TEXT MAX — shorten to MAX columns
    local t=$1 m=$2
    (( ${#t} <= m )) && { printf '%s' "$t"; return; }
    if [[ $IS_CONSOLE -eq 1 ]]; then printf '%s..' "${t:0:m-2}"; else printf '%s…' "${t:0:m-1}"; fi
}

_items_parse() {  # fills _NAME _DESC _VAL _OFF and _W (name column width)
    _NAME=(); _DESC=(); _VAL=(); _OFF=(); _W=0
    local it n d v x
    for it in "$@"; do
        IFS='|' read -r n d v x <<< "$it"
        _NAME+=("$n"); _DESC+=("$d"); _VAL+=("$v"); _OFF+=("${x:-0}")
        (( ${#n} > _W )) && _W=${#n}
    done
    # descriptions: whatever fits after "› ◉ name  " on this screen
    local i max=$(( COLS - 4 - 4 - _W - 2 - 1 ))
    for i in "${!_DESC[@]}"; do _DESC[i]="$(fit "${_DESC[i]}" "$max")"; done
}

menu() {  # menu ROW CURRENT_VALUE item...   (item 4th field "1" = greyed out)
    local row=$1 cur=$2; shift 2
    _items_parse "$@"
    local n=${#_VAL[@]} i sel=0 k line top=0
    # Scroll when the list is taller than the space above the footer.
    local h=$(( ROWS - row - 3 )); (( h > n )) && h=$n; (( h < 3 )) && h=3
    for i in "${!_VAL[@]}"; do [[ ${_VAL[i]} == "$cur" ]] && sel=$i; done
    hide_cursor
    while true; do
        (( sel < top )) && top=$sel
        (( sel >= top + h )) && top=$(( sel - h + 1 ))
        for (( i = top; i < top + h && i < n; i++ )); do
            if (( _OFF[i] )); then
                line="$( (( i == sel )) && printf '%s' "${P}${SYM_ARROW}${R}" || printf ' ')"
                line+=" ${O}$(printf "%-${_W}s" "${_NAME[i]}")  ${_DESC[i]}${R}"
            elif (( i == sel )); then
                line="${P}${B}${SYM_ARROW}${R} ${P}${B}$(printf "%-${_W}s" "${_NAME[i]}")${R}  ${X}${_DESC[i]}${R}"
            else
                line="  ${X}$(printf "%-${_W}s" "${_NAME[i]}")${R}  ${D}${_DESC[i]}${R}"
            fi
            at $(( row + i - top )) 3; out "${line}${EL}"
        done
        if (( n > h )); then   # scroll hint under the list
            local more=""
            (( top > 0 )) && more+="↑ ${top} more  "
            (( top + h < n )) && more+="↓ $(( n - top - h )) more"
            at $(( row + h )) 5; out "${D}${more}${R}${EL}"
        fi
        k="$(read_key)"
        case $k in
            up)    sel=$(( (sel - 1 + n) % n )) ;;
            down|tab) sel=$(( (sel + 1) % n )) ;;
            home)  sel=0 ;;
            end)   sel=$(( n - 1 )) ;;
            enter|right)
                if (( _OFF[sel] )); then err_line "${_NAME[sel]}: ${_DESC[sel]}"; continue; fi
                at 8 3; out "$EL"
                ANSWER=${_VAL[sel]}; show_cursor; return 0 ;;
            backspace|left) [[ $INSTALL_STARTED -eq 0 ]] && { show_cursor; return 2; } ;;
            esc)   show_cursor; [[ $INSTALL_STARTED -eq 1 ]] && return 1; cancelled ;;
        esac
    done
}

# Multi-select. MIN=1: Enter with nothing ticked picks the highlighted item.
# ANSWER = ticked values, space separated, in list order.
checklist() {  # checklist ROW "ticked values (space separated)" MIN item...
    local row=$1 ticked=" $2 " min=$3; shift 3
    _items_parse "$@"
    local n=${#_VAL[@]} i sel=0 k line box on=()
    for i in "${!_VAL[@]}"; do [[ $ticked == *" ${_VAL[i]} "* && ${_OFF[i]} -eq 0 ]] && on[i]=1 || on[i]=0; done
    local note_row=$(( row + n + 1 ))
    hide_cursor
    while true; do
        for i in "${!_VAL[@]}"; do
            if (( on[i] )); then box="${S}${B}${SYM_ON}${R}"; else box="${O}${SYM_OFF}${R}"; fi
            if (( _OFF[i] )); then
                line="$( (( i == sel )) && printf '%s' "${P}${SYM_ARROW}${R}" || printf ' ')"
                line+=" ${O}${SYM_OFF}${R} ${O}$(printf "%-${_W}s" "${_NAME[i]}")  ${_DESC[i]}${R}"
            elif (( i == sel )); then
                line="${P}${B}${SYM_ARROW}${R} ${box} ${P}${B}$(printf "%-${_W}s" "${_NAME[i]}")${R}  ${X}${_DESC[i]}${R}"
            elif (( on[i] )); then
                line="  ${box} ${S}$(printf "%-${_W}s" "${_NAME[i]}")${R}  ${D}${_DESC[i]}${R}"
            else
                line="  ${box} ${X}$(printf "%-${_W}s" "${_NAME[i]}")${R}  ${D}${_DESC[i]}${R}"
            fi
            at $(( row + i )) 3; out "${line}${EL}"
        done
        k="$(read_key)"
        case $k in
            up)    sel=$(( (sel - 1 + n) % n )) ;;
            down|tab) sel=$(( (sel + 1) % n )) ;;
            home)  sel=0 ;;
            end)   sel=$(( n - 1 )) ;;
            space|char:x)
                if (( _OFF[sel] )); then at "$note_row" 3; out "${E}${SYM_FAIL} ${_NAME[sel]}: ${_DESC[sel]}${R}${EL}"
                else on[sel]=$(( 1 - on[sel] )); fi ;;
            enter|right)
                local count=0; for i in "${!_VAL[@]}"; do (( on[i] )) && count=$((count + 1)); done
                if (( min > 0 && count == 0 )); then   # nothing ticked: take the highlighted one
                    if (( _OFF[sel] )); then
                        at "$note_row" 3; out "${E}${SYM_FAIL} ${_NAME[sel]}: ${_DESC[sel]}. Pick another one.${R}${EL}"; continue
                    fi
                    on[sel]=1
                fi
                ANSWER=""
                for i in "${!_VAL[@]}"; do (( on[i] )) && ANSWER+="${_VAL[i]} "; done
                ANSWER=${ANSWER% }
                show_cursor; return 0 ;;
            backspace|left) show_cursor; return 2 ;;
            esc)   show_cursor; cancelled ;;
        esac
    done
}

# Text field. Backspace edits; Backspace on an empty field goes back.
text_input() {  # text_input ROW INITIAL PLACEHOLDER [mask]
    local row=$1 text=$2 ph=$3 mask=${4:-0} k shown
    show_cursor
    while true; do
        if [[ -z $text ]]; then shown="${D}${ph}${R}"
        elif [[ $mask -eq 1 ]]; then shown="${X}$(rep "${SYM_BUL}" ${#text})${R}"
        else shown="${X}${text}${R}"; fi
        at "$row" 3; out "${P}${B}${SYM_ARROW}${R} ${shown}${EL}"
        # put the terminal cursor at the end of the typed text
        if [[ -z $text ]]; then at "$row" 5; else at "$row" $(( 5 + ${#text} )); fi
        k="$(read_key)"
        case $k in
            char:*) (( ${#text} < 64 )) && text+="${k#char:}" ;;
            space)  [[ $mask -eq 1 ]] && (( ${#text} < 64 )) && text+=" " ;;
            backspace)
                if [[ -z $text ]]; then return 2; fi
                text=${text%?} ;;
            enter)  ANSWER=$text; return 0 ;;
            esc)    cancelled ;;
        esac
    done
}

# ---------- UI setup ----------
init_ui() {
    [[ $ASSUME_YES -eq 1 || $NO_TUI -eq 1 || $HAVE_TTY -eq 0 ]] && return 0
    read -r ROWS COLS < <(stty size </dev/tty 2>/dev/null || echo "24 80")
    if (( ROWS < 22 || COLS < 76 )); then
        warn "Terminal is ${COLS}x${ROWS}; the installer UI needs at least 76x22 — using plain prompts."
        return 0
    fi
    (( COLS > 100 )) && COLS=100
    # Make sure bash handles the UI's UTF-8 characters.
    if locale -a 2>/dev/null | grep -qi '^c\.utf-\?8$'; then export LC_ALL=C.UTF-8; fi
    UI=tui
    setup_theme
    [[ $IS_CONSOLE -eq 1 ]] && BKSP_KEY="bksp"
    build_steps
}

# ---------- TUI pages ----------
# Each page returns 0 = next, 2 = back, 3 = not shown (skip in the same direction).
existing_users() { getent passwd | awk -F: '$3>=1000 && $3<60000 && $7 !~ /(nologin|false)$/ {print $1}'; }

p_welcome() {
    screen "Welcome" "" ""
    at 7 5;  out "${P}${B}█▄ █ █▀█ █▀▀ ▀█▀ ▄▀█ █   █ ▄▀█${R}"
    at 8 5;  out "${P}${B}█ ▀█ █▄█ █▄▄  █  █▀█ █▄▄ █ █▀█${R}"
    at 10 5; out "${X}A complete Noctalia v5 desktop on the compositor you choose.${R}"
    local laptop dm
    [[ $IS_LAPTOP -eq 1 ]] && laptop="$(pill laptop "$BS")" || laptop="$(pill desktop "$BS")"
    [[ -n $CURRENT_DM ]] && dm="$(pill "$CURRENT_DM" "$BO" "$X")" || dm="$(pill "no login manager" "$BO" "$X")"
    local lines=(
        "${P}${SYM_BUL}${R} ${X}Noctalia v5${R}       ${D}bar, launcher, notifications, lock${R}"
        "${P}${SYM_BUL}${R} ${X}8 compositors${R}     ${D}niri, Hyprland, Sway, Scroll, Mango, Labwc,${R}"
        "                    ${D}Umbriel or KDE Plasma, each preconfigured${R}"
    )
    if [[ $CONFIGS_ONLY -eq 1 ]]; then
        lines+=("${P}${SYM_BUL}${R} ${X}Configs only${R}      ${D}you install the packages yourself${R}")
    else
        [[ $GREETER_DISTRO -eq 1 ]] && lines+=("${P}${SYM_BUL}${R} ${X}Noctalia Greeter${R}  ${D}optional login screen (greetd)${R}")
        if [[ $FAMILY == arch ]]; then lines+=("${P}${SYM_BUL}${R} ${X}yay or paru${R}       ${D}optional AUR helper${R}")
        else lines+=("${P}${SYM_BUL}${R} ${X}Packages${R}          ${D}from ${FAMILY_LABEL} and Noctalia's repository${R}"); fi
    fi
    card 12 "${lines[@]}"
    at 19 5; out "${D}Detected${R}  $(pill "$FAMILY_LABEL" "$BP") ${laptop} ${dm}"
    if [[ $CONFIGS_ONLY -eq 1 ]]; then
        at 20 5; out "${P}Configs only:${R} ${D}${FAMILY_NOTE:0:$(( COLS - 22 ))}${R}"
    fi
    at 21 5; out "${D}Nothing changes until you confirm the review.${R}"
    press_continue 22 "Get started" 0
}

USER_PRESET=0   # --user=NAME for an existing user: no user pages
p_user() {
    [[ $IS_ROOT -eq 1 && $USER_PRESET -eq 0 ]] || return 3
    local users opts=() u cur
    mapfile -t users < <(existing_users)
    for u in "${users[@]}"; do opts+=("$u|existing user|$u"); done
    opts+=("Create a new user|added to wheel · sudo enabled|+new")
    cur=$TARGET_USER; [[ $CREATE_USER -eq 1 ]] && cur="+new"
    screen "User" "Who is this desktop for?" "You're running as root. Pick a user, or create one."
    nav_footer "enter" "select"
    menu 9 "$cur" "${opts[@]}" || return 2
    if [[ $ANSWER == "+new" ]]; then
        [[ $CREATE_USER -eq 0 ]] && TARGET_USER=""
        CREATE_USER=1
    else
        CREATE_USER=0; TARGET_USER=$ANSWER
    fi
}

p_newname() {
    [[ $CREATE_USER -eq 1 ]] || return 3
    local errmsg=""
    while true; do
        screen "User" "Create a user" "Lowercase letters, digits, - or _. Gets sudo via the wheel group."
        [[ -n $errmsg ]] && err_line "$errmsg"
        footer "enter" "continue" "$BKSP_KEY" "back (when empty)" "esc" "quit"
        text_input 9 "$TARGET_USER" "username" || return 2
        if [[ ! $ANSWER =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then errmsg="'$ANSWER' isn't a valid username."; TARGET_USER=$ANSWER
        elif id "$ANSWER" &>/dev/null; then errmsg="'$ANSWER' already exists."; TARGET_USER=$ANSWER
        else TARGET_USER=$ANSWER; return 0; fi
    done
}

p_newpass() {
    [[ $CREATE_USER -eq 1 ]] || return 3
    local errmsg="" p1 p2
    while true; do
        screen "User" "Password for $TARGET_USER" "Type it twice. Only dots are shown."
        [[ -n $errmsg ]] && err_line "$errmsg"
        footer "enter" "continue" "$BKSP_KEY" "back (when empty)" "esc" "quit"
        at 9 3; out "${D}Password${R}"
        text_input 10 "" "password" 1 || return 2
        p1=$ANSWER
        at 12 3; out "${D}Repeat${R}"
        if ! text_input 13 "" "repeat password" 1; then errmsg=""; continue; fi   # back to the first field
        p2=$ANSWER
        if [[ -z $p1 ]]; then errmsg="The password can't be empty."
        elif [[ $p1 != "$p2" ]]; then errmsg="The passwords didn't match."
        else NEW_USER_PASS=$p1; return 0; fi
    done
}

p_desktop() {
    local opts=() row id name aur desc
    for row in "${COMP_TABLE[@]}"; do
        IFS='|' read -r id name _ aur _ desc <<< "$row"
        [[ -n $(comp_aur_pkgs "$id") ]] && desc+="  (AUR)"
        if [[ ${COMP_OK[$id]:-1} -eq 1 ]]; then opts+=("$name|$desc|$id|0")
        else opts+=("$name|${COMP_WHY[$id]}|$id|1"); fi
    done
    local sub="Space ticks one or more. Enter alone picks the highlighted one."
    [[ $CONFIGS_ONLY -eq 1 ]] && sub="Configs only on $FAMILY_LABEL: install the compositor yourself."
    screen "Desktop" "Choose your compositor" "$sub"
    nav_footer "space" "tick" "enter" "continue"
    local keep=() c
    for c in "${COMPS[@]}"; do [[ ${COMP_OK[$c]:-1} -eq 1 ]] && keep+=("$c"); done
    checklist 9 "${keep[*]}" 1 "${opts[@]}" || return 2
    read -ra COMPS <<< "$ANSWER"
    lid_supported || LID_FIX=0
}

p_extras() {
    local opts=() ticked=""
    if [[ $GREETER_DISTRO -eq 1 && $CONFIGS_ONLY -eq 0 ]]; then opts+=("Noctalia Greeter|login screen with greetd|greeter")
    else INSTALL_GREETER=0; fi
    opts+=(
        "Bar preset|floating · blurred · custom widgets|bar"
        "Wallpapers|6 wallpapers in Noctalia's colours|walls"
        "Type-to-launch|type in the overview to open the launcher|launch"
        "Polkit agent|Noctalia asks for app passwords|polkit"
        "File manager and browser|apps for Mod+E and Mod+B|apps"
    )
    [[ $IS_LAPTOP -eq 1 && $HAS_SYSTEMD -eq 1 && $CONFIGS_ONLY -eq 0 ]] && lid_supported && opts+=("Lid lock|lock before suspend on lid close|lid")
    [[ $SERVICES_DISTRO -eq 1 ]] && opts+=("Desktop services|NetworkManager, Bluetooth, power profiles|services")
    [[ $NVIDIA_DRIVER -eq 1 && $CONFIGS_ONLY -eq 0 ]] && opts+=("NVIDIA tweaks|modesetting and niri's VRAM fix|nvidia")
    [[ $INSTALL_GREETER -eq 1 ]] && ticked+="greeter "
    [[ $BAR_PRESET -eq 1 ]] && ticked+="bar "
    [[ $WALLPAPERS_ON -eq 1 ]] && ticked+="walls "
    [[ $TYPE_TO_LAUNCH -eq 1 ]] && ticked+="launch "
    [[ $POLKIT_AGENT -eq 1 ]] && ticked+="polkit "
    [[ $INSTALL_APPS -eq 1 ]] && ticked+="apps "
    [[ $LID_FIX -eq 1 ]] && ticked+="lid "
    [[ $SERVICES -eq 1 ]] && ticked+="services "
    [[ $NVIDIA_FIX -eq 1 ]] && ticked+="nvidia "
    local sub="Noctalia, portals, audio, fonts and a terminal are always installed."
    [[ $CONFIGS_ONLY -eq 1 ]] && sub="Configs only: these settings go into the configs written."
    screen "Extras" "Choose your extras" "$sub"
    nav_footer "space" "toggle" "enter" "continue"
    checklist 9 "$ticked" 0 "${opts[@]}" || return 2
    INSTALL_GREETER=0; TYPE_TO_LAUNCH=0; POLKIT_AGENT=0; INSTALL_APPS=0; LID_FIX=0; BAR_PRESET=0; WALLPAPERS_ON=0; SERVICES=0; NVIDIA_FIX=0
    local v
    for v in $ANSWER; do
        case $v in
            greeter) INSTALL_GREETER=1 ;; launch) TYPE_TO_LAUNCH=1 ;; polkit) POLKIT_AGENT=1 ;; bar) BAR_PRESET=1 ;; walls) WALLPAPERS_ON=1 ;;
            apps) INSTALL_APPS=1 ;; lid) LID_FIX=1 ;; services) SERVICES=1 ;; nvidia) NVIDIA_FIX=1 ;;
        esac
    done
}

p_wallpaper() {
    [[ $WALLPAPERS_ON -eq 1 ]] || return 3
    local opts=() row id desc
    for row in "${WALLPAPER_TABLE[@]}"; do
        IFS='|' read -r id desc <<< "$row"
        opts+=("${id^}|$desc|$id")
    done
    screen "Extras" "Wallpaper" "All six go to ~/Pictures/Wallpapers; pick the one to start with."
    nav_footer "enter" "select"
    menu 9 "$WALLPAPER" "${opts[@]}" || return 2
    WALLPAPER=$ANSWER
}

p_aur() {
    [[ $FAMILY == arch ]] || { AUR_HELPER=none; return 3; }
    local sub opts=() cur errmsg=""
    if needs_aur; then sub="$(aur_comp_names) is only in the AUR, so it needs a helper."
    else sub="Optional. AUR browsers use it; without one they come from Flathub."; fi
    [[ -n $EXISTING_HELPER ]] && opts+=("Use installed $EXISTING_HELPER|already on this system|$EXISTING_HELPER")
    [[ $EXISTING_HELPER != paru ]] && opts+=("paru|fast · written in Rust|paru")
    [[ $EXISTING_HELPER != yay ]] && opts+=("yay|popular · written in Go|yay")
    opts+=("None|skip the AUR|none")
    cur=$AUR_HELPER; [[ $cur == auto ]] && cur="$(default_helper)"
    while true; do
        screen "Extras" "AUR helper" "$sub"
        [[ -n $errmsg ]] && err_line "$errmsg"
        nav_footer "enter" "select"
        menu 9 "$cur" "${opts[@]}" || return 2
        if [[ $ANSWER == none ]] && needs_aur; then
            errmsg="$(aur_comp_names) needs a helper. Pick one, or go back and untick it."
            cur=none; continue
        fi
        AUR_HELPER=$ANSWER; return 0
    done
}

p_term() {
    screen "Apps" "Terminal" "Opens with Mod+Return. Always installed."
    nav_footer "enter" "select"
    menu 9 "$TERM_APP" \
        "Alacritty|fast and simple · GPU accelerated|alacritty" \
        "Kitty|GPU · tabs · inline images|kitty" \
        "Foot|tiny and Wayland-native|foot" \
        "Ghostty|modern and GPU accelerated|ghostty" \
        "WezTerm|GPU with a built-in multiplexer|wezterm" || return 2
    TERM_APP=$ANSWER
}

p_fm() {
    [[ $INSTALL_APPS -eq 1 ]] || return 3
    if [[ ${FM_SCANNED:-0} -eq 0 && $CONFIGS_ONLY -eq 0 ]]; then
        screen "Apps" "File manager" "Checking which file managers $FAMILY_LABEL packages…"
    fi
    fm_scan
    local opts=() row id name desc
    for row in "${FM_TABLE[@]}"; do
        IFS='|' read -r id name desc _ <<< "$row"
        if [[ -n ${FM_PKG[$id]} ]]; then opts+=("$name|$desc|$id|0")
        else opts+=("$name|not in your repositories|$id|1"); fi
    done
    opts+=("None|leave Mod+E unbound|none|0")
    local cur=$FM_APP; [[ $cur != none && -z ${FM_PKG[$cur]:-} ]] && cur=none
    screen "Apps" "File manager" "Opens with Mod+E. Terminal ones open in $(printf '%s' "$TERM_APP")."
    nav_footer "enter" "select"
    menu 9 "$cur" "${opts[@]}" || return 2
    FM_APP=$ANSWER
}

p_browser() {
    [[ $INSTALL_APPS -eq 1 ]] || return 3
    local opts=() row id name desc src tag
    for row in "${BROWSER_TABLE[@]}"; do
        IFS='|' read -r id name desc _ <<< "$row"
        tag=""
        if [[ $CONFIGS_ONLY -eq 0 ]]; then
            src="$(browser_source "$id")"
            case $src in
                aur) tag="  (AUR)" ;;
                flatpak) tag="  (Flathub)"; [[ $id == mullvad ]] && tag="  (Flathub, unofficial)" ;;
            esac
        fi
        opts+=("$name|$desc$tag|$id")
    done
    opts+=("None|leave Mod+B unbound|none")
    screen "Apps" "Browser" "Opens with Mod+B. Your distribution's package is used when there is one."
    nav_footer "enter" "select"
    menu 9 "$BROWSER_APP" "${opts[@]}" || return 2
    BROWSER_APP=$ANSWER
}

p_keyboard() {
    local errmsg=""
    while true; do
        screen "Keyboard" "Keyboard layout" "xkb layout(s), comma separated. Examples: us  de  fr  us,ru"
        [[ -n $errmsg ]] && err_line "$errmsg"
        footer "enter" "continue" "$BKSP_KEY" "back (when empty)" "esc" "quit"
        text_input 9 "$KB_LAYOUT" "us" || return 2
        if [[ $ANSWER =~ ^[a-z]{2,}(,[a-z]{2,})*$ ]]; then KB_LAYOUT=$ANSWER; return 0; fi
        errmsg="'$ANSWER' doesn't look like an xkb layout list."
    done
}

p_dm() {
    [[ $INSTALL_GREETER -eq 1 && -n $CURRENT_DM ]] || { SWITCH_DM=1; return 3; }
    screen "Review" "Replace $CURRENT_DM?" "Two login managers can't run together."
    card 9 \
        "${X}${CURRENT_DM}${R} ${D}is your current login manager. Replacing it disables${R}" \
        "${D}it and enables greetd with Noctalia Greeter after the next reboot.${R}" \
        "${D}Your current session keeps running.${R}"
    nav_footer "enter" "select"
    menu 15 "$([[ $SWITCH_DM -eq 1 ]] && echo yes || echo no)" \
        "Replace it|use Noctalia Greeter|yes" \
        "Keep $CURRENT_DM|the greeter is installed but not enabled|no" || return 2
    [[ $ANSWER == yes ]] && SWITCH_DM=1 || SWITCH_DM=0
}

p_review() {
    [[ $AUR_HELPER == auto ]] && AUR_HELPER="$(default_helper)"
    screen "Review" "Ready to install" "Check your choices. Nothing has changed yet."
    local user_txt="$TARGET_USER" apps_txt="$TERM_APP" greeter_txt desk_txt aur_txt
    [[ $CREATE_USER -eq 1 ]] && user_txt="$TARGET_USER ${D}(new, sudo)${R}"
    if [[ $INSTALL_APPS -eq 1 ]]; then
        local bname="none"; [[ $BROWSER_APP != none ]] && bname="$(browser_field "$BROWSER_APP" 2)"
        local fname="none"; [[ $FM_APP != none ]] && fname="$(fm_field "$FM_APP" 2)"
        apps_txt="$TERM_APP, $fname, $bname"
    fi
    if [[ $INSTALL_GREETER -eq 0 ]]; then greeter_txt="${D}off${R}"
    elif [[ -n $CURRENT_DM && $SWITCH_DM -eq 0 ]]; then greeter_txt="installed ${D}(keeps $CURRENT_DM)${R}"
    elif [[ -n $CURRENT_DM ]]; then greeter_txt="Noctalia Greeter ${D}(replaces $CURRENT_DM)${R}"
    else greeter_txt="Noctalia Greeter"; fi
    desk_txt="$(comp_names)"
    if (( ${#desk_txt} > 50 )); then desk_txt="$(comp_field "${COMPS[0]}" 2), $(comp_field "${COMPS[1]}" 2) ${D}+$(( ${#COMPS[@]} - 2 )) more${R}"; fi
    case $AUR_HELPER in
        none) aur_txt="${D}none${R}" ;;
        "$EXISTING_HELPER") aur_txt="$AUR_HELPER ${D}(already installed)${R}" ;;
        *) aur_txt="$AUR_HELPER ${D}(will be installed)${R}" ;;
    esac
    local row4_label="AUR helper  " row4_txt=$aur_txt
    [[ $FAMILY != arch ]] && { row4_label="System      "; row4_txt="$FAMILY_LABEL"; }
    local core_txt
    if [[ $CONFIGS_ONLY -eq 1 ]]; then core_txt="configs only ${D}(install packages yourself)${R}"
    elif [[ $FAMILY == arch ]]; then core_txt="noctalia, portals, pipewire, fonts ${D}+ pacman -Syu${R}"
    else core_txt="noctalia, portals, pipewire, fonts ${D}(${FAMILY_LABEL})${R}"; fi
    local yes_chip="${T}${SYM_DONE} on${R}" off="${D}${SYM_TODO} off${R}" tl pa ll
    [[ $TYPE_TO_LAUNCH -eq 1 ]] && tl=$yes_chip || tl=$off
    [[ $POLKIT_AGENT -eq 1 ]] && pa=$yes_chip || pa=$off
    [[ $LID_FIX -eq 1 ]] && ll=$yes_chip || ll=$off
    local bp; [[ $BAR_PRESET -eq 1 ]] && bp=$yes_chip || bp=$off
    local sys_txt="${D}services${R} " nv
    if [[ $SERVICES_DISTRO -eq 0 ]]; then sys_txt+="${D}n/a${R}"
    elif [[ $SERVICES -eq 1 ]]; then sys_txt+=$yes_chip; else sys_txt+=$off; fi
    if [[ $NVIDIA_DRIVER -eq 1 && $CONFIGS_ONLY -eq 0 ]]; then
        [[ $NVIDIA_FIX -eq 1 ]] && nv=$yes_chip || nv=$off
        sys_txt+="  ${D}NVIDIA tweaks${R} ${nv}"
    fi
    local wp_txt="${D}Noctalia's default${R}"; [[ $WALLPAPERS_ON -eq 1 ]] && wp_txt="${WALLPAPER^} ${D}(+5 more in ~/Pictures/Wallpapers)${R}"
    card 8 \
        "${D}User        ${R}${X}${user_txt}${R}" \
        "${D}Desktop     ${R}${X}${desk_txt}${R}" \
        "${D}Core        ${R}${X}${core_txt}${R}" \
        "${D}${row4_label}${R}${X}${row4_txt}${R}" \
        "${D}Apps        ${R}${X}${apps_txt}${R}" \
        "${D}Keyboard    ${R}${X}${KB_LAYOUT}${R}" \
        "${D}Wallpaper   ${R}${X}${wp_txt}${R}" \
        "${D}Login       ${R}${X}${greeter_txt}${R}" \
        "${D}Extras      ${R}${D}bar${R} ${bp}  ${D}type-to-launch${R} ${tl}  ${D}polkit${R} ${pa}  ${D}lid${R} ${ll}" \
        "${D}System      ${R}${sys_txt}"
    nav_footer "enter" "select"
    local go="Install now|start the installation|install"
    [[ $DRY_RUN -eq 1 ]] && go="Show the plan|dry run: list what would change, change nothing|install"
    menu 20 install \
        "$go" \
        "Change my choices|back to the compositor list|change" \
        "Quit|leave without changing anything|quit" || return 2
    case $ANSWER in
        install) return 0 ;;
        change)  return 4 ;;
        *)       cancelled ;;
    esac
}

# Wizard: Backspace walks back through the pages, skipping hidden ones.
PAGES=(p_welcome p_user p_newname p_newpass p_desktop p_extras p_wallpaper p_aur p_term p_fm p_browser p_keyboard p_dm p_review)
tui_decisions() {
    if [[ $IS_ROOT -eq 1 && -n $TARGET_USER ]]; then
        if id "$TARGET_USER" &>/dev/null; then USER_PRESET=1; else CREATE_USER=1; fi
    fi
    [[ $IS_ROOT -eq 0 ]] && TARGET_USER="$(id -un)"
    # Start the compositor list unticked, so Enter picks the highlighted one.
    [[ $COMPS_FROM_FLAG -eq 0 ]] && COMPS=()
    local i=0 dir=1 rc desktop_i=0 j
    for j in "${!PAGES[@]}"; do [[ ${PAGES[j]} == p_desktop ]] && desktop_i=$j; done
    while (( i < ${#PAGES[@]} )); do
        if "${PAGES[i]}"; then rc=0; else rc=$?; fi
        case $rc in
            0) dir=1; i=$(( i + 1 )) ;;
            2) dir=-1; i=$(( i - 1 )) ;;
            3) i=$(( i + dir )) ;;
            4) dir=1; i=$desktop_i ;;
        esac
        (( i < 0 )) && { i=0; dir=1; }
    done
    return 0   # the loop's last test is usually false; don't let set -e see that
}

plain_decisions() {
    if [[ $IS_ROOT -eq 1 ]]; then
        local users; mapfile -t users < <(existing_users)
        if [[ -z $TARGET_USER ]]; then
            (( ${#users[@]} == 1 )) || die "Running as root: pass --user=NAME (existing users: ${users[*]:-none}). To create a user, use the TUI."
            TARGET_USER="${users[0]}"
        fi
        id "$TARGET_USER" &>/dev/null || die "User '$TARGET_USER' doesn't exist. Create it first or use the TUI."
    else
        TARGET_USER="$(id -un)"
    fi
    plain_ask() {  # plain_ask "question" default
        local q="$1" def="$2" reply
        [[ $ASSUME_YES -eq 1 ]] && { [[ $def == y ]]; return; }
        [[ $def == y ]] && q+=" [Y/n] " || q+=" [y/N] "
        read -r -p "$q" reply </dev/tty || reply=""
        [[ ${reply:-$def} =~ ^[Yy] ]]
    }
    [[ $GREETER_DISTRO -eq 1 && $CONFIGS_ONLY -eq 0 ]] || INSTALL_GREETER=0
    if [[ $INSTALL_GREETER -eq 1 ]]; then plain_ask "Install Noctalia Greeter (login screen) with greetd?" y || INSTALL_GREETER=0; fi
    if [[ $INSTALL_GREETER -eq 1 && -n $CURRENT_DM ]]; then plain_ask "Disable $CURRENT_DM and use greetd?" y || SWITCH_DM=0; fi
    if [[ $IS_LAPTOP -eq 1 && $LID_FIX -eq 0 ]] && lid_supported; then plain_ask "Laptop detected. Lock before suspend on lid close?" n && LID_FIX=1; fi
    lid_supported || LID_FIX=0
    [[ $HAS_SYSTEMD -eq 1 && $CONFIGS_ONLY -eq 0 ]] || LID_FIX=0
    [[ $GREETER_DISTRO -eq 1 && $CONFIGS_ONLY -eq 0 ]] || INSTALL_GREETER=0
    for c in "${COMPS[@]}"; do
        [[ ${COMP_OK[$c]:-1} -eq 1 ]] || die "$(comp_field "$c" 2) can't be installed here: ${COMP_WHY[$c]}."
    done
    if [[ $INSTALL_APPS -eq 1 && $FM_APP != none && $CONFIGS_ONLY -eq 0 ]]; then
        fm_scan
        [[ -n ${FM_PKG[$FM_APP]} ]] || die "$(fm_field "$FM_APP" 2) isn't in your repositories on $FAMILY_LABEL; pick another --file-manager."
    fi
    [[ $AUR_HELPER == auto ]] && AUR_HELPER="$(default_helper)"
    if [[ $AUR_HELPER == none ]] && needs_aur; then die "$(aur_comp_names) is only in the AUR: use --aur-helper=paru or yay."; fi
    info "Compositors: $(comp_names) | AUR helper: $AUR_HELPER"
    info "User: $TARGET_USER | apps: $([[ $INSTALL_APPS -eq 1 ]] && echo "$TERM_APP $FM_APP $BROWSER_APP" || echo "$TERM_APP") | layout: $KB_LAYOUT"
    [[ $SERVICES_DISTRO -eq 1 ]] && info "Desktop services: $([[ $SERVICES -eq 1 ]] && echo on || echo off)$([[ $NVIDIA_FIX -eq 1 ]] && echo " | NVIDIA tweaks: on")"
    [[ $DRY_RUN -eq 1 ]] && return 0
    if [[ $CONFIGS_ONLY -eq 1 ]]; then
        info "Configs only on $FAMILY_LABEL: $FAMILY_NOTE"
        plain_ask "Write the configs now?" y || die "Aborted."
    else
        plain_ask "Continue with installation on $FAMILY_LABEL?" y || die "Aborted."
    fi
}

# =====================================================================
#  Install steps
# =====================================================================
# Step list for the install screen (id|label), built from the choices.
INSTALL_STEPS=()
# Packages for the current choices -> PK_ESSENTIAL, PK_OPTIONAL, PK_BACKPORTS.
# Essential ones must exist; optional ones are skipped when missing.
collect_packages() {
    PK_ESSENTIAL=(); PK_OPTIONAL=(); PK_BACKPORTS=()
    local c g p cp line
    addp() { local -n _arr=$1; local _t=(); read -ra _t <<< "$2"; _arr+=("${_t[@]}"); }   # addp ARRAY "pkg pkg"
    addp PK_ESSENTIAL "$(pkgs noctalia)"
    for c in "${COMPS[@]}"; do
        cp="$(comp_repo_pkgs "$c")"
        [[ -z $cp ]] && continue
        PK_ESSENTIAL+=("${cp%% *}")
        [[ $cp == *" "* ]] && addp PK_OPTIONAL "${cp#* }"
    done
    for g in portal-gtk keyring audio media fonts; do addp PK_OPTIONAL "$(pkgs "$g")"; done
    addp PK_ESSENTIAL "$(pkgs "$TERM_APP")"   # always: Mod+Return is your way in
    if [[ $INSTALL_APPS -eq 1 && $FM_APP != none ]]; then
        fm_scan; [[ -n ${FM_PKG[$FM_APP]} ]] && PK_OPTIONAL+=("${FM_PKG[$FM_APP]}")
    fi
    [[ $INSTALL_GREETER -eq 1 ]] && addp PK_ESSENTIAL "$(pkgs greeter)"
    if [[ $INSTALL_GREETER -eq 1 || $POLKIT_AGENT -eq 1 ]]; then addp PK_OPTIONAL "$(pkgs polkit)"; fi
    if [[ $AUR_HELPER != none ]]; then PK_OPTIONAL+=(base-devel git); [[ $IS_ROOT -eq 1 ]] && PK_OPTIONAL+=(sudo); fi
    while IFS=$'\t' read -r _ line; do addp PK_OPTIONAL "$line"; done < <(service_plan)

    # Debian trixie: the greeter and Umbriel come from trixie-backports.
    if [[ $FAMILY == debian && $DEB_SUITE == trixie ]]; then
        local keep=()
        for p in "${PK_ESSENTIAL[@]}"; do
            case $p in noctalia-greeter|umbriel|xdg-desktop-portal-umbriel) PK_BACKPORTS+=("$p") ;; *) keep+=("$p") ;; esac
        done
        PK_ESSENTIAL=("${keep[@]}")
        for p in "${PK_OPTIONAL[@]}"; do [[ $p == xdg-desktop-portal-umbriel ]] && PK_BACKPORTS+=("$p"); done
    fi
    true
}

# Services worth enabling: prints "UNIT<TAB>packages" lines. Skips anything
# already enabled and anything that would fight another tool.
service_plan() {
    [[ $SERVICES -eq 1 ]] || return 0
    local u net=1
    for u in NetworkManager systemd-networkd connman netctl wicked; do unit_enabled "$u.service" && net=0; done
    [[ $net -eq 1 ]] && printf 'NetworkManager.service\t%s\n' "$(pkgs networkmanager)"
    if [[ $HAS_BT -eq 1 ]] && ! unit_enabled bluetooth.service; then
        printf 'bluetooth.service\t%s\n' "$(pkgs bluetooth)"
    fi
    if [[ $IS_LAPTOP -eq 1 ]]; then
        local power=1
        for u in power-profiles-daemon tuned tuned-ppd tlp auto-cpufreq; do unit_enabled "$u.service" && power=0; done
        [[ $power -eq 1 ]] && printf 'power-profiles-daemon.service\t%s\n' "$(pkgs power)"
    fi
    true
}

# NVIDIA tweaks: prints "FILE<TAB>what it does" for each file it would write.
NV_MODESET_FILE=/etc/modprobe.d/90-noctalia-nvidia.conf
NV_PROFILE_FILE=/etc/nvidia/nvidia-application-profiles-rc.d/50-noctalia-niri-vram.json
nvidia_plan() {
    [[ $NVIDIA_FIX -eq 1 ]] || return 0
    if [[ $(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null) != Y ]]; then
        printf '%s\t%s\n' "$NV_MODESET_FILE" "turn on NVIDIA kernel modesetting (Wayland needs it)"
    fi
    if has_comp niri && ! grep -rqs GLVidHeapReuseRatio /etc/nvidia/nvidia-application-profiles-rc.d/; then
        printf '%s\t%s\n' "$NV_PROFILE_FILE" "stop niri holding on to video memory (niri's NVIDIA fix)"
    fi
    true
}
apply_nvidia() {
    local f what
    while IFS=$'\t' read -r f what; do
        as_root mkdir -p "$(dirname "$f")"
        case $f in
            "$NV_MODESET_FILE")
                printf '# Written by noctalia-installer: Wayland compositors need modesetting\noptions nvidia_drm modeset=1\n' \
                    | as_root tee "$f" >/dev/null
                warn "NVIDIA modesetting turned on. Rebuild your initramfs (e.g. sudo mkinitcpio -P, sudo dracut -f or sudo update-initramfs -u) and reboot." ;;
            "$NV_PROFILE_FILE")
                cat <<'JSON' | as_root tee "$f" >/dev/null
{
    "rules": [
        {
            "pattern": { "feature": "procname", "matches": "niri" },
            "profile": "Limit Free Buffer Pool On Wayland Compositors"
        }
    ],
    "profiles": [
        {
            "name": "Limit Free Buffer Pool On Wayland Compositors",
            "settings": [ { "key": "GLVidHeapReuseRatio", "value": 0 } ]
        }
    ]
}
JSON
                ;;
        esac
        rec sysfile "$f"
        ok "NVIDIA: $what ($f)"
    done < <(nvidia_plan)
}

build_install_steps() {
    INSTALL_STEPS=()
    [[ $CREATE_USER -eq 1 ]] && INSTALL_STEPS+=("user|Create user $TARGET_USER")
    if [[ $CONFIGS_ONLY -eq 0 ]]; then
        [[ $FAMILY != arch ]] && INSTALL_STEPS+=("repos|Add the Noctalia repository")
        INSTALL_STEPS+=("pkgs|Install packages")
    fi
    [[ $AUR_HELPER != none && $AUR_HELPER != "$EXISTING_HELPER" ]] && INSTALL_STEPS+=("helper|Install $AUR_HELPER")
    needs_aur && INSTALL_STEPS+=("aur|Build $(aur_comp_names) from the AUR")
    if [[ $INSTALL_APPS -eq 1 && $BROWSER_APP != none && $CONFIGS_ONLY -eq 0 ]]; then
        INSTALL_STEPS+=("browser|Install $(browser_field "$BROWSER_APP" 2) ($(browser_source "$BROWSER_APP"))")
    fi
    INSTALL_STEPS+=("files|Write $(comp_names | cut -c1-40) config" "check|Validate configs")
    [[ $LID_FIX -eq 1 ]] && INSTALL_STEPS+=("lid|Configure lid close")
    if [[ $INSTALL_GREETER -eq 1 ]]; then INSTALL_STEPS+=("greeter|Set up Noctalia Greeter" "dm|Enable the login screen"); fi
    [[ $SERVICES -eq 1 ]] && INSTALL_STEPS+=("services|Enable desktop services")
    [[ $NVIDIA_FIX -eq 1 ]] && INSTALL_STEPS+=("nvidia|Apply NVIDIA tweaks")
    return 0
}

# ---------- --dry-run: show the plan, change nothing ----------
planned_files() {  # every file the install would write, one per line
    local c
    for c in "${COMPS[@]}"; do
        case $c in
            niri)     echo "$CONFIG_HOME/niri/config.kdl" ;;
            hyprland) echo "$CONFIG_HOME/hypr/hyprland.lua" ;;
            sway|scroll) echo "$CONFIG_HOME/$c/config" ;;
            mango)    echo "$CONFIG_HOME/mango/config.conf" ;;
            labwc)    printf '%s\n' "$CONFIG_HOME/labwc/rc.xml" "$CONFIG_HOME/labwc/autostart" "$CONFIG_HOME/labwc/environment" ;;
            umbriel)  echo "$CONFIG_HOME/umbriel/config.toml" ;;
            kde)      echo "$CONFIG_HOME/autostart/noctalia.desktop" ;;
        esac
    done
    echo "$CONFIG_HOME/noctalia/10-installer.toml"
    [[ $BAR_PRESET -eq 1 ]] && echo "$CONFIG_HOME/noctalia/20-bar.toml"
    if [[ $WALLPAPERS_ON -eq 1 ]]; then
        echo "$CONFIG_HOME/noctalia/30-wallpaper.toml"
        echo "$TARGET_HOME/Pictures/Wallpapers/noctalia-*.jpg (${#WALLPAPER_TABLE[@]} wallpapers)"
    fi
    true
}

print_plan() {
    local home
    if [[ $CREATE_USER -eq 1 ]]; then home="/home/$TARGET_USER"
    else home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"; fi
    TARGET_HOME=$home
    if [[ $IS_ROOT -eq 1 || $CREATE_USER -eq 1 ]]; then CONFIG_HOME="$home/.config"
    else CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"; fi

    echo
    info "Dry run on $FAMILY_LABEL: nothing has been changed. The installer would:"
    [[ $CREATE_USER -eq 1 ]] && echo "  • create the user $TARGET_USER (wheel group, sudo enabled)"
    if [[ $CONFIGS_ONLY -eq 1 ]]; then
        echo "  • install no packages ($FAMILY_NOTE)"
    else
        [[ $FAMILY != arch ]] && echo "  • add the Noctalia package repository for $FAMILY_LABEL"
        collect_packages
        echo "  • install: ${PK_ESSENTIAL[*]}"
        echo "  • install if available: ${PK_OPTIONAL[*]}"
        (( ${#PK_BACKPORTS[@]} )) && echo "  • install from trixie-backports: ${PK_BACKPORTS[*]}"
        [[ $AUR_HELPER != none && $AUR_HELPER != "$EXISTING_HELPER" ]] && echo "  • build $AUR_HELPER from the AUR"
        if needs_aur; then
            local c a=(); for c in "${COMPS[@]}"; do read -ra _t <<< "$(comp_aur_pkgs "$c")"; a+=("${_t[@]}"); done
            echo "  • build from the AUR: ${a[*]}"
        fi
        if [[ $INSTALL_APPS -eq 1 && $BROWSER_APP != none ]]; then
            echo "  • install $(browser_field "$BROWSER_APP" 2) ($(browser_source "$BROWSER_APP"))"
        fi
    fi
    echo "  • write these files (an existing file is backed up next to itself first):"
    local f
    while IFS= read -r f; do
        if [[ -e ${f%% *} ]]; then echo "      $f   (exists: backed up)"; else echo "      $f"; fi
    done < <(planned_files)
    has_comp hyprland && [[ -f $CONFIG_HOME/hypr/hyprland.conf ]] && echo "  • move $CONFIG_HOME/hypr/hyprland.conf aside (Hyprland then reads hyprland.lua)"
    has_comp kde && echo "  • turn on KWin's blur and add a KWin rule opening Noctalia settings maximized"
    [[ $LID_FIX -eq 1 ]] && echo "  • write /etc/systemd/logind.conf.d/10-noctalia-lid.conf (the compositor handles the lid)"
    if [[ $INSTALL_GREETER -eq 1 ]]; then
        echo "  • point greetd ($GREETD_CONF, backed up) at Noctalia Greeter"
        if [[ -n $CURRENT_DM && $SWITCH_DM -eq 1 ]]; then echo "  • disable $CURRENT_DM and enable greetd"
        elif [[ -z $CURRENT_DM ]]; then echo "  • enable greetd"; fi
    fi
    local unit what
    while IFS=$'\t' read -r unit _; do echo "  • enable $unit"; done < <(service_plan)
    while IFS=$'\t' read -r f what; do echo "  • write $f: $what"; done < <(nvidia_plan)
    echo "  • keep a record in $home/.local/state/noctalia-installer/manifest, so --uninstall can undo it"
    echo
    echo "Run the same command without --dry-run to install."
}

# ---------- --uninstall: undo the recorded changes ----------
do_uninstall() {
    if [[ $IS_ROOT -eq 1 && -z $TARGET_USER ]]; then
        TARGET_USER="${SUDO_USER:-}"
        if [[ -z $TARGET_USER || $TARGET_USER == root ]]; then
            local found=() m
            for m in /home/*/.local/state/noctalia-installer/manifest; do [[ -f $m ]] && found+=("$(stat -c %U "$m")"); done
            (( ${#found[@]} == 1 )) || die "Pass --user=NAME (install records found for: ${found[*]:-nobody})."
            TARGET_USER=${found[0]}
        fi
    elif [[ $IS_ROOT -eq 0 ]]; then
        TARGET_USER="$(id -un)"
    fi
    id "$TARGET_USER" &>/dev/null || die "User '$TARGET_USER' doesn't exist."
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    local m="$TARGET_HOME/.local/state/noctalia-installer/manifest"
    [[ -s $m ]] || die "No install record for $TARGET_USER ($m). Only installs from v1.0.0 on can be undone."

    # Keep the first record of each thing: the state before the first install.
    local -A seen=()
    local lines=() kind a b key
    while IFS=$'\t' read -r kind a b; do
        case $kind in
            file|moved|sysfile) key="$kind:$a" ;;
            greetd|kde_blur|kde_rule) key=$kind ;;
            dm_disabled|enabled) key="$kind:$a" ;;
            *) continue ;;
        esac
        [[ -n ${seen[$key]:-} ]] && continue
        seen[$key]=1
        lines+=("$kind"$'\t'"$a"$'\t'"$b")
    done < "$m"
    local pk; pk="$(awk -F'\t' '$1 == "packages" { print $2 }' "$m" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | paste -sd' ' -)"

    info "This puts back what the installer changed for $TARGET_USER:"
    local l
    for l in "${lines[@]}"; do
        IFS=$'\t' read -r kind a b <<< "$l"
        case $kind in
            file)    if [[ $b == - ]]; then echo "  • remove $a"; else echo "  • restore $a from $(basename "$b")"; fi ;;
            moved)   echo "  • move $(basename "$b") back to $a" ;;
            sysfile) echo "  • remove $a" ;;
            greetd)  [[ $a != - ]] && echo "  • restore $GREETD_CONF from its backup" ;;
            dm_disabled) echo "  • re-enable $a" ;;
            enabled) echo "  • disable $a" ;;
            kde_blur) echo "  • set KWin's blur back to how it was" ;;
            kde_rule) echo "  • remove the KWin rule for Noctalia settings" ;;
        esac
    done
    [[ -n $pk ]] && echo "  Packages stay installed. Remove them yourself if you like: $pk"
    if [[ $ASSUME_YES -eq 0 ]]; then
        local reply; read -r -p "Undo these changes? [y/N] " reply </dev/tty || reply=""
        [[ $reply =~ ^[Yy] ]] || die "Nothing changed."
    fi

    local greetd_enabled_by_us=0
    for l in "${lines[@]}"; do [[ $l == enabled$'\t'greetd.service$'\t'* ]] && greetd_enabled_by_us=1; done
    for l in "${lines[@]}"; do
        IFS=$'\t' read -r kind a b <<< "$l"
        case $kind in
            file)
                if [[ $b == - ]]; then rm -f "$a" && ok "Removed $a"
                elif [[ -f $b ]]; then cp -p "$b" "$a" && ok "Restored $a"
                else warn "Backup $b is gone; left $a as it is"; fi ;;
            moved)
                if [[ -f $b && ! -e $a ]]; then mv "$b" "$a" && ok "Moved $a back"; else warn "Couldn't move $b back to $a"; fi ;;
            sysfile) as_root rm -f "$a" && ok "Removed $a" ;;
            greetd)
                # The first greetd record holds the backup path in field 2.
                if [[ $a != - ]] && as_root test -f "$a"; then as_root cp -p "$a" "$GREETD_CONF" && ok "Restored $GREETD_CONF"; fi ;;
            dm_disabled)
                [[ $greetd_enabled_by_us -eq 1 ]] && { as_root systemctl disable greetd.service || true; }
                as_root systemctl enable "$a" && ok "Re-enabled $a (log in with it after a reboot)" ;;
            enabled) as_root systemctl disable "$a" && ok "Disabled $a" ;;
            kde_blur|kde_rule) undo_kde "$kind" "$a" ;;
        esac
    done
    mv "$m" "$m.undone.$(date +%Y%m%d-%H%M%S)"
    ok "Done. Reboot (or log out) to finish."
}
undo_kde() {  # undo_kde KIND VALUE
    local kw kr
    kw="$(command -v kwriteconfig6 || command -v kwriteconfig5)" || return 0
    kr="$(command -v kreadconfig6 || command -v kreadconfig5)" || return 0
    if [[ $1 == kde_blur ]]; then
        if [[ -n $2 ]]; then as_user "$kw" --file kwinrc --group Plugins --key blurEnabled "$2"
        else as_user "$kw" --file kwinrc --group Plugins --key blurEnabled --delete; fi
        ok "KWin blur set back"
        return 0
    fi
    local rules k
    rules="$(as_user "$kr" --file kwinrulesrc --group General --key rules 2>/dev/null || true)"
    rules="$(tr ',' '\n' <<< "$rules" | grep -vx noctalia-settings | paste -sd, -)"
    as_user "$kw" --file kwinrulesrc --group General --key rules "$rules"
    as_user "$kw" --file kwinrulesrc --group General --key count "$(tr ',' '\n' <<< "$rules" | grep -c . || true)"
    for k in Description wmclass wmclassmatch maximizehoriz maximizehorizrule maximizevert maximizevertrule; do
        as_user "$kw" --file kwinrulesrc --group noctalia-settings --key "$k" --delete
    done
    ok "Removed the KWin rule for Noctalia settings"
}

progress() {  # progress PCT STEP_ID "message"
    if [[ $UI == tui ]]; then
        printf '%s %s\n' "$1" "$2" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
        printf '\n==> [%d%%] %s\n' "$1" "$3"
    else
        info "$3"
    fi
}

run_long() {  # run_long FROM TO STEP_ID "message" cmd...  (TUI: creep the bar while it runs)
    local from=$1 to=$2 id=$3 text=$4; shift 4
    if [[ $UI != tui ]]; then "$@"; return $?; fi
    "$@" & local pid=$! p=$from
    while kill -0 "$pid" 2>/dev/null; do
        progress "$p" "$id" "$text"
        (( p < to - 1 )) && p=$((p + 1))
        sleep 2
    done
    wait "$pid"
}

as_root() { "${SUDO[@]}" "$@"; }

mk_user_dir() {
    local d
    for d in "$@"; do
        if [[ $IS_ROOT -eq 1 ]]; then install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$d"
        else mkdir -p "$d"; fi
    done
}

put_user_file() {  # put_user_file SRC DEST
    if [[ $IS_ROOT -eq 1 ]]; then install -m 644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$1" "$2"
    else install -m 644 "$1" "$2"; fi
}

LAST_BACKUP="-"
backup_if_exists() {  # sets LAST_BACKUP to the backup's path, or "-"
    LAST_BACKUP="-"
    [[ -f $1 ]] || return 0
    local b n=1; b="$1.bak.$(date +%Y%m%d-%H%M%S)"
    while [[ -e $b ]]; do n=$((n + 1)); b="$1.bak.$(date +%Y%m%d-%H%M%S)-$n"; done   # two runs in one second
    cp -p "$1" "$b"; ok "Backed up $1 -> $b"
    LAST_BACKUP="$b"
}

# ---------- install record (for --uninstall) ----------
# One tab-separated line per change, oldest first, kept across runs in
# ~/.local/state/noctalia-installer/manifest. --uninstall undoes the first
# record of each thing, which is the state before the first install.
MANIFEST=""
manifest_open() {
    local d="$TARGET_HOME/.local/state/noctalia-installer"
    mk_user_dir "$TARGET_HOME/.local" "$TARGET_HOME/.local/state" "$d"
    MANIFEST="$d/manifest"
    [[ -f $MANIFEST ]] || { : > "$MANIFEST"; [[ $IS_ROOT -eq 1 ]] && chown "$TARGET_USER:$TARGET_GROUP" "$MANIFEST"; }
    true
}
rec() {  # rec KIND FIELD...
    [[ -n $MANIFEST ]] || return 0
    local IFS=$'\t'; printf '%s\n' "$*" >> "$MANIFEST"
}
unit_enabled() { [[ $HAS_SYSTEMD -eq 1 ]] && systemctl is-enabled --quiet "$1" 2>/dev/null; }
enable_service() {  # enable_service UNIT — enable for next boot; record it if it was off
    unit_enabled "$1" && return 0
    if as_root systemctl enable "$1"; then rec enabled "$1"; ok "Enabled $1"
    else warn "Couldn't enable $1"; return 1; fi
}

# Set `key = "value"` inside [default_session] of greetd's config,
# keeping every other line/section untouched.
greetd_set() {  # greetd_set key value
    local key="$1" val="$2" tmp
    tmp="$(mktemp)"
    as_root cat "$GREETD_CONF" | awk -v key="$key" -v val="$val" '
        BEGIN { in_ds = 0; done = 0; seen = 0 }
        /^[[:space:]]*\[.*\][[:space:]]*$/ {
            if (in_ds && !done) { print key " = \"" val "\""; done = 1 }
            in_ds = ($0 ~ /^[[:space:]]*\[default_session\][[:space:]]*$/)
            if (in_ds) seen = 1
            print; next
        }
        in_ds && $0 ~ "^[[:space:]]*#?[[:space:]]*" key "[[:space:]]*=" {
            if (!done) { print key " = \"" val "\""; done = 1 }
            next
        }
        { print }
        END {
            if (in_ds && !done) { print key " = \"" val "\""; done = 1 }
            if (!seen) { print ""; print "[default_session]"; print key " = \"" val "\"" }
        }
    ' > "$tmp"
    as_root install -m 644 "$tmp" "$GREETD_CONF"
    rm -f "$tmp"
}

as_user() {  # run as the target user (needed for makepkg / AUR helpers)
    if [[ $IS_ROOT -eq 1 ]]; then runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" USER="$TARGET_USER" "$@"
    else "$@"; fi
}

get_cfg() {  # get_cfg REPO_PATH DEST  — from the clone, or download it
    if [[ -n $SCRIPT_DIR && -f $SCRIPT_DIR/configs/$1 ]]; then cp "$SCRIPT_DIR/configs/$1" "$2"
    else curl -fsSL "$REPO_RAW/configs/$1" -o "$2" || die "Could not download configs/$1"; fi
}

# Swap the default apps in a config for the chosen ones; comment out
# the line when "none" was chosen. STYLE: kdl lua hash xml
apply_apps() {  # apply_apps FILE STYLE
    local f=$1 style=$2 app def
    sed -i "s/\balacritty\b/$TERM_APP/g" "$f"
    local bcmd=${BROWSER_CMD:-$BROWSER_APP} fcmd="none"
    [[ $BROWSER_APP == none ]] && bcmd=none
    [[ $FM_APP != none ]] && fcmd="$(fm_command)"
    for def in "nautilus:$fcmd" "firefox:$bcmd"; do
        app=${def#*:}; def=${def%%:*}
        if [[ $app == none ]]; then
            case $style in
                kdl)  sed -i "/\b$def\b/ s|^|//|" "$f" ;;
                lua)  sed -i "/\b$def\b/ s|^|-- |" "$f" ;;
                hash) sed -i "/\b$def\b/ s|^|# |" "$f" ;;
                xml)  sed -i "/\b$def\b/ s|^\(.*\)$|<!-- \1 -->|" "$f" ;;
            esac
        elif [[ $style == kdl && $app == *" "* ]]; then
            # niri's spawn takes each argument as its own string: "kitty" "yazi"
            local q; q="$(printf '"%s" ' $app)"; q=${q% }
            sed -i "s|\"$def\"|$q|g" "$f"
        else
            sed -i "s|\b$def\b|$app|g" "$f"
        fi
    done
}

place_user_file() {  # place_user_file SRC DEST — back up, then install for the user
    mk_user_dir "$(dirname "$2")"
    backup_if_exists "$2"
    put_user_file "$1" "$2"
    rec file "$2" "$LAST_BACKUP"
    ok "Wrote $2"
}

# SwayFX installs itself as "sway"; its version string names it.
is_swayfx() { command -v sway >/dev/null 2>&1 && sway --version 2>/dev/null | grep -qi swayfx; }

# Mango 0.18 renamed its options to snake_case (window_rule, is_floating,
# gap_inner_horizontal, ...). Our config uses the new names; older Mango
# gets them translated back.
mango_is_legacy() {
    local v
    v="$(mango -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1)" || true
    [[ -n $v ]] || return 1
    [[ ${v%%.*} -eq 0 && ${v#*.} -lt 18 ]]
}
mango_legacy_names() {  # mango_legacy_names FILE
    local pair
    for pair in window_rule:windowrule layer_rule:layerrule tag_rule:tagrule \
                is_floating:isfloating app_id:appid no_blur:noblur no_animation:noanim \
                gap_inner_horizontal:gappih gap_inner_vertical:gappiv \
                gap_outer_horizontal:gappoh gap_outer_vertical:gappov \
                border_px:borderpx focus_color:focuscolor border_color:bordercolor \
                maximized_screen_color:maxmizescreencolor root_color:rootcolor \
                numlock_on:numlockon sloppy_focus:sloppyfocus warp_cursor:warpcursor \
                mouse_accel_profile:accel_profile move_client:exchange_client \
                togglemaximizescreen:togglemaxmizescreen; do
        sed -i "s/\b${pair%%:*}\b/${pair#*:}/g" "$1"
    done
    ok "Older Mango found: config written with its option names"
}

# KDE Plasma: turn on KWin's blur effect (Noctalia asks for blur behind its
# bar and panels) and open Noctalia's settings window maximized, like niri.
kde_extras() {
    local kw kr rules
    kw="$(command -v kwriteconfig6 || command -v kwriteconfig5)" || return 0
    kr="$(command -v kreadconfig6 || command -v kreadconfig5)" || return 0
    rec kde_blur "$(as_user "$kr" --file kwinrc --group Plugins --key blurEnabled 2>/dev/null || true)"
    as_user "$kw" --file kwinrc --group Plugins --key blurEnabled true
    rules="$(as_user "$kr" --file kwinrulesrc --group General --key rules 2>/dev/null)" || rules=""
    if [[ ,$rules, != *,noctalia-settings,* ]]; then
        local g=(--file kwinrulesrc --group noctalia-settings)
        as_user "$kw" "${g[@]}" --key Description "Noctalia settings: open maximized"
        as_user "$kw" "${g[@]}" --key wmclass "dev.noctalia.Noctalia"
        as_user "$kw" "${g[@]}" --key wmclassmatch 1
        as_user "$kw" "${g[@]}" --key maximizehoriz true
        as_user "$kw" "${g[@]}" --key maximizehorizrule 3
        as_user "$kw" "${g[@]}" --key maximizevert true
        as_user "$kw" "${g[@]}" --key maximizevertrule 3
        rules="${rules:+$rules,}noctalia-settings"
        as_user "$kw" --file kwinrulesrc --group General --key rules "$rules"
        as_user "$kw" --file kwinrulesrc --group General --key count "$(tr ',' '\n' <<<"$rules" | grep -c .)"
        rec kde_rule noctalia-settings
    fi
    ok "KDE Plasma: blur on, Noctalia settings open maximized"
}

write_comp_config() {  # write_comp_config ID
    local id=$1 w="$TMP_DIR/cfg-$1"
    mkdir -p "$w"
    case $id in
        niri)
            get_cfg niri/config.kdl "$w/config.kdl"
            sed -i "s/layout \"us\"/layout \"$KB_LAYOUT\"/" "$w/config.kdl"
            apply_apps "$w/config.kdl" kdl
            place_user_file "$w/config.kdl" "$CONFIG_HOME/niri/config.kdl" ;;
        hyprland)
            get_cfg hyprland/hyprland.lua "$w/hyprland.lua"
            sed -i "s/kb_layout = \"us\"/kb_layout = \"$KB_LAYOUT\"/" "$w/hyprland.lua"
            apply_apps "$w/hyprland.lua" lua
            # Noctalia's Hyprland setup uses the Lua config; move an old
            # hyprland.conf aside (backed up) so it can't take over.
            if [[ -f $CONFIG_HOME/hypr/hyprland.conf ]]; then
                local moved; moved="$CONFIG_HOME/hypr/hyprland.conf.bak.$(date +%Y%m%d-%H%M%S)"
                mv "$CONFIG_HOME/hypr/hyprland.conf" "$moved"
                rec moved "$CONFIG_HOME/hypr/hyprland.conf" "$moved"
                warn "Moved your hyprland.conf aside (backup next to it); Hyprland now uses hyprland.lua."
            fi
            place_user_file "$w/hyprland.lua" "$CONFIG_HOME/hypr/hyprland.lua" ;;
        sway|scroll)
            get_cfg "$id/config" "$w/config"
            sed -i "s/xkb_layout \"us\"/xkb_layout \"$KB_LAYOUT\"/" "$w/config"
            apply_apps "$w/config" hash
            # SwayFX understands blur, corners and shadows; plain Sway doesn't.
            if [[ $id == sway ]] && is_swayfx; then
                get_cfg sway/swayfx-effects "$w/fx"
                cat "$w/fx" >> "$w/config"
                ok "SwayFX found: blur, rounded corners and shadows turned on"
            fi
            if [[ $LID_FIX -eq 1 ]]; then
                printf '\n# Lock and suspend on lid close (Noctalia)\nbindswitch --locked lid:on exec noctalia msg session lock-and-suspend\n' >> "$w/config"
            fi
            place_user_file "$w/config" "$CONFIG_HOME/$id/config" ;;
        mango)
            get_cfg mango/config.conf "$w/config.conf"
            sed -i "s/^xkb_rules_layout=us$/xkb_rules_layout=$KB_LAYOUT/" "$w/config.conf"
            apply_apps "$w/config.conf" hash
            mango_is_legacy && mango_legacy_names "$w/config.conf"
            place_user_file "$w/config.conf" "$CONFIG_HOME/mango/config.conf" ;;
        labwc)
            get_cfg labwc/rc.xml "$w/rc.xml"
            apply_apps "$w/rc.xml" xml
            place_user_file "$w/rc.xml" "$CONFIG_HOME/labwc/rc.xml"
            # autostart / environment: add our lines, keep the user's others.
            local f
            f="$CONFIG_HOME/labwc/autostart"
            if [[ -f $f ]] && grep -q '^[^#]*\bnoctalia\b' "$f"; then :
            else
                get_cfg labwc/autostart "$w/autostart"
                [[ -f $f ]] && { backup_if_exists "$f"; cat "$f" "$w/autostart" > "$w/autostart.new"; mv "$w/autostart.new" "$w/autostart"; }
                place_user_file "$w/autostart" "$f"
            fi
            f="$CONFIG_HOME/labwc/environment"
            { [[ -f $f ]] && grep -v '^XKB_DEFAULT_LAYOUT=' "$f"; echo "XKB_DEFAULT_LAYOUT=$KB_LAYOUT"; } > "$w/environment" || true
            place_user_file "$w/environment" "$f" ;;
        umbriel)
            get_cfg umbriel/config.toml "$w/config.toml"
            sed -i "s/^layout = \"us\"$/layout = \"$KB_LAYOUT\"/" "$w/config.toml"
            apply_apps "$w/config.toml" hash
            place_user_file "$w/config.toml" "$CONFIG_HOME/umbriel/config.toml" ;;
        kde)
            get_cfg kde/noctalia.desktop "$w/noctalia.desktop"
            place_user_file "$w/noctalia.desktop" "$CONFIG_HOME/autostart/noctalia.desktop"
            kde_extras
            warn "KDE Plasma: Noctalia autostarts, but screenshots and clipboard history are limited there. Add shortcuts (noctalia msg ...) in System Settings." ;;
    esac
}

# Root installs build AUR packages as the target user, whose sudo needs
# a password; allow it without one only for the length of the install.
aur_sudo_open()  { [[ $IS_ROOT -eq 1 ]] || return 0; echo "$TARGET_USER ALL=(ALL:ALL) NOPASSWD: ALL" > "$SUDOERS_TMP"; chmod 440 "$SUDOERS_TMP"; }
aur_sudo_close() { [[ $IS_ROOT -eq 1 ]] || return 0; rm -f "$SUDOERS_TMP"; }

install_browser() {
    local id=$BROWSER_APP src pkg bin fp
    src="$(browser_source "$id")"
    case $src in
        repo)
            if [[ $FAMILY == arch ]]; then pkg="$(browser_field "$id" 4)"
            elif [[ $FAMILY == gentoo ]]; then pkg="$(pkgs "$id")"
            else pkg="$(browser_field "$id" 6)"; fi
            pm_install "$pkg" ;;
        aur)
            aur_sudo_open
            aur_install "$(browser_field "$id" 5)" || { aur_sudo_close; return 1; }
            aur_sudo_close ;;
        flatpak)
            fp="$(browser_field "$id" 8)"
            command -v flatpak >/dev/null || pm_install "$( [[ $FAMILY == gentoo ]] && echo sys-apps/flatpak || echo flatpak )"
            as_root flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
            as_root flatpak install -y --noninteractive flathub "$fp"
            BROWSER_CMD="$FLATPAK_BIN/$fp"; echo "$BROWSER_CMD" > "$TMP_DIR/browser_cmd"
            ok "Installed $(browser_field "$id" 2) from Flathub ($fp)"
            [[ $id == mullvad ]] && warn "Mullvad Browser's Flatpak is a community build, not made by Mullvad."
            return 0 ;;
    esac
    # Native package: use whichever of its known commands exists.
    for bin in $(browser_field "$id" 7); do
        if command -v "$bin" >/dev/null || [[ -x /usr/bin/$bin ]]; then BROWSER_CMD=$bin; break; fi
    done
    [[ -n $BROWSER_CMD ]] || { BROWSER_CMD="$(browser_field "$id" 7)"; BROWSER_CMD=${BROWSER_CMD%% *}
        warn "Couldn't find the $(browser_field "$id" 2) command after installing; Mod+B runs '$BROWSER_CMD'."; }
    echo "$BROWSER_CMD" > "$TMP_DIR/browser_cmd"
    ok "Installed $(browser_field "$id" 2) ($src): Mod+B runs $BROWSER_CMD"
}

install_aur_helper() {
    # Both are built from source from the AUR:
    #   sudo pacman -S --needed git base-devel
    #   git clone https://aur.archlinux.org/yay.git   (or paru.git)
    #   cd yay && makepkg -si
    # makepkg -s pulls in the build tools: go for yay, rust (cargo) for paru.
    local d; d="$(mktemp -d)"
    [[ $IS_ROOT -eq 1 ]] && chown "$TARGET_USER:$TARGET_GROUP" "$d"
    pm_install git base-devel
    as_user git clone "https://aur.archlinux.org/${AUR_HELPER}.git" "$d/$AUR_HELPER"
    ( cd "$d/$AUR_HELPER" && as_user makepkg -si --noconfirm )
    rm -rf "$d"
    command -v "$AUR_HELPER" >/dev/null || die "$AUR_HELPER didn't install — see $LOG"
    ok "Installed $AUR_HELPER"
}

aur_install() {  # aur_install PKG...
    local flags=(-S --needed --noconfirm)
    case $AUR_HELPER in
        yay)  flags+=(--answerdiff None --answerclean None --answeredit None --removemake) ;;
        paru) flags+=(--skipreview --removemake) ;;
    esac
    as_user "$AUR_HELPER" "${flags[@]}" "$@"
}

run_steps() {
    set -e

    if [[ $CREATE_USER -eq 1 ]]; then
        progress 2 user "Creating user $TARGET_USER…"
        command -v useradd >/dev/null || die "useradd isn't available here; create the user yourself and run with --user=NAME."
        command -v sudo >/dev/null || [[ $CONFIGS_ONLY -eq 1 ]] || pm_install "$(pkgs sudo)"
        getent group wheel >/dev/null || groupadd wheel
        useradd -m -G wheel -s /bin/bash "$TARGET_USER"
        printf '%s:%s\n' "$TARGET_USER" "$NEW_USER_PASS" | chpasswd
        NEW_USER_PASS=""
        echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
        chmod 440 /etc/sudoers.d/10-wheel
        ok "Created $TARGET_USER (wheel, sudo enabled)"
    fi
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    TARGET_GROUP="$(id -gn "$TARGET_USER")"
    [[ -d $TARGET_HOME ]] || die "Home directory for $TARGET_USER not found."
    if [[ $IS_ROOT -eq 1 ]]; then CONFIG_HOME="$TARGET_HOME/.config"
    else CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"; fi
    NOCTALIA_DIR="$CONFIG_HOME/noctalia"
    manifest_open
    rec run "$(date +%Y-%m-%dT%H:%M:%S)" "$VERSION" "${COMPS[*]}"

    # --- packages ---
    if [[ $CONFIGS_ONLY -eq 0 ]]; then
        if [[ $FAMILY != arch ]]; then
            run_long 3 8 repos "Adding the Noctalia repository for $FAMILY_LABEL…" setup_repos \
                || die "Adding the repository failed — see $LOG"
        fi

        local essential=() optional=() backports=() p
        collect_packages
        essential=("${PK_ESSENTIAL[@]}"); optional=("${PK_OPTIONAL[@]}")
        (( ${#PK_BACKPORTS[@]} )) && backports=("${PK_BACKPORTS[@]}")

        # Look every package up in the repositories: stop on a missing
        # essential one, skip (and report) missing optional ones.
        progress 9 pkgs "Checking packages…"
        local install=() missing=()
        # The repositories are set up now, so ask the package manager directly.
        for p in "${essential[@]}"; do
            pm_has "$p" || die "$p isn't available in your repositories on $FAMILY_LABEL."
            install+=("$p")
        done
        for p in "${optional[@]}"; do
            [[ " ${backports[*]} " == *" $p "* ]] && continue
            if pm_has "$p"; then install+=("$p"); else missing+=("$p"); fi
        done
        mapfile -t install < <(printf '%s\n' "${install[@]}" | awk 'NF && !seen[$0]++')
        (( ${#missing[@]} )) && warn "Not in your repositories, skipped: ${missing[*]}"

        run_long 10 55 pkgs "Installing packages (this can take a while)…" pm_install "${install[@]}" \
            || die "Installing packages failed — see $LOG"
        if (( ${#backports[@]} )); then
            as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -t trixie-backports "${backports[@]}" \
                || die "Installing ${backports[*]} from trixie-backports failed — see $LOG"
        fi
        rec packages "${install[*]} ${backports[*]}"
        ok "Packages installed"
    fi

    # --- AUR helper and AUR packages ---
    if [[ $AUR_HELPER != none ]]; then
        aur_sudo_open
        if [[ $AUR_HELPER != "$EXISTING_HELPER" ]]; then
            run_long 56 62 helper "Building $AUR_HELPER from the AUR…" install_aur_helper \
                || { aur_sudo_close; die "Installing $AUR_HELPER failed — see $LOG"; }
        fi
        if needs_aur; then
            local aurp=()
            for c in "${COMPS[@]}"; do
                # shellcheck disable=SC2207
                aurp+=($(comp_field "$c" 4))
            done
            run_long 62 72 aur "Building ${aurp[*]} from the AUR (this can take a while)…" aur_install "${aurp[@]}" \
                || { aur_sudo_close; die "AUR build failed — see $LOG"; }
            ok "Built ${aurp[*]}"
        fi
        aur_sudo_close
    fi

    # --- browser: distribution package, AUR (Arch), or Flathub ---
    if [[ $INSTALL_APPS -eq 1 && $BROWSER_APP != none && $CONFIGS_ONLY -eq 0 ]]; then
        run_long 72 73 browser "Installing $(browser_field "$BROWSER_APP" 2)…" install_browser \
            || die "Installing the browser failed — see $LOG"
        # run_long may run it in the background, so the command comes back via a file
        BROWSER_CMD="$(cat "$TMP_DIR/browser_cmd" 2>/dev/null)"
    elif [[ $BROWSER_APP != none ]]; then
        BROWSER_CMD="$(browser_field "$BROWSER_APP" 7)"; BROWSER_CMD=${BROWSER_CMD%% *}
    fi

    if [[ $FAMILY == arch ]] && { pacman -Qq noctalia-shell &>/dev/null || pacman -Qq noctalia-shell-git &>/dev/null; }; then
        warn "Noctalia v4 (noctalia-shell) is still installed. Remove it once v5 works: sudo pacman -Rns noctalia-shell noctalia-qs"
    fi

    # --- configs ---
    progress 74 files "Writing compositor configs…"
    mk_user_dir "$CONFIG_HOME" "$NOCTALIA_DIR" \
        "$TARGET_HOME/Pictures" "$TARGET_HOME/Pictures/Screenshots" "$TARGET_HOME/Pictures/Wallpapers"
    for c in "${COMPS[@]}"; do write_comp_config "$c"; done

    local toml="$TMP_DIR/10-installer.toml"
    {
        echo "# Written by noctalia-installer/install.sh"
        echo "[shell]"
        if has_comp niri && [[ $TYPE_TO_LAUNCH -eq 1 ]]; then
            echo "niri_overview_type_to_launch_enabled = true"
            echo "niri_overview_close_on_launch_enabled = true"
        fi
        if has_comp umbriel && [[ $TYPE_TO_LAUNCH -eq 1 ]]; then
            echo "umbriel_overview_type_to_launch_enabled = true"
            echo "umbriel_overview_close_on_launch_enabled = true"
        fi
        [[ $POLKIT_AGENT -eq 1 ]] && echo "polkit_agent = true"
        true
    } > "$toml"
    # Older versions of this installer wrote 10-niri.toml; replace it.
    if [[ -f $NOCTALIA_DIR/10-niri.toml ]] && grep -q 'noctalia-niri-config-setup' "$NOCTALIA_DIR/10-niri.toml"; then
        rm -f "$NOCTALIA_DIR/10-niri.toml"
    fi
    place_user_file "$toml" "$NOCTALIA_DIR/10-installer.toml"

    if [[ $WALLPAPERS_ON -eq 1 ]]; then
        local wdir="$TARGET_HOME/Pictures/Wallpapers" row id
        for row in "${WALLPAPER_TABLE[@]}"; do
            id=${row%%|*}
            get_cfg "wallpapers/noctalia-$id.jpg" "$TMP_DIR/noctalia-$id.jpg"
            [[ -e $wdir/noctalia-$id.jpg ]] || rec file "$wdir/noctalia-$id.jpg" -
            put_user_file "$TMP_DIR/noctalia-$id.jpg" "$wdir/noctalia-$id.jpg"
        done
        ok "Copied ${#WALLPAPER_TABLE[@]} wallpapers to $wdir"
        printf '# Written by noctalia-installer/install.sh\n[wallpaper]\ndirectory = "%s"\n\n[wallpaper.default]\npath = "%s"\n' \
            "$wdir" "$wdir/noctalia-$WALLPAPER.jpg" > "$TMP_DIR/30-wallpaper.toml"
        place_user_file "$TMP_DIR/30-wallpaper.toml" "$NOCTALIA_DIR/30-wallpaper.toml"
        if [[ -f $TARGET_HOME/.local/state/noctalia/settings.toml ]] && grep -q '^\[wallpaper' "$TARGET_HOME/.local/state/noctalia/settings.toml"; then
            warn "A wallpaper you picked in Noctalia earlier overrides this one (~/.local/state/noctalia/settings.toml); pick a new one in Noctalia's wallpaper panel."
        fi
    fi

    if [[ $BAR_PRESET -eq 1 ]]; then
        get_cfg noctalia/20-bar.toml "$TMP_DIR/20-bar.toml"
        place_user_file "$TMP_DIR/20-bar.toml" "$NOCTALIA_DIR/20-bar.toml"
        if [[ -f $TARGET_HOME/.local/state/noctalia/settings.toml ]] && grep -q '^\[bar' "$TARGET_HOME/.local/state/noctalia/settings.toml"; then
            warn "Bar settings you changed in Noctalia's Settings window override the bar preset (~/.local/state/noctalia/settings.toml)."
        fi
    fi

    # --- validation (only compositors that can check a config offline) ---
    progress 78 check "Validating configs…"
    if has_comp niri && command -v niri >/dev/null; then
        if niri validate -c "$CONFIG_HOME/niri/config.kdl"; then ok "niri config is valid"
        else warn "niri validate failed. If it mentions blur or background-effect, update niri. Details in $LOG"; fi
    fi
    if command -v noctalia >/dev/null; then
        if as_user env XDG_CONFIG_HOME="$CONFIG_HOME" noctalia config validate; then ok "Noctalia config is valid"
        else warn "noctalia config validate reported problems in $NOCTALIA_DIR. Details in $LOG"; fi
    fi
    for c in sway scroll; do
        has_comp "$c" && command -v "$c" >/dev/null || continue
        if "$c" -C -c "$CONFIG_HOME/$c/config"; then ok "$c config is valid"
        else warn "$c -C reported problems with $CONFIG_HOME/$c/config. Details in $LOG"; fi
    done

    if [[ $LID_FIX -eq 1 ]]; then
        progress 80 lid "Configuring lid close…"
        as_root mkdir -p /etc/systemd/logind.conf.d
        as_root test -e /etc/systemd/logind.conf.d/10-noctalia-lid.conf || rec sysfile /etc/systemd/logind.conf.d/10-noctalia-lid.conf
        printf '[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\n' \
            | as_root tee /etc/systemd/logind.conf.d/10-noctalia-lid.conf >/dev/null
        ok "Lid close is handled by the compositor and Noctalia (after reboot)"
    fi

    if [[ $INSTALL_GREETER -eq 1 ]]; then
        progress 84 greeter "Configuring greetd for Noctalia Greeter…"
        local session
        session="$(command -v noctalia-greeter-session || echo /usr/bin/noctalia-greeter-session)"
        [[ -x $session ]] || die "noctalia-greeter-session not found at $session"
        as_root mkdir -p /etc/greetd
        if as_root test -f "$GREETD_CONF"; then
            local gbak; gbak="$GREETD_CONF.bak.$(date +%Y%m%d-%H%M%S)"
            as_root cp -p "$GREETD_CONF" "$gbak"
            rec greetd "$gbak"
        else
            printf '[terminal]\nvt = 1\n\n[default_session]\n' | as_root tee "$GREETD_CONF" >/dev/null
            rec greetd -
        fi
        local guser
        guser="$(as_root awk '/^\[default_session\]/{d=1;next} /^\[/{d=0} d && /^[[:space:]]*user[[:space:]]*=/{gsub(/.*=[[:space:]]*"|".*/,""); print; exit}' "$GREETD_CONF")"
        if [[ $FAMILY == debian ]]; then
            ok "Debian's noctalia-greeter package configures greetd itself"
        else
            greetd_set command "$session"
            [[ -z $guser ]] && { greetd_set user "greeter"; guser=greeter; }
            ok "greetd starts $session as '$guser'"
        fi
        guser=${guser:-greeter}
        id "$guser" &>/dev/null || die "greetd's user '$guser' doesn't exist."
        as_root systemd-tmpfiles --create
        if as_root env GREETER_USER="$guser" noctalia-greeter-apply-appearance --setup-system; then
            ok "Greeter config initialised"
        else
            warn "Greeter setup helper failed; run: sudo noctalia-greeter-apply-appearance --setup-system"
        fi

        progress 95 dm "Enabling the login screen…"
        if [[ -n $CURRENT_DM && $SWITCH_DM -eq 1 ]]; then
            as_root systemctl disable "$CURRENT_DM"
            rec dm_disabled "$CURRENT_DM"
            ok "Disabled $CURRENT_DM"
        fi
        if [[ -z $CURRENT_DM || $SWITCH_DM -eq 1 ]]; then
            enable_service greetd.service
            echo 1 > "$TMP_DIR/greeter_enabled"
        else
            warn "Kept $CURRENT_DM; greetd was not enabled (two login managers would conflict)."
        fi
    fi

    if [[ $SERVICES -eq 1 ]]; then
        progress 97 services "Enabling desktop services…"
        local unit
        while IFS=$'\t' read -r unit _; do enable_service "$unit" || true; done < <(service_plan)
    fi
    if [[ $NVIDIA_FIX -eq 1 ]]; then
        progress 98 nvidia "Applying NVIDIA tweaks…"
        apply_nvidia
    elif [[ $NVIDIA_GPU -eq 1 && $NVIDIA_DRIVER -eq 0 && $CONFIGS_ONLY -eq 0 ]]; then
        warn "NVIDIA card found without NVIDIA's driver loaded. If the desktop is slow or blank, install your distribution's NVIDIA driver."
    fi

    if [[ $CONFIGS_ONLY -eq 1 ]]; then
        local need=() c
        for c in "${COMPS[@]}"; do need+=("$(comp_field "$c" 2)"); done
        warn "Configs only: ${FAMILY_NOTE} Install Noctalia and ${need[*]} yourself: https://docs.noctalia.dev/noctalia/getting-started/installation/"
    fi
    progress 100 "done" "Done."
}

# ---------- live install screen ----------
log_tail() {  # last N readable log lines, trimmed to width
    tail -c 6000 "$LOG" 2>/dev/null | tr '\r' '\n' | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' \
        | grep -v '^[[:space:]]*$' | grep -v '^==> \[' | tail -n "$1" | cut -c1-"$(( COLS - 10 ))" \
        | if [[ $IS_CONSOLE -eq 1 ]]; then sed 's/✓/√/g; s/✗/x/g; s/—/-/g; s/…/.../g'; else cat; fi
}

render_install() {  # render_install PID
    local pid=$1 frame=0 pct=0 cur="" i label row line fill w=$(( COLS - 16 ))
    printf '\e[?25l' >/dev/tty
    stty -echo -icanon </dev/tty 2>/dev/null || true   # keys pressed now must not print
    screen "Install" "Installing your desktop" "This can take a while. Please keep this terminal open."
    footer "${SYM_BUL}" "installing, keys are disabled until it finishes"
    while true; do
        [[ -f $STATE ]] && read -r pct cur < "$STATE" || true
        local running=0; kill -0 "$pid" 2>/dev/null && running=1
        local cur_idx=-1
        for i in "${!INSTALL_STEPS[@]}"; do [[ ${INSTALL_STEPS[i]%%|*} == "$cur" ]] && cur_idx=$i; done
        [[ $cur == "done" ]] && cur_idx=${#INSTALL_STEPS[@]}

        # Small terminals: show a window of steps around the current one,
        # so the progress bar and log lines always fit above the footer.
        local n=${#INSTALL_STEPS[@]} fit=$(( ROWS - 15 )) first=0 last
        (( fit < 3 )) && fit=3
        if (( n > fit )); then
            first=$(( cur_idx - 2 )); (( first > n - fit )) && first=$(( n - fit )); (( first < 0 )) && first=0
        fi
        last=$(( first + (n < fit ? n : fit) - 1 ))
        row=9
        for i in "${!INSTALL_STEPS[@]}"; do
            (( i < first || i > last )) && continue
            label="${INSTALL_STEPS[i]#*|}"
            if (( i < cur_idx )); then line="${T}${SYM_DONE}${R}  ${D}${label}${R}"
            elif (( i == cur_idx )); then
                if [[ $running -eq 1 ]]; then line="${P}${SPIN[frame % ${#SPIN[@]}]}${R}  ${X}${B}${label}${R}"
                else line="${E}${SYM_FAIL}${R}  ${E}${label}${R}"; fi
            else line="${O}${SYM_TODO}${R}  ${D}${label}${R}"; fi
            at "$row" 5; out "${line}${EL}"; row=$((row + 1))
        done

        fill=$(( pct * w / 100 ))
        at $(( row + 1 )) 5
        out "${P}$(rep "$BAR_ON" "$fill")${R}${O}$(rep "$BAR_OFF" $(( w - fill )))${R} ${X}${B}$(printf '%3d%%' "$pct")${R}${EL}"

        local lrow=$(( row + 3 )) nlog
        nlog=$(( ROWS - 1 - lrow )); (( nlog > 4 )) && nlog=4
        if (( nlog > 0 )); then
            while IFS= read -r line; do
                at "$lrow" 5; out "${D}${line}${R}${EL}"; lrow=$((lrow + 1))
            done < <(log_tail "$nlog")
        fi

        [[ $running -eq 0 ]] && break
        frame=$((frame + 1)); sleep 0.15
    done
    # Drop anything typed during the install, then restore the terminal.
    while IFS= read -rsn1 -t 0.01 _ </dev/tty; do :; done
    stty echo icanon </dev/tty 2>/dev/null || true
    printf '\e[?25h' >/dev/tty
}

scr_failed() {
    screen "Install" "Installation failed" "Nothing after the failed step was changed."
    at 6 3; out "${E}${B}${SYM_FAIL} Installation failed${R}"
    local lines=() l
    while IFS= read -r l; do lines+=("${D}${l}${R}"); done < <(log_tail 9)
    card 8 "${X}Last lines of the log${R}" "" "${lines[@]}"
    at 21 5; out "${D}Full log: ${X}${LOG}${R}"
    press_continue 22 "Exit" 0
}

scr_done() {
    local login
    local first_name first_cmd
    first_name="$(comp_field "${COMPS[0]}" 2)"; first_cmd="$(comp_field "${COMPS[0]}" 5)"
    if [[ $CONFIGS_ONLY -eq 1 ]]; then login="Configs written. Install Noctalia and ${P}${first_name}${R}${X}, then run ${P}${first_cmd}${R}"
    elif [[ $GREETER_ENABLED -eq 1 ]]; then login="Reboot, pick ${P}${first_name}${R}${X} (or another session) in Noctalia Greeter"
    elif [[ -n $CURRENT_DM ]]; then login="Log out and pick ${P}${first_name}${R}${X} in ${CURRENT_DM}"
    else login="Log in on a TTY as ${P}${TARGET_USER}${R}${X} and run ${P}${first_cmd}${R}"; fi

    cls; header "__all_done__"   # an unknown step name marks every step as done
    if [[ $CONFIGS_ONLY -eq 1 ]]; then at 6 3; out "${T}${B}${SYM_DONE} Your Noctalia configs are ready${R}"
    else at 6 3; out "${T}${B}${SYM_DONE} Your Noctalia desktop is ready${R}"; fi
    at 7 3; out "${X}${login}${R}"
    keyrow() {  # keyrow KEY LABEL KEY LABEL -> two aligned columns
        local a; a="$(pill "$1" "$BS") ${X}$2${R}"
        printf '%s%s%s' "$a" "$(rep " " $(( 34 - $(vlen "$a") )))" "$(pill "$3" "$BS") ${X}$4${R}"
    }
    # niri binds settings to Mod+Shift+Comma (Mod+Comma is taken there).
    local settings_key="Mod+,"
    [[ ${#COMPS[@]} -eq 1 && ${COMPS[0]} == niri ]] && settings_key="Mod+Shift+,"
    card 9 \
        "$(keyrow "Mod+Return" "terminal ($TERM_APP)" "Mod+Space" "launcher")" \
        "$(keyrow "Mod+S" "control center" "Mod+Q" "close window")" \
        "$(keyrow "$settings_key" "Noctalia settings" "Mod+1..9" "workspaces")"
    local row=16 w
    if [[ -s $WARN_FILE ]]; then
        at "$row" 3; out "${P}${B}! Notes${R}"; row=$((row + 1))
        while IFS= read -r w && (( row < 20 )); do
            at "$row" 5; out "${D}$(printf '%s' "$w" | cut -c1-$(( COLS - 8 )))${R}"; row=$((row + 1))
        done < "$WARN_FILE"
        row=$((row + 1))
    fi
    at "$row" 1
    if [[ $GREETER_ENABLED -eq 1 ]]; then
        footer "↑↓" "move" "enter" "select"
        menu "$row" reboot "Reboot now|start Noctalia Greeter|reboot" "Exit to the shell|reboot later yourself|exit" || ANSWER="exit"
        if [[ $ANSWER == reboot ]]; then ui_restore; as_root systemctl reboot; fi
    else
        press_continue "$row" "Exit" 0
    fi
}

# =====================================================================
#  main
# =====================================================================
# Another user's log from an earlier run may be in the way.
{ : > "$LOG"; } 2>/dev/null || LOG="$(mktemp /tmp/noctalia-install.XXXXXX.log)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

if [[ $UNINSTALL -eq 1 ]]; then
    UI=plain
    do_uninstall
    exit 0
fi

check_comp_availability
init_ui
if [[ $UI == tui ]]; then tui_decisions; else plain_decisions; fi

if [[ $DRY_RUN -eq 1 ]]; then
    [[ $UI == tui ]] && { ui_restore; UI=plain; }
    print_plan
    exit 0
fi

INSTALL_STARTED=1
build_install_steps

if [[ $UI == tui ]]; then
    [[ $IS_ROOT -eq 0 && $CONFIGS_ONLY -eq 0 ]] && SUDO=(sudo -n)   # sudo must never prompt behind the UI
    trap '' INT                              # don't abort halfway through pacman
    set +e
    ( run_steps ) >>"$LOG" 2>&1 &
    INSTALL_PID=$!
    render_install "$INSTALL_PID"
    wait "$INSTALL_PID"; rc=$?
    set -e
    trap - INT
    if [[ $rc -ne 0 ]]; then
        scr_failed
        ui_restore; UI=plain
        die "Installation failed. Full log: $LOG"
    fi
else
    run_steps
fi

GREETER_ENABLED=0; [[ -f $TMP_DIR/greeter_enabled ]] && GREETER_ENABLED=1

if [[ $UI == tui ]]; then
    scr_done
    ui_restore; UI=plain
fi

echo
ok "All done."
echo "Compositors: $(comp_names)"
if [[ $GREETER_ENABLED -eq 1 ]]; then echo "Reboot: Noctalia Greeter appears. Pick a session and log in as $TARGET_USER."
elif [[ -n $CURRENT_DM ]]; then echo "Log out and pick $(comp_field "${COMPS[0]}" 2) in $CURRENT_DM."
else echo "Log in on a TTY as $TARGET_USER and run: $(comp_field "${COMPS[0]}" 5)"; fi
[[ -s $WARN_FILE ]] && { echo; echo "Notes:"; sed 's/^/  • /' "$WARN_FILE"; }
echo "Log: $LOG"
