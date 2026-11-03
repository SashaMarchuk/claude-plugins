# Requirements format: OpenSpec

Read this only when the person has set `requirements.format` to `openspec` (see `references/config.md`). If the project has no OpenSpec root (see Detect), ask explicitly whether to use OpenSpec here before anything else; never create one without a yes. It adds one thing to the plugin: carrying the person's **confirmed** decisions into an OpenSpec change, and seeding a round from one. It replaces nothing. The analysis file is still written first, every round, and is never rewritten; what lands in OpenSpec is derived from it.

Checked against OpenSpec 1.16 (`schemas/spec-driven`, `docs/agent-contract.md`, the validator). When the installed version disagrees with this file, the installed one wins: say so and follow it.

## Detect

The project has an OpenSpec root when an `openspec/` folder exists at the project root or a parent: `openspec/specs/` holds the current behaviour, `openspec/changes/<name>/` holds one unit of work. A folder under `openspec/changes/archive/` is history, not a change.

The `openspec` command line tool is optional. Use it when it is installed, never install it. Without it, read and write the Markdown files directly, with two exceptions below (stores, validation).

**Stores.** If `openspec/config.yaml` points to a store (`store:`), the change does not live in the local folder. With the tool, take the change path from `openspec status --change <name> --json` (`changeRoot`) or `openspec new change <name> --json` (`change.path`). Without the tool, do not write anything: say why and leave it there.

## Which change a topic belongs to

The link lives in the context document, never in config: one line naming the change folder, or saying the person chose "not for this topic". It is set the first time it matters, in run or in collect, by asking: an existing active change (`openspec list --json`, or the folders under `openspec/changes/` minus `archive/`), a new one with a kebab-case name proposed from the topic, or not for this topic.

If the linked change has since been archived, never write into `archive/`. Say that its decisions are now in the main specs and offer a new change.

## Run: seeding a round

Offered as one more answer to the existing question about where the context document takes its starting material from.

- **Main specs the change touches** go into the context document as *current documented behaviour*, by link, never copied. They are not the person's decisions and are never presented as such.
- **The change's own delta specs and design decisions** are drafts, often written by an assistant. They go into the next package's ratification block (`references/analysis.md`), as sentences to say yes or a correction to.
- **`design.md` → `## Open Questions`** become candidates for the grill. The grill still runs the whole tree and the person still confirms every item.
- **The rejected list is never filled from OpenSpec.** A REMOVED requirement is behaviour going away, not an idea the person refused.

## Collect: carrying decisions in

This is the last step of collect, after the analysis is written and after anything the person answered right there in the session.

### What is eligible

Only an item that is **all** of: labelled `settled`, ratified `confirmed`, from a resource marked source of truth, and carrying no unresolved contradiction. A contradiction the person settled in the session counts as resolved.

Everything else stays open in the plugin's next round and is never written: `partial`, `untouched`, `not ratified`, an unresolved contradiction, anything from a resource that needs confirmation. A `deferred` item may go to `design.md` → `## Open Questions`. A `premise rejected` item is never turned into a REMOVED requirement by inference; only an explicit decision by the person removes a requirement.

### Where each one goes

- **Observable behaviour** → a delta spec, `specs/<capability>/spec.md` inside the change.
  - Reuse the exact existing capability path (`openspec list --specs`, or the folders under `openspec/specs/`). Never invent a near-duplicate.
  - A new requirement goes under `## ADDED Requirements`. A requirement that already exists in the main spec goes under `## MODIFIED Requirements`, with the **whole** existing block copied in and only the decided part changed. Partial content loses detail when the change is archived.
  - Before drafting, compare each decision with the main specs and the other active changes **by meaning**, not only by name. An overlap with a requirement under a different name is put to the person as a contradiction (`references/analysis.md`), showing both, and they choose: new requirement or change to the existing one.
- **How it is built** → `design.md` → `## Decisions`.
- **Deferred** → `design.md` → `## Open Questions`.

Verbatim quotes stay in the analysis, out of requirement text. What traces each written block back to its evidence is the ledger in the context document (below): item id, analysis path, file and requirement.

### The shape OpenSpec expects

```markdown
## ADDED Requirements

### Requirement: <name>
The system SHALL <one behaviour>.

#### Scenario: <the case, named>
- **WHEN** <trigger>
- **THEN** <outcome>
```

- **IDs follow the project.** Where the existing requirement headers carry an ID (`### Requirement: PREFIX-NNN Title`), a new requirement takes the next unused number with the same prefix, and a MODIFIED block keeps its header exactly. An ID is never reused. Where headers carry no ID, add none.
- One behaviour per requirement, with SHALL or MUST. At least one scenario, exactly four `#`, with WHEN and THEN.
- A delta that creates a new capability opens with `## Purpose`: one or two sentences, 50 characters or more.
- A REMOVED entry carries `**Reason**` and `**Migration**`.
- Headings and SHALL/MUST stay in English; the validator relies on them. Prose follows the language `openspec/config.yaml` sets, else the language the existing OpenSpec files use, else `language.documents`.
- A new change also needs a `proposal.md`: `## Why` (50 to 1000 characters, from the person's own reason for the topic), `## What Changes`, and `## Capabilities` listing every capability it touches.
- **Scenarios carry no dates**, like every requirement this plugin records.

### Scenarios come from the person

Build a scenario only from the person's own words, or from a worked case they confirmed. Any detail they did not say makes the whole block *drafted*.

### Preview, then write

Every write is shown first, block by block, each with the item id it comes from. Drafted detail is marked **in the preview only**, never in the file, since the file reaches the main specs on archive. The person answers yes, an edit, or skip per block. "Yes to all" covers only fully grounded blocks; a drafted block needs its own yes. **Autopilot never skips this**: it is a decision about the subject, not a setting.

An edit the person makes in the preview is new words from them. Record it verbatim in the context document, because the analysis is not rewritten and the next contradiction check must see it.

Then:

- Re-read each target file right before writing it; other people edit these files.
- Existing text is changed only with a yes on that exact change, and nothing is deleted without a yes on that deletion.
- **A later round changing a block this plugin added to the same change** edits that ADDED block in place, with a yes on the edit. Never ADDED and MODIFIED for the same name in one change: the validator rejects it.
- A new change is created with `openspec new change <name>` when the tool is installed, otherwise as a plain folder. It is created only after the person agreed to it.

### Validate

With the tool installed, run `openspec validate <change> --json` and report what it says, warnings included. Offer fixes; never fix silently. Without the tool, say that validation was not run.

A change holding only design decisions has no delta and fails validation. That is expected: report it and stop. **Never set `skip_specs: true`** (it asserts that no behaviour changes, which is the person's call) and never invent a requirement to satisfy the validator.

### Record and re-run

The context document, rewritten anyway, keeps the change link and a ledger: item id → file and requirement it went to. A re-run of collect on a resource already processed does not analyse it again, but offers this step for confirmed items with no ledger entry yet. Nothing is written twice.

## Never

- Write into `openspec/specs/`, `openspec/changes/archive/`, `openspec/config.yaml` or a change's `tasks.md`.
- Archive or sync a change.
- Set `skip_specs` or `retire_capabilities`.
- Write a requirement the person did not confirm, or a scenario detail they did not say without their yes on it.
- Replace the analysis, or treat an OpenSpec file as evidence of what the person said.
