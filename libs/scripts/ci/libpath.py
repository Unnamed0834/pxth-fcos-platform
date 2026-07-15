#!/usr/bin/env python3



















import importlib
import sys
from pathlib import Path


_SHARED_LIB = Path(__file__).resolve().parent


def shared_lib():
    """Return the path to libs/scripts/ci/ as a string."""
    return str(_SHARED_LIB)


def import_contract():
    """Ensure contract.py is importable and return the imported module.

    Idempotent: repeated calls do not duplicate sys.path entries. Side effects
    are limited to inserting our own directory at the front of sys.path, which
    is what the historical ``from contract import ...`` calling convention
    relies on.
    """
    lib = shared_lib()
    if lib not in sys.path:
        sys.path.insert(0, lib)
    return importlib.import_module("contract")
