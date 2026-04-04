# Journal: Frontend Architecture Review — murmur_web & murmur_demo

## 2026-04-04

- Resumed ticket 011 during the specification phase.
- Reviewed project-level specs, ticket research, and the current frontend code in `jido_murmur_web` and `murmur_demo`.
- Confirmed the main research findings still match the codebase: `jido_murmur_web` still includes arXiv-oriented default artifact renderers, and `murmur_demo` still contains SQL-specific artifact behavior in the workspace UI.
- Drafted `Spec.md` around three primary outcomes: a generic reusable workspace shell, consumer-owned domain presentation, and cleaner frontend boundaries with consistent DaisyUI-driven interaction patterns.
- Drafted `Plan.md` and `Tasks.md` for the validated spec.
- Flagged that the implementation changes package responsibilities and should be captured with an ADR and architecture doc updates during implementation.
- Completed the artifact boundary refactor by removing built-in domain renderers from `jido_murmur_web`, adding demo-owned artifact renderer and action modules, and delegating SQL artifact follow-up behavior out of `WorkspaceLive`.
- Refined the shared chat primitives around DaisyUI chat and collapse patterns, extracted split and unified workspace presentation into dedicated components, and moved non-rendering state helpers into `MurmurWeb.Live.WorkspaceState`.
- Validated the refactor with focused shared-component, installer, LiveView, artifact, and integration tests before documenting the new frontend ownership model.
- Fixed post-refactor regressions in the shared chat layer by restoring the demo app's access to `jido_murmur_web` hook and Tailwind sources, and by updating shared tool-call rendering to handle `JidoMurmur.UITurn.ToolCall` structs without Access errors.
- Fixed the `murmur_demo` child-app asset aliases to use the configured `murmur_demo` Tailwind and esbuild profiles so `mix assets.build` works from the child app as well as the umbrella root.