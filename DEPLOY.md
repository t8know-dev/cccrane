# Deploy i Setup Systemu Sterowania Żurawiem

## Wymagania

- **ComputerCraft: Tweaked** (CC:Tweaked) — dwa komputery
- **Create mod** (dla mechaniki żurawia)
- **Wireless modem** — podłączony do strony **top** na obu komputerach
- **Dostęp do internetu** na komputerach CC (opcjonalnie, dla bezpieczniejszej inicjalizacji RNG)

## Pobieranie plików na komputer CC

Wszystkie pliki projektu znajdują się w katalogu `/cccrane/` na każdym komputerze.

### Komputer PANEL

```
# Utwórz katalog projektu
mkdir /cccrane

# Pobierz główne pliki
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/crane-panel.lua /cccrane/crane-panel.lua

# Pobierz biblioteki
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/ccryptolib/ccryptolib/random.lua /cccrane/ccryptolib/ccryptolib/random.lua
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/ccryptolib/ccryptolib/blake3.lua /cccrane/ccryptolib/ccryptolib/blake3.lua
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/ccryptolib/ccryptolib/chacha20.lua /cccrane/ccryptolib/ccryptolib/chacha20.lua
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/ccryptolib/ccryptolib/poly1305.lua /cccrane/ccryptolib/ccryptolib/poly1305.lua
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/ccryptolib/ccryptolib/util.lua /cccrane/ccryptolib/ccryptolib/util.lua
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/ccryptolib/ccryptolib/internal/util.lua /cccrane/ccryptolib/ccryptolib/internal/util.lua
```

### Komputer ŻURAW

```
# Utwórz katalog projektu
mkdir /cccrane

# Pobierz główne pliki
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/crane-client.lua /cccrane/crane-client.lua
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/crane-lib.lua /cccrane/crane-lib.lua
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/config.lua /cccrane/config.lua
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/crane-remote-config.lua /cccrane/crane-remote-config.lua

# Pobierz biblioteki
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/ccryptolib/ccryptolib/random.lua /cccrane/ccryptolib/ccryptolib/random.lua
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/ccryptolib/ccryptolib/blake3.lua /cccrane/ccryptolib/ccryptolib/blake3.lua
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/ccryptolib/ccryptolib/chacha20.lua /cccrane/ccryptolib/ccryptolib/chacha20.lua
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/ccryptolib/ccryptolib/poly1305.lua /cccrane/ccryptolib/ccryptolib/poly1305.lua
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/ccryptolib/ccryptolib/util.lua /cccrane/ccryptolib/ccryptolib/util.lua
wget https://raw.githubusercontent.com/TWOJ_REPO/cccrane/main/ccryptolib/ccryptolib/internal/util.lua /cccrane/ccryptolib/ccryptolib/internal/util.lua
```

## Instalacja ECNet2

ECNet2 jest zewnętrzną biblioteką (nie zawartą w repozytorium). Należy ją pobrać na **oba komputery**.

### Opcja A: Pobranie z GitHub

```lua
wget https://raw.githubusercontent.com/Kuerschner/ecnet2/main/ecnet2.lua /cccrane/ecnet2.lua
```

### Opcja B: Ręczne skopiowanie

Jeśli komputer nie ma dostępu do internetu, skopiuj plik `ecnet2.lua` przez dyskietkę lub pastebin:
```
pastebin get <PASTE_ID> /cccrane/ecnet2.lua
```

**Ważne**: plik musi znaleźć się w `/cccrane/ecnet2.lua` — skrypt ładuje go przez `require "cccrane.ecnet2"`.

## Weryfikacja struktury plików

Po instalacji sprawdź, czy struktura na każdym komputerze wygląda tak:

### Komputer PANEL

```
/cccrane/
├── crane-panel.lua
├── ecnet2.lua
└── ccryptolib/
    └── ccryptolib/
        ├── random.lua
        ├── blake3.lua
        ├── chacha20.lua
        ├── poly1305.lua
        ├── util.lua
        └── internal/
            └── util.lua
```

### Komputer ŻURAW

