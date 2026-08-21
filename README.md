# Czechator

Restores Czech diacritics in whatever is on your clipboard — press a hotkey,
paste the fixed text.

Czech text typed without diacritics ("Prilis zlutoucky kun" instead of "Příliš
žluťoučký kůň") is everywhere: chat messages, commit messages, notes written on
a foreign keyboard. Czechator sends that text to a language model and puts the
corrected version back on your clipboard.

The point of the tool is what it does **not** touch. If the clipboard holds
JSON, XML or HTML, only the text nodes are corrected — keys, tags, attributes,
indentation and formatting come back byte-for-byte identical. And nothing is
ever written back unless it passes verification.

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

The guarantee is a single invariant, checked before anything is written:

```
fold(output) == fold(input)
```

where `fold` strips Czech diacritics. If the model changed a word, the casing,
the whitespace, the structure, or added a comment of its own, the two sides
differ and the result is refused. **When Czechator cannot do the job safely, it
does nothing at all and tells you why** — your clipboard is never left worse
than it was.

## Features

- **Two ways to trigger it** — a global hotkey (`Cmd+Ctrl+D` by default), or
  a double tap of the right ⌘ that takes no shortcut away from anything.
- **Structure-aware.** Plain text, Markdown, JSON, XML and HTML. In structured
  formats only text nodes are corrected; the document is reassembled from the
  original bytes around them.
- **Verification before every write.** Nothing unverified reaches the clipboard.
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

Czechator does not fix typos, grammar or punctuation, does not translate, and
does not reformat. It adds accents and nothing else.

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

### Just the CLI

```bash
make install-cli                       # to ~/.local/bin
make install-cli BINDIR=/usr/local/bin # somewhere else (may need sudo)
```

`make install-cli` warns if the target directory is not on your `PATH`.

### Building without installing

```bash
make build     # both targets
make test      # 196 tests
make icon      # build/Czechator.icns from img/exports/AppIcon.appiconset
make app       # build/Czechator.app
```

Tests run through `make test`, never bare `swift test`: with only the Command
Line Tools installed, `Testing.framework` sits outside the default search paths
and the Makefile supplies the flags.

## Tuning

`czechator fix --debug` prints what went to the model and what came back, on
stderr, so a refused run shows the actual answer instead of just a count:

```
$ echo 'Prilis zlutoucky kun.' | czechator fix - --debug
── dávka (1 položek) ──
  1. posláno: Prilis zlutoucky kun.
     vráceno: Příliš žluťoučký kůň.
     → jen diakritika, v pořádku
```

On a rejection it also points at the first character where the folded forms
diverge — the change the model made beyond adding accents.

Four things are worth turning, roughly in order of effect: the **model**
(`profiles.<name>.model`), the **prompt** (`prompt.override`), the **batch size**
(`limits.maxBatchChars` — set it low while tuning so each line goes on its own),
and **what gets sent at all** (`segmentation`, inspected with `czechator
segments --show-skipped`).

Measure rather than guess: `Tools/quality.py <model>` runs the fixtures in
`Fixtures/quality/` and reports both how many samples came out exactly right and
how many passed verification. Those are different numbers and both matter.

## Which model to use

`qwen3:4b-instruct` is the default and the one that was measured. On the
23-sample suite in `Fixtures/quality/` it got 15 exactly right and 22 past
verification. Its misses are almost all a missing `ě`.

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
  openai:
    kind: openai-compat
    endpoint: https://api.openai.com/v1
    model: gpt-4o-mini
    temperature: 0
    timeoutSeconds: 30
    apiKey: { source: keychain, account: czechator-openai }

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
  history: true
  historySize: 20
  letterCase: preserve   # preserve | segmentStart | model
```

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
default and why the permission is only ever asked for at the moment you switch.
There is no silent fallback: if the permission is missing, the menu says so and
nothing is registered, rather than quietly going back to stealing a combination.

## Tuning segmentation

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

- **The Accessibility permission has to be granted again after every build.**
  It is tied to the code signature, and the ad-hoc signing this project uses
  produces a new one each time. The stale entry usually has to be removed from
  the list in System Settings by hand before the new one takes effect. This
  affects the double-tap trigger only.
- **Neither trigger fires into a secure input field.** While a password field
  has focus, macOS delivers no key events to any application.
- **Wrong diacritics are not detected.** Verification proves nothing *but*
  diacritics changed; it cannot prove the diacritics are right. `bít` and `byt`
  fold identically, so picking the wrong one passes. That is a model-quality
  problem, and the reason the model matters.
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
- **Distribution needs signing.** The build is ad-hoc signed, which is fine on
  your own machine. Handing the `.app` to someone else would need a Developer ID
  and notarization.

## Architecture

```
Sources/
  CzechatorCore/     format detection, segmentation, verification, providers
  czechator/         CLI
  CzechatorApp/      menu bar app, hotkey, clipboard, Keychain
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

### Testing

`make test`, never `swift test` — the flags that let swift-testing run under
Command Line Tools live in the Makefile.

`CzechatorCoreTests` covers the portable core. `CzechatorAppTests` covers the
macOS layer by injecting the parts that touch the system: `AppModel` takes its
config store, its permission check and its trigger factory from outside, so the
rules for choosing and replacing a trigger are tested without registering a
global hotkey or asking macOS for anything.

The settings window's rules — whether saving is allowed, whether a change
should ask for the Accessibility permission, what the warning says — live in
`SettingsFormState` rather than inside the view, so they are tested as ordinary
logic. Both bugs that once escaped review are pinned by a test that fails if
the bug is reintroduced.

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
