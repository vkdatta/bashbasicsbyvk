import os
import glob
from setuptools import setup

all_paths = glob.glob("script/**/*", recursive=True)

script_files = [
    f for f in all_paths
    if os.path.isfile(f)
    and not f.endswith((".xlsx", ".txt"))
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
    ],
)