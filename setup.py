import os
import glob
from setuptools import setup

all_paths = glob.glob('script/**/*', recursive=True)
script_files = [f for f in all_paths if os.path.isfile(f)]

setup(
    scripts=script_files
)
