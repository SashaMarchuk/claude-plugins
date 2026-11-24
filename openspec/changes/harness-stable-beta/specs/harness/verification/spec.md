## ADDED Requirements

### Requirement: H-053 Verification block in every pull request
Every pull request that the harness opens MUST contain a Verification block.

Source: interview 2026-11-24 R12.1
OPEN: see design.md OPEN-VERIFICATION-3

#### Scenario: Pull request opened by the harness
- **WHEN** the harness opens a pull request for a ticket
- **THEN** the pull request body contains a Verification block

### Requirement: H-054 The block records the checks actually done, with or without a predefined list
The Verification block SHALL keep a record of what happened and of the checks that were actually done, and it SHALL record those checks even when no predefined list of checks exists.

Source: interview 2026-11-24 R12.2, R12.3
OPEN: see design.md OPEN-VERIFICATION-3

#### Scenario: Checks from a predefined list
- **WHEN** a predefined list of checks exists and checks are done
- **THEN** the Verification block records each check that was actually done

#### Scenario: Checks without a predefined list
- **WHEN** checks are done without a predefined list
- **THEN** the Verification block records each check that was actually done

### Requirement: H-055 Merge requires an independent validator pass verdict
Before it merges, the harness merge step MUST check that the independent validator gave the change a "passed" verdict, and MUST NOT merge without one. "Passed with remarks" alone does not satisfy this gate; H-058 governs it.

Source: interview 2026-11-24 R13.1; the independent validator is existing harness behaviour that stays (decided context of the interview, not asked); remarks handling: design.md D15
OPEN: see design.md OPEN-VERIFICATION-5

#### Scenario: Pass verdict present
- **WHEN** the merge step runs and a "passed" verdict from the independent validator exists for the change
- **THEN** the merge may proceed, subject to the other merge gates

#### Scenario: Verdict missing
- **WHEN** the merge step runs and no validator verdict exists for the change
- **THEN** the merge step refuses to merge

#### Scenario: Fail verdict
- **WHEN** the merge step runs and the validator verdict is a fail
- **THEN** the merge step refuses to merge

#### Scenario: Passed-with-remarks verdict
- **WHEN** the merge step runs and the only validator verdict is "passed with remarks"
- **THEN** the merge step does not treat it as "passed" and follows H-058

### Requirement: H-056 By default at least one test runs and all tests pass
By default, verification SHALL check that all tests passed and that the number of tests run is not zero.

Source: interview 2026-11-24 R13.3
OPEN: see design.md OPEN-VERIFICATION-2

#### Scenario: All tests pass
- **WHEN** the default profile is active and at least one test ran and every test passed
- **THEN** the test check passes

#### Scenario: A test fails
- **WHEN** the default profile is active and any test failed
- **THEN** the test check fails

#### Scenario: Zero tests
- **WHEN** the default profile is active and zero tests ran
- **THEN** the test check fails

### Requirement: H-057 Zero tests pass only when the profile allows it
A profile MAY be configured to skip the test-count check, and verification SHALL accept zero tests only when the active profile is configured that way.

Source: interview 2026-11-24 R13.4
OPEN: see design.md OPEN-VERIFICATION-2

#### Scenario: Profile allows zero tests
- **WHEN** the active profile is configured to skip the test-count check and zero tests ran
- **THEN** the test count does not fail verification

#### Scenario: Non-default profile keeps the count check
- **WHEN** the active profile is not the default profile, it does not skip the test-count check, and zero tests ran
- **THEN** verification fails

### Requirement: H-058 Pass-with-remarks follows the autonomy level
What the harness does with a "passed with remarks" verdict SHALL depend on the configured autonomy level. The owner's likely default for maximum autonomy: the agent SHALL decide how to fix the remarks, and the change SHALL merge only after everything is OK. The behaviour below maximum autonomy is an agent decision: see design.md D15.

Source: interview 2026-11-24 R13.5 (given as the likely behaviour, not a firm decision); D15
OPEN: see design.md OPEN-VERIFICATION-5

