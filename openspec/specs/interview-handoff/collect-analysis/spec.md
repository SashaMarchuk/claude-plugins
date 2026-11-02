# collect-analysis Specification

## Purpose
How `collect` reads whatever the interview produced, matches every answer to its question, classifies it, flags contradictions and offers the next round.

## Requirements

### Requirement: IH-004 Resource location configurable
When a resource location is configured, `collect` SHALL read it without asking; otherwise it SHALL ask, SHALL confirm a place already named in the conversation rather than asking again, and SHALL accept content the user simply hands over.

#### Scenario: Location configured
- **WHEN** a resource location is configured
- **THEN** `collect` reads it without asking

### Requirement: IH-005 Contradictions shown, never resolved
When the analysis finds contradictions or too much that is unclear, the plugin SHALL show the list and ask what to do with it, offering at least a further round and asking right now in the current session, and SHALL NOT resolve them itself.

#### Scenario: Contradictions found
- **WHEN** the analysis finds contradictions
- **THEN** the plugin shows the list and asks what to do

### Requirement: IH-013 Classification labels
The analysis SHALL classify each question with the recommended labels settled, partial, untouched, premise rejected and deferred; the set SHALL be overridable, the model MAY add a label of its own when there is a reason, and an answer that contradicts an earlier one SHALL carry a separate flag.

#### Scenario: Answer classified
- **WHEN** a question is classified
- **THEN** it carries a label from the set, and a contradicting answer also carries the contradiction flag

### Requirement: IH-016 Verbatim quotes
The person's words SHALL be kept exactly as said, in the language they were said in, because they are the evidence if the person later disagrees.

#### Scenario: Quote recorded
- **WHEN** the analysis records the person's words
- **THEN** they are verbatim, in their original language

### Requirement: IH-019 Two trust levels
Each processed resource SHALL carry one of two trust levels, source of truth or needs further confirmation, set by asking once per resource, and the label SHALL stay in the analysis permanently.

#### Scenario: New resource
- **WHEN** a resource is processed for the first time
- **THEN** the plugin asks once for its trust level and records it in the analysis

### Requirement: IH-020 Compression offered
Before processing a noisy resource the plugin SHALL ask in one line whether to compress it for accuracy or to send it through a cheaper sub-agent, SHALL NOT ask when the resource is already clean, and configuration MAY set always-compress.

#### Scenario: Noisy resource
- **WHEN** a noisy resource is about to be processed and always-compress is not set
- **THEN** the plugin asks in one line whether to compress it

### Requirement: IH-021 Compression is lossless
Compression SHALL be lossless, by tokens only and only where possible, for example compacting JSON that arrives as a JSON resource; it SHALL NOT drop the interviewer's restatements, and the original SHALL always be processed and kept whole.

#### Scenario: Resource compressed
- **WHEN** a resource is compressed
- **THEN** nothing original is lost, the interviewer's restatements remain, and the original is kept

### Requirement: IH-022 Voice repetition removed
Compression of a voice resource SHALL remove repetitions of the same phrase without removing anything else.

#### Scenario: Voice resource compressed
- **WHEN** a voice resource that repeats a phrase is compressed
- **THEN** the repetitions are removed and nothing else is

### Requirement: IH-049 Contradiction is its own item
A contradiction SHALL be its own item carrying both statements and when each was said; if the person marked one final in the session, that SHALL be the decision, recorded with the words that settled it; otherwise it SHALL go back to the person as a question showing both sides and their timing.

#### Scenario: Nothing marked final
- **WHEN** two statements contradict and neither was marked final
- **THEN** the person gets a question showing both sides and their timing

### Requirement: IH-050 Recency is not finality
Recency alone SHALL NOT count as finality, and a contradiction touching the rejected list SHALL be called out, because a rejected entry that is now live policy must be corrected or the next interviewer will refuse to discuss it.

#### Scenario: Rejected entry contradicted
- **WHEN** a contradiction touches the rejected list
- **THEN** it is called out

### Requirement: IH-054 Any resource accepted
`collect` SHALL take a resource of any kind, a file, a path, pasted content or anything else the user hands over; a session transcript SHALL be one kind of resource with no special status, and a resource unrelated to the questions MAY still be important context.

#### Scenario: Pasted content
- **WHEN** the user pastes content into `collect`
- **THEN** it is processed as a resource

### Requirement: IH-055 Processing never breaks the flow
Processing a resource SHALL NOT break the flow: whatever it answers SHALL be removed from the open set and the next round offered from what remains; when it answers nothing, the round already planned SHALL be offered unchanged.

#### Scenario: Resource answers nothing
- **WHEN** a processed resource answers no open question
- **THEN** the planned round is offered unchanged

### Requirement: IH-056 Analysis steps
The analysis SHALL find the resource, compress it if that was offered and accepted while keeping the original, match each answer to its question, classify each question, compare against everything answered before and flag every contradiction, write the result to the configured location, and then show the contradictions and what is still open and ask what to do.

#### Scenario: Collect runs
- **WHEN** `collect` analyses a resource
- **THEN** it performs these steps in this order

### Requirement: IH-057 Impossible values flagged
A word, name or number that looks impossible SHALL be flagged, never guessed.

#### Scenario: Impossible name
- **WHEN** a recognised name looks impossible
- **THEN** it is flagged, not guessed

### Requirement: IH-061 Ratification recorded
A recorded answer SHALL carry how it was confirmed; an answer the interviewer formulated without a yes SHALL be `not ratified`, SHALL never be treated as settled, and SHALL open the next package as a short ratification block.

#### Scenario: No yes given
- **WHEN** the interviewer formulated an answer without the person's yes
- **THEN** it is recorded `not ratified` and opens the next package's ratification block

### Requirement: IH-063 Later beats earlier
Inside one resource a later statement SHALL beat an earlier one, explicit self-cancellation marks SHALL be recognised, and both versions SHALL be kept.

#### Scenario: Self-correction
- **WHEN** the person corrects themselves later in the same resource
- **THEN** the later version wins and both are kept

### Requirement: IH-064 Dictated decisions swept
Decisions dictated outside any question SHALL be swept for separately from question matching.

#### Scenario: Decision outside the list
- **WHEN** the person dictates a decision outside any question
- **THEN** the separate sweep records it

### Requirement: IH-065 Cascading closures checked
A closure that cascades to questions that were never asked SHALL be checked against the whole open set.

#### Scenario: Answer closes unasked questions
- **WHEN** an answer closes questions that were never asked
- **THEN** the closure is checked against the whole open set

### Requirement: IH-066 Idempotent collect
`collect` SHALL recognise a resource already processed and SHALL NOT count it twice.

#### Scenario: Same resource again
- **WHEN** `collect` is given a resource it already processed
- **THEN** nothing is counted twice

### Requirement: IH-067 Unattributable segments flagged
A segment that cannot be attributed to a speaker SHALL be flagged, never guessed, because attributing the interviewer's words to the person fabricates a decision at the highest authority the record has.

#### Scenario: Speaker unclear
- **WHEN** a segment's speaker cannot be determined
- **THEN** it is flagged
