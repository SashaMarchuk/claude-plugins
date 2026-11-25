## ADDED Requirements

### Requirement: H-053 Verification block in every pull request
Every pull request that the harness opens MUST contain a Verification block. The block SHALL show the verdict in its opening lines, so the result is visible at once. The ticket's report comments and the block SHALL agree.

Source: interview 2026-11-24 R12.1; owner answer to interview question X9; owner answer to interview question X11
Decided: design.md D37-VERIFICATION-4 (block layout)

#### Scenario: Pull request opened by the harness
- **WHEN** the harness opens a pull request for a ticket
- **THEN** the pull request body contains a Verification block

#### Scenario: The result is visible at once
- **WHEN** a person opens a pull request that the harness created
- **THEN** the verdict stands in the opening lines of the Verification block, before the list of checks
- **AND** the person needs no log or other page to read it

#### Scenario: The ticket comment and the block agree
- **WHEN** the harness reports a ticket's verification in a ticket comment and in the Verification block
- **THEN** both show the same checks, results and verdict, because both come from the same recorded results

### Requirement: H-054 The block records the checks actually done, with or without a predefined list
The Verification block SHALL keep a record of what happened and of the checks that were actually done, and it SHALL record those checks even when no predefined list of checks exists. What was checked SHALL be visible by name, with the result of each check. Unfinished checks and exceptions SHALL be stated explicitly.

Source: interview 2026-11-24 R12.2, R12.3; owner answer to interview question X8; owner answer to interview question X10
Decided: design.md D37-VERIFICATION-4 (block layout)

#### Scenario: Checks from a predefined list
- **WHEN** a predefined list of checks exists and checks are done
- **THEN** the Verification block records each check that was actually done

#### Scenario: Checks without a predefined list
- **WHEN** checks are done without a predefined list
- **THEN** the Verification block records each check that was actually done

#### Scenario: What was checked is visible
- **WHEN** a person reads the Verification block
- **THEN** each check that was done is named, with its own result

#### Scenario: A listed check was not done
- **WHEN** a predefined list names a check and no result was recorded for it
- **THEN** the Verification block shows that check as not done, with a reason, and does not show it as passed

#### Scenario: An exception is stated
- **WHEN** verification passed under an exception, for example zero tests allowed by the profile
- **THEN** the Verification block names that exception in plain words and does not leave it out

### Requirement: H-055 Merge requires an independent validator pass verdict
Before it merges, the harness merge step MUST check that the independent validator gave the change a "passed" verdict, and MUST NOT merge without one. "Passed with remarks" alone does not satisfy this gate; H-058 governs it.

Source: interview 2026-11-24 R13.1; the independent validator is existing harness behaviour that stays (decided context of the interview, not asked); remarks handling: design.md D15
Decided: design.md D37-VERIFICATION-6

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
Decided: design.md D37-VERIFICATION-3

#### Scenario: All tests pass
- **WHEN** the default profile is active and at least one test ran and every test passed
- **THEN** the test check passes

#### Scenario: A test fails
- **WHEN** the default profile is active and any test failed
- **THEN** the test check fails

#### Scenario: Zero tests
- **WHEN** the default profile is active and zero tests ran
- **THEN** the test check fails

#### Scenario: Counts do not add up
- **WHEN** the reported passed, failed and skipped counts do not add up to the total
- **THEN** the test check fails

### Requirement: H-057 Zero tests pass only when the profile allows it
A profile MAY be configured to skip the test-count check, and verification SHALL accept zero tests only when the active profile is configured that way.

Source: interview 2026-11-24 R13.4
Decided: design.md D37-VERIFICATION-3

#### Scenario: Profile allows zero tests
- **WHEN** the active profile is configured to skip the test-count check and zero tests ran
- **THEN** the test count does not fail verification

#### Scenario: Non-default profile keeps the count check
- **WHEN** the active profile is not the default profile, it does not skip the test-count check, and zero tests ran
- **THEN** verification fails

#### Scenario: Zero tests allowed, but a test fails
- **WHEN** the active profile skips the test-count check and a test failed
- **THEN** verification fails

#### Scenario: Unreadable test result
- **WHEN** the active profile skips the test-count check and the test command fails to run or its result cannot be read
- **THEN** verification fails and the result is not treated as zero tests

### Requirement: H-058 Pass-with-remarks follows the autonomy level
The reaction to a "passed with remarks" verdict SHALL depend on the autonomy profile. With `remarks: fix`, the agent SHALL fix the remarks, and the change SHALL merge only after a fresh validator gives a clean "passed". Otherwise, or when the fix rounds run out, the change SHALL go to a human. Settings: design.md D15.

Source: interview 2026-11-24 R13.5, R13.6; D15
Decided: design.md D37-VERIFICATION-6

#### Scenario: Maximum autonomy
- **WHEN** the verdict is "passed with remarks" and the autonomy level is maximum
- **THEN** the agent fixes the remarks, a fresh validator checks the new head, and the change merges only on a clean "passed"

