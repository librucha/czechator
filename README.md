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

- **Global hotkey** — `Cmd+Ctrl+D` by default, configurable.
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
git clone <repository-url> czechator
cd czechator

ollama pull qwen3:4b-instruct     # ~2.5 GB
make install                      # builds and copies to /Applications
```

Then open `/Applications/Czechator.app`. It has no Dock icon — look for it in
the menu bar. macOS will ask once for permission to show notifications.

Copy some Czech text without diacritics, press `Cmd+Ctrl+D`, and paste.

### Just the CLI

```bash
swift build -c release
cp .build/release/czechator /usr/local/bin/
```

### Building without installing

```bash
make build     # both targets
make test      # 192 tests
make app       # build/Czechator.app
```

Tests run through `make test`, never bare `swift test`: with only the Command
Line Tools installed, `Testing.framework` sits outside the default search paths
and the Makefile supplies the flags.

## Which model to use

`qwen3:4b-instruct` is the default and the one that was measured. On a
ten-sample Czech suite it got 6/10 exactly right and 9/10 past verification.

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
```

### API keys

Config files hold a *reference*, never the key itself:

```yaml
apiKey: { source: keychain, account: czechator-openai }   # macOS app
apiKey: { source: env, name: OPENAI_API_KEY }             # CLI
```

Enter the key in the settings window and it goes to the Keychain. The key is
read lazily, right before the request is built, so nothing logged or kept in
history can contain it.

### Shortcut

`Cmd+B` is deliberately **not** the default. Registering it globally would steal
"bold" from every application on the system. Anything that parses works —
`cmd+ctrl+d`, `cmd+alt+k`, `ctrl+shift+p` — and the settings window warns you
about shortcuts that are likely to collide.

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

- **Wrong diacritics are not detected.** Verification proves nothing *but*
  diacritics changed; it cannot prove the diacritics are right. `bít` and `byt`
  fold identically, so picking the wrong one passes. That is a model-quality
  problem, and the reason the model matters.
- **RTF-only clipboards** are reported as unsupported rather than mangled.
- **Structure that does not parse is refused, not guessed.** JSON with comments
  or a trailing comma, NDJSON, a truncated fragment — Czechator declines rather
  than fall back to treating the document as prose, which would let the model
  rename your keys. Verification cannot catch that on its own, because
  `fold("název") == fold("nazev")`.
- **CSV headers are not protected.** A CSV handler is not implemented, so a
  header row is corrected like any other line.
- **A word before a colon or equals sign at the start of a line is left
  alone.** That is how TOML, INI, YAML and .properties keys are protected from
  being renamed — the cost is that prose like `Poznamka: …` keeps its first word
  unaccented. The rest of the line is corrected normally.
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

Design notes and the implementation plan are in `docs/superpowers/`.

## License

TBD
