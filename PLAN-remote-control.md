# Plan: Panel Sterowania Żurawiem (Crane Control Panel)

## Context

Obecnie `crane.lua` działa jako samodzielny skrypt — przyjmuje 4 argumenty (`srcX srcY dstX dstY`) i wykonuje sekwencyjnie pełen cykl pick-and-place. Celem jest rozdzielenie tego na **dwa komputery**:

- **Panel sterowania (server)** — komputer z GUI do wybierania pozycji i wysyłania komend
- **Żuraw (client)** — komputer sterujący mechaniką żurawia, odbierający komendy przez ECNet2

Oba komputery mają wireless modem na stronie `"top"`. Wykorzystujemy framework **ECNet2** (z `ccryptolib.random`) do szyfrowanej komunikacji.

## Zależności

Projekt zawiera teraz:

- `ccryptolib/` — submoduł biblioteki kryptograficznej (CCryptoLib ≥1.1.0)
- ECNet2 — zewnętrzna biblioteka, do zainstalowania na komputerach CC (nie w repozytorium)

### Instalacja na komputerze

Na każdym komputerze (panel i żuraw) trzeba umieścić:

```
# W katalogu głównym (/):
ccryptolib/          → cały katalog z submodułu
ecnet2.lua           → biblioteka ECNet2
```

W ComputerCraft nie ma `require` z zewnętrznej ścieżki jak na dysku lokalnym — pliki muszą być w filesystemie komputera. Skopiuj cały katalog `ccryptolib` oraz `ecnet2.lua` (lub cały pakiet) na każdy komputer.

### Inicjalizacja ccryptolib.random

ECNet2 wymaga zainicjalizowanego generatora `ccryptolib.random`. Dokumentacja biblioteki oferuje dwie metody:

#### Metoda A: initWithTiming() — prostsza, bez internetu

```lua
local random = require "ccryptolib.random"
random.initWithTiming()
```

- Zbiera entropię z timingów instrukcji VM przez ~512ms
- Wygodniejsze, nie wymaga dostępu do internetu
- Uwaga: czynniki wpływające na timing instrukcji mogą być przewidywalne dla innych graczy na tym samym serwerze

**Zalecana dla żurawia**, który może nie mieć dostępu do internetu.

#### Metoda B: init(url) przez Krist WebSocket — bezpieczniejsza

```lua
local random = require "ccryptolib.random"

-- Pobiera token WebSocket z Krist node.
local postHandle = assert(http.post("https://krist.dev/ws/start", ""))
local data = textutils.unserializeJSON(postHandle.readAll())
postHandle.close()

-- Inicjalizuje generator seedingiem z URL-a.
random.init(data.url)

-- Dobra praktyka: faktycznie otworzyć socket.
http.websocket(data.url).close()
```

- Wymaga dostępu do internetu (CC: Tweaked z `http` API)
- Entropia z zewnętrznego źródła — trudniejsza do przewidzenia
- `data.url` zawiera unikalny, losowy URL tymczasowego WebSocketu

**Zalecana dla panelu**, jeśli ma dostęp do internetu.

#### W obu skryptach (crane-client.lua i crane-panel.lua)

Należy umieścić inicjalizację **przed** użyciem ECNet2:

```lua
local ecnet2 = require "ecnet2"
local random = require "ccryptolib.random"

-- Inicjalizacja ccryptolib.random (wybierz metodę)
random.initWithTiming()  -- lub random.init(url) z Krist
```

## Architektura Komunikacji

### Role ECNet2

- **Panel** = server (Listener) — czeka na połączenie od żurawia
- **Żuraw** = client (Connector) — łączy się z panelem

Adres panelu (jego ECNet2 identity key) jest przechowywany w pliku konfiguracyjnym na komputerze żurawia — konfiguracja jednorazowa.

### Protokół

Nowy protokół ECNet2 o nazwie `"crane_control"`, serializacja przez `textutils.serialize`/`textutils.unserialize`.

Format wiadomości (Lua table):

```lua
{
  type = "request" | "response" | "event",
  body = { message_type = "...", ... }
}
```

### Typy wiadomości

