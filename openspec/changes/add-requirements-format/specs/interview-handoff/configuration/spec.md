## MODIFIED Requirements

### Requirement: IH-023 Shared and plugin-only settings
The language to speak to the person in and where session records live SHALL go to the general config (`shared/identity.json`); output location, package composition and the answers-file switch, per artifact language, labels, compression, context source and requirements format SHALL stay in the plugin's own file (`shared/plugins/interview-handoff.json`).

#### Scenario: Setting stored
- **WHEN** the plugin stores a setting
- **THEN** the speaking language and session-record location go to `shared/identity.json`, and output location, package composition, per artifact language, labels, compression, context source and requirements format go to `shared/plugins/interview-handoff.json`
