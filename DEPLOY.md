# Instrukcja Deployu — CC: Crane

## Wymagania wstępne

- **ComputerCraft: Create** (lub CC:Tweaked z dodatkiem Create)
- Dwa komputery w grze:
  - **Kompas żurawia** — steruje mechaniką żurawia (precyzyjny mechanizm, przekaźnik redstone)
  - **Komputer panelu** — zdalne sterowanie przez ECNet2 (opcjonalnie, tylko dla trybu zdalnego)
- Oba komputery muszą mieć **modem bezprzewodowy** na stronie `top` (tryb zdalny)
- Łącze internetowe w grze (dla `wget` / `gitclone`)

---

## 1. Pobranie plików

Użyj skryptu `gitclone`, aby pobrać repozytorium:

```
gitclone cccrane jigga2
```

Po wykonaniu tej komendy wszystkie pliki projektu trafiają do katalogu `/cccrane/`.

Struktura katalogu po pobraniu:

```
/cccrane/
├── crane.lua                 # Program CLI żurawia
├── crane-lib.lua             # Biblioteka sterowania żurawiem
├── crane-client.lua          # Klient zdalnego sterowania (działa na komputerze żurawia)
├── crane-panel.lua           # Panel zdalnego sterowania (działa na komputerze panelu)
├── config.lua                # Konfiguracja (wymiary, timing, peryferia)
├── crane-remote-config.lua   # Konfiguracja zdalna (adres panelu, heartbeat)
├── ecnet2/                   # Biblioteka sieciowa ECNet2
└── ccryptolib/               # Biblioteka kryptograficzna (ChaCha20, Ed25519, itp.)
```

> **Uwaga:** Jeżeli `gitclone` nie jest dostępne, możesz pobrać każdy plik ręcznie przez `wget` z GitHub:
> ```
> wget https://raw.githubusercontent.com/jigga2/cccrane/main/crane.lua
> ```
> a następnie przenieść do `/cccrane/`:
> ```
> mv crane.lua /cccrane/
> ```

---

## 2. Wdrożenie na komputer żurawia

### 2.1. Wymagane pliki

Na komputerze żurawia muszą znaleźć się:

```
/cccrane/crane.lua
/cccrane/crane-lib.lua
/cccrane/crane-client.lua       # (tylko tryb zdalny)
/cccrane/config.lua
/cccrane/crane-remote-config.lua # (tylko tryb zdalny)
/cccrane/ecnet2/
/cccrane/ccryptolib/
```

### 2.2. Konfiguracja peryferiów

Dostosuj `/cccrane/config.lua` do swojego setupu mechanicznego:

| Parametr | Domyślnie | Opis |
|---|---|---|
| `MAX_X` | 97 | Maksymalny zasięg w osi X |
| `MAX_Y` | 56 | Maksymalny zasięg w osi Y |
| `LIFT_HEIGHT` | 23 | Pełny skok wciągarki (w blokach) |
| `TRANSPORT_LOWER` | 10 | O ile niżej opuścić ładunek podczas transportu |
| `HOME_OFFSET_X` | 0 | Offset pozycji domowej X |
| `HOME_OFFSET_Y` | 0 | Offset pozycji domowej Y |
| `GEAR_PERIPHERAL` | `"right"` | Strona, po której podpięty jest precyzyjny mechanizm |
| `RELAY_PERIPHERAL` | `"left"` | Strona, po której podpięty jest przekaźnik redstone |
| `AXIS_SIDE` | `"front"` | Wyjście przekaźnika do wyboru osi |
| `LIFT_SIDE` | `"top"` | Wyjście przekaźnika do wciągarki |
| `STICKER_SIDE` | `"bottom"` | Wyjście przekaźnika do strickera |
| `INVERSE_X` | `false` | Odwrócenie kierunku osi X |
| `INVERSE_Y` | `false` | Odwrócenie kierunku osi Y |

### 2.3. Uruchomienie (tryb lokalny CLI)

```
cccrane/crane <srcX> <srcY> <dstX> <dstY>
```

Przykład — podnieś blok z pozycji (10, 5) i przenieś na (42, 30):

```
cccrane/crane 10 5 42 30
```

### 2.4. Uruchomienie (tryb zdalny)

Jeżeli używasz panelu zdalnego, uruchom klienta:

```
cccrane/crane-client
```

Klient automatycznie połączy się z panelem i będzie czekał na komendy.

---

## 3. Wdrożenie na komputer panelu (tryb zdalny)

### 3.1. Wymagane pliki

Na komputerze panelu muszą znaleźć się:

```
/cccrane/crane-panel.lua
/cccrane/ecnet2/
/cccrane/ccryptolib/
```

### 3.2. Uruchomienie

```
cccrane/crane-panel
```

Panel wyświetli swój adres ECNet2:

