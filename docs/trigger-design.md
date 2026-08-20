# Czechator — spouštěč: dvojí stisk modifikátoru

Datum: 2026-08-20
Stav: schváleno, připraveno k rozpracování do implementačního plánu

Navazuje na [design.md](design.md) a **otáčí jeho rozhodnutí v §10**: Carbon byl
zvolen proto, že nepotřebuje žádné oprávnění. Tady vědomě přijímáme Accessibility
výměnou za spouštěč, který nekrade žádnou klávesovou zkratku.

## 1. Problém

Globální registrace přes `RegisterEventHotKey` je nepodmíněná: jakmile aplikace
zkratku zaregistruje, drží ji ve všech aplikacích, dokud běží. Doložený případ —
`cmd+shift+d` zabralo v iTermu rozdělení panelu; zareagoval jen Czechator.

Nejde tedy o výběr volné kombinace. U vývojáře, který používá Claude, JetBrains
a přepínání layoutu klávesnice, je obsazené prakticky všechno, a jakákoli pevná
kombinace jen přesune problém jinam.

Kontrola `ShortcutSpec.isCommonSystemShortcut` dnes hlídá pouze `⌘` plus jedno
písmeno, takže `cmd+shift+d` propustila bez varování.

## 2. Řešení

**Dvojí stisk pravého ⌘.** Jednotlivé stisknutí projde beze změny dál, takže
žádná aplikace o nic nepřijde. Nástroj se spustí až na dvojici stisků v krátkém
okně.

Cena je oprávnění Accessibility, protože klávesové události nejsou bez něj
k dispozici.

## 3. Rozsah

| oblast | stav |
|---|---|
| Nový spouštěč | dvojí stisk modifikátoru |
| Původní spouštěč | zůstává jako **volba**, ne jako záchranná síť |
| Výchozí pro čerstvou instalaci | kombinace `cmd+ctrl+d` |
| Výchozí po upgradu | kombinace — chybějící blok `trigger` znamená původní chování |
| Volitelné modifikátory | pravý/levý ⌘, pravý/levý ⌥ |

### Proč je výchozí kombinace, a ne dvojí stisk

Nástroj, který po instalaci hned funguje, je lepší než nástroj, který nejdřív
chce oprávnění. Kolize je problém, na který se přijde až používáním — teprve
tehdy má uživatel důvod oprávnění dát. Vynutit ho předem znamená ptát se dřív,
než člověk chápe proč.

### Proč není automatický pád zpět na kombinaci

Uživatel si dvojí stisk zvolil právě proto, aby žádnou kombinaci nekradl. Tiché
zapnutí kradoucí zkratky při odebrání oprávnění by ho vrátilo přesně do
problému, před kterým utíká, navíc bez varování. Chybí-li oprávnění, spouštěč
nefunguje a aplikace to hlásí.

## 4. Volba mechanismu odchytu

Zvažovaly se tři cesty:

**A) `NSEvent.addGlobalMonitorForEvents` na `.flagsChanged`.** Zvoleno.

**B) `CGEventTap`.** Zamítnuto. Jeho hlavní předností je schopnost událost
spolknout — a to je přesně to, co tady **nesmíme** udělat, protože jednotlivý
stisk musí projít dál. Platili bychom tedy za schopnost, kterou nelze použít.
Systém navíc tap při pomalé obsluze sám vypne (`kCGEventTapDisabledByTimeout`)
a aplikace ho musí umět zapnout zpět; jinak spouštěč po čase tiše přestane
fungovat.

**C) `IOHIDManager`.** Zamítnuto. Dávalo by smysl, kdybychom potřebovali
rozlišovat fyzické klávesnice; nepotřebujeme.

Oprávnění stojí u A i B stejně, protože klávesové události jsou za Accessibility
tak jako tak.

**Známé omezení A:** globální monitor nedostává události, když je vepředu vlastní
aplikace. Přidá se proto i lokální monitor. Praktický dopad je malý — Czechator
je vepředu jen při otevřeném okně nastavení.

## 5. Sémantika dvojího stisku

### Co je stisk

Dvojice sepnutí a rozepnutí sledovaného modifikátoru, u které platí **všechny**
podmínky:

1. jde o sledovaný modifikátor, rozlišený podle `keyCode` (pravý ⌘ = 54,
   levý ⌘ = 55, pravý ⌥ = 61, levý ⌥ = 58)