#### Scenario: Maximum autonomy
- **WHEN** the verdict is "passed with remarks" and the autonomy level is maximum
- **THEN** the agent fixes the remarks, and the change merges only after everything passes

#### Scenario: Below maximum autonomy
- **WHEN** the verdict is "passed with remarks" and the autonomy level is below maximum
- **THEN** the change does not merge by itself and is handed to a human (default per design.md D15)

### Requirement: H-059 UI changes are verified in a browser
When a change touches the user interface, the standard verification cycle SHALL verify it independently, beyond end-to-end tests, by clicking through it in a browser to confirm it works as required.

Source: interview 2026-11-24 R15.14. Placing this check in the standard cycle rather than in the optional skill of H-060 is an inference from the interview analysis, not the owner's words.
OPEN: see design.md OPEN-VERIFICATION-6

#### Scenario: UI change
- **WHEN** a ticket changes the user interface
- **THEN** verification opens a browser, clicks through the change and confirms that it works as required

#### Scenario: Check in addition to end-to-end tests
- **WHEN** a ticket changes the user interface and end-to-end tests have passed
- **THEN** the browser check still runs

### Requirement: H-060 Optional, separately installed verify-and-prove skill named by a workflow
The verify-and-prove skill SHALL be optional, recommended by default and refusable by the user. It SHALL be installed apart from the harness and named by a custom workflow for its step. Visual reference default: design.md D16.

Source: interview 2026-11-24 R14.1, R14.2; D16
OPEN: see design.md OPEN-4 (opt-in versus opt-out: the same answer says both)
OPEN: see design.md OPEN-VERIFICATION-1 (whether the harness calls the skill when no workflow names it)

#### Scenario: Skill offered at setup
- **WHEN** setup runs
- **THEN** the verify-and-prove skill is offered as recommended, and the user can decline it

#### Scenario: Skill refused
- **WHEN** the user refuses the verify-and-prove skill
- **THEN** the harness runs without it and does not treat its absence as an error

#### Scenario: Workflow names the skill
- **WHEN** a custom workflow names the verify-and-prove skill for a step and the skill is installed
- **THEN** that step uses the named skill

#### Scenario: Skill not bundled
- **WHEN** the harness is installed
- **THEN** the verify-and-prove skill is not part of the harness install and is installed separately

### Requirement: H-061 External code-review comments are handled by default
By default, when an external code-review system comments on a pull request, the harness SHALL take the comments into account, reply to them and fix what it accepts. It MAY decline a comment, and a separate skill MAY handle the comments.

Source: interview 2026-11-24 R15.10
OPEN: see design.md OPEN-VERIFICATION-4

#### Scenario: External reviewer comments
- **WHEN** an external code-review system posts comments on a harness pull request and the default applies
- **THEN** the harness takes the comments into account, replies to them and fixes what it accepts

#### Scenario: A comment is not accepted
- **WHEN** the harness judges that an external review comment should not be applied
- **THEN** it may decline that comment instead of applying it

#### Scenario: A separate skill handles the comments
- **WHEN** a separate skill is configured to handle external review comments and such comments appear
- **THEN** that skill handles the comments

### Requirement: H-062 Unconfigured review comments are highlighted to a human
When review comments appear and the harness was not configured for them, the harness SHALL be able to highlight them to a human and ask whether to look at them or ignore them.

Source: interview 2026-11-24 R15.11
OPEN: see design.md OPEN-VERIFICATION-4

#### Scenario: Comments without configuration
- **WHEN** review comments appear on a pull request and the harness has no configuration for them
- **THEN** the harness can show the comments to a human and ask whether to look at them or ignore them

### Requirement: H-063 External review is ignored when the user sets it
When the user sets the harness to ignore external review, the harness MUST NOT act on external review comments.

Source: interview 2026-11-24 R15.12

#### Scenario: Ignore is set
- **WHEN** the user has set the harness to ignore external review and an external code-review system comments on a pull request
- **THEN** the harness does not act on those comments
