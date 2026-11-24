"""Loaded by Python itself at start, when this folder is on PYTHONPATH (the
page's host and the launchers put it there): Linux's line endings for
whatever Longhand's Python writes on Windows (longhand_lf.py), and a file
replaced even while another process reads it (longhand_replace.py)."""
import longhand_lf  # noqa: F401
import longhand_replace

longhand_replace.install()
