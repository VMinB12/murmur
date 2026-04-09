# Tasks: Remove Raw AI Stream Chat Path

## P1: Chat Path Cleanup

- [x] T001 Remove the demo chat surface's subscription to the raw agent stream topic and delete dead `ai.*` chat handlers that no longer affect rendering.
- [x] T002 Confirm whether any non-test runtime consumer still depends on the raw stream topic and, if none remain, remove the extra topic and broadcast path from the relevant `jido_murmur` modules.
- [x] T003 Update focused tests under `apps/murmur_demo/test/murmur_web/live/` and `apps/jido_murmur/test/jido_murmur/` to verify unchanged canonical chat behavior after the raw chat path is removed.
- [x] T004 Run focused tests for the touched LiveView and streaming files, then run `mix precommit` from `/Users/vincent.min/Projects/murmur`.