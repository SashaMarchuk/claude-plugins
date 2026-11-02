# orchestrator

## Purpose

Requirements for the from-scratch rebuild of this plugin as an orchestrator. Only firm owner decisions are
written here; everything else is open (see `../../reference/open-questions.md`).

## Requirements

### Requirement: H-001 · The workflow is agnostic and built from replaceable elements

The orchestrator's workflow MUST be assembled from replaceable elements, each chosen in configuration rather
than fixed in the plugin. The default MUST be GSD for execution and OpenSpec for requirements. The requirements
format MUST be swappable for any other format the user prefers, without changing the plugin's code.

#### Scenario: Acceptance

Given no workflow is configured, When a run starts, Then GSD executes the work and OpenSpec holds the
requirements; and Given the user has configured another requirements format, When a run starts, Then that format
is used in place of OpenSpec and no plugin code changed to allow it.

*Trace: owner decision, 2026-11-01 (relayed by the orchestrator session that assigned this work)*