2. mezi sepnutím a rozepnutím nepřišla žádná klávesa — jinak šlo o `⌘C`
3. mezi sepnutím a rozepnutím nepřibyl další modifikátor — jinak šlo o `⌘⇧`
4. drželo se nejvýše `maxHoldMs` — jinak jde o držení, ne stisk

### Co je dvojí stisk

Dva stisky, kde druhé sepnutí přijde do `intervalMs` od prvního rozepnutí.

Po spuštění se stav resetuje, takže trojí stisk spustí nástroj právě jednou.

Jakákoli neočekávaná posloupnost — sepnutí bez předchozího rozepnutí, rozepnutí
bez sepnutí — stav rovněž resetuje. Automat se nikdy nesnaží dopočítat, co
se stalo mezi tím; raději zahodí rozdělanou dvojici, než aby spustil nástroj
z nejasného vstupu.

### Výchozí hodnoty a jejich zdůvodnění

| hodnota | výchozí | proč |
|---|---|---|
| `intervalMs` | 300 | dvojklik myši má v macOS okno kolem 500 ms, ale modifikátor se mačká při běžné práci pořád; širší okno by chytalo náhody |
| `maxHoldMs` | 500 | nad touto hranicí uživatel drží ⌘ a přepíná okna |

Obě jsou vědomě přísné. **Falešné spuštění je horší než netrefený stisk** —
nástroj by sáhl na schránku, když to uživatel nechtěl. Ukáže-li se to jako moc
přísné, mění se konfigurace, ne kód.

## 6. Konfigurace

Nový blok nejvyšší úrovně:

```yaml
trigger:
  kind: combination        # combination | doubleTap
  modifier: rightCommand   # rightCommand | leftCommand | rightOption | leftOption
  intervalMs: 300
  maxHoldMs: 500
```

`hotkeys[0].shortcut` zůstává beze změny a použije se, když `kind: combination`.

Chybějící blok znamená `combination`, takže **upgrade nikomu nezmění chování**.
To je přímý důsledek zkušenosti zaznamenané v [design.md](design.md): konfigurace
se při prvním spuštění materializuje na disk a od té chvíle přebíjí vestavěné
hodnoty, takže výchozí hodnota musí být ta, která nic nerozbije.

`intervalMs` i `maxHoldMs` se při načtení ořežou na rozumný rozsah (10–2000 ms),
stejně jako `Limits`.

## 7. Oprávnění

`AXIsProcessTrusted()` zjistí stav bez dialogu. `AXIsProcessTrustedWithOptions`
s `kAXTrustedCheckOptionPrompt` ho vyvolá — a to **jen** ve chvíli, kdy uživatel
v nastavení zvolí dvojí stisk. Nikdy při startu.

### Past: ad-hoc podpis

Oprávnění Accessibility je vázané na podpis aplikace. Czechator se podepisuje
ad-hoc (`codesign --sign -`), tedy **novým podpisem při každém buildu**. Po
každém `make install` považuje macOS aplikaci za jinou a oprávnění je nutné dát
znovu; stará položka v seznamu může zůstat viset a je potřeba ji smazat.

Řešení jsou dvě: podepisovat stabilním Developer ID (99 USD ročně), nebo to vzít
na vědomí. Volíme druhé a zapisujeme do README jako známé omezení.

## 8. Architektura

### Protokol spouštěče

```swift
@MainActor
protocol Trigger: AnyObject {
    func start(_ action: @escaping @MainActor () -> Void) throws
    func stop()
}
```

Dvě implementace — `HotKeyManager` (Carbon) a `DoubleTapMonitor` (NSEvent). Obě
ústí do téhož `AppModel.run()`. Nic za spouštěčem o rozdílu neví; to je smysl
protokolu, jinak by změna prosákla celou aplikací.

### Rozdělení odpovědností

Sémantika je stavový automat nad posloupností událostí a nepotřebuje AppKit ani
oprávnění. Patří proto do jádra:

```swift
public struct DoubleTapDetector: Sendable {
    public enum Event: Sendable {
        case modifierPressed(ModifierKey)
        case modifierReleased(ModifierKey)
        case otherKeyDown
        case otherModifierChanged
    }

    public init(modifier: ModifierKey, intervalMs: Int, maxHoldMs: Int)
    public mutating func accept(_ event: Event, at time: TimeInterval) -> Bool
}
```

