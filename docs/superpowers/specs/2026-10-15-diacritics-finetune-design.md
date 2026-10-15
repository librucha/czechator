# Fine-tuning malého modelu na doplňování diakritiky — design

**Stav:** návrh k implementaci
**Datum:** 2026-10-15
**Umístění kódu:** `llm/` (nový subsystém, nezávislý na Swift balíčku)

## 1. Motivace

Czechator dnes doplňuje diakritiku promptovaným obecným modelem
`qwen3:4b-instruct`. Na 23 vzorcích v `Fixtures/quality/` dává 15 přesně a 22
projde verifikací; většina chyb je chybějící `ě`. Model je 2,5 GB a každou
zprávu zpracovává s cca 400 tokeny pravidel a few-shot příkladů.

Úzká úloha — doplnit háčky a čárky a nic jiného — je ideální kandidát na
fine-tuning menšího modelu: trénovací data se dají vyrobit automaticky (vezmi
správný český text, odstraň diakritiku), a menší specializovaný model by měl
být rychlejší i přesnější než větší obecný.

Druhá motivace je **hybridní čeština**: dev chat, commity a tickety plné
anglických výrazů s českým skloňováním (`mergnul jsem PR do mainu`,
`pushnu to na staging zitra`). Promptovaný model s nimi nemá žádnou zkušenost a
spisovné korpusy je skoro neobsahují.

## 2. Rozsah

**V rozsahu (iterace 1):**

- pouze režim `strict` — doplnění diakritiky, nic dalšího,
- výstup: model spustitelný v Ollamě (`ollama create`) i v `llama-server`
  (stejný GGUF),
- vstupní smlouva kompatibilní s dnešním czechatorem (drop-in) **i** krátká
  smlouva pro budoucí použití (viz §4),
- sweep 2–4 malých kandidátů se stejnými daty a stejným evalem, výběr podle čísel.

**Mimo rozsah:**

- režimy `minorFixes` a `proofread` — případně pozdější samostatná iterace,
- změny ve Swift kódu czechatoru — drop-in formát je nevyžaduje; per-profile
  system prompt pro krátkou smlouvu se udělá jen tehdy, když ho měření ospravedlní,
- trénink v cloudu — vše běží lokálně (Apple M4 Max, 64 GB).

**Pracovní režim:** iterativní. Po každém runu uživatel model intenzivně testuje
v czechatoru a společně se rozhodne další krok (víc dat, větší rank, full FT,
jiný kandidát, další režim). Tento spec pokrývá pipeline a první iteraci.

## 3. Architektura

Pipeline má pět kroků. Každý je samostatný CLI krok, který čte a zapisuje
soubory; mezivýsledky leží na disku, takže kterýkoli krok jde spustit znovu bez
přepočtu předchozích.

```
1. data     korpusy -> filtr -> dedup                 data/raw, data/clean
2. synth    Claude Batch API -> hunspell kontrola      data/synth
3. format   páry -> augmentace -> chat JSONL           data/sets/<id>/{train,valid}.jsonl
4. train    mlx_lm.lora -> checkpointy -> fuse         runs/<run-id>/
5. export   GGUF -> kvantizace -> ollama create        runs/<run-id>/gguf, Modelfile
   eval     harness přes Ollama HTTP -> report         runs/<run-id>/report.md
```

Struktura:

```
llm/
  pyproject.toml          # uv, Python 3.12
  Makefile                # make data / synth / format / train / export / eval
  README.md
  configs/
    sweep-01.yaml         # kandidáti, hyperparametry, mix formátů a zdrojů
  czllm/
    fold.py               # odstranění diakritiky, stejná tabulka jako Swift
    numbered_list.py      # port NumberedList.encode/escape
    data/                 # stažení, filtrace, dedup
    synth/                # generování hybridu, hunspell kontrola
    format/               # augmentace, šablony smluv, JSONL
    train/                # obal nad mlx_lm.lora a mlx_lm.fuse
    export/               # GGUF, kvantizace, Modelfile, ollama create
    eval/                 # metriky, latence, report
  tests/
  data/                   # .gitignore — kromě zmražených eval setů
    eval/                 # web, hybrid (commitnuté)
    private/              # texty uživatele, vždy ignorováno
  runs/                   # .gitignore
```

Python 3.12 místo systémového 3.14: MLX a llama.cpp konvertor mají kolečka
spolehlivě pro starší verze. `uv` se nainstaluje jen pro `llm/`.

### 3.1 `fold` je jediný zdroj pravdy

Swift `DiacriticFolding` mapuje přesně 30 znaků (`áéíóúýčďěňřšťůž` v obou
velikostech); ostatní znaky (`ä`, `ö`, …) nechává beze změny. Python `fold`
používá stejnou tabulku a **test ji parsuje přímo ze
`Sources/CzechatorCore/Verification/DiacriticFolding.swift`**, takže se nemohou
rozejít. Tím je zaručeno, že trénovací vstup vypadá přesně jako to, co czechator
posílá a čím ověřuje výstup.

## 4. Vstupní smlouva