#### Scenario: Below maximum autonomy
- **WHEN** the verdict is "passed with remarks" and the autonomy level is below maximum
- **THEN** the change does not merge by itself and is handed to a human (setting `remarks: human` per design.md D15)

#### Scenario: Fix rounds run out
- **WHEN** the profile sets `remarks: fix` and the allowed fix rounds (default 3) end without a clean "passed"
- **THEN** the change does not merge and the ticket goes to needs-review

### Requirement: H-059 UI changes are verified in a browser
When a change touches the user interface, the standard verification cycle SHALL verify it independently, beyond end-to-end tests, by clicking through it in a browser to confirm it works as required. A flow configuration MAY switch it off or name another runner (H-066).

Source: interview 2026-11-24 R15.14. Placing this check in the standard cycle rather than in the optional skill of H-060 is an inference from the interview analysis, not the owner's words.
Decided: design.md D37-VERIFICATION-7

#### Scenario: UI change
- **WHEN** a ticket changes the user interface
- **THEN** verification opens a browser, clicks through the change and confirms that it works as required

#### Scenario: Check in addition to end-to-end tests
- **WHEN** a ticket changes the user interface and end-to-end tests have passed
- **THEN** the browser check still runs

#### Scenario: Browser check switched off
- **WHEN** the project flow configuration switches off the browser check and a ticket changes the user interface
- **THEN** the browser check does not run, and the Verification block shows it as not done, switched off by the flow configuration

#### Scenario: Browser check cannot run
- **WHEN** the browser check is on and it cannot run
- **THEN** the step fails and the ticket does not move to shipping

### Requirement: H-060 Optional, separately installed verify-and-prove skill named by a workflow
The verify-and-prove skill SHALL be optional, recommended by default and refusable by the user. It SHALL be installed apart from the harness and named by a custom workflow for its step. Visual reference default: design.md D16.

Source: interview 2026-11-24 R14.1, R14.2; D16
Decided: design.md D37-VERIFICATION-1 (offered, and on only after a yes), D37-VERIFICATION-2 (called only when a flow step names it)

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

#### Scenario: No answer at setup
- **WHEN** setup offers the verify-and-prove skill and the user gives no answer
- **THEN** the skill stays off and the harness runs without it

#### Scenario: No workflow names the skill
- **WHEN** the skill is installed and no flow step names it
- **THEN** the harness does not call the skill

### Requirement: H-061 External code-review comments are handled by default
By default, when an external code-review system comments on a pull request, the harness SHALL react to the comments: take them into account and fix what it accepts. It MAY decline a comment, and a separate skill MAY handle the comments. It SHALL act by itself only on comments from a trusted author.

Source: interview 2026-11-24 R15.10
Decided: design.md D37-VERIFICATION-5

#### Scenario: External reviewer comments
- **WHEN** an external code-review system posts comments on a harness pull request, its account is a trusted author, and the default applies
- **THEN** the harness reacts to the comments, takes them into account and fixes what it accepts

#### Scenario: A comment is not accepted
- **WHEN** the harness judges that an external review comment should not be applied
- **THEN** it may decline that comment instead of applying it

#### Scenario: An outside commenter posts a review
- **WHEN** an account that has no write access to the repository, or whose access is unknown, and that is not a listed review bot, posts a review on a harness pull request
- **THEN** the harness records the review in the ticket thread and does not apply it, in every profile

#### Scenario: A listed review bot comments
- **WHEN** a review bot named in the project's list of approved review bots comments on a harness pull request
- **THEN** the harness treats it as a trusted author (design.md D37-VERIFICATION-5)

#### Scenario: A separate skill handles the comments
- **WHEN** a separate skill is configured to handle external review comments and such comments appear
- **THEN** that skill handles the comments

#### Scenario: A fix after review needs a new verdict
- **WHEN** the harness pushes a fix for an external review comment
- **THEN** the merge requires a fresh validator pass on the new commit

### Requirement: H-062 Unconfigured review comments are highlighted to a human
When review comments appear and the harness was not configured for them, the harness SHALL be able to highlight them to a human and ask whether to look at them or ignore them.

Source: interview 2026-11-24 R15.11
Decided: design.md D37-VERIFICATION-5

#### Scenario: Comments without configuration
- **WHEN** review comments appear on a pull request and the setting is `ask`, or the setting is `react` and the run cannot act on them (the flow has no step for them, or the profile does not allow a push)
- **THEN** the harness shows the comments to a human, asks whether to look at them or ignore them, and moves the ticket to needs-review

### Requirement: H-063 External review is ignored when the user sets it
When the user sets the harness to ignore external review, the harness MUST NOT act on external review comments.

Source: interview 2026-11-24 R15.12; D37-VERIFICATION-5

#### Scenario: Ignore is set
- **WHEN** the user has set the harness to ignore external review and an external code-review system comments on a pull request
- **THEN** the harness does not act on those comments
