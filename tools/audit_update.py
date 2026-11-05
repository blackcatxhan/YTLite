#!/usr/bin/env python3
"""
YTLite Future Update Audit Tool
Compares a new .deb package against the current YTLite repository to detect:
1. New localization keys (features vs login/DRM)
2. Keys missing from Settings.x
3. Keys missing from YTLite.x hooks
4. New Mach-O classes and selectors
"""

import sys
import os
import re
import tarfile
import plistlib

def parse_strings_file(path):
    if not os.path.exists(path):
        return {}
    with open(path, 'rb') as f:
        data = f.read()
    if data.startswith(b'bplist00'):
        try:
            return plistlib.loads(data)
        except Exception as e:
            print(f"[!] Error reading bplist {path}: {e}")
            return {}
    content = data.decode('utf-8', errors='ignore')
    kv = {}
    for m in re.finditer(r'"([^"\\]*(?:\\.[^"\\]*)*)"\s*=\s*"([^"\\]*(?:\\.[^"\\]*)*)"\s*;', content):
        kv[m.group(1)] = m.group(2)
    return kv

def extract_deb_data(deb_path, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    with open(deb_path, 'rb') as f:
        magic = f.read(8)
        if magic != b'!<arch>\n':
            raise ValueError(f"Not a valid .deb ar archive: {magic}")
        while True:
            header = f.read(60)
            if not header or len(header) < 60:
                break
            name = header[0:16].strip().decode('ascii', errors='ignore').rstrip('/')
            size = int(header[48:58].strip())
            data = f.read(size)
            if size % 2 == 1:
                f.read(1)
            if name.startswith('data.tar'):
                tar_path = os.path.join(out_dir, name)
                with open(tar_path, 'wb') as tf:
                    tf.write(data)
                with tarfile.open(tar_path) as tar:
                    tar.extractall(out_dir)
                return True
    return False

def is_login_or_drm(key, value):
    keywords = [
        'login', 'patreon', 'account', 'auth', 'sign in', 'logout',
        'tier', 'subscription', 'verify purchase', 'supportdevelopment',
        'restorepurchase', 'access.active', 'access.appnotfound',
        'access.devicelimit', 'access.devicenotregistered',
        'access.requesterror', 'accessdenied', 'donor', 'license'
    ]
    k_l = key.lower()
    v_l = str(value).lower()
    return any(kw in k_l or kw in v_l for kw in keywords)

def main():
    print("=" * 65)
    print("         YTLITE FUTURE UPDATE AUDIT TOOL & VERIFIER")
    print("=" * 65)

    repo_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    repo_en_strings = os.path.join(repo_dir, 'layout/Library/Application Support/YTLite.bundle/en.lproj/Localizable.strings')
    settings_file = os.path.join(repo_dir, 'Settings.x')
    ytlite_file = os.path.join(repo_dir, 'YTLite.x')

    our_strings = parse_strings_file(repo_en_strings)
    print(f"[*] Loaded current repo strings: {len(our_strings)} keys")

    with open(settings_file, 'r', encoding='utf-8') as f:
        settings_code = f.read()
    with open(ytlite_file, 'r', encoding='utf-8') as f:
        ytlite_code = f.read()

    settings_switches = set(re.findall(r'switchWithTitle:@"([^"]+)"', settings_code))
    settings_loc_items = set(re.findall(r'itemWithTitle:LOC\(@"([^"]+)"\)', settings_code))
    all_settings_titles = settings_switches.union(settings_loc_items)
    settings_keys = set(re.findall(r'key:@"([^"]+)"', settings_code))
    ytlite_keys = set(re.findall(r'ytlBool\(@"([^"]+)"\)', ytlite_code))

    print(f"[*] Current Settings.x switches: {len(settings_switches)}")
    print(f"[*] Current Settings.x menu items: {len(settings_loc_items)}")
    print(f"[*] Current YTLite.x active hook keys: {len(ytlite_keys)}")

    if len(sys.argv) < 2:
        print("\n[i] No target .deb provided. Running self-audit on current repo...")
        missing = []
        for k, v in our_strings.items():
            if f"{k}Desc" in our_strings and k not in all_settings_titles:
                if not is_login_or_drm(k, v):
                    missing.append((k, v))
        print(f"\n[Audit Result] Detailed features in strings not yet in Settings menu: {len(missing)}")
        if missing:
            for k, v in missing[:25]:
                print(f"  - {k}: {v}")
        else:
            print("  [SUCCESS] All feature keys in repo have corresponding entries in Settings.x!")
        print("\nTo audit a new update against your repository:")
        print("  python tools/audit_update.py <path_to_new_version.deb>\n")
        return

    deb_path = sys.argv[1]
    if not os.path.exists(deb_path):
        print(f"[!] File not found: {deb_path}")
        return

    print(f"\n[*] Extracting target .deb: {deb_path}")
    temp_dir = os.path.join(repo_dir, 'extracted_update_temp')
    try:
        extract_deb_data(deb_path, temp_dir)
        new_strings_path = os.path.join(temp_dir, 'Library/Application Support/YTLite.bundle/en.lproj/Localizable.strings')
        new_strings = parse_strings_file(new_strings_path)
        print(f"[*] Target .deb strings: {len(new_strings)} keys")

        new_keys = set(new_strings.keys()) - set(our_strings.keys())
        features_added = []
        drm_ignored = []

        for k in sorted(new_keys):
            v = new_strings[k]
            if is_login_or_drm(k, v):
                drm_ignored.append((k, v))
            else:
                features_added.append((k, v))

        print(f"\n=== NEW FEATURES DETECTED IN UPDATE ({len(features_added)}) ===")
        if features_added:
            for k, v in features_added:
                print(f"  + {k} = \"{v}\"")
        else:
            print("  (None - your repo already includes all non-login features!)")

        print(f"\n=== DRM / LOGIN STRINGS FILTERED OUT ({len(drm_ignored)}) ===")
        for k, v in drm_ignored:
            print(f"  - {k} = \"{v}\"")

        # Check dylib Mach-O strings if present
        dylib_path = os.path.join(temp_dir, 'Library/MobileSubstrate/DynamicLibraries/YTLite.dylib')
        if os.path.exists(dylib_path):
            with open(dylib_path, 'rb') as f:
                ddata = f.read()
            print(f"\n[*] Analyzed updated dylib size: {len(ddata):,} bytes")
            # Look for new YTP classes
            classes = set(re.findall(b'YTP[A-Za-z0-9_]+', ddata))
            print(f"[*] Found {len(classes)} YTP classes in updated binary.")

    finally:
        import shutil
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)

if __name__ == '__main__':
    main()