Model se trénuje na mixu dvou formátů nad stejnými daty:

| formát | system | user | podíl |
|---|---|---|---|
| drop-in | `PromptBuilder.defaultSystem`, byte-identický | `NumberedList.encode(items)` | ~60 % |
| krátká smlouva | `Restore Czech diacritics in each numbered item. Change nothing else.` | `NumberedList.encode(items)` | ~40 % |

Odpověď je vždy číslovaný seznam se stejným počtem a číslováním položek.

- **Drop-in** znamená, že stačí v profilu czechatoru změnit `model` — testovat
  se dá od první iterace bez zásahu do Swiftu. `defaultSystem` se pro trénink
  čte ze Swift zdroje, ne kopíruje ručně.
- **Krátká smlouva** se zapíše jako `SYSTEM` do Modelfile: když klient system
  nepošle, použije se ona. Czechator dnes system posílá vždy, takže ji zatím
  nevyužije; připravuje cestu k rychlejšímu cold startu.

## 5. Data

### 5.1 Zdroje

| zdroj | podíl v train | účel |
|---|---|---|
| FineWeb-2 `ces_Latn` (stream, ODC-By) | ~55 % | běžná a neformální čeština |
| česká Wikipedie | ~15 % | čistá spisovná čeština, vlastní jména |
| syntetický hybrid (Claude API) | ~20 % | dev chat, commity, tickety, code review, maily |
| tvrdé negativy | ~10 % | čistá angličtina, identifikátory, URL, čísla; cíl = vstup |

**Filtrace webu:** web obsahuje hodně textu psaného bez diakritiky; ten by
model naučil cíl bez háčků. Dokument, ve kterém má diakritiku méně než 25 %
slov, se zahodí (běžná čeština má kolem 40–50 %). Dále jazyková detekce, dedup
a délkové limity.

### 5.2 Syntetický hybrid

Generuje Claude přes Batch API (−50 % ceny). Kategorie: dev chat, commit
messages, tickety, code review, pracovní maily, poznámky z porad. Prompt
vyžaduje česky skloňované anglické výrazy (`mergnout`, `deploynout`, `pushnu`,
`fixnutý`, `refaktorovat`), identifikátory, URL a čísla. Cíl iterace 1: cca 8k
vět, náklad v jednotkách USD.

**Kontrola:** hunspell `cs_CZ`. Když hunspell slovo z generátoru odmítne, ale
přijme jinou variantu se stejným `fold`, je vzorek podezřelý a zahodí se celý.
Anglická slova neznámá hunspellu nevadí.

### 5.3 Augmentace vstupu

Cíl je vždy plně diakritický text se **stejnou velikostí písmen jako vstup**.

- plné odstranění diakritiky — hlavní případ,
- částečná diakritika: náhodně se ponechá 0–50 % diakritických znaků (lidé
  někdy pár háčků napíšou a model je nesmí rozbít),
- vstup už plně diakritický — identita, cca 3 %,
- celá věta malými písmeny, ALL CAPS segmenty,
- literální escapy `\n`, `\r`, `\t`, `\\` přesně podle `NumberedList.escape`,
- 1–N položek v seznamu; délky podle segmentace czechatoru a výchozího
  `limits.maxBatchChars: 1500`.

**Invariant:** pro každý pár platí `fold(input) == fold(target)`. Kontrola běží
nad celým datasetem před tréninkem; porušení zastaví pipeline.

### 5.4 Velikost

Iterace 1: 40k trénovacích a 1k validačních příkladů — malé, aby sweep proběhl
rychle. Zvětšuje se podle křivky učení.

### 5.5 Eval sety

Zmražené, deduplikované proti train přes hash `fold(text)`:

- `eval/web` — 500 odložených vět z webu a Wikipedie,
- `eval/hybrid` — 300 vět; **cca 200 z nich ručně zkontroluje uživatel**,
  protože tento set rozhoduje o hybridu a generátor se mýlit může,
- `eval/private` — texty uživatele (Slack, poznámky, commity), jen lokálně v
  `data/private/`, nikdy v gitu a nikdy v train,
- `Fixtures/quality` — přes `czechator quality`.

## 6. Kandidáti

Stav k 2026-10 (ověřit přesná repo jména na HF v rámci fáze 0):

| kandidát | velikost | poznámka |
|---|---|---|
| Qwen3.5-0.8B (instruct) | 0.8B | non-thinking defaultně; nová hybridní architektura |
| Qwen3.5-2B (instruct) | 2B | obsahuje vision encoder — pro text se nepoužije |
| Gemma 4 E2B-it | ~2B efektivně | slovník 262k, úspornější tokenizace češtiny |
| Gemma 3 270M-it | 0.27B | navržená pro úzký fine-tuning; kontrola „jak malé stačí“ |

Rychlost: model generuje celý text znovu, takže latence roste s počtem
výstupních tokenů. Tokenizer, který rozbíjí `ř`, `ů`, `ě` na víc tokenů,
stejnou větu prodraží. Fáze 0 proto měří tokeny na znak.

