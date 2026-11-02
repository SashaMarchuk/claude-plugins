# orchestrator-workflow Specification

## Purpose
The workflow of the rebuilt harness orchestrator: which process it runs, and how far each element of it can be replaced.

## Requirements

### Requirement: H-001 Agnostic workflow of replaceable elements
The orchestrator's workflow MUST be agnostic and built from replaceable elements; the default MUST be GSD for execution and OpenSpec for requirements, and OpenSpec MUST be swappable for another requirements format the user prefers.

#### Scenario: Default workflow
- **WHEN** a run starts and the user has chosen nothing
- **THEN** GSD executes the work and OpenSpec holds the requirements

#### Scenario: Another requirements format
- **WHEN** a run starts and the user prefers another requirements format
- **THEN** that format is used in place of OpenSpec