**Čas se předává zvenčí, nečte se z hodin.** Jinak by testy musely spát a byly by
nespolehlivé — stejný důvod, proč `Pipeline` dostává poskytovatele zvenčí místo
aby si stavěla HTTP klienta.

`DoubleTapMonitor` je pak tenká slupka: převádí `NSEvent` na `Event`, dodává
`event.timestamp`, volá akci.

## 9. Dopad na stávající kód

### Přibude

| soubor | odpovědnost |
|---|---|
| `CzechatorCore/IO/DoubleTapDetector.swift` | stavový automat |
| `CzechatorCore/IO/ModifierKey.swift` | výčet modifikátorů a kódy kláves |
| `CzechatorCore/Config/TriggerConfig.swift` | blok `trigger` |
| `CzechatorApp/Trigger.swift` | protokol |
| `CzechatorApp/DoubleTapMonitor.swift` | slupka nad `NSEvent`, včetně ladicího režimu z §11 |
| `CzechatorApp/AccessibilityPermission.swift` | zjištění stavu a vyžádání |

### Změní se

- **`HotKeyManager`** dostane konformitu k `Trigger`; `register(_:handler:)` se
  přejmenuje na `start(_:)` a spec si vezme z konfigurace sám.
- **`AppModel`** přestane držet `HotKeyManager` napevno; `reload()` postaví
  spouštěč podle `config.trigger.kind`. Přibude kontrola oprávnění a stav pro
  jeho absenci.
- **`SettingsView`** dostane přepínač spouštěče; při volbě dvojího stisku
  vyžádá oprávnění. Pole se zkratkou se zašedne, když se nepoužije.
- **`ErrorMessages`** dostane hlášku o chybějícím oprávnění.
- **`Config`** dostane `trigger` s výchozím `combination`.

### Nedotkne se

Nic v `Pipeline`, handlerech, verifikaci ani poskytovatelích.

### Zaznamenané riziko

`AppModel` už dnes drží konfiguraci, spouštěč, notifikace, schránku, historii,
pipeline i nastavení. Touto změnou poroste dál. **Rozdělení není součástí této
práce** — bylo by to nesouvisející refaktorování uprostřed jiné změny. Ale je to
soubor, který si při příští úpravě zaslouží rozdělit.

## 10. Chování při chybách

| situace | reakce |
|---|---|
| dvojí stisk zvolen, oprávnění chybí | chybový stav ikony, v menu tlačítko „Povolit v Nastavení systému" |
| oprávnění odebráno za běhu | zjistí se při otevření menu a při aktivaci aplikace, stejná hláška |
| registrace kombinace selže | stávající chování, hláška ve `startupProblem` |
| secure input (pole s heslem) | události nechodí, spouštěč mlčí — systémové omezení |

## 11. Testovací strategie

### Testuje se

`DoubleTapDetector` headless, bez oprávnění a bez klávesnice:

- poctivý dvojí stisk projde
- `⌘C` neprojde — mezi sepnutím a rozepnutím přišla klávesa
- `⌘⇧` neprojde — přibyl modifikátor
- držení přes `maxHoldMs` neprojde
- druhé sepnutí po `intervalMs` neprojde
- trojí stisk spustí právě jednou
- levý ⌘ nespustí spouštěč nastavený na pravý
- hranice přesně na `intervalMs` a `maxHoldMs`

`TriggerConfig` na dekódování, výchozí hodnoty a ořez rozsahů.

### Netestuje se automaticky

1. že `NSEvent` monitor události skutečně doručuje
2. že `keyCode 54` je opravdu pravý ⌘ na dané klávesnici
3. že se stisk nekříží s přepínáním layoutu nebo Spotlightem

Bod 2 je jediné místo, kde se lze mýlit tiše. Součástí implementace proto bude
**ladicí režim monitoru**, který vypisuje přijaté události s kódy kláves. Ověří
se jím rozložení klávesnice dřív, než se budou ladit časy.

## 12. Mimo rozsah

- Detekce, které zkratky už drží jiné aplikace — systém k tomu nedává API
- Blokace spouštěče podle aktivní aplikace — dvojí stisk ji činí zbytečnou
- Dlouhý stisk modifikátoru jako alternativní gesto
- Selection → PasteInPlace, které Accessibility nově odemyká — samostatná práce
