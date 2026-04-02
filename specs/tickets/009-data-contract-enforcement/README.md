---
id: "009"
title: "Data Contract Enforcement"
status: specifying
jira: ""
owner: ""
created: 2026-03-31
updated: 2026-04-02
---

# 009 — Data Contract Enforcement

Enforce typed data contracts across module boundaries to prevent shape mismatches (like the artifact envelope bug) from reaching production. Covers typed structs with `@enforce_keys`, integration tests for rendering pipelines, normalized data paths, and Dialyzer integration.

For this ticket, the key distinction is:

- `%Envelope{}` is the canonical in-memory artifact shape inside Murmur
- `:erlang.term_to_binary` is the checkpoint serialization format used to persist that shape
