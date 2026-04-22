---
name: explore
description: Socratic interview to help decide WHAT to analyze and WHY before committing to seeds. Use when you have a data source but don't yet know the right questions to ask.
allowed-tools: Read, Write, Bash, Glob, Grep
---

# Role
Ideation partner. Helps the user produce a sharp seeds.md by interviewing about their decision context. Outputs a draft seeds.md if they already have a run, or a standalone seeds-draft.md if not.

# Invocation
  /ultra-analyzer:explore [run-name]

# Protocol

## Step 1: Context-gather (ask, do not assume)

Use AskUserQuestion to ask ONE question at a time, pausing for the user's answer before proceeding.

**Q1: Who is the decision-maker?**
- Who will read the final report, and what do they decide with it?
- Options offered: "myself — understand the data" / "stakeholder — prove a hypothesis" / "team — align on priorities" / "client — deliver insight" / "other"
- Why it matters: shapes report tone, depth, and narrative framing.

**Q2: What's the decision?**
- What choice depends on the answer you're looking for?
- Free-form text. Probe for specificity — "understand X better" is NOT a decision; "whether to invest in Y" IS a decision.

**Q3: What's the hypothesis?**
- Before looking at data, what do you BELIEVE is true? Name the expected answer.
- This surfaces confirmation bias and gives the pipeline something to test.

**Q4: What would change your mind?**
- What evidence, if found, would falsify your hypothesis?
- Falsifiability test. If the user cannot answer, the hypothesis is not well-formed — help them sharpen it.

**Q5: What's the unit of analysis?**
- Per-user? Per-event? Per-session? Per-document? Per-aggregate-metric?
- Affects denominator strategy (seeds.md §0).

**Q6: What's the time horizon?**
- All-time? Last N days? Specific date range?
- Shapes query filters and whether time-series topics are needed.

**Q7: What cohorts matter?**
- Are there natural groups (role, region, tier, product) whose comparison would be informative?
- Or is this a population-level analysis with no cohort split?

**Q8: What's out-of-scope?**
- Name 2-3 related questions you DON'T want to answer in this run.
- Prevents scope creep during seed generation.

**Q9: What's the minimum useful finding?**
- If the pipeline returns just ONE result, what would it need to show to be worth the effort?
- Forces priority-setting. This becomes the #1 P1 seed.

## Step 2: Propose seed structure

Based on answers, draft the seed skeleton. Show it to the user:

```
Proposed seeds (review before committing):

§0 Evidence base (T000): <derived from Q5 + Q6>

P1 (<count> seeds):
  1. <seed derived from Q9 — the minimum useful>
  2. <seed derived from Q3 — the hypothesis under test>
  3. <seed derived from Q4 — what would falsify it>
  4-N. <cohort/subset variations from Q7>

P2 (<count> seeds): <context questions that inform P1>

P3 (<count> seeds): <appendix-worthy tangents>

Excluded by scope (Q8): <list>
```

Ask: "Does this look right? Anything to add/remove/reweight?"

## Step 3: Write or update seeds.md

- If invoked with a run-name → write to `<run>/seeds.md` (confirm overwrite if exists).
- If no run-name → write to `.planning/ultra-analyzer/_explore-drafts/seeds-<timestamp>.md` as a draft for later adoption.

Fill in each seed with the structure from `templates/seeds.md.template`: Hypothesis, Units, Fields, Query sketch, Complexity, Why.

## Step 4: Next steps
```
✓ seeds.md drafted at <path>
Review + refine, then:
  (if in a run)       /ultra-analyzer:run       # Gate 1 will validate these seeds
  (if standalone)     /ultra-analyzer:init <name> → copy draft in → /ultra-analyzer:run
```

# Hard rules
- NEVER fabricate a hypothesis for the user. If Q3 is unanswered, surface that instead of inventing one.
- NEVER auto-generate >5 P1 seeds from a single user question — over-expansion hides the real question.
- ALWAYS honor out-of-scope constraints (Q8). Do not slip excluded topics into the draft.
- If the user can't answer Q4 (falsifiability), flag explicitly: "This hypothesis is not falsifiable as stated — pipeline can only confirm, not test. Consider reframing."
