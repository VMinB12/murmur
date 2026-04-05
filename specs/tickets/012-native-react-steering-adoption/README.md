---
id: "012"
title: "Native ReAct Steering Adoption"
status: done
owner: ""
created: 2026-04-04
updated: 2026-04-05
---

Replaced Murmur's previous follow-up mechanism with an ingress-coordinated model built around native `jido_ai` `steer/3` and `inject/3` controls. The completed work introduces a per-session ingress coordinator, aligns the runtime input contract to `jido_ai`, removes the previous Murmur-owned runtime workaround, narrows `MessageInjector` to context shaping, and updates tests and package documentation to match the new runtime boundary.