# Osobní slovník — design

**Stav:** návrh k implementaci
**Datum:** 2026-10-21

## 1. Motivace

Model občas přidá diakritiku tam, kam nepatří, nebo ji u konkrétního výrazu
opakovaně netrefí. Skutečný případ: `google docs` → `google dočš`. Výstup se
od vstupu liší jen diakritikou, takže prošel verifikací a dostal se do
schránky. Stejně dopadají vlastní jména (`Ahmadinezad` → `Ahmadinezad` místo
`Ahmadínežád`), firemní a produktové názvy a žargon.

Uživatel chce mít možnost takové výrazy zadat jednou a mít je pak opravené
vždy, bez přetrénování modelu. Později z nich chce udělat trénovací data.

**Proč ne RAG** (zhodnoceno a zamítnuto): příklady vložené do promptu by
rozbily cache prefillu, fine-tunované modely znají jen svůj kontrakt (riziko
kopírování příkladů a chyb formátu) a v režimu `strict` je pár stejně jen
pravidlo nahrazení, které jde uplatnit deterministicky a se zárukou.

## 2. Cíle, ne-cíle, anti-cíle

**Cíle**

- Uživatel zadá páry *zadaný text → požadovaný text*; czechator je uplatní na
  každý výstup modelu, deterministicky, ve všech profilech a režimech.
- Pravidlo umí obojí: **ochranu** (`google docs` → `google docs`, tedy „na tohle
  nesahej“) i **opravu** (`Ahmadinezad` → `Ahmadínežád`).
- Zadávání copy-paste v nastavení aplikace.
- Slovník je strojově čitelný, aby ho pipeline v `llm/` později mohla načíst
  a vyrobit z něj trénovací data.

**Ne-cíle**

- Sběr vět z uživatelovy schránky. Věty pro trénink se později dogenerují
  přes Batch API z párů a ručně zkontrolují, mimo czechator.
- Generování trénovacích dat v `llm/`. To je samostatný pozdější krok; tento
  návrh jen zajistí stabilní formát.
- Skloňování a kontext. Pravidlo zná jen přesný tvar.
- Import a export slovníku jako samostatného souboru, synchronizace.

**Anti-cíle** — co by bylo selhání, i kdyby to technicky fungovalo:

- Slovník, kterým jde měnit cokoli jiného než diakritiku. Czechator slibuje,
  že mění jen háčky a čárky (README, *Not in scope*); pravidlo `teda → tedy`
  by ten slib porušilo.
- Zpomalení opravy, závislost na dalším modelu, změna promptu.
- Tiché selhání: hand-written pravidlo, které nejde uplatnit, a nikdo se to
  nedozví.

## 3. Pravidlo

Pravidlo je dvojice `from` → `to`.

**Platné pravidlo:**

- `fold(from).lowercased() == fold(to).lowercased()` — liší se nejvýš
  diakritikou a velikostí písmen. `fold` je stávající `DiacriticFolding.fold`.
  Protože `fold` mění znak na znak, mají obě strany stejnou délku. Velikost
  písmen se toleruje, protože ve výsledku se stejně bere z výstupu (§4); `to`
  je kanonický tvar, který později poslouží jako trénovací cíl. *Moje volba.*
- Žádná dvě pravidla nemají stejné `fold(from).lowercased()` — chytala by
  stejná místa a jedno by tiše přebilo druhé; rozporné páry by se navíc dostaly
  do trénovacích dat. Duplicita je chyba jako každá jiná (§5, §6). *Moje volba.*
- `from` po oříznutí bílých znaků není prázdné a neobsahuje nový řádek
  (segmenty prostého textu jsou řádky; pravidlo přes konec řádku by se nikdy
  neuplatnilo).
- Okraje se ořezávají při ukládání; vnitřní mezery zůstávají, jak jsou.

Neplatné pravidlo se do konfigurace nedostane: nastavení ho neuloží (viz §5)
a ručně zapsané neplatné pravidlo zastaví načtení konfigurace chybou, která
pravidlo jmenuje — stejně jako dnes neplatný endpoint (`ConfigError`,
`Config.validate()`).

## 4. Uplatnění

**Kde:** na výstup modelu, po stávajícím zarovnání bílých znaků a velikosti
písmen (`alignEdgeWhitespace`, `alignCase`) a **před verifikací**. Platí ve
všech režimech oprav, u všech profilů, v aplikaci i v CLI (`czechator fix`,
`czechator quality`).

