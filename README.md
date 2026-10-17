# Czechator

Restores Czech diacritics in whatever is on your clipboard — press a hotkey,
paste the fixed text.

Czech text typed without diacritics ("Prilis zlutoucky kun" instead of "Příliš
žluťoučký kůň") is everywhere: chat messages, commit messages, notes written on
a foreign keyboard. Czechator sends that text to a language model and puts the
corrected version back on your clipboard.

The point of the tool is what it does **not** touch. If the clipboard holds
JSON, XML or HTML, only the text nodes are corrected — keys, tags, attributes,
indentation and formatting come back byte-for-byte identical. And, with
verification on, nothing is written back at all unless it passes.

```
$ echo 'Prilis zlutoucky kun upel dabelske ody.' | czechator fix -
Příliš žluťoučký kůň úpěl ďábelské ódy.

$ echo '{"popis":"Vcera jsem koupil novy pocitac.","id":"abc"}' | czechator fix -
{"popis":"Včera jsem koupil nový počítač.","id":"abc"}
```

## How it protects your text

A language model asked to "fix the diacritics" will happily do more than that.
During development `gemma3:4b` turned *"schůzka se koná v úterý"* into *"schůzka
se koná ve středu"* — it changed the day of a meeting. Czechator caught it and
left the clipboard alone.

By default the guarantee is a single invariant, checked before anything is
written:

```
fold(output) == fold(input)
```

where `fold` strips Czech diacritics. If the model changed a word, the casing,
the whitespace, the structure, or added a comment of its own, the two sides
differ and the result is refused.

A profile may relax this. In **Drobné opravy** and **Korektura** the model is
also allowed to fix typos, punctuation and capitalization, and the check becomes
a per-word edit budget: no word may change by more than its allowance. That is a
weaker guarantee — it bounds how much was rewritten, it does not prove that
nothing was. Every shipped profile stays strict; relaxing it is a deliberate
choice per profile.

**With verification on, when Czechator cannot do the job safely it does nothing
at all and tells you why** — your clipboard is never left worse than it was.

A profile can also switch verification off entirely. That is a different thing
from relaxing the budget: it removes the check altogether, so whatever the
model returns is written back unexamined — a rewritten sentence, a dropped
word, a swallowed non-breaking space, anything the model does reaches the
clipboard as-is. Every shipped profile keeps verification on; turning it off
is a deliberate choice per profile, for a model you already trust completely.

## Features

- **Two ways to trigger it** — a global hotkey (`Cmd+Ctrl+D` by default), or
  a double tap of the right ⌘ that takes no shortcut away from anything.
- **Structure-aware.** Plain text, Markdown, JSON, XML and HTML. In structured
  formats only text nodes are corrected; the document is reassembled from the
  original bytes around them.
- **Verification before every write.** With it on, nothing unverified reaches
  the clipboard. A profile can switch it off, deliberately and per profile.
- **Local first.** Runs against [Ollama](https://ollama.com) on your machine, so
  the clipboard never leaves it. Any OpenAI-compatible API works too.
- **Rich clipboard preserved.** An HTML clipboard is written back as both HTML
  and plain text, so pasting into Word keeps the formatting.
- **Menu bar app** with run state, history and undo — click a history entry to
  put the original text back on the clipboard.
- **Tunable segmentation.** URLs, e-mails, code spans and fenced blocks are
  skipped by default; the rules live in the config file, not in the source.
- **Debugging built in.** `czechator segments` shows exactly what would be sent
  to the model, and why anything was left out.
- **CLI as a first-class citizen.** `git diff | czechator fix -` works, and the
  core is free of AppKit so it can be ported off macOS.

### Not in scope

Czechator never translates, never reformats, never reorders and never swaps a
word for a synonym — in any mode. By default it adds accents and nothing else;
a profile can additionally allow typos, punctuation and capitalization to be
fixed, bounded per word. See [Correction modes](#correction-modes).

## Requirements

- macOS 14 or newer
- Swift 6.0 toolchain (Xcode or just the Command Line Tools — `xcode-select
  --install`)
- [Ollama](https://ollama.com) with a small instruct model

## Install from source

```bash
git clone https://github.com/librucha/czechator.git
cd czechator

ollama pull qwen3:4b-instruct     # ~2.5 GB
make install                      # app to /Applications, CLI to ~/.local/bin
```

Then open `/Applications/Czechator.app`. It has no Dock icon — look for it in
the menu bar. macOS will ask once for permission to show notifications.

Copy some Czech text without diacritics, press `Cmd+Ctrl+D`, and paste.

Without a signing certificate the build is ad-hoc signed, and macOS then sees a
different application on every build. `make install` clears the app's
Accessibility record for you in that case, because the stale one would otherwise
sit in the list looking granted while pointing at a binary that no longer exists
— the double tap would then do nothing at all, silently. Run
`make reset-accessibility` on its own if you ever need to.

With a Developer ID certificate in your keychain the signature stops changing,
`make install` leaves the permission alone, and you grant it once. See
[Signing](#signing).

### Just the CLI

```bash
make install-cli                       # to ~/.local/bin
make install-cli BINDIR=/usr/local/bin # somewhere else (may need sudo)
```

`make install-cli` warns if the target directory is not on your `PATH`.

### Signing

`make app` and `make install-cli` sign with the first *Developer ID Application*
identity they find in your keychain, and fall back to an ad-hoc signature when
there is none. Nothing to configure — check what it picked:

```bash
security find-identity -v -p codesigning   # what is available
make app                                   # prints the identity it used
```

Override with `make app SIGN_ID="Developer ID Application: Name (TEAMID)"`, or
force the fallback with `SIGN_ID=-`.

The identity is worth having because macOS keys both the Accessibility
permission and the Keychain ACL on the code signature. Ad-hoc signing produces a
new one every build, so both have to be granted again every time; a Developer ID
does not change, so both survive. Switching to one costs granting each of them
one final time.

Getting the certificate, with no Xcode required: create a CSR in Keychain Access
(*Certificate Assistant → Request a Certificate From a Certificate Authority*,
saved to disk), upload it at *developer.apple.com → Certificates* as **Developer
ID Application** with profile type **G2 Sub-CA**, download and double-click the
`.cer`. Back up the private key — without it the certificate is worthless, and a
team is limited to five.

Two things that break signing after that, both with the same unhelpful
`errSecInternalComponent`:

- **Do not set the certificate to *Always Trust* in Keychain Access.** That makes
  macOS treat the leaf as a trust anchor, and `codesign` then refuses because a
  leaf is not a self-signed root. Trust must stay at *Use System Defaults*.
- **The *Developer ID Certification Authority (G2)* intermediate has to be in
  your login keychain.** The copy macOS ships in `SystemRootCertificates.keychain`
  serves as an anchor but is not used to build the chain. Download it from
  [Apple](https://www.apple.com/certificateauthority/) and double-click it.

Verify what you got:

```bash
codesign -dv --verbose=2 build/Czechator.app
```

Three `Authority=` lines — the identity, the Developer ID CA and Apple Root CA —
mean the chain is complete.

The build is signed but **not notarized**, so `spctl` rejects it as
`Unnotarized Developer ID`. That is harmless here: a locally built app carries
no quarantine attribute and Gatekeeper never evaluates it. It is what would have
to change before handing the `.app` to someone else.

### Building without installing

```bash
make build     # both targets
make test      # 431 tests
make icon      # build/Czechator.icns from img/exports/AppIcon.appiconset
make app       # build/Czechator.app
make fixtures  # regenerate the embedded fixtures after editing Fixtures/
```

Tests run through `make test`, never bare `swift test`: with only the Command
Line Tools installed, `Testing.framework` sits outside the default search paths
and the Makefile supplies the flags.

## Tuning

`czechator fix --debug` prints what went to the model and what came back, on
stderr, so a refused run shows the actual answer instead of just a count:

```
$ echo 'Prilis zlutoucky kun.' | czechator fix - --debug
── režim ──
  opravy: Přísný
  ověřování: zapnuto

── dávka (1 položek) ──
  1. posláno: Prilis zlutoucky kun.
     vráceno: Příliš žluťoučký kůň.
     → jen diakritika, v pořádku
```

The header says what the run was judged by, which is the first thing to check
when a correction is refused you expected to pass — or accepted you expected to
be refused.

On a rejection it also points at the first character where the folded forms
diverge. In a tolerant mode it additionally names the word that went over its
allowance and by how much:

```
── ZAMÍTNUTO ──
  originál: schuzka se kona v utery
  model:    schůzka se koná ve středu
  rozdíl:   na pozici 17: „v utery" vs „ve stredu"
  přes rozpočet: „utery" — 4 editů, povoleno 1
```

Five things are worth turning, roughly in order of effect: the **model**
(`profiles.<name>.model`), the **correction mode** (`profiles.<name>.corrections`
— see [Correction modes](#correction-modes)), the **prompt**
(`prompt.override`), the **batch size** (`limits.maxBatchChars` — set it low
while tuning so each line goes on its own), and **what gets sent at all**
(`segmentation`, inspected with `czechator segments --show-skipped`).

Measure rather than guess: `czechator quality` runs the built-in fixtures and
reports three numbers per profile and correction mode — how many came out
exactly right, how many the tool accepted, and how many it refused. They are
different numbers and all three matter.

With no `--corrections` and no `--letter-case` it measures each profile in the
correction mode and under the letter-case policy your configuration actually
uses, so bare `czechator quality` answers "how is what I run doing" rather than
"how is the default doing". `verification` is the one setting it does not take
from the profile — see [Known limitations](#known-limitations).

```bash
czechator quality                                   # the active profile, as configured
czechator quality --profile local --profile claude --corrections all
czechator quality --format md > docs/quality.md     # a table to commit
czechator quality --fixtures-dir ./my-samples       # your own text
```

Two fixture sets ship with the tool and answer different questions. **`clean`**
is correct Czech missing only its accents, so in a tolerant mode it measures how
often the model touches text that was already fine. **`typos`** carries
deliberate mistakes and measures how many the mode actually fixes. A high
refusal count for `typos` under `strict` is the **correct** result, not a
failure: the model cannot fix a typo and still pass exact verification.

> **Running this against a paid API costs money.** There is no confirmation
> prompt and no spending guard — it is a measurement tool and it does what you
> ask. Two built-in sets across three correction modes is 105 measured runs per
> profile, each of which is one or more model calls depending on how the
> samples batch. `--corrections strict` and `--fixtures-dir` with a handful of
> samples keep a trial cheap.

## Which model to use

`qwen3:4b-instruct` is the default, because it is the one you can `ollama pull`.
On the 23-sample suite in `Fixtures/quality/` it got 15 exactly right and 22
past verification. Its misses are almost all a missing `ě`.

**Two models fine-tuned for this tool do better**, and neither needs any change
to czechator — they are trained on its own prompt and wire format:

| model | `quality` exact / verified | p50, 300 chars | use it when |
|---|---|---|---|
| `czechator-gemma3-270m:v1-q8_0` | 18/23, 23/23 | 0.5 s | speed matters: the answer arrives before you reach for paste |
| `czechator-gemma4-e2b:v1-q8_0` | 23/23, 23/23 | 2.1 s | accuracy matters: half the errors of the small one on web text |
| `qwen3:4b-instruct` (default) | 15/23, 22/23 | 1.9–2.7 s | you have not built either of the above |

Measured on an M4 Max with Q8_0 quantization. On a larger held-out set — 500
lines of web text and 297 hand-checked Czech/English workplace messages — the
small model is exact on 37 % and 77 % of lines, the larger one on 54 % and 89 %,
the default on 14 % and 23 %.

They are not on the Ollama registry: **you build them yourself** with the
pipeline in [`llm/`](llm/README.md) — data preparation, an MLX LoRA run (about
1.5 h for 270M, 11 h for E2B on an M4 Max) and the export to Ollama. Both are
diacritics-only (`corrections: strict`); a tolerant mode sends them a prompt
they were not trained on. The fine-tuning adds no safety of its own: words
whose spellings differ only in diacritics (`byt`/`být`) are still guessed from
context, and verification cannot catch a wrong guess there.

A fast and an accurate profile side by side:

```yaml
profiles:
  fast:
    kind: ollama
    endpoint: http://localhost:11434
    model: czechator-gemma3-270m:v1-q8_0
    temperature: 0
    timeoutSeconds: 30
    corrections: strict        # the only mode these models were trained for
  accurate:
    kind: ollama
    endpoint: http://localhost:11434
    model: czechator-gemma4-e2b:v1-q8_0
    temperature: 0
    timeoutSeconds: 30
    corrections: strict
```

`gemma3:4b` was measured too and is **not recommended** — 4/10 exact, 5/10
verified, and its failures included swapping whole words (see above). Nothing
unsafe reaches the clipboard either way, but you get refusals instead of
corrections.

Bigger models should do better. Avoid reasoning models: they emit paragraphs of
deliberation and turn a keystroke into a half-minute wait.

## Configuration

Written to `~/.config/czechator/config.yaml` on first launch, with every default
spelled out so the rules can be edited without reading the source. Unknown keys
you add by hand survive being saved from the settings window.

```yaml
activeProfile: local

profiles:
  local:
    kind: ollama
    endpoint: http://localhost:11434
    model: qwen3:4b-instruct
    temperature: 0
    timeoutSeconds: 30
    corrections: strict        # strict | minor-fixes | proofread
    editBudget:
      percent: 20              # of each word's length
      minimum: 1               # floor, in edits
    verification: true
  openai:
    kind: openai-compat
    endpoint: https://api.openai.com/v1
    model: gpt-4o-mini
    temperature: 0
    timeoutSeconds: 30
    apiKey: { source: keychain, account: czechator-openai }
    corrections: strict
    editBudget:
      percent: 20
      minimum: 1
    verification: true

hotkeys:
  - shortcut: cmd+ctrl+d
    source: clipboard
    sink: clipboard

trigger:
  kind: combination        # combination | doubleTap
  modifier: rightCommand   # rightCommand | leftCommand | rightOption | leftOption
  intervalMs: 300
  maxHoldMs: 500
  debug: false

limits:
  maxInputBytes: 51200
  maxBatchChars: 1500

segmentation:
  common:
    minLength: 2
    requireLetters: true
    skipPatterns:
      - 'https?://\S+'
      - '\S+@\S+\.\S+'
  html:
    skipElements: [script, style, code, pre, kbd, samp, var]
    skipAttributes: true
    skipComments: true
  json:
    skipKeys: true
    skipValuesForKeys: [id, uuid, url, href, path, type, kind]
  plain:
    skipPatterns:
      - '`[^`]+`'

features:
  preview: false
  history: true
  historySize: 20
  letterCase: preserve   # preserve | segmentStart | model
```

### Correction modes

Three settings, one per profile, each doing one thing. They are per profile
because trustworthiness is a property of the model, not of the tool: a local 4B
model and Claude do not deserve the same latitude.

| setting | what it controls |
|---|---|
| `corrections` | what the model is **asked** for — it picks the prompt |
| `editBudget` | how much is **tolerated** |
| `verification` | whether anything is **checked** |

`corrections` and `verification` are not two steps of one scale. The first
chooses the prompt, the second decides whether the result is inspected at all.

| `corrections` | in the window | the model may also… | checked by |
|---|---|---|---|
| `strict` (default) | Přísný | nothing — accents only | `fold(output) == fold(input)`, exact |
| `minor-fixes` | Drobné opravy | fix typos, spacing, punctuation, capitalization | per-word edit budget |
| `proofread` | Korektura | additionally fix spelling and grammatical agreement | per-word edit budget |

The budget is per **word**, not per segment: a segment-wide allowance grows with
length, so a 300-character paragraph would be permitted enough edits to rewrite
a whole sentence. Each word gets `max(minimum, length * percent / 100)` edits,
counted as Damerau-Levenshtein — two swapped letters cost 1, because that is the
commonest typo there is and scoring it 2 would put it out of reach.

The defaults are tight rather than generous. At 20 % with a floor of 1,
`kndeliky` → `knedlíky` and `bil` → `byl` each land exactly on the allowance.

Switching mode in the settings window pre-fills `(20 %, 1)` for *Drobné opravy*
and `(35 %, 2)` for *Korektura*, once. Tuned numbers are never reset by touching
another control.

**What you give up.** In a tolerant mode the tool can no longer prove that only
diacritics changed — it can only bound how much any single word changed. On a
short word that bound is loose: at `(35 %, 2)` a three-letter word may change
two of its three characters, so `pes` → `kos` passes. There is also no cap on
how many words in a segment may change, so a long paragraph can be reworded a
word at a time within budget. Both are the reason every shipped profile stays
`strict`, and the reason *Korektura* on a small local model is a bad idea.

Segments longer than 2000 characters are compared strictly whatever the mode
says: the alignment is O(n·m) and not worth running on a paragraph that size.

### Letter case

Capitalizing the first word of a sentence is good Czech, and small models do it
whatever the prompt says. But case is not diacritics, and `fold(output) ==
fold(input)` is what proves nothing else changed — so how much freedom the model
gets is a choice:

| `letterCase` | `proc se to stalo v praze` becomes | guarantee |
|---|---|---|
| `preserve` (default) | `proč se to stalo v praze` | intact — case is forced back |
| `segmentStart` | `Proč se to stalo v praze` | only the first letter of a segment may change |
| `model` | `Proč se to stalo v Praze` | given up — `PRAHA` may come back as `Praha` |

A segment is a line of plain text, a JSON string value or one HTML text node —
often a sentence, but not always one, which is why `segmentStart` is a rule about
segments rather than about sentences.

**`letterCase` only acts in `strict` mode.** A tolerant mode asks the model to
fix capitalization, so forcing the original case back would undo the very thing
that was requested. The settings window greys the control out when the active
profile is tolerant.

### API keys

Config files hold a *reference*, never the key itself:

```yaml
apiKey: { source: keychain, account: czechator-openai }   # macOS app
apiKey: { source: env, name: OPENAI_API_KEY }             # CLI
```

Enter the key in the settings window and it goes to the Keychain. The key is
read lazily, right before the request is built, so nothing logged or kept in
history can contain it.

### Trigger

There are two ways to start a correction, and they trade off against each other.

**A key combination** (the default) needs no permission and works the moment you
install the app. Its cost is that a global hotkey is unconditional: whatever
combination it registers, it holds in every application, for as long as the app
runs. `Cmd+B` is deliberately not the default for exactly that reason —
registering it would steal "bold" everywhere. Anything that parses works —
`cmd+ctrl+d`, `cmd+alt+k`, `ctrl+shift+p` — and the settings window warns you
about the single-⌘ combinations (`cmd+c`, `cmd+b`, …) that every application
relies on. It cannot warn about the rest: nothing on macOS can enumerate what
other applications have registered.

For a developer that is often still not enough: the combinations worth reaching
are already taken by an editor, a terminal, a launcher, or the keyboard-layout
switcher.

**A double tap of a modifier key** steals nothing, because a single press passes
straight through. Tap right ⌘ twice and the clipboard gets fixed; press it once
and it behaves exactly as it always did.

```yaml
trigger:
  kind: doubleTap          # combination | doubleTap
  modifier: rightCommand   # rightCommand | leftCommand | rightOption | leftOption
  intervalMs: 300          # allowed gap between the two taps
  maxHoldMs: 500           # longer than this counts as holding, not tapping
  debug: false             # log every modifier event with its key code
```

**Upgrading an existing install does not switch this on.** The config file is
written once and from then on overrides the built-in values, so a config that
predates this feature has no `trigger:` block at all and keeps the combination.
Choose the double tap in the settings window, or add the block by hand.

The side matters: `rightCommand` and `leftCommand` are different keys, which is
what keeps `⌘C ⌘V` typed with the left hand from ever looking like a double tap.
A tap only counts if nothing else happened during it — no other key, no other
modifier, and the key released within `maxHoldMs`.

The thresholds are deliberately strict. A false trigger rewrites the clipboard
when you did not ask for it, which is worse than a tap that did not register.

If a double tap does nothing at all, the key codes are the thing to check
first — they are the one part that cannot be verified without your keyboard.
Set `debug: true` under `trigger:`, restart the app, then watch:

```sh
log stream --predicate 'subsystem == "cz.czechator.app"'
```

Right ⌘ should report `keyCode=54`, left ⌘ `55`, right ⌥ `61`, left ⌥ `58`.

Setting `CZECHATOR_TRIGGER_DEBUG=1` does the same thing and is handier when you
run the binary straight from a terminal — but an app launched from the Dock or
by Finder never sees an environment you set in a shell, which is why the config
key is the one that works in the normal case.

It costs the Accessibility permission, which is why `combination` stays the
default. Choose the double tap and save, and macOS asks there and then — its
own dialog, where you accept or decline. Nothing asks at any other time: not on
launch, not on opening the settings window. If you decline, the menu keeps a
button that opens the Accessibility pane, since macOS shows that dialog only
once per application.
There is no silent fallback: if the permission is missing, the menu says so and
nothing is registered, rather than quietly going back to stealing a combination.

## Tuning segmentation

The rules are in *Settings → Advanced → Segmentation*, and in the config file.
When the tool corrects something it should have left alone, or skips something
it should have fixed, `czechator segments` shows what is actually being sent:

```bash
$ printf '{"id":"x","popis":"Prilis kun na https://example.com"}' \
    | czechator segments - --show-skipped
formát: json
segmentů: 1
1. [19+13] jsonString: Prilis kun na

vyloučené spany:
  [33] https://example.com   <- https?://\S+

aktivní pravidla:
  common.minLength = 2
  common.requireLetters = true
  common.skipPatterns = ["https?://\\S+", "\\S+@\\S+\\.\\S+"]
  json.skipKeys = true
  json.skipValuesForKeys = ["id", "uuid", "url", "href", "path", "type", "kind"]
```

Add a pattern to `segmentation`, re-run, and see the effect immediately — no
rebuild.

## Known limitations

- **The CLI asks for Keychain access the first time.** A key stored from the
  app belongs to the app, and the CLI is a different program as far as macOS is
  concerned, so it prompts once — click *Always Allow*. The terminal blocks
  until you answer. The approval is tied to the code signature: with an ad-hoc
  one a rebuilt CLI asks again every time, with a Developer ID it asks once.
- **Without a Developer ID, the Accessibility permission has to be granted
  again after every build.** It is tied to the code signature, and ad-hoc
  signing produces a new one each time. `make install` then clears the stale
  record for you (`make reset-accessibility` does it on its own), but granting
  it again is yours to do. A Developer ID signature does not change, so the
  permission survives — see [Signing](#signing). This affects the double-tap
  trigger only.
- **Neither trigger fires into a secure input field.** While a password field
  has focus, macOS delivers no key events to any application.
- **Wrong diacritics are not detected.** Verification proves nothing *but*
  diacritics changed; it cannot prove the diacritics are right. `bít` and `byt`
  fold identically, so picking the wrong one passes. That is a model-quality
  problem, and the reason the model matters.
- **A tolerant mode bounds the damage, it does not prevent it.** The per-word
  budget proves no word changed by more than its allowance — not that no word
  should have changed. Nothing caps how many words in one segment may each spend
  their allowance, so a long paragraph can be reworded a word at a time and pass.
- **With `verification: false`, a swallowed non-breaking space is lost
  silently.** Non-breaking spaces are hidden from the model and restored by
  position afterwards; the check that catches a failed restoration is part of
  verification. Turning verification off turns that off with it. Entities and
  JSON escapes are still protected — those would corrupt the document rather
  than merely lose a character, so they are refused in every mode.
- **`czechator quality` measures again every time; there is no cache.** The
  same profile on the same model is re-asked from scratch on every run, so
  against a paid API a repeated measurement is repeated spend. There is no
  confirmation prompt and no spending guard anywhere in the command — an
  unknown profile, a bad `--format` or an unreadable fixtures directory is
  refused before the first call, but a sweep you meant to run costs what it
  costs.
- **`--model` is sent to every measured profile.** It is a shortcut for
  comparing models, not backends. A matrix that mixes an Ollama profile with an
  OpenAI-compatible one gets one model name pushed into both, and the run fails
  on the second call.
- **Measured comparison is exact equality against the reference.** A legitimate
  different correction of the same typo counts as a miss, and so does a
  different but equally correct comma placement. The number is a floor, not a
  verdict.
- **Measurement forces `verification: true`,** even against a profile that has
  it turned off — without it the *accepted* and *refused* columns would be
  constant. The provenance line says `ověřování vynuceno` when that happened,
  but the profile's own numbers are not what you measured.
- **In a tolerant mode the comparison ignores letter case,** because
  `letterCase` does not act there. A sample that exists to measure a missing
  capital therefore cannot be measured — see `Fixtures/typos/README.md` on
  `09-velke-pismeno`.
- **RTF-only clipboards** are reported as unsupported rather than mangled.
- **Structure that does not parse is refused, not guessed.** JSON with comments
  or a trailing comma, NDJSON, a truncated fragment, and config formats that are
  not supported at all — TOML, INI, YAML, .properties — are declined rather than
  treated as prose, which would let the model rename your keys. Verification
  cannot catch that on its own, because `fold("název") == fold("nazev")`.
  Telling a config file from a note that happens to use labels is a heuristic
  with no exact answer, so it is tuned to err on the side of refusing: a line
  that assigns with `=`, a dotted or underscored key, a `[section]` header or a
  YAML block will be declined even when it was prose.
- **CSV headers are not protected.** A CSV handler is not implemented, so a
  header row is corrected like any other line — `jmeno,prijmeni` becomes
  `jméno,příjmení`.
- **Changing a built-in default does not reach existing installations.** The
  config file is materialized in full on first run and then wins. Rules that
  exist to prevent corruption are therefore kept out of the config entirely.
- **The clipboard is replaced silently.** There is no diff preview yet; the
  history in the menu bar is the undo.
- **Distribution needs notarization.** A Developer ID signature is enough on
  your own machine, where a locally built app carries no quarantine attribute.
  Handing the `.app` to someone else would additionally need notarization, which
  this project does not do — `spctl` rejects the bundle as
  `Unnotarized Developer ID`.

## Architecture

```
Sources/
  CzechatorCore/     format detection, segmentation, verification, providers
  czechator/         CLI
  CzechatorApp/      menu bar app, hotkey, clipboard, Keychain
llm/                 Python pipeline that fine-tunes the czechator-* models
```

`CzechatorCore` never imports AppKit, SwiftUI, Security or Carbon — the clipboard,
the hotkey and the Keychain all live in the app shell. The core is therefore
portable and every interesting rule in it is tested headlessly.

The central design decision: **handlers report ranges, they never serialize.**
`JSONSerialization` would lose key order and formatting, so a handler only says
"characters 19 to 34 are correctable text" and the document is rebuilt around
those ranges from the original string. Everything outside them is untouched by
construction rather than by care.

[`docs/design.md`](docs/design.md) is the design note the tool was built from —
why segments are ranges rather than tree nodes, why the prompt is English with
Czech examples, which alternatives were rejected and on what grounds. It records
the reasoning, not the current code: the implementation moved on in several
places, notably how JSON escapes and HTML entities are tracked (by grapheme
position rather than by flag) and everything around whitespace and letter case,
none of which the design anticipated.

[`docs/superpowers/specs/2026-08-24-tolerance-oprav-design.md`](docs/superpowers/specs/2026-08-24-tolerance-oprav-design.md)
supersedes its section on verification: it is the design note for the per-word
budget, and it records what the relaxation costs as well as what it buys.

### Testing

`make test`, never `swift test` — the flags that let swift-testing run under
Command Line Tools live in the Makefile.

`CzechatorCoreTests` covers the portable core. `CzechatorAppTests` covers the
macOS layer by injecting the parts that touch the system: `AppModel` takes its
config store, its permission check and its trigger factory from outside, so the
rules for choosing and replacing a trigger are tested without registering a
global hotkey or asking macOS for anything.

The settings window's rules — whether saving is allowed, whether a change
should ask for the Accessibility permission, what the warning says, which
controls are live — live in `SettingsFormState` rather than inside the view, so
they are tested as ordinary logic. Every bug that has escaped review is pinned
by a test that fails if it is reintroduced.

One of those is worth naming, because no ordinary test could have caught it:
`protectedIndices` was declared only in a protocol extension, so through an
`any FormatHandler` it dispatched statically to the empty default and the whole
protected-index branch was dead code. The handler tests passed because they call
concrete types, where the override dispatches normally. It surfaced only because
a mutation check stayed green when it should have gone red, and it is now pinned
by a test that goes through the existential.

What is still not covered is SwiftUI itself: that the right controls appear in
the right sections is verified by review, not by tests. ViewInspector would
cover it but cannot be built here — it imports XCTest unconditionally, and
Command Line Tools ship only Testing.framework.

## Versioning

The version lives in one place, `Sources/CzechatorCore/Version.swift`. The
Makefile stamps it into the bundle's `Info.plist` at build time, so the app, the
CLI (`czechator --version`) and the About panel can never disagree.

The CLI has no default subcommand — `czechator fix` and `czechator segments` are
always spelled out, which leaves `--version` and `--help` at the root where they
are expected.

## Contributing

Issues and pull requests are welcome. Two things to know before you open one:

- `make test` must stay green, and it runs with only the Command Line Tools
  installed — no Xcode required.
- Rules that exist to prevent data corruption are deliberately **not**
  configurable. The config file is materialized on first run and then wins, so a
  safety default shipped later would never reach an existing installation.

## License

MIT — see [LICENSE](LICENSE).

Dependencies are linked statically; their notices are in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
