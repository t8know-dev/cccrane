# Deploy i Setup Systemu Sterowania Żurawiem

## Wymagania

- **ComputerCraft: Tweaked** (CC:Tweaked) — dwa komputery
- **Create mod** (dla mechaniki żurawia)
- **Wireless modem** — podłączony do strony **top** na obu komputerach
- **Dostęp do internetu** na komputerach CC do `git clone`

## Instalacja przez git clone

Repozytorium projektu zawiera wszystko, czego potrzebujesz — framework ECNet2, bibliotekę ccryptolib oraz kod źródłowy. Wystarczy sklonować na każdym komputerze:

```
git clone https://github.com/TWOJ_USER/cccrane /cccrane
```

Po klonowaniu struktura na komputerze wygląda tak:

```
/cccrane/
├── init.lua                    ← bootstrap (package.path) — każdy skrypt
├── ecnet2.lua                  ← shim: require("ecnet2") → framework
├── crane-panel.lua             ← panel sterowania (komputer PANEL)
├── crane-client.lua            ← klient żurawia (komputer ŻURAW)
├── crane-lib.lua               ← biblioteka sterowania żurawiem
├── crane.lua                   ← CLI wrapper (tryb standalone)
├── crane-remote-config.lua     ← konfiguracja zdalna (komputer ŻURAW)
├── config.lua                  ← konfiguracja żurawia
├── ecnet/                      ← framework ECNet2
│   └── ecnet2/
│       ├── init.lua
│       ├── identity.lua
│       ├── connection.lua
│       ├── protocol.lua
│       ├── listener.lua
│       ├── handshake_state.lua
│       ├── symmetric_state.lua
│       ├── cipher_state.lua
│       ├── ecnetd.lua
│       ├── modems.lua
│       ├── class.lua
│       ├── uid.lua
│       ├── constants.lua
│       └── address_encoder.lua
├── ccryptolib/                 ← biblioteka kryptograficzna
│   └── ccryptolib/
│       ├── random.lua
│       ├── blake3.lua
│       ├── chacha20.lua
│       ├── poly1305.lua
│       ├── aead.lua
│       ├── x25519.lua
│       ├── x25519c.lua
│       └── internal/
│           ├── util.lua
│           ├── packing.lua
│           ├── sha512.lua
│           ├── fp.lua
│           ├── fq.lua
│           ├── mp.lua
│           ├── curve25519.lua
│           └── edwards25519.lua
├── DEPLOY.md
├── README.md
└── CLAUDE.md
```

**Uwaga**: Jeśli nie masz dostępu do `git clone` na komputerze CC, pobierz pojedyncze pliki za pomocą `wget` (patrz niżej).

### Alternatywnie — pobranie przez wget

Jeśli `git clone` nie jest dostępne, pobierz pliki ręcznie:

**Komputer PANEL:**
```
mkdir /cccrane

# Bootstrap
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/init.lua /cccrane/init.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet2.lua /cccrane/ecnet2.lua

wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/crane-panel.lua /cccrane/crane-panel.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/init.lua /cccrane/init.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet2.lua /cccrane/ecnet2.lua

# Framework ECNet2
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet/ecnet2/init.lua /cccrane/ecnet/ecnet2/init.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet/ecnet2/identity.lua /cccrane/ecnet/ecnet2/identity.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet/ecnet2/connection.lua /cccrane/ecnet/ecnet2/connection.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet/ecnet2/protocol.lua /cccrane/ecnet/ecnet2/protocol.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet/ecnet2/listener.lua /cccrane/ecnet/ecnet2/listener.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet/ecnet2/class.lua /cccrane/ecnet/ecnet2/class.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet/ecnet2/constants.lua /cccrane/ecnet/ecnet2/constants.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet/ecnet2/uid.lua /cccrane/ecnet/ecnet2/uid.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet/ecnet2/modems.lua /cccrane/ecnet/ecnet2/modems.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet/ecnet2/ecnetd.lua /cccrane/ecnet/ecnet2/ecnetd.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet/ecnet2/cipher_state.lua /cccrane/ecnet/ecnet2/cipher_state.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet/ecnet2/handshake_state.lua /cccrane/ecnet/ecnet2/handshake_state.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet/ecnet2/symmetric_state.lua /cccrane/ecnet/ecnet2/symmetric_state.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ecnet/ecnet2/address_encoder.lua /cccrane/ecnet/ecnet2/address_encoder.lua

# CCryptoLib
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/random.lua /cccrane/ccryptolib/ccryptolib/random.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/blake3.lua /cccrane/ccryptolib/ccryptolib/blake3.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/chacha20.lua /cccrane/ccryptolib/ccryptolib/chacha20.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/poly1305.lua /cccrane/ccryptolib/ccryptolib/poly1305.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/aead.lua /cccrane/ccryptolib/ccryptolib/aead.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/x25519.lua /cccrane/ccryptolib/ccryptolib/x25519.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/x25519c.lua /cccrane/ccryptolib/ccryptolib/x25519c.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/internal/util.lua /cccrane/ccryptolib/ccryptolib/internal/util.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/internal/packing.lua /cccrane/ccryptolib/ccryptolib/internal/packing.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/internal/sha512.lua /cccrane/ccryptolib/ccryptolib/internal/sha512.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/internal/fp.lua /cccrane/ccryptolib/ccryptolib/internal/fp.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/internal/fq.lua /cccrane/ccryptolib/ccryptolib/internal/fq.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/internal/mp.lua /cccrane/ccryptolib/ccryptolib/internal/mp.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/internal/curve25519.lua /cccrane/ccryptolib/ccryptolib/internal/curve25519.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/ccryptolib/ccryptolib/internal/edwards25519.lua /cccrane/ccryptolib/ccryptolib/internal/edwards25519.lua
```

**Komputer ŻURAW — to samo plus pliki projektu:**
```
# Najpierw frameworki (jak wyżej), a potem:
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/crane-client.lua /cccrane/crane-client.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/crane-lib.lua /cccrane/crane-lib.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/config.lua /cccrane/config.lua
wget https://raw.githubusercontent.com/TWOJ_USER/cccrane/main/crane-remote-config.lua /cccrane/crane-remote-config.lua
```

## Uruchomienie krok po kroku

### Krok 1: Wygenerowanie tożsamości ECNet2

Przy pierwszym uruchomieniu ECNet2 automatycznie utworzy plik tożsamości w `/.ecnet2`. Możesz też wywołać ręcznie:

```
lua -e "dofile('/cccrane/init.lua') local e=require'ecnet2' e.open('top') local i=e.Identity('/.ecnet2') print('ID:', i.address) e.close()"
```

### Krok 2: Uruchom panel

Na komputerze **PANEL**:

```
crane-panel
```

Panel wyświetli swój adres ECNet2. **Skopiuj go** — będzie potrzebny na żurawiu:
```
=== Crane Control Panel ===
ECNet2 address: AZ2cVrQTGDLLRodwHFS3RoNYQOW0O_iCctVWxc9IrXQ=
Copy this address to crane-remote-config.lua on the crane.
Waiting for connection...
```

### Krok 3: Skonfiguruj adres panelu na żurawiu

Na komputerze **ŻURAW** edytuj `crane-remote-config.lua`:

```
edit /cccrane/crane-remote-config.lua
```

Zmień:
```lua
PANEL_ADDRESS = "PASTE_PANEL_ADDRESS_HERE",
```
na:
```lua
PANEL_ADDRESS = "AZ2cVrQTGDLLRodwHFS3RoNYQOW0O_iCctVWxc9IrXQ=",
```

### Krok 4: Uruchom klienta żurawia

Na komputerze **ŻURAW**:

```
crane-client
```

Oczekiwany output:
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

### Krok 5: Sterowanie

Panel jest gotowy. Użyj przycisków i pól zgodnie z opisem w dalszej części dokumentu.

## Obsługa panelu

### Pola edycyjne

- **SOURCE (Pickup)**: X/Y — pozycja, skąd żuraw ma podnieść ładunek
- **DEST (Drop)**: X/Y — pozycja, gdzie żuraw ma odłożyć ładunek
- Kliknij w pole, aby je aktywować (niebieskie tło)
- Wpisz cyfry z klawiatury, **Enter** zatwierdza, **Tab** przechodzi dalej
- **Backspace** cofa ostatnią cyfrę

### Przyciski