## 7. Trénink a export

### 7.1 Fáze 0 — kompatibilní brána

Pro každého kandidáta (cca 15 minut): 50 kroků tréninku → fuse → GGUF →
`ollama run` → odpověď se rozparsuje jako číslovaný seznam; plus tokeny na znak
na `eval/web`. Kandidát, který neprojde (nepodporovaná architektura v MLX-LM
nebo v `convert_hf_to_gguf.py`, rozbitý chat template), vypadne ze sweepu.
Fallback exportu: `ollama create --quantize q4_K_M` přímo ze safetensors.

### 7.2 Trénink

`mlx_lm.lora` nad instruct variantami:

- JSONL `{"messages": [system, user, assistant]}`, `--mask-prompt` (loss jen z
  odpovědi),
- start: LoRA rank 16, alpha 32, všechny lineární vrstvy, lr 1e-4 (2e-4 pro
  270M), batch 16, 1 epocha, max seq 1024, pevný seed,
- validace každých 200 kroků, checkpointy zachované,
- thinking vypnutý v šabloně; eval kontroluje, že výstup neobsahuje `<think>`,
- full fine-tune až jako pozdější krok, pokud LoRA narazí na strop.

### 7.3 Export

```
mlx_lm.fuse --dequantize   ->  HF safetensors
convert_hf_to_gguf.py      ->  f16 GGUF
llama-quantize             ->  Q8_0, Q4_K_M
ollama create czechator-<base>:v<N>-<quant> -f Modelfile
```

Modelfile: `TEMPLATE` z base modelu, `PARAMETER temperature 0`,
`PARAMETER num_ctx 4096`, stop tokeny, `SYSTEM` = krátká smlouva.

### 7.4 Reprodukovatelnost

`runs/<run-id>/` obsahuje snapshot configu, git SHA, hash datového manifestu,
loss křivky, GGUF a report.

## 8. Eval

Harness volá model přes Ollama HTTP API stejně jako czechator (`/api/chat`,
`temperature` 0). Baseline `qwen3:4b-instruct` + `defaultSystem` běží přes
stejný harness.

### 8.1 Metriky (pro každý set a model)

| metrika | definice |
|---|---|
| exact % | segment byte-identický s referencí |
| verified % | `fold(out) == fold(in)` a seznam se rozparsuje — to, co czechator přijme |
| word DER | chybovost diakritiky po slovech; chybějící (recall) a přebývající (precision) zvlášť |
| EN untouched % | hybrid: anglická slova a identifikátory beze změny |
| ambiguous | chyby na slovech se stejným `fold` (`byt`/`být`, `rad`/`rád`/`řád`) zvlášť |
| format fail | chyba parsování, `<think>`, preambule, chybějící položka |
| latence | p50/p95 warm pro zprávu 300 znaků, cold první volání, tok/s; Q8_0 i Q4_K_M |

### 8.2 Rozhodovací kritéria iterace 1

- **povinné:** verified ≥ baseline na všech setech, 0 format fail, p50 < 1 s
  (300 znaků, warm, M4 Max),
- **výběr:** z kandidátů, kteří splní povinná kritéria, rozhoduje exact a DER
  na `hybrid` a `private`; při shodě vyhrává menší model,
- **konečný test:** `czechator quality --model <vítěz>`; baseline 15/23 exact,
  cíl ≥ 20/23.

Výstup: `runs/<run-id>/report.md` a souhrnná tabulka sweepu.

## 9. Testy kódu pipeline

pytest, TDD:

- `fold` — shoda s tabulkou parsovanou ze Swift zdroje,
- `numbered_list` — round-trip a shoda se Swift escapováním na stejných
  příkladech jako Swift testy,
- augmentace — invariant `fold(input) == fold(target)` a zachování velikosti
  písmen na náhodných vzorcích,
- validace datasetu — porušení invariantu zastaví pipeline,
- metriky — na ručně spočítaných příkladech,
- hunspell filtr — na připravených dobrých i chybných větách.

Trénink, export a latence se neunit-testují; ověřuje je fáze 0 a eval.

## 10. Dokumentace

- `llm/README.md` — jak spustit, výsledky iterací, known limitations,
- hlavní `README.md` — až existuje vítěz: sekce *Which model to use* a ukázka
  profilu v configu,
- tento spec — při odchylce implementace se opraví, nebo se uvede, co ho
  nahrazuje.

## 11. Known limitations (očekávané)

- Slova se stejným `fold` (`byt`/`být`, `pani`/`paní`) jdou rozhodnout jen z
  kontextu; malý model se bude mýlit. Verifikace czechatoru je nezachytí —
  obě varianty foldují stejně.
- Syntetický hybrid je jen tak dobrý jako generátor a hunspell kontrola; chyby,
  které hunspell přijme (existující slovo, špatný tvar), projdou do train.
- Eval set `private` je malý a reprezentuje jednoho autora.
- Fine-tuning nepřidává žádnou bezpečnostní záruku: ochranu dál zajišťuje
  verifikace czechatoru, ne model.
