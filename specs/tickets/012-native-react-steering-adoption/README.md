---
id: "012"
title: "Native ReAct Steering Adoption"
status: specifying
owner: ""
created: 2026-04-04
updated: 2026-04-04
---

Analyze whether Murmur should replace its custom mid-run message injection path with the native `steer/3` and `inject/3` controls added in `jido_ai` 2.1. The ticket covers current-state analysis, upstream feature evaluation, migration fit, and a validation-ready spec for adopting the native ReAct control path where it reduces Murmur-owned runtime behavior without regressing workspace semantics.