```
/cccrane/
├── crane-client.lua
├── crane-lib.lua
├── crane-remote-config.lua
├── config.lua
├── ecnet2.lua
└── ccryptolib/
    └── ccryptolib/
        ├── random.lua
        ├── blake3.lua
        ├── chacha20.lua
        ├── poly1305.lua
        ├── util.lua
        └── internal/
            └── util.lua
```

## Uruchomienie krok po kroku

### Krok 1: Generowanie tożsamości ECNet2 (oba komputery)

Po raz pierwszy ECNet2 utworzy plik tożsamości automatycznie przy pierwszym uruchomieniu. Możesz też wygenerować go ręcznie:

```
lua -e "local e=require'cccrane.ecnet2' e.open('top') local i=e.Identity('/.ecnet2') print('ID:', i.address) e.close()"
```

To utworzy plik `/.ecnet2` — klucz prywatny i publiczny twojego komputera.

### Krok 2: Uruchom panel

Na komputerze panelu:

```
crane-panel
```

Panel wyświetli:
```
=== Crane Control Panel ===
ECNet2 address: AZ2cVrQTGDLLRodwHFS3RoNYQOW0O_iCctVWxc9IrXQ=
Copy this address to crane-remote-config.lua on the crane.
Waiting for connection...
```

**Skopiuj adres ECNet2** (długi base64 string) — będzie potrzebny w następnym kroku.

> **Uwaga**: Jeśli pojawi się błąd "attempt to use an uninitialized random generator", biblioteka `ccryptolib` nie została zainstalowana poprawnie. Sprawdź, czy plik `/cccrane/ccryptolib/ccryptolib/random.lua` istnieje.

### Krok 3: Skonfiguruj adres panelu na żurawiu

Na komputerze żurawia edytuj plik `/cccrane/crane-remote-config.lua`:

```
edit /cccrane/crane-remote-config.lua
```

Zmień linię:
```lua
    PANEL_ADDRESS = "PASTE_PANEL_ADDRESS_HERE",
```
na:
```lua
    PANEL_ADDRESS = "AZ2cVrQTGDLLRodwHFS3RoNYQOW0O_iCctVWxc9IrXQ=",
```

Używając adresu, który wyświetlił się na panelu w Kroku 2.

### Krok 4: Uruchom klienta żurawia

Na komputerze żurawia:

```
crane-client
```

Powinieneś zobaczyć:
```
Crane client starting...
State loaded, crane idle at (0, 0)
Connected: crane_panel_v1.0
Crane client ready, listening for commands.
```

Na panelu pojawi się:
```
[hh:mm:ss] Crane connected!
[hh:mm:ss] Sent config query
[hh:mm:ss] Config: 97x56 grid
```

### Krok 5: Sterowanie żurawiem

Panel jest gotowy do sterowania:

1. Wpisz współrzędne **SOURCE (Pickup)** — skąd żuraw ma podnieść ładunek
2. Wpisz współrzędne **DEST (Drop)** — gdzie żuraw ma odłożyć ładunek
3. Kliknij przycisk ` GOTO ` — żuraw przejedzie na pozycję źródłową
4. Kliknij ` PICKUP ` — żuraw podniesie ładunek
5. Kliknij ` GOTO ` ponownie (lub od razu ` DROP ` jeśli już na pozycji docelowej)
6. Kliknij ` DROP ` — żuraw odłoży ładunek

Lub dla pełnego cyklu automatycznego:
- Ustaw SOURCE i DEST
- Kliknij ` GOTO ` → ` PICKUP ` → (automatycznie) → ` DROP `

### Przyciski sterujące

| Przycisk | Działanie |
|---|---|
| ` GOTO ` | Przejedź na pozycję SOURCE (x, y) |
| ` PICKUP ` | Opuść → chwyć stickerem → podnieś do pozycji transportowej |
| ` DROP ` | Opuść → zwolnij sticker → podnieś |
| ` HOME ` | Wykonaj homing (jedź do pozycji (0,0)) |
| ` EMRG ` | **EMERGENCY STOP** — natychmiastowe zatrzymanie ruchu |

### Pola edycyjne

- Kliknij na pole X/Y aby je aktywować (podświetli się na niebiesko)
- Wpisz cyfry z klawiatury
- **Enter** lub kliknij poza polem — zatwierdź
- **Tab** — przejście do następnego pola
- **Backspace** — usuń ostatnią cyfrę