**Verifikace zůstává poslední slovo.** Protože pravidlo mění jen diakritiku,
`fold` výstupu se jím nezmění: segment, který verifikací prošel by bez
slovníku, projde i s ním, a obráceně. Se zapnutou verifikací slovník nic
nového nepropustí. Se **vypnutou** verifikací se slovník uplatní také —
přebije výstup modelu (výslovné přání uživatele).

**Jak se hledá shoda:**

- Porovnává se `fold(text).lowercased()` s `fold(from).lowercased()`: bez
  ohledu na diakritiku a velikost písmen. `google docs` tedy chytí
  `google dočš`, `Google Dočš` i `GOOGLE DOCS`.
- Jen na hranicích slov: znak před shodou a znak za ní nesmí být písmeno ani
  číslice (nebo je shoda na okraji segmentu). `docs` nechytí `docsy` ani
  `mydocs`.
- Mezera v `from` chytí jakýkoli jeden bílý znak včetně nezlomitelné mezery
  (`Google&nbsp;Docs` v HTML), vždy jeden za jeden; bílé znaky výstupu se
  nemění. *Moje volba.*
- Při překryvu vyhrává delší pravidlo; mezi stejně dlouhými to, které začíná
  dřív. Nalezená shoda se už znovu neprohledává.

**Co se zapíše:** na pozice shody se přenese diakritika z `to`; **velikost
písmen zůstane z výstupu**. Pravidlo `Ahmadinezad → Ahmadínežád` udělá z
`AHMADINEZAD` `AHMADÍNEŽÁD` a z `ahmadinezad` `ahmadínežád`. V režimu `strict`
je velikost písmen výstupu už srovnaná se vstupem (`alignCase`), takže
výsledek verifikací projde; v tolerantních režimech zůstane velikost tak, jak
ji model opravil.

**Ochrana** je pravidlo, kde `from == to`: zapsáním `to` na pozice shody se
z `dočš` stane zpět `docs`.

**Diakritiku, kterou napsal uživatel, slovník nepřepisuje** (rozhodnutí
uživatele). Pravidlo se na shodu uplatní, jen když odpovídající úsek
**vstupu** neobsahuje žádný znak s diakritikou. Slovník opravuje model, ne
uživatele:

- vstup `rad`, výstup `rad`, pravidlo `rad → rád` → `rád`;
- vstup `řad` (napsáno záměrně), výstup `řad` → zůstane `řad`;
- vstup `Dočš` (záměrně) → ochranné pravidlo `docs → docs` ho nezmění.

Rozhoduje se po celých shodách, ne po znacích: kdyby se `ř` ze vstupu
zachovalo a zbytek vzal z pravidla, vzniklo by `řád`, které nechtěl nikdo.

Odpovídající úsek vstupu: když má výstup stejnou délku jako vstup (vždy v
režimu `strict` po `alignCase`, a pokaždé, kdy model změnil jen diakritiku),
jsou to tytéž pozice. Jinak (tolerantní režim nebo vypnutá verifikace a model
změnil délku) se vstup a výstup zarovnají stávajícím `EditAlignment`; když se
celý úsek shody na vstup zobrazit nedá, pravidlo se na tu shodu neuplatní.
*Moje volba* — nejistota znamená nesahat.

## 5. Nastavení

Nová, třetí záložka **Slovník** vedle *Základní* a *Pokročilé*.

- Tabulka se dvěma sloupci *Zadaný text* a *Požadovaný text*, přidání a
  odebrání řádku. Text se do polí vkládá copy-paste.
- Rozumné výchozí chování pro nový řádek: *Požadovaný* se předvyplní kopií
  *Zadaného* (nejčastější případ je ochrana a uživatel pak jen opraví
  diakritiku). *Volba builderu.*
- **Validace hned u řádku.** Řádek s chybou **zablokuje uložení** stejně jako
  dnes jiné chyby formuláře (`SettingsFormState.canSave`) a hláška u něj řekne
  proč; nic se tiše neztratí. Úplně prázdný řádek (obě pole prázdná) není
  chyba a při uložení se zahodí. *Moje volba.* Chyby:
  - liší se víc než diakritikou → vysvětlení, že czechator mění jen
    diakritiku, a ukázka, kde se texty liší;
  - jen jedno pole prázdné, nebo nový řádek v textu → krátká zpráva;
  - duplicita k jinému řádku (§3) → odkaz na ten řádek.
