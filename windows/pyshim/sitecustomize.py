"""Loaded by Python itself at start, when this folder is on PYTHONPATH (the
page's host and the launchers put it there): Linux's line endings for
whatever Longhand's Python writes on Windows (longhand_lf.py), a file
replaced even while another process reads it (longhand_replace.py), and a
line appended whole while another process appends too (longhand_append.py)."""
import longhand_lf  # noqa: F401
import longhand_append
import longhand_replace

longhand_replace.install()
longhand_append.install()   # after longhand_lf: it wraps the open that one leaves