| Przycisk | Działanie |
|---|---|
| ` GOTO ` | Przejedź na pozycję SOURCE |
| ` PICKUP ` | Opuść → chwyć → podnieś do transportu |
| ` DROP ` | Opuść → puść → podnieś |
| ` HOME ` | Homing do (0,0) |
| ` EMRG ` | Natychmiastowe zatrzymanie |

### Pełny cykl automatyzacji

1. Ustaw SOURCE (skąd) i DEST (dokąd)
2. Kliknij ` GOTO ` → żuraw jedzie na pozycję źródłową
3. Kliknij ` PICKUP ` → podnosi ładunek
4. Kliknij ` GOTO ` ponownie (żuraw przejedzie na DEST)
5. Kliknij ` DROP ` → odkłada ładunek

## Inicjalizacja generatora liczb losowych

Projekt domyślnie używa `random.initWithTiming()`, która zbiera entropię przez ~512ms.

### Bezpieczniejsza alternatywa (przez Krist WebSocket)

Jeśli komputer ma dostęp do internetu, zastąp w skryptach:

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

## Użycie standalone (bez panelu)

Jeśli chcesz sterować żurawiem z terminala bez panelu:

```
crane 10 5 42 30
```

Wymaga plików: `crane.lua`, `crane-lib.lua`, `config.lua`.

## Rozwiązywanie problemów

### "module 'ecnet2' not found"

Sprawdź, czy struktura plików frameworka jest poprawna:
```
ls /cccrane/ecnet/ecnet2/init.lua
```

### "attempt to use an uninitialized random generator"

Brak plików ccryptolib. Sprawdź:
```
ls /cccrane/ccryptolib/ccryptolib/random.lua
```

Wymagane minimum:
| Plik | Ścieżka |
|---|---|
| `random.lua` | `/cccrane/ccryptolib/ccryptolib/random.lua` |
| `blake3.lua` | `/cccrane/ccryptolib/ccryptolib/blake3.lua` |
| `chacha20.lua` | `/cccrane/ccryptolib/ccryptolib/chacha20.lua` |
| `poly1305.lua` | `/cccrane/ccryptolib/ccryptolib/poly1305.lua` |
| `util.lua` | `/cccrane/ccryptolib/ccryptolib/util.lua` |
| `internal/util.lua` | `/cccrane/ccryptolib/ccryptolib/internal/util.lua` |
| `internal/packing.lua` | `/cccrane/ccryptolib/ccryptolib/internal/packing.lua` |
| `ed25519.lua` | `/cccrane/ccryptolib/ccryptolib/ed25519.lua` |
| `x25519.lua` | `/cccrane/ccryptolib/ccryptolib/x25519.lua` |
| `x25519c.lua` | `/cccrane/ccryptolib/ccryptolib/x25519c.lua` |
| `sha256.lua` | `/cccrane/ccryptolib/ccryptolib/sha256.lua` |
| `aead.lua` | `/cccrane/ccryptolib/ccryptolib/aead.lua` |
| `internal/sha512.lua` | `/cccrane/ccryptolib/ccryptolib/internal/sha512.lua` |
| `internal/curve25519.lua` | `/cccrane/ccryptolib/ccryptolib/internal/curve25519.lua` |
| `internal/edwards25519.lua` | `/cccrane/ccryptolib/ccryptolib/internal/edwards25519.lua` |
| `internal/fp.lua` | `/cccrane/ccryptolib/ccryptolib/internal/fp.lua` |
| `internal/fq.lua` | `/cccrane/ccryptolib/ccryptolib/internal/fq.lua` |
| `internal/mp.lua` | `/cccrane/ccryptolib/ccryptolib/internal/mp.lua` |

### Panel pokazuje "DISCONNECTED"

Żuraw poza zasięgiem wireless modemu (~64-128 bloków). Rozwiązania:
- Zbliż komputery do siebie
- Użyj wzmacniaczy sygnału / chunkloaderów
- Sprawdź, czy modem jest na stronie **top**

### "SEND FAILED — connection lost"

Przerwane połączenie. Żuraw automatycznie próbuje reconnect z backoffem. Panel wykryje timeout po 15s i pokaże DISCONNECTED. Po ponownym połączeniu wszystko wraca do normy.

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
