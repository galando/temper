# Ledger

A small multi-tenant invoicing service. Everything is in memory; `ledger.api.handle` is the entry point the web
layer calls. Read `CONVENTIONS.md` before changing anything: every change must follow it.

Run the suite: `python3 -m unittest discover -s unit -t .`
