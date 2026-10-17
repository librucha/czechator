# Nápady na vylepšení

Zásobník námětů, které zatím nemají spec. U každého je problém, návrh a co
stojí. Když se některý začne dělat, dostane vlastní spec v
`docs/superpowers/specs/` a odsud se odkáže.

## 1. `keep_alive` — model připravený v paměti

**Problém.** Ollama po 5 minutách bez requestu model z paměti uvolní. První
oprava po pauze pak čeká na načtení: u `czechator-gemma3-270m` zhruba 1 s, u
`czechator-gemma4-e2b` 3 s a u `qwen3:4b-instruct` kolem 6 s. Czechator
`keep_alive` neposílá, takže každý jeho request vrátí časovač na výchozích
5 minut. Ruční předehřátí s `"keep_alive": -1` proto vydrží jen do první
opravy.

**Návrh.** Nový nepovinný klíč profilu `keepAlive` (pro `kind: ollama`),
posílaný jako `keep_alive` v každém `/api/chat`:

```yaml
profiles:
  fast:
    kind: ollama
    model: czechator-gemma3-270m:v1-q8_0
    keepAlive: -1          # -1 = nikdy neuvolnit | "30m" | 0 = uvolnit hned; chybí = výchozí Ollamy
```

Volitelně předehřátí po startu aplikace a po přepnutí profilu: prázdný
request s `keep_alive`, aby první oprava nečekala.

**Spolu s tím `num_ctx`.** Czechator neposílá ani `num_ctx`, a Ollama proto
načte `qwen3:4b-instruct` s výchozím kontextem modelu 262 144 tokenů, což je
24 GB paměti. Czechator přitom posílá dávky do 1500 znaků. Klíč `numCtx` (např.
4096) poslaný v `options` by paměť srazil na zlomek. Fine-tunované modely mají
`num_ctx 4096` už ve svém Modelfile.

**Co to stojí.** `keepAlive: -1` drží model v paměti napořád: 270M zhruba
300 MB, E2B 5 GB, `qwen3:4b-instruct` bez `numCtx` 24 GB. Do README patří
varování a doporučení nastavit oba klíče spolu.

## 2. Učicí režim — sběr vět, které neprošly kontrolou

**Problém.** Když verifikace výsledek odmítne, czechator neudělá nic a důvod
oznámí v notifikaci. Informace, *na čem* model selhává, se tím ztratí. Přitom
právě tyhle věty jsou nejcennější data pro další iteraci fine-tuningu a pro
privátní eval set (`llm/data/private/`).

**Návrh.** Volba v nastavení, ve výchozím stavu vypnutá:

```yaml
learning:
  enabled: false
  path: ~/Library/Application Support/Czechator/learning.jsonl
```

Při zapnuté verifikaci se každý odmítnutý segment zapíše jako jeden řádek
JSONL: vstup, výstup modelu, důvod odmítnutí (první rozdílná pozice po `fold`,
počet položek, chyba formátu), profil, model, režim oprav a čas. Zapisuje se
segment, ne celá schránka.

Navazující krok v `llm/`: příkaz, který záznamy projde, nechá uživatele
doplnit správnou verzi (TSV jako u `hybrid.review.tsv`) a výsledek naimportuje
jako privátní eval nebo jako trénovací data další iterace.

**Rozšíření.** Ukládat volitelně i segmenty, které verifikací prošly, ale
uživatel je po vložení ručně opravil. To ale czechator nevidí; šlo by jen přes
explicitní akci „tohle bylo špatně“ v historii v menu.

**Co to stojí a rizika.**
- **Soukromí.** Schránka obsahuje cokoli: hesla zkopírovaná mimo zabezpečené
  pole, osobní zprávy, klíče. Soubor proto zůstává jen lokálně, je vypnutý
  ve výchozím stavu a zapnutí musí jasně říct, co se ukládá. Hodí se i limit
  velikosti nebo stáří a příkaz na smazání.
- Odmítnutí nemusí být chyba modelu: vstup může obsahovat překlep, který
  `strict` režim opravit nesmí. Záznam proto musí nést režim oprav, ať se při
  importu dá filtrovat.
- Nová cesta, kterou je potřeba popsat v README včetně Known limitations.
