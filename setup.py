import os
import glob
from setuptools import setup

all_paths = [
    p for p in glob.glob("script/**/*", recursive=True)
    if "__pycache__" not in p.split(os.sep) and not p.endswith((".pyc", ".pyo"))
]

# Go sources (script/file/engine/bvk-ls/*.go, go.mod, build.sh) are build-time only:
# they ship in the sdist but must not be installed as executable scripts.
_GO_SRC = os.sep + "bvk-ls" + os.sep
def _is_go_src(f):
    return _GO_SRC in f

# Prebuilt bvk-ls-linux-<arch> binaries are installed as data files, not scripts:
# setuptools reads scripts as text to rewrite shebangs, which is unsafe for ELF.
binary_files = [
    f for f in all_paths
    if os.path.isfile(f) and _is_go_src(f)
    and os.path.basename(f).startswith("bvk-ls-linux-")
]
script_files = [
    f for f in all_paths
    if os.path.isfile(f)
    and not f.endswith((".xlsx", ".txt"))
    and not _is_go_src(f)
]

resource_files = [
    f for f in all_paths
    if os.path.isfile(f)
    and f.endswith((".xlsx", ".txt"))
]

setup(
    scripts=script_files,
    data_files=[
        ("bashbasicsbyvk", resource_files),
        ("bashbasicsbyvk/bin", binary_files),
    ],
)