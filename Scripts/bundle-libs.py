"""Copy the reachable Homebrew dylibs and rewrite their install names."""
import pathlib
import shutil
import subprocess
import sys

exe, frameworks, notices = map(pathlib.Path, sys.argv[1:4])
prefix = pathlib.Path(sys.argv[4])
copied = {}

def run(*args):
    return subprocess.check_output(args, text=True).strip()

def bundle(source, target):
    dependencies = [
        row.strip().split(" (compatibility version", 1)[0]
        for row in run("otool", "-L", str(source)).splitlines()[1:]
    ]
    if source.suffix == ".dylib":
        old_id = run("otool", "-D", str(source)).splitlines()[-1]
        dependencies = [dep for dep in dependencies if dep != old_id]
        run("install_name_tool", "-id", "@rpath/" + target.name, str(target))
    for dep in dependencies:
        if dep.startswith(("/usr/lib/", "/System/Library/")):
            continue
        path = pathlib.Path(dep)
        if not path.is_absolute() or not path.is_relative_to(prefix):
            raise RuntimeError(f"Cannot bundle {dep} (from {source})")
        dest = frameworks / path.name
        original = path.resolve(strict=True)
        if dest in copied and copied[dest] != original:
            raise RuntimeError(f"Conflicting libraries named {path.name}")
        if dest not in copied:
            copied[dest] = original
            shutil.copyfile(original, dest)
            bundle(original, dest)
            relative = original.relative_to(prefix / "Cellar")
            formula = relative.parts[0]
            cellar = prefix / "Cellar" / formula / relative.parts[1]
            for license_file in cellar.iterdir():
                if license_file.is_file() and license_file.name.lower().startswith(("license", "copying", "copyright", "notice")):
                    shutil.copyfile(license_file, notices / (formula + "-" + license_file.name))
        base = "@loader_path/" if source.suffix == ".dylib" else "@executable_path/../Frameworks/"
        run("install_name_tool", "-change", dep, base + dest.name, str(target))

bundle(exe, exe)

# Homebrew bottles can require a newer system than the app's own SDK minimum.
versions = [sys.argv[5]]
for path in copied:
    for line in run("vtool", "-show-build", str(path)).splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[0] == "minos":
            versions.append(fields[1])
print(max(versions, key=lambda value: tuple(map(int, value.split(".")))))