| message_type | Kierunek | Opis |
|---|---|---|
| `REGISTER` | Żuraw → Panel | Identyfikacja po połączeniu (crane_id, wersja) |
| `STATUS` | Żuraw → Panel | Status: pozycja (x,y), sticker on/off, busy, error |
| `ACK` | Żuraw → Panel | Potwierdzenie komendy (ok/error + treść) |
| `EVENT_LOG` | Żuraw → Panel | Wiadomości logowania operacji |
| `COMMAND` | Panel → Żuraw | Komenda: GOTO, PICKUP, DROP, HOME, EMERGENCY_STOP, STATUS_QUERY |
| `CONFIG_QUERY` | Panel → Żuraw | Żądanie konfiguracji (wymiary, limity) |
| `CONFIG_RESPONSE` | Żuraw → Panel | Odpowiedź z config.lua |

### Komendy (COMMAND)

| Komenda | Parametry | Opis |
|---|---|---|
| `GOTO` | `{ x, y }` | Przejedź na absolutną pozycję |
| `PICKUP` | `{}` | Wykonaj sekwencję podnoszenia |
| `DROP` | `{}` | Wykonaj sekwencję odkładania |
| `HOME` | `{}` | Wykonaj homing |
| `EMERGENCY_STOP` | `{}` | Natychmiastowe zatrzymanie |
| `STATUS_QUERY` | `{}` | Wymuś raport statusu |

### Przebieg połączenia

```
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
      |   <-- EVENT_LOG {moving...} --      |
      |   <-- STATUS {busy} --              |
      |   <-- STATUS {idle} --              |
```

## Struktura Plików

### Nowe pliki

1. **crane-lib.lua** — Biblioteka żurawia. Ekstrakcja funkcji z `crane.lua` jako moduł (zwraca tabelę z funkcjami). Usunięty kod argumentów i sekwencji startowej. Dodane: `crane.init()`, `crane.done()`, globalna flaga `EMERGENCY_STOP` modyfikująca `waitUntilStopped()`.

2. **crane-client.lua** — Klient ECNet2 na komputerze żurawia. Ładuje `crane-lib.lua`, łączy się z panelem, pętla zdarzeń ECNet2 → dispatch komend → raportowanie statusu. Logika ponownego łączenia. Inicjalizacja ccryptolib przed ECNet2.

3. **crane-panel.lua** — Panel sterowania (server ECNet2). GUI pełnoekranowe w terminalu (term API z kolorami), obsługa touch/klawiatury dla pól X/Y, przyciski komend, log operacji. Inicjalizacja ccryptolib przed ECNet2.

4. **crane-remote-config.lua** — Konfiguracja zdalna (na komputerze żurawia):
   - `PANEL_ADDRESS` — adres ECNet2 panelu
   - `HEARTBEAT_INTERVAL`, `CONNECTION_TIMEOUT`, parametry ponownych łączeń
   - `MAX_LOG_LINES`

### Modyfikowane pliki

5. **crane.lua** — Cienka nakładka CLI na `crane-lib.lua` (zachowana kompatybilność wsteczna).

### Niezmieniane pliki

- `config.lua` — bez zmian
- `server.lua`, `client.lua` — pozostają jako przykłady ECNet2
- `ccryptolib/` — submoduł, bez zmian

## GUI Panela (Terminal-based)

```
+--------------------------------------------------+
| CRANE CONTROL PANEL          [● CONNECTED]        |
+--------------------------------------------------+
|                                                    |
|  SOURCE (Pickup)        DESTINATION (Drop-off)    |
|  X: [ 10 ]              X: [ 42 ]                 |
|  Y: [  5 ]              Y: [ 30 ]                 |
|                                                    |
|  [GOTO]  [PICKUP]  [DROP]  [HOME]  [EMRG STOP]  |
|                                                    |
|  Status: IDLE  |  Poz: (10,5)  |  Sticker: OFF    |
|                                                    |
+-- Operation Log -----------------------------------+
| [12:00] Connected to crane "gantry-1"              |
| [12:01] Moving to (10, 5)...                       |
| [12:02] Picking up...                              |
+--------------------------------------------------+
```

- term API: `term.clear()`, `term.setCursorPos()`, `term.setTextColor()`, `term.write()`
- `mouse_click` dla przycisków i aktywacji pól X/Y
- `char` + `key` dla edycji aktywnych pól (tylko cyfry, backspace, enter)
- Log o stałym rozmiarze (50 linii), scrollowanie przez usuwanie najstarszych
- Stan: `panelState.connected`, `panelState.craneStatus`, `panelState.srcX/srcY`, `panelState.dstX/dstY`, `panelState.logLines[]`

