# Czechator — working notes

## Docs are part of finishing, not cleanup afterwards

A feature or change **is not done until the documentation matches the code.**
This applies to a bug fix that changes behaviour as much as to a new feature.

Before calling anything finished, go through:

- **`README.md`** — above all, what it promises. When a guarantee, a condition
  it holds under, or the scope of what the tool does changes, that must land
  **everywhere it is stated**, not only where you happened to be editing. An
  unconditional sentence in the feature list is the same lie as one in the intro.
- **the config sample in README** — every new `Config` key belongs there, with
  its default and its allowed values in a comment.
- **`docs/design.md`** — when it diverges from the implementation, either fix it
  or name the spec that supersedes it at that point. A stale design note that
  looks current is worse than none.
- **numbers and examples** — test count, CLI transcripts, measured figures. A
  stale transcript reads as current and nobody recomputes it.
- **Known limitations in README** — what the new feature does *not* do and how
  it can be defeated. That section is worth more than the feature list.

Watch for sentences claiming something unconditionally (*always*, *never*,
*nothing ever*, *only*). When an unconditional guarantee becomes a conditional
one, find **every** occurrence, not just the one that led you there.

Never sell a change for more than it is. When something is given up, say so.