- **Upozornění u jednoslovného pravidla** (neblokuje uložení): proč to není
  dobrý nápad — pravidlo zasáhne každý výskyt slova bez ohledu na kontext
  (`rad` je *rád*, *řád* i *řad*) a nepokryje jiné tvary (`Ahmadínežád`
  nepokryje `Ahmadínežáda`); doporučení zapsat ho jako frázi (`chce byt` →
  `chce být`). Jednoslovné = `from` po oříznutí neobsahuje mezeru.
- Ukládá se stávající cestou `ConfigStore.save`, se zachováním ručně
  dopsaných klíčů.

Přesné rozvržení, texty hlášek a ovládání jsou na builderovi; musí odpovídat
stylu stávajících záložek (`Form`, `Section`, české popisky).

## 6. Konfigurace

Nový klíč nejvyšší úrovně v `config.yaml`, globální pro všechny profily:

```yaml
dictionary:                  # osobní slovník; pravidla mění jen diakritiku
  - from: google docs
    to: google docs          # ochrana: from == to
  - from: Ahmadinezad
    to: Ahmadínežád
```

- Výchozí hodnota: prázdný seznam. Starý konfig bez klíče se načte (ručně
  psané `init(from:)` s `decodeIfPresent`, jako ostatní typy v `Config`).
- Formát je kontrakt i pro `llm/`: seznam objektů s klíči `from` a `to`,
  řetězce v UTF-8. Měnit ho jen se spec, která řeší i čtení v `llm/`.
- Vzorek v README dostane klíč i s komentářem (pravidlo `CLAUDE.md`).

## 7. Co je na builderovi

- Datové typy (`DictionaryRule`, `PersonalDictionary` …) a kde žijí v
  `CzechatorCore` (bez AppKit).
- Algoritmus vyhledávání (počet pravidel jsou desítky až stovky; jednoduchý
  průchod stačí).
- Zda se pravidla uplatní i na výsledek vzatý z cache segmentů (`cache` v
  `Pipeline.fill`) — musí platit, že stejný vstup dává stejný výstup.
- Debug výstup (`czechator fix --debug`): rozumné je vypsat, které pravidlo
  se kde uplatnilo.

## 8. Testy

TDD. Minimálně:

- validace: diakritika-only (i s jinou velikostí písmen) přijato, jiná změna
  odmítnuta, prázdné a s novým řádkem odmítnuto, okraje oříznuty, duplicita
  odmítnuta; neplatné ručně zapsané pravidlo zastaví `load` chybou se jménem
  pravidla;
- shoda: bez ohledu na diakritiku i velikost písmen, jen na hranicích slov,
  víceslovné pravidlo, mezera chytí NBSP, delší vyhrává, ochrana `from == to`;
- přenos diakritiky se zachováním velikosti písmen výstupu;
- diakritika ze vstupu se nepřepíše (`řad` zůstane), ani při ochraně
  (`Dočš` zůstane); v tolerantním režimu s jinou délkou výstupu přes
  zarovnání, a když se úsek zarovnat nedá, pravidlo se neuplatní;
- uložení formuláře: chybný řádek blokuje, prázdný se zahodí;
- v pipeline: uplatní se před verifikací, ve `strict` i tolerantním režimu,
  při vypnuté verifikaci; s verifikací se nezmění, co projde a co ne;
- konfigurace: round-trip YAML, starý konfig bez klíče, zachování ručních
  klíčů při uložení;
- nastavení: stav formuláře (validace řádku, upozornění u jednoho slova)
  testovatelný bez UI, jako stávající `SettingsFormState`.

## 9. Dokumentace

- **README**: funkce v seznamu *Features*; nová sekce o slovníku; vzorek
  konfigurace; **Known limitations**: skloňování, kontext u jednoslovných
  pravidel, jen diakritika, pravidlo nepřekročí hranici segmentu (řádku),
  úsek se vstupem psaným s diakritikou slovník nechá být (i když je tam chyba),
  v tolerantním režimu se pravidlo neuplatní, když model úsek přestavěl tak, že
  ho nejde zarovnat se vstupem;
  odstavec *How it protects your text* doplnit, že slovník běží před
  verifikací a nic jí neobchází. Projít výskyty *never*/*only* o tom, co
  czechator mění — slovník je nesmí zneplatnit (nezneplatní, ale ověřit).
- **`docs/napady.md`**: poznámka, že slovník je hotový, a odkaz na budoucí
  krok v `llm/` (generování vět z párů přes Batch API + ruční kontrola).
- Počet testů v README.
