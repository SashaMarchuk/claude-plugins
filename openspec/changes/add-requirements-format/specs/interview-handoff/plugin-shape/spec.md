## MODIFIED Requirements

### Requirement: IH-058 No connector or method named in code
No file under `commands/`, `skills/` or `scripts/` SHALL name a connector, a method or a requirements format; the skill SHALL name the sources it needs and read what answers them from the resolved config; concrete tool and method names SHALL appear only in `config/recommended.json`, and a requirements format SHALL be named only inside its own file under `references/formats/`.

#### Scenario: Source searched for names
- **WHEN** the files under `commands/`, `skills/` and `scripts/` are searched for a connector, method or format name
- **THEN** none is found; concrete tool and method names appear only in `config/recommended.json`, and a format name only in its own file under `references/formats/`

### Requirement: IH-069 Edits only its own output
The plugin SHALL NOT edit anything except its own package files, the analysis output, its own configuration settings, and, with the person's yes on each write, the files of the one requirements-format change the person linked to the topic.

#### Scenario: Files written
- **WHEN** the plugin runs
- **THEN** the only files it changes are its package files, the analysis output, its configuration settings, and requirements-format change files the person approved write by write
