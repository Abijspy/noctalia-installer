#!/usr/bin/env python3
"""Offline checks for every config in configs/.

  python3 tests/check-configs.py [--mango-src DIR] [--umbriel-src DIR]

Always: TOML/XML/KDL parse, Hyprland Lua runs against a stub of the hl.*
API, and every config keeps the placeholders install.sh rewrites
(alacritty / nautilus / firefox, the "us" layout) and the rule that opens
Noctalia settings full size. With --mango-src / --umbriel-src (git clones
of those compositors), Mango option names and Umbriel keys and actions are
checked against their source code.
"""
import argparse, glob, re, sys, tomllib, xml.dom.minidom
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CFG = ROOT / "configs"
errors = []


def fail(msg):
    errors.append(msg)
    print(f"  FAIL {msg}")


def ok(msg):
    print(f"  ok   {msg}")


def read(rel):
    return (CFG / rel).read_text()


# ---------------------------------------------------------------- parsing
def check_parsing():
    for f in ["umbriel/config.toml", *[str(p.relative_to(CFG)) for p in (CFG / "noctalia").glob("*.toml")]]:
        try:
            tomllib.loads(read(f)); ok(f"{f} is valid TOML")
        except Exception as e:  # noqa: BLE001
            fail(f"{f}: {e}")
    try:
        xml.dom.minidom.parseString(read("labwc/rc.xml")); ok("labwc/rc.xml is valid XML")
    except Exception as e:  # noqa: BLE001
        fail(f"labwc/rc.xml: {e}")
    try:
        import ckdl
        ckdl.parse(read("niri/config.kdl")); ok("niri/config.kdl is valid KDL")
    except ImportError:
        print("  skip niri KDL parse (pip install ckdl)")
    except Exception as e:  # noqa: BLE001
        fail(f"niri/config.kdl: {e}")


def check_hyprland_lua():
    try:
        import lupa
    except ImportError:
        print("  skip Hyprland Lua run (pip install lupa)"); return
    lua = lupa.LuaRuntime()
    stub = """
    local calls = 0
    local function any(name)
      return setmetatable({}, {
        __index = function(_, k) return any(name .. "." .. k) end,
        __call = function(...) calls = calls + 1; return any(name .. "()") end })
    end
    hl = any("hl")
    return function(path) dofile(path); return calls end
    """
    try:
        n = lua.execute(stub)(str(CFG / "hyprland/hyprland.lua"))
        ok(f"hyprland.lua runs ({n} hl.* calls)")
    except Exception as e:  # noqa: BLE001
        fail(f"hyprland.lua: {e}")


# ------------------------------------------- what install.sh depends on
PLACEHOLDERS = {
    "niri/config.kdl":     ['layout "us"'],
    "hyprland/hyprland.lua": ['kb_layout = "us"'],
    "sway/config":         ['xkb_layout "us"'],
    "scroll/config":       ['xkb_layout "us"'],
    "mango/config.conf":   ["xkb_rules_layout=us"],
    "umbriel/config.toml": ['layout = "us"'],
    "labwc/rc.xml":        [],
}
SETTINGS_RULE = {
    "niri/config.kdl": r'app-id="dev\.noctalia\.Noctalia".*\n\s*open-maximized true',
    "hyprland/hyprland.lua": r'dev\\\\\.noctalia\\\\\.Noctalia.*\n\s*maximize = true',
    "sway/config": r'dev\\\.noctalia\\\.Noctalia.*resize set width',
    "scroll/config": r'dev\\\.noctalia\\\.Noctalia.*set_size h 1\.0',
    "mango/config.conf": r'is_floating:1,width:0\.\d+,height:0\.\d+,app_id:\^dev',
    "umbriel/config.toml": r'dev\.noctalia\.Noctalia.*\n\s*default_maximize = true',
    "labwc/rc.xml": r'identifier="dev\.noctalia\.Noctalia"><action name="Maximize"/>',
}


def check_installer_contract():
    for f, needles in PLACEHOLDERS.items():
        text = read(f)
        for app in ("alacritty", "nautilus", "firefox"):
            if not re.search(rf"\b{app}\b", text):
                fail(f"{f}: missing the '{app}' placeholder install.sh replaces")
        for n in needles:
            if n not in text:
                fail(f"{f}: missing '{n}' (install.sh sets the keyboard layout there)")
        if re.search(SETTINGS_RULE[f], text):
            ok(f"{f}: placeholders and Noctalia settings rule present")
        else:
            fail(f"{f}: Noctalia settings window rule not found")


# ------------------------------------------------- against upstream source
def check_mango(src):
    src = Path(src)
    opts = set(re.findall(r'strc?n?cmp\(key, "([a-z_0-9]+)"', (src / "src/config/option_defs.c").read_text()))
    disp = set(re.findall(r'strcmp\(func_name, "([a-z_0-9]+)"\)', (src / "src/config/binding_parse.c").read_text()))
    bad = 0
    for line in read("mango/config.conf").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, val = line.split("=", 1)
        if key.startswith(("bind", "mousebind", "axisbind", "gesturebind")):
            fields = val.split(",")
            d = fields[3] if key == "gesturebind" else fields[2]
            if d.strip() not in disp:
                fail(f"mango: unknown dispatcher '{d}' in: {line}"); bad += 1
        elif key not in opts and key not in ("env", "exec_once"):
            fail(f"mango: unknown option '{key}'"); bad += 1
        if key in ("window_rule", "layer_rule", "tag_rule"):
            for part in val.split(","):
                if part.split(":")[0] not in opts:
                    fail(f"mango: unknown rule field '{part.split(':')[0]}'"); bad += 1
    if not bad:
        ok("mango: every option, rule field and dispatcher exists in Mango's source")


def check_umbriel(src):
    src = Path(src)
    code = "".join(Path(f).read_text() for f in glob.glob(str(src / "src/config/*.cpp")))
    actions = set(re.findall(r'\{"([a-z][a-z0-9-]+)",\s*"', (src / "src/config/keybind_parse.cpp").read_text()))
    cfg = tomllib.loads(read("umbriel/config.toml"))
    bad = 0
    for k, v in cfg["keybinds"].items():
        a = (v["action"] if isinstance(v, dict) else v).split()[0]
        if a not in actions:
            fail(f"umbriel: unknown action '{a}' for {k}"); bad += 1

    def walk(x, path):
        nonlocal bad
        if isinstance(x, dict):
            for k, v in x.items():
                if path and path[0] in ("keybinds", "environment"):
                    continue
                if f'"{k}"' not in code:
                    fail(f"umbriel: unknown key {'.'.join(path + [k])}"); bad += 1
                walk(v, path + [k])
        elif isinstance(x, list):
            for i in x:
                walk(i, path)
    walk(cfg, [])
    if not bad:
        ok("umbriel: every key and action exists in Umbriel's source")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mango-src")
    ap.add_argument("--umbriel-src")
    a = ap.parse_args()
    print("Parsing"); check_parsing(); check_hyprland_lua()
    print("Installer placeholders"); check_installer_contract()
    if a.mango_src:
        print("Mango"); check_mango(a.mango_src)
    if a.umbriel_src:
        print("Umbriel"); check_umbriel(a.umbriel_src)
    print(f"\n{len(errors)} problem(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
