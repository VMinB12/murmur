---
id: "014"
title: "Runtime Metadata Boundary Cleanup"
status: done
jira: ""
owner: ""
created: 2026-04-05
updated: 2026-04-05
---

# 014 — Runtime Metadata Boundary Cleanup

Cleaned up the runtime metadata path introduced by the ingress refactor so canonical ingress metadata is now the single source of truth for downstream tool context, observability correlation, and programmatic delivery helpers. This completed ticket fixes the inter-agent hop-count propagation bug, makes the hop limit configurable, ensures hop-limit exhaustion produces an informative agent-visible outcome instead of crashing the run, implements the ADR-003 metadata projection boundary in runtime code, aligns runtime data structures around that boundary, and removes duplicated producer-side delivery assembly, legacy paths, and fallback behavior that would otherwise leak into the first published package surface.