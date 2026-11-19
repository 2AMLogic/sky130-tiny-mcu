# records

Append-only evidence. A record is never edited after it lands; a later record
supersedes it.

```
records/<kind>/<timestamp>-<sha>/
    provenance.json     required
    ...                 logs, results.xml, a README explaining them
```

- `<kind>`: what was measured, e.g. `smoke`.
- `<timestamp>`: UTC, `YYYYMMDDTHHMMSSZ` (e.g. `20261119T054321Z`).
  `<sha>`: 7-40 hex chars of the commit the run used.
- `provenance.json` is a JSON object with non-empty values for: `commit` (full
  SHA), `pdk_revision` (the open_pdks revision, or an explicit
  `"n/a, no PDK used"` note while no record uses the PDK), `tool_versions`
  (object, tool name to version, probed from the tools that actually ran —
  never copied from the pins in `scripts/setup-env.sh`) and `command` (the
  exact command that produced the record).

A re-run adds a new directory; it never edits or deletes an existing one.
Records are committed to the repository, so the evidence trail travels with
the code it was produced from.

`make -C verification smoke` writes a `smoke/` record as part of its run.
Check the whole tree with
`python3 -I verification/tools/lint_records.py` (CI runs it too).
