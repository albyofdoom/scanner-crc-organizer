"""Compatibility wrapper module.

Tests import `CRC32_Folder_Calc` (underscore name), but the implementation
file in this repo uses a hyphen in its filename. This shim loads the real
implementation and exposes the expected functions.
"""
from __future__ import annotations
import importlib.util
import os
import sys

_here = os.path.dirname(__file__)
_impl_path = os.path.join(_here, 'CRC32-Folder-Calc.py')

if not os.path.exists(_impl_path):
    raise ImportError(f"Implementation not found: {_impl_path}")

spec = importlib.util.spec_from_file_location('crc32_folder_calc_impl', _impl_path)
_mod = importlib.util.module_from_spec(spec)
# Execute the module to populate its globals
spec.loader.exec_module(_mod)

# Export commonly used symbols expected by tests
for _name in ('compute_crc32', 'scan_directory'):
    if hasattr(_mod, _name):
        globals()[_name] = getattr(_mod, _name)

# Also expose the original module for advanced use
impl = _mod
