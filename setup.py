import os
import re
import glob
import subprocess
from setuptools import setup

try:                                            # setuptools >= 70.1 carries its own bdist_wheel
    from setuptools.command.bdist_wheel import bdist_wheel as _bdist_wheel
except ImportError:                             # older setuptools: the separate "wheel" package
    try:
        from wheel.bdist_wheel import bdist_wheel as _bdist_wheel
    except ImportError:
        _bdist_wheel = None

all_paths = [
    p for p in glob.glob("script/**/*", recursive=True)
    if "__pycache__" not in p.split(os.sep) and not p.endswith((".pyc", ".pyo"))
]

# C / Go sources (bvk-ls, bvk-fr, bvk-xfer: src, include, *.go, go.mod, Makefile, build script) are build-time only:
# they ship in the sdist but must not be installed as executable scripts.
_ENGINE_DIRS = tuple(os.sep + d + os.sep for d in ("bvk-ls", "bvk-fr", "bvk-xfer"))
def _is_bvk_src(f):
    return any(d in f for d in _ENGINE_DIRS)

# Prebuilt bvk-<engine>-<os>-<cpu> binaries are installed as data files, not scripts:
# setuptools reads scripts as text to rewrite shebangs, which is unsafe for ELF / Mach-O.
_BIN_RE = re.compile(r"^bvk-(ls|fr|xfer)-(android|linux|darwin|freebsd)-(amd64|arm64|arm|386)$")

# ── which machine are we installing for? ─────────────────────────────────────────────────────────────────────────────
# The CPU / OS mapping lives in ONE place, _bvk_engine_target (AGENTS.md rule 9); setup.py asks it instead of copying it.
# pip builds the wheel ON the machine it installs to, so "this machine" is the right answer.  BVK_TARGET=<os>-<cpu>
# (e.g. darwin-arm64) overrides it, for building a wheel for another machine in CI.
_FORCED = os.environ.get("BVK_TARGET", "").strip()
_WHEEL_PLAT = {        # plat tag a wheel built for BVK_TARGET gets (a native build uses the tag of the running python)
    "linux-amd64":   "manylinux2014_x86_64",
    "linux-arm64":   "manylinux2014_aarch64",
    "linux-arm":     "manylinux2014_armv7l",
    "linux-386":     "manylinux2014_i686",
    "darwin-amd64":  "macosx_10_15_x86_64",
    "darwin-arm64":  "macosx_11_0_arm64",
    "freebsd-amd64": "freebsd_14_0_release_amd64",
    "android-arm64": "android_24_arm64_v8a",
    "android-arm":   "android_24_armeabi_v7a",
    "android-amd64": "android_24_x86_64",
}

def _host_target():
    """'<os>-<cpu>' for the engines this machine can run, '' = no prebuilt engine fits it, None = could not tell."""
    if _FORCED:
        return _FORCED
    probe = [p for p in all_paths if os.path.basename(p) == "bashbasicsbyvk_engine_target.sh"]
    if not probe:
        return None
    try:
        out = subprocess.check_output(
            ["bash", "-c", 'source "$1"; _bvk_engine_target; printf "%s %s" "$_bet_os" "$_bet_m"', "_", probe[0]],
            stderr=subprocess.DEVNULL, universal_newlines=True)
    except (OSError, subprocess.CalledProcessError):
        return None
    parts = out.split()
    return "-".join(parts) if len(parts) == 2 else ""

TARGET = _host_target()

def _wanted(f):
    name = os.path.basename(f)
    if not _BIN_RE.match(name):
        return False
    if TARGET is None:                           # cannot tell which machine this is: ship everything, as before
        return True
    return TARGET != "" and name.endswith("-" + TARGET)

binary_files = [f for f in all_paths if os.path.isfile(f) and _is_bvk_src(f) and _wanted(f)]
if TARGET == "":
    print("bashbasicsbyvk: no prebuilt engine for this CPU / OS; installing without binaries (Python / Node fallbacks are used)")
elif TARGET:
    print("bashbasicsbyvk: installing the %s engines (%d binaries)" % (TARGET, len(binary_files)))

script_files = [
    f for f in all_paths
    if os.path.isfile(f)
    and not f.endswith((".xlsx", ".txt"))
    and not _is_bvk_src(f)
]

resource_files = [
    f for f in all_paths
    if os.path.isfile(f)
    and f.endswith((".xlsx", ".txt"))
]

cmdclass = {}
if _bdist_wheel is not None:
    class bdist_wheel(_bdist_wheel):
        """A wheel that carries machine code is a PLATFORM wheel: tag it py3-none-<platform>, never py3-none-any.
        With the 'any' tag pip's wheel cache hands a wheel built on one CPU / OS to a different one (a copied home
        folder, a new phone, a docker image run on another CPU) and the wrong binaries get installed."""
        def finalize_options(self):
            if _FORCED and self.plat_name is None and TARGET in _WHEEL_PLAT:
                self.plat_name = _WHEEL_PLAT[TARGET]
            super().finalize_options()
            self.root_is_pure = not binary_files

        def get_tag(self):
            _impl, _abi, plat = super().get_tag()
            return ("py3", "none", plat)
    cmdclass["bdist_wheel"] = bdist_wheel

setup(
    # explicit empty list turns OFF setuptools flat-layout auto-discovery: the repo has no python
    # packages (everything under script/ is installed as scripts/data), and a second top-level
    # folder (corpus/) makes auto-discovery abort with "Multiple top-level packages discovered".
    packages=[],
    scripts=script_files,
    data_files=[
        ("bashbasicsbyvk", resource_files),
        ("bashbasicsbyvk/bin", binary_files),
    ],
    cmdclass=cmdclass,
)
