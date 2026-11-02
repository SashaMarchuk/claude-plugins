# harness — requirements (OpenSpec)

Requirements for the **from-scratch rebuild** of this plugin (the orchestrator). The plugin that ships today
(v0.6) is described by `../docs/DESIGN.md`, not by this tree.

Status: **one requirement defined** (H-001, the agnostic workflow). Everything else is **not yet defined**;
`reference/open-questions.md` says why and where it is being decided.

| Path | What it holds |
|---|---|
| `specs/orchestrator/spec.md` | Firm owner decisions, `### Requirement: H-nnn · Title`, one `#### Scenario:` each |
| `reference/open-questions.md` | Q-: not decided. Never build against these |
| `changes/<change>/` | Proposed changes (deltas by ID) |

This is the plugin's own OpenSpec root, isolated from every other plugin. Validate from this plugin's folder:

    OPENSPEC_TELEMETRY=0 npx -y @fission-ai/openspec@1.15.0 validate --specs --no-interactive

This folder ships with the plugin when it is installed. It is documentation only; nothing reads it at run time.
