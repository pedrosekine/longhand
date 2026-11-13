# Agent references

For logo placement, asset exports, or logo theme integration, read
[the logo source of truth](docs/brand/README.md) before changing assets or UI.

For tests, read [README → Tests](README.md#tests) before adding or changing
one. The runner (`tests/run_all.py`) runs every test file in parallel, so a
new test must be parallel-safe: its own `tempfile` folders, its own
`XDG_STATE_HOME`/`XDG_CONFIG_HOME`, nothing written into the repo or the home
folder. Run only what you touched while working (`python3 tests/run_all.py
plan agent`, `--failed` after a failure), then the whole suite before
committing.