## Inicjalizacja generatora liczb losowych

Skrypty domyślnie używają `random.initWithTiming()`, która zbiera entropię z timingów instrukcji VM przez ~512ms. Jest to wygodne, ale może być przewidywalne dla innych graczy na tym samym serwerze.

### Bezpieczniejsza alternatywa (przez Krist WebSocket)

Jeśli komputer ma dostęp do internetu, możesz zastąpić:

```lua
random.initWithTiming()
```

przez:

```lua
local postHandle = assert(http.post("https://krist.dev/ws/start", ""))
local data = textutils.unserializeJSON(postHandle.readAll())
postHandle.close()
random.init(data.url)
http.websocket(data.url).close()
```

## Rozwiązywanie problemów

### "attempt to use an uninitialized random generator"

**Przyczyna**: Biblioteka `ccryptolib` nie jest zainstalowana lub jest w złej ścieżce.

**Rozwiązanie**: Sprawdź, czy plik istnieje:
```
ls /cccrane/ccryptolib/ccryptolib/random.lua
```

Wymagane pliki ccryptolib:
| Plik | Ścieżka |
|---|---|
| `random.lua` | `/cccrane/ccryptolib/ccryptolib/random.lua` |
| `blake3.lua` | `/cccrane/ccryptolib/ccryptolib/blake3.lua` |
| `chacha20.lua` | `/cccrane/ccryptolib/ccryptolib/chacha20.lua` |
| `poly1305.lua` | `/cccrane/ccryptolib/ccryptolib/poly1305.lua` |
| `util.lua` | `/cccrane/ccryptolib/ccryptolib/util.lua` |
| `internal/util.lua` | `/cccrane/ccryptolib/ccryptolib/internal/util.lua` |

### "module 'cccrane.ecnet2' not found"

**Przyczyna**: Plik `ecnet2.lua` nie znajduje się w `/cccrane/`.

**Rozwiązanie**: Pobierz ECNet2:
```
wget https://raw.githubusercontent.com/Kuerschner/ecnet2/main/ecnet2.lua /cccrane/ecnet2.lua
```

### Panel pokazuje "DISCONNECTED"

**Przyczyna**: Żuraw poza zasięgiem wireless (modem ma ograniczony zasięg ~64-128 bloków w zależności od konfiguracji serwera).

**Rozwiązania**:
- Przybliż komputery do siebie
- Użyj wzmacniaczy sygnału (wireless bridge / chunkloader)
- Sprawdź, czy modem na stronie `top` jest poprawnie podłączony na obu komputerach

### "SEND FAILED — connection lost"

**Przyczyna**: Przerwane połączenie wireless — żuraw automatycznie próbuje się ponownie połączyć z backoffem.

**Rozwiązanie**: Poczekaj aż żuraw ponownie się połączy (panel pokaże "CONNECTED"). Jeśli nie łączy się po dłuższym czasie, sprawdź czy panel jest uruchomiony.

## Użycie standalone (bez panelu)

Oryginalny `crane.lua` działa niezależnie od panelu, jeśli chcesz sterować żurawiem ręcznie z terminala:

```
crane 10 5 42 30
```

To wykona pełny cykl: podnieś z (10,5) → odłóż na (42,30). Wymaga plików:
- `/cccrane/crane.lua`
- `/cccrane/crane-lib.lua`
- `/cccrane/config.lua`

## Struktura komunikacji ECNet2

```
Protokół:      "crane_control"
Serializacja:  textutils.serialize / textutils.unserialize
Modem:         strona "top" na obu komputerach
Tożsamość:     /.ecnet2 (plik klucza prywatnego)

Panel (Listener)                    Żuraw (Connector)
      |                                    |
      |   <-- ecnet2_request --             |
      |   -- accept("crane_panel_v1") -->   |
      |   <-- REGISTER {crane_id} --        |
      |   -- CONFIG_QUERY -->               |
      |   <-- CONFIG_RESPONSE --            |
      |   <-- STATUS {idle} --              |
      |   -- COMMAND {GOTO} -->            |
      |   <-- ACK {ok} --                   |
      |   <-- STATUS {busy} --              |
      |   <-- STATUS {idle} --              |
```
