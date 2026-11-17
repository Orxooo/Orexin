#!/usr/bin/env python3
"""Exercise local installer handoff checks against isolated application fixtures."""
import os
from pathlib import Path
import plistlib
import shlex
import subprocess
import tempfile

root = Path(tempfile.mkdtemp(prefix="orexin-install-fixture-"))
source = root / "Source.app"
(source / "Contents/MacOS").mkdir(parents=True)
(source / "Contents/Info.plist").write_bytes(plistlib.dumps({
    "CFBundleIdentifier": "test.orexin.installer",
    "CFBundleExecutable": "Fixture",
    "CFBundlePackageType": "APPL",
    "CFBundleVersion": "1",
    "CFBundleShortVersionString": "9.9.9",
}))
subprocess.run(["/bin/cp", "/usr/bin/true", str(source / "Contents/MacOS/Fixture")], check=True)
subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(source)], check=True, capture_output=True)
installer = (Path(__file__).parent / "install-local.sh").read_text()

def run_case(label, version, marker, accepted):
    case = root / label
    target = case / "Orexin.app"
    (target / "Contents/Helpers").mkdir(parents=True)
    (target / "Contents/MacOS").mkdir()
    info = {"CFBundleIdentifier": "test.orexin.installed",
            "CFBundleVersion": "1", "CFBundleShortVersionString": version}
    if marker:
        info["OrexinHelperHandoffSupported"] = True
    (target / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    for path in [target / "Contents/Helpers/orexin", target / "Contents/MacOS/Orexin"]:
        path.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$OREXIN_TEST_CALLS"\n')
        path.chmod(0o700)
    replacements = {
        "TARGET_APP=/Applications/Orexin.app": "TARGET_APP=" + shlex.quote(str(target)),
        "/usr/bin/pkill -x Orexin || true": ":",
        '/usr/bin/open "$TARGET_APP"': ":",
    }
    script = installer
    for old, new in replacements.items():
        if script.count(old) != 1:
            raise AssertionError(f"installer isolation anchor changed: {old}")
        script = script.replace(old, new)
    shell = case / "install.zsh"
    shell.write_text(script)
    env = dict(os.environ, OREXIN_BACKUP_DIR=str(case / "backup"),
               OREXIN_TEST_CALLS=str(case / "calls"))
    result = subprocess.run(["/bin/zsh", str(shell), str(source)], env=env,
                            text=True, capture_output=True, timeout=30)
    calls = (case / "calls").read_text().splitlines() if (case / "calls").exists() else []
    assert (result.returncode == 0) == accepted, (label, result.returncode, calls)
    if accepted:
        assert calls == ["service-start", "--prepare-helper-update", "service-stop"], (label, calls)
        assert (case / "backup/Orexin.app").is_dir()
        assert (target / "Contents/MacOS/Fixture").is_file()
    else:
        assert not calls and not (case / "backup").exists()
    print(f"{label}: {'accepted' if accepted else 'rejected'}")

run_case("stable-with-handoff", "1.1.1", True, True)
run_case("old-dev-without-handoff", "1.1.1", False, False)
run_case("existing-dev-without-marker", "1.1.3", False, True)
run_case("old-stable-without-handoff", "1.1.0", False, False)
print(f"fixtures: {root}")
