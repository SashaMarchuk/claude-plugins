# grill-and-package Specification

## Purpose
How `run` grills the user until the design tree is exhausted and writes the handoff package (questions, context and prompt) that a separate interviewer works from.

## Requirements

### Requirement: IH-001 Grill runs the full tree
The plugin SHALL interview the user round by round until the frontier is empty, in the manner of the `grilling` skill (work the design tree, ask the whole frontier in one round with a recommendation on each question, wait, recompute), and SHALL NOT produce a first package from a partial tree.

#### Scenario: Unvisited branches remain
- **WHEN** the design tree still has unvisited branches
- **THEN** no first package is produced

### Requirement: IH-002 Package of separate files
A package SHALL consist of at least three separate files, questions, context and the prompt the user pastes into the session, never merged; a fourth file for answers MAY be added, and which files a package contains SHALL be configuration.

#### Scenario: Package written
- **WHEN** a package is written
- **THEN** questions, context and prompt are separate files, and the file set follows configuration

### Requirement: IH-009 Context document is the memory
The context document SHALL be rewritten each round on the basis of the previous interview, so the user never repeats something already said, and SHALL be both the file the interviewer reads and the plugin's own memory between rounds.

#### Scenario: Later round
- **WHEN** a package is built for a later round
- **THEN** the context document is rewritten from the previous interview and serves as the plugin's memory

### Requirement: IH-010 Context points to earlier analyses
The rewritten context document SHALL link to the earlier rounds' analyses rather than restate them, and those analyses SHALL be written once and never rewritten.

#### Scenario: Context rewritten
- **WHEN** the context document is rewritten
- **THEN** it links to earlier analyses, and those analyses are unchanged

### Requirement: IH-011 Context source asked
The plugin SHALL ask where to take the short context from, even when the project is empty; working it out itself SHALL be one of the options, confirmed or chosen by the user rather than taken silently, and the user MAY describe where to look and what to take.

#### Scenario: Context needed
- **WHEN** the short context is needed
- **THEN** the plugin asks where to take it from

### Requirement: IH-014 Answers file off by default
The answers file SHALL be off by default and enabled only through configuration confirmed with the user; when it is on, it SHALL be the file the interviewer writes into and therefore the resource `collect` reads.

#### Scenario: Answers file on
- **WHEN** the answers file is enabled
- **THEN** the interviewer writes into it and `collect` reads it as the resource

### Requirement: IH-017 Topic is the folder name
The topic given at `run` SHALL be the folder name; when no topic is given, the plugin SHALL propose one from the first grilling round for the user to confirm, and `collect` with no topic SHALL take the most recent active handoff.

#### Scenario: No topic given
- **WHEN** `run` starts without a topic
- **THEN** the plugin proposes one from the first grilling round and the user confirms it

### Requirement: IH-018 Second run never overwrites
A second `run` on an existing topic SHALL NOT overwrite anything; it SHALL show what is closed and what is open and build a package from the open part only, leaving earlier rounds where they are.

#### Scenario: Existing topic
- **WHEN** `run` is used on a topic that already has a package
- **THEN** nothing is overwritten and the new package covers only the open part

### Requirement: IH-031 Interviewer that cannot open files
The generated prompt SHALL tell an interviewer that cannot open the package files to stop, say so plainly and ask for the whole package as one block of text; the skill SHALL then produce that inline package with every project path stripped, including paths inside the pasted content, and no separate command SHALL exist for it.

#### Scenario: Files unreadable
- **WHEN** the interviewer cannot open the package files
- **THEN** it says so and asks for the package as one block, and the skill produces it with every project path stripped

### Requirement: IH-032 Options line optional
An item's options line SHALL be optional: an open question SHALL omit it, and a list of one option SHALL NOT be used; question wording beyond this SHALL be left to the interview method.

#### Scenario: Open question
- **WHEN** a question has no real options
- **THEN** it carries no options line

### Requirement: IH-036 Open items worded live
By default each package item SHALL carry an id, one line on what breaks if it is answered wrong, options where there are real ones, and a recommendation, and the interviewer SHALL word the questions live; `questions.style: written` SHALL restore finished wording.

#### Scenario: Default package
- **WHEN** a package is written with default settings
- **THEN** each item carries an id, a what-breaks line, real options if any, and a recommendation, with no finished wording

### Requirement: IH-037 Written question shape
With finished wording, each question SHALL have a plain-language title, one line on what breaks if it is answered wrong, a body with a concrete worked case with named people, an options line where there are real options, and a recommendation with its single strongest reason.

#### Scenario: Written style
- **WHEN** a package is written with `questions.style: written`
- **THEN** each question follows this shape

### Requirement: IH-038 Question text rules
Question text SHALL use no jargon, SHALL open with why the question is asked, and SHALL state the recommendation out loud together with the fact that overturning it is worth more than agreeing with it.

#### Scenario: Question written
- **WHEN** a question is written
- **THEN** it has no jargon, opens with why it is asked, and states its recommendation with that note

### Requirement: IH-039 Context holds state and rejections
The context file SHALL hold the current state plus what has already been rejected, so the interviewer can explain a question that did not land and does not propose dead ideas.

#### Scenario: Context written
- **WHEN** the context file is written
- **THEN** it holds the current state and the rejected list

### Requirement: IH-040 Item id named aloud
The interviewer SHALL name the item id aloud in every confirmation and read the list back item by item at the end; the analysis SHALL match answers by id and report meaning-matching, the fallback, as such.

#### Scenario: Answer confirmed
- **WHEN** the interviewer confirms an answer
- **THEN** it names the item id aloud

### Requirement: IH-045 Plugin prepares recommendations
The plugin SHALL prepare each item's recommendation by default; `questions.recommendedBy: interviewer` SHALL move it to the interviewer.

#### Scenario: Default recommendations
- **WHEN** a package is written with default settings
- **THEN** each item's recommendation was prepared by the plugin

### Requirement: IH-062 Interviewer behaviour rules
The generated prompt SHALL carry the fixed set of behavioural rules in `references/interviewer-prompt.md`, each derived from an observed failure.

#### Scenario: Prompt generated
- **WHEN** the prompt is generated
- **THEN** it carries the rules from `references/interviewer-prompt.md`
