# Instrukcja Deployu — CC: Crane

> Szczegółowa dokumentacja po angielsku: [README.md](README.md)

## Wymagania wstępne

- **ComputerCraft: Create** (lub CC:Tweaked z dodatkiem Create)
- Dwa komputery w grze:
  - **Komputer żurawia** — steruje mechaniką żurawia (precyzyjny mechanizm, przekaźnik redstone)
  - **Komputer panelu** — zdalne sterowanie przez ECNet2 (opcjonalnie)
- Oba komputery muszą mieć **modem bezprzewodowy** na stronie `top` (tryb zdalny)

---

## 1. Pobranie plików

```
gitclone cccrane jigga2
```

Wszystkie pliki trafiają do katalogu `/cccrane/`.

> Jeśli `gitclone` nie jest dostępne, pobierz ręcznie przez `wget`:
> ```
> wget https://raw.githubusercontent.com/jigga2/cccrane/main/crane.lua
> mv crane.lua /cccrane/
> ```

---

## 2. Wdrożenie na komputer żurawia

### 2.1. Wymagane pliki

```
/cccrane/crane.lua
/cccrane/src/lib/crane.lua
/cccrane/crane-client.lua         # (tylko tryb zdalny)
/cccrane/src/config.lua
/cccrane/src/remote_config.lua    # (tylko tryb zdalny)
/cccrane/ecnet2/
/cccrane/ccryptolib/
```

### 2.2. Konfiguracja peryferiów

Edytuj `/cccrane/src/config.lua`:

| Parametr | Domyślnie | Opis |
|---|---|---|
| `MAX_X` | 97 | Maksymalny zasięg X |
| `MAX_Y` | 56 | Maksymalny zasięg Y |
| `LIFT_HEIGHT` | 23 | Skok wciągarki |
| `TRANSPORT_LOWER` | 10 | O ile niżej opuścić ładunek podczas transportu |
| `GEAR_PERIPHERAL` | `"right"` | Strona precyzyjnego mechanizmu |
| `RELAY_PERIPHERAL` | `"left"` | Strona przekaźnika redstone |
| `AXIS_SIDE` | `"front"` | Wyjście wyboru osi |
| `LIFT_SIDE` | `"top"` | Wyjście wciągarki |
| `STICKER_SIDE` | `"bottom"` | Wyjście stickera |
| `INVERSE_X` | `false` | Odwrócenie kierunku X |
| `INVERSE_Y` | `false` | Odwrócenie kierunku Y |

### 2.3. Uruchomienie — tryb lokalny CLI

```
cccrane/crane <srcX> <srcY> <dstX> <dstY>
```

Przykład:
```
cccrane/crane 10 5 42 30
```

### 2.4. Uruchomienie — tryb zdalny

```
cccrane/crane-client
```

Klient automatycznie połączy się z panelem i będzie czekał na komendy.

---

## 3. Wdrożenie na komputer panelu

### 3.1. Wymagane pliki

```
/cccrane/crane-panel.lua
/cccrane/src/config.lua
/cccrane/src/lib/panel_ui.lua
/cccrane/lib/pixelui.lua
/cccrane/lib/shrekbox.lua
/cccrane/ecnet2/
/cccrane/ccryptolib/
```

### 3.2. Uruchomienie

```
cccrane/crane-panel
```

Panel wyświetli swój adres ECNet2. Skopiuj go, a następnie na komputerze żurawia edytuj `/cccrane/src/remote_config.lua`:

```lua
return {
    PANEL_ADDRESS = "<adres_panelu>",
    HEARTBEAT_INTERVAL = 3,
    CONNECTION_TIMEOUT = 15,
    RECONNECT_BACKOFF_INITIAL = 1,
    RECONNECT_BACKOFF_MULT = 1.5,
    RECONNECT_BACKOFF_MAX = 30,
    MAX_LOG_LINES = 50,
}
```

### 3.3. Panel na monitor (load/unload)

```
cccrane/crane-load-unload
```

---

## 4. Schemat połączeń

```
┌──────────────────────────┐     ECNet2     ┌──────────────────────────┐
│  KOMPUTER ŻURAWIA        │ ◄══════════►   │  KOMPUTER PANELU        │
│                          │                │                          │
│  crane.lua               │                │  crane-panel.lua         │
│  src/lib/crane.lua       │                │  src/config.lua          │
│  crane-client.lua        │                │  src/lib/panel_ui.lua    │
│  src/config.lua          │                │  lib/pixelui.lua         │
│  src/remote_config.lua   │                │  lib/shrekbox.lua        │
│  ecnet2/                 │                │  ecnet2/                 │
│  ccryptolib/             │                │  ccryptolib/             │
└────────┬─────────────────┘                └──────────────────────────┘
         │
         ├── precyzyjny mechanizm (gear)
         └── przekaźnik redstone
               ├── AXIS_SIDE → wybór osi (LOW=X, HIGH=Y)
               ├── LIFT_SIDE → wciągarka
               └── STICKER_SIDE → sticker
```

---

## 5. Kolejność uruchamiania

1. Zbuduj mechanikę żurawia (gantry, wciągarka, sticker)
2. Podłącz komputer żurawia do mechanizmu i przekaźnika
3. Zamontuj modem bezprzewodowy (tryb zdalny)
4. Pobierz pliki: `gitclone cccrane jigga2`
5. Skonfiguruj `src/config.lua` na żurawiu
6. (Tryb zdalny) Skonfiguruj `src/remote_config.lua` z adresem panelu
7. (Tryb zdalny) Uruchom panel: `cccrane/crane-panel`
8. (Tryb zdalny) Uruchom klienta: `cccrane/crane-client`
9. Test: `cccrane/crane 0 0 1 1`

---

## 6. Plik stanu (`.crane-state`)

Żuraw zapisuje pozycję i stan stickera do `/.crane-state`. Przy starcie:
- Brak pliku → homing
- `craneRunning=false` → pomija homing, wznawia pozycję
- `craneRunning=true` → przerwana operacja → homing

---

## 7. Troubleshooting

| Problem | Rozwiązanie |
|---|---|
| Homing przy każdym starcie | Sprawdź `/.crane-state` |
| Żuraw nie rusza | Sprawdź peryferia w `src/config.lua` |
| Błąd ECNet2 | Modem na `top` + poprawny adres panelu |
| Panel nie widzi żurawia | Zasięg modemu |
| Sticker nie chwyta | Sprawdź `STICKER_SIDE` i delay |
| Zły kierunek | `INVERSE_X` / `INVERSE_Y` w `src/config.lua` |

---

## 8. Użycie panelu load/unload na monitorze

Panel `crane-load-unload` działa na małym monitorze (2×1 blok, ~15×30 znaków przy skali 0.5).

Wymaga plików punktów w `data/`:
- `data/pickup_points.lua` — punkty załadunku
- `data/drop_points.lua` — punkty rozładunku

Format pliku punktów:
```lua
return {
    { name = "Nazwa punktu", x = 10, y = 20 },
}
```
