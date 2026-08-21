# Configuration

## Where a value is written

Reusability decides, not convenience. A value usable by more than this plugin goes to the general config. Only a value nothing but this plugin can use goes into the plugin's own file. A value whose reach is unclear counts as reusable.

Then the level decides where that answer is true: on this machine in every project, in this project for everyone, or in this project for me only.

| Slot | Path | Kind |
|---|---|---|
| 1 | `<config-root>/shared/identity.json` | personal, every project |
| 2 | `<config-root>/shared/plugins/interview-handoff.json` | personal, every project |
| 3 | `./.claude/shared/identity.json` | committed |
| 4 | `./.claude/shared/plugins/interview-handoff.json` | committed |
| 5 | `./.claude/shared/identity.local.json` | personal, gitignored |
| 6 | `./.claude/shared/plugins/interview-handoff.local.json` | personal, gitignored |

Higher slot wins. `<config-root>` is `$CLAUDE_CONFIG_DIR` when set, otherwise the home directory plus `/.claude`. Never write a literal `~` into a file call, and never use `<config-root>/plugins/`.

On a clean first setup, with no config file anywhere, a shared answer goes to slot 1 and a plugin-only answer to slot 2. Nothing under `./.claude/` is created.

A setting some layer already holds is written back into that same layer, not created somewhere else as a side effect. Every write preserves keys it does not recognise.

## General config

Three keys, because each is useful to any plugin that talks to this person, not just this one.

```jsonc
{
  "language": "the language to talk to this person in",

  "connectors": {
    "session-logs": {
      "use": { "kind": "auto" }
    },
    "interview-method": {
      "use": { "kind": "auto" }
    }
  }
}
```

**`language`** is what the person is spoken to in. Absent means detect it from the live conversation, which is the default and is usually right.

**`connectors.session-logs`** is where the record of a finished interview session can be found. `{ "kind": "auto" }` or an absent `use` sends it to detection, which here means asking.

**`connectors.interview-method`** is how the user is questioned while a package is being prepared. It is shared because a method that suits this person suits any plugin that questions them. Absent or `auto` means look at what is available, offer it with a recommendation, and record the answer. Resolution runs on every invocation, so a method that has changed since last time is used as it now is. Set it to `built-in` to use the method the plugin ships and stop being asked.

Note on naming: another plugin in this marketplace uses a `transcripts` source, and there it means a notetaker service. Here the source is a place where a session record lives. Two different things, so two different names. Do not merge them.

## Plugin config

Everything else. None of it means anything outside this plugin.

```jsonc
{
  "output": {
    "path": "docs/handoff/{topic}"
  },

  "package": {
    "answersFile": false
  },

  "language": {
    "questions": null,
    "documents": null,
    "analysis": null
  },

  "classification": {
    "labels": null
  },

  "compress": {
    "always": false
  },

  "context": {
    "source": null
  }
}
```

**`output.path`** is where packages and analyses land. There is no forced default. On first run the person is asked, and `docs/handoff/{topic}` is offered as the recommendation.

**`package.answersFile`** adds a file for the interviewer to write into. Off by default, and confirmed with the person before it is added. When it is on, that file becomes the resource `collect` reads.

**`language.*`** overrides the general `language` per artifact. Null means fall back to the general key, and an absent general key means detect. Verbatim quotes ignore all of this and stay in the language they were said.

**`classification.labels`** replaces the recommended five. Null keeps them.

**`compress.always`** compresses a noisy resource without asking, but only losslessly. Off by default, in which case the person is asked once per resource, and not asked at all when the resource is already clean. The original is kept whole either way.

**`context.source`** is where the context document takes its starting material from. Null means ask, which includes offering to work it out and having the person confirm that choice.

## Running with nothing configured

That is a normal state, not an error. Ask what is needed, use the answer, and write it down in the right file by the rules above. Never fail because a config file is missing.

## Config mode

Start at the first question every time. For a stored value, ask whether it is still current: keep it on a yes, collect a replacement on a no.