## Rozwiązania Problemów

| Problem | Rozwiązanie |
|---|---|
| **Adres panelu nieznany żurawiowi** | Konfiguracja w `crane-remote-config.lua` — panel wypisuje swój adres przy starcie, kopiowany raz |
| **Zasięg wireless / utrata połączenia** | Heartbeat co 3s z statusem. Po stronie żurawia: wykrycie błędu `send()` → pętla reconnect z backoffem (1.5x, max 30s). Panel: timeout 15s → status DISCONNECTED |
| **Żuraw zajęty, przychodzi nowa komenda** | Odrzucenie z `ACK {status="error", message="Crane is busy"}` — tylko STATUS_QUERY i EMERGENCY_STOP przechodzą |
| **Restart panelu** | Żuraw wykrywa błąd wysyłki, wchodzi w reconnect; po ponownym połączeniu rejestruje się od nowa |
| **Restart żurawia** | Panel wykrywa disconnect, żuraw po starcie łączy się i rejestruje; stan żurawia zachowany w `.crane-state` przez `crane-lib.lua` |
| **Blokujące operacje żurawia** | EMERGENCY_STOP przez flagę globalną sprawdzaną w `waitUntilStopped()` i między krokami; pętla ECNet2 w `parallel.waitForAny()` |
| **ccryptolib niezainicjalizowany** | ECNet2 rzuci błędem. Każdy skrypt używa `random.initWithTiming()` (lub Krist WebSocket) przed `ecnet2.open()` |

## Kolejność Implementacji

### Faza 1: Ekstrakcja crane-lib.lua
- Skopiować `crane.lua` → `crane-lib.lua`
- Usunąć: parsowanie argumentów (linie 93-106), blok wykonawczy (linie 365-403)
- Dodać: `crane.init()` (obsługa homingu/stanu), `crane.done()` (reset przekaźników + zapis stanu)
- Dodać flagę `EMERGENCY_STOP` i modyfikację `waitUntilStopped()` do jej sprawdzania
- Zwrócić tabelę ze wszystkimi funkcjami

### Faza 2: Refaktoryzacja crane.lua
- Zastąpić zawartość nakładką ładującą `crane-lib.lua`
- Zachować CLI: `crane <srcX> <srcY> <dstX> <dstY>` → sequence przez crane-lib

### Faza 3: crane-remote-config.lua
- Plik konfiguracyjny z adresem panelu i parametrami komunikacji

### Faza 4: crane-client.lua
- `require "ccryptolib.random"` + `random.initWithTiming()`
- Setup ECNet2 (identity, protocol `"crane_control"`)
- Połączenie z panelem, rejestracja, init żurawia
- Pętla: odbieranie komend → dispatch → ACK/STATUS/EVENT_LOG
- Heartbeat, reconnect, obsługa EMERGENCY_STOP
- `parallel.waitForAny(mainLoop, ecnet2.daemon)`

### Faza 5: crane-panel.lua
- `require "ccryptolib.random"` + `random.initWithTiming()`
- Setup ECNet2 (listener)
- GUI: rysowanie, przyciski, pola tekstowe, log
- Pętla zdarzeń: `mouse_click`, `char`, `key`, `ecnet2_request`, `ecnet2_message`, `timer`
- Wysyłanie komend, obsługa odpowiedzi

## Weryfikacja

1. **Test crane-lib standalone**: `crane 10 5 42 30` działa jak przed refaktoryzacją
2. **Test ECNet2**: Uruchomić `crane-panel.lua` na komputerze A, `crane-client.lua <panel_address>` na komputerze B — sprawdzić połączenie i rejestrację
3. **Test komend**: Kliknąć GOTO na panelu → sprawdzić ACK + ruch żurawia
4. **Test busy**: Podczas ruchu wysłać drugą komendę → sprawdzić ACK error "busy"
5. **Test EMERGENCY_STOP**: W trakcie ruchu kliknąć EMERGENCY STOP → żuraw zatrzymuje się
6. **Test reconnect**: Wyłączyć panel, żuraw wykrywa disconnect, włączyć panel → żuraw reconnect
7. **Test restart żurawia**: Wyłączyć i włączyć żurawia → panel pokazuje reconnect + nowy stan po homingu