```
=== Crane Control Panel ===
ECNet2 address: <adres_klucza_publicznego>
Copy this address to crane-remote-config.lua on the crane.
Waiting for connection...
```

### 3.3. Konfiguracja połączenia

1. Skopiuj adres ECNet2 wyświetlony przez panel.
2. Na komputerze żurawia edytuj `/cccrane/crane-remote-config.lua`:

```lua
return {
    PANEL_ADDRESS = "<wklej_adres_panelu>",
    HEARTBEAT_INTERVAL = 3,
    CONNECTION_TIMEOUT = 15,
    RECONNECT_BACKOFF_INITIAL = 1,
    RECONNECT_BACKOFF_MULT = 1.5,
    RECONNECT_BACKOFF_MAX = 30,
    MAX_LOG_LINES = 50,
}
```

3. Uruchom klienta na żurawiu: `cccrane/crane-client`
4. Panel automatycznie zaakceptuje połączenie — zobaczysz zielony status `CONNECTED`.

---

## 4. Schemat połączenia

```
┌──────────────────────┐         ECNet2 (szyfrowane)         ┌──────────────────────┐
│  KOMPUTER ŻURAWIA    │ ◄═══════════════════════════════►   │  KOMPUTER PANELU     │
│                      │    modem bezprzewodowy (top)        │                      │
│  crane.lua           │                                     │  crane-panel.lua     │
│  crane-lib.lua       │                                     │  ecnet2/             │
│  crane-client.lua    │                                     │  ccryptolib/         │
│  config.lua          │                                     └──────────────────────┘
│  crane-remote-config │
│  ecnet2/             │         ┌──────────────────┐
│  ccryptolib/         │         │  SPRZĘT           │
└───────┬──────────────┘         │  ┌─ precyzyjny    │
        │                        │  │   mechanizm    │
        ├── precyzyjny mechanizm │  ├─ przekaźnik    │
        └── przekaźnik redstone  │  │   redstone     │
                                 │  └─ silniki X/Y   │
                                 │  ─ wciągarka      │
                                 │  ─ sticker        │
                                 └──────────────────┘
```

### 4.1. Okablowanie przekaźnika redstone

| Wyjście przekaźnika | Podłączone do | Opis |
|---|---|---|
| `AXIS_SIDE` (top) | Przekaźnik wyboru osi | LOW = oś X, HIGH = oś Y |
| `LIFT_SIDE` (front) | Silnik wciągarki | HIGH = włącz |
| `STICKER_SIDE` (bottom) | Sticker (toggle latch) | Pulse = przełącz |

---

## 5. Kolejność uruchamiania

1. **Zbuduj mechanikę żurawia** w grze (gantry, wciągarka, sticker)
2. **Podłącz komputer żurawia** do precyzyjnego mechanizmu i przekaźnika
3. **Zamontuj modem bezprzewodowy** na obu komputerach (tryb zdalny)
4. **Pobierz pliki** przez `gitclone cccrane jigga2`
5. **Skonfiguruj** `config.lua` na komputerze żurawia
6. (Tryb zdalny) **Skonfiguruj** `crane-remote-config.lua` z adresem panelu
7. (Tryb zdalny) **Uruchom panel** → `cccrane/crane-panel`
8. (Tryb zdalny) **Uruchom klienta** na żurawiu → `cccrane/crane-client`
9. **Przetestuj** prostym ruchem → `cccrane/crane 0 0 1 1`

---

## 6. Plik stanu (.crane-state)

Żuraw automatycznie zapisuje swoją pozycję i stan stickera do pliku `/.crane-state`. Dzięki temu:

- Po czystym wyłączeniu (operacja zakończona) → homing jest pomijany przy ponownym uruchomieniu
- Po przerwaniu operacji (chunk unload / Ctrl+T) → żuraw automatycznie wykonuje homing

---

## 7. Troubleshooting

| Problem | Rozwiązanie |
|---|---|
| `No saved state found, homing...` przy każdym starcie | Sprawdź czy plik `/.crane-state` jest zapisywany (uprawnienia) |
| Żuraw nie rusza | Sprawdź strony peryferiów w `config.lua` |
| Błąd połączenia ECNet2 | Upewnij się, że oba komputery mają modem na `top` i adres panelu jest poprawny |
| Panel nie widzi żurawia | Sprawdź zasięg modemu (wzmocnij modemem Ender / zakresem) |
| Sticker nie chwyta | Sprawdź wyjście `STICKER_SIDE` w konfiguracji i delay toggle |
| Żuraw jedzie w złym kierunku | Ustaw `INVERSE_X` lub `INVERSE_Y` na `true` w `config.lua` |
| `ecnet2_message` not handled | Upewnij się, że `ecnet2/` i `ccryptolib/` są w pełni pobrane |
