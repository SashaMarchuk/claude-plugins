# orchestrator

## Purpose

Requirements for the from-scratch rebuild of this plugin as an orchestrator. Only firm owner decisions are
written here; everything else is open (see `../../reference/open-questions.md`).

## Requirements

### Requirement: H-001 · The workflow is agnostic and built from replaceable elements

The orchestrator's workflow MUST be agnostic and built from replaceable elements. The default MUST be GSD for
execution and OpenSpec for requirements. OpenSpec MUST be swappable for another requirements format the user
prefers.

#### Scenario: Acceptance

Given the user has chosen nothing, When a run starts, Then GSD executes the work and OpenSpec holds the
requirements; and Given the user prefers another requirements format, When a run starts, Then that format is
used in place of OpenSpec.

*Trace: owner decision, 2026-11-01, given in the task that started this OpenSpec migration*
