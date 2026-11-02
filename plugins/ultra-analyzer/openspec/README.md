# ultra-analyzer — requirements (OpenSpec)

Status: **requirements not yet defined.** Nothing in this tree is a decision yet, and `specs/` is empty on
purpose. Until requirements are written here, the plugin's README and source describe what it does today.

This is the plugin's own OpenSpec root, isolated from every other plugin in the marketplace. A firm owner
decision becomes a requirement in `specs/<area>/spec.md` (`### Requirement: <ID> · <title>`, one
`#### Scenario:` each); a proposed change goes under `changes/<change>/`. Validate from this plugin's folder:

    OPENSPEC_TELEMETRY=0 npx -y @fission-ai/openspec@1.15.0 validate --specs --no-interactive

This folder ships with the plugin when it is installed. It is documentation only; nothing reads it at run time.
