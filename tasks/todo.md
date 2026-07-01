# Plan: Dokładniejsze statusy operacji PICKANDDROP

## Problem

Obecnie w `kiosk.lua` wyświetlane są tylko 4 fazy operacji PICKANDDROP, co nie odzwierciedla rzeczywistych podkroków crane'a. Chcemy 6 faz:

1. **Moving to pickup point...** — crane rozpoczyna `gotoXY` do punktu pickup
2. **Picking up...** — crane zakończył ruch XY, lina zaczyna opuszczanie (`lower()`)
3. **Moving to drop point...** — lina zakończyła podnoszenie (`raiseTo()`), crane rusza XY do drop point
4. **Dropping...** — crane zakończył ruch XY, zaczyna opuszczanie liny (`lowerTo()`)
5. **Returning...** — lina opuszczona, sticker zwolniony, lina zaczyna podnoszenie (`raise()`)
6. **Done!** — wszystkie ruchy zakończone, ekran pokazuje Done przez 3s

## Problemy do rozwiązania

### Problem 1: Fazy 2, 3, 4, 5 nie mogą być wnioskowane z pozycji/stickera

`inferExecPhase()` w kiosk.lua opiera się na pozycji XY i stanie stickera. Tymczasem:
- Fazy 2 (pickup) i 4 (drop) mają tę samą pozycję co faza poprzednia
- Sticker zmienia się dopiero po zakończeniu lower/stickerGrab, czyli w trakcie fazy 2

**Rozwiązanie:** Client wysyła explicite numer fazy w STATUS (`phase`). Panel używa go zamiast `inferExecPhase`, gdy jest dostępny.

### Problem 2: pickup() i drop() są monolityczne w crane.lua

`pickup()` i `drop()` wykonują wiele podkroków (lower, sticker, raise) wewnątrz jednej funkcji, bez możliwości wysłania STATUS między nimi.

**Rozwiązanie:** W client.lua rozbijamy `pickup()` i `drop()` na indywidualne wywołania (`crane.lower()`, `crane.stickerGrab()`, `crane.raiseTo()`, etc.) — wszystkie te funkcje są już publicznie eksportowane z `crane.lua:440-476`.

### Problem 3: TRANSPORT_HEIGHT jest lokalny w crane.lua

`TRANSPORT_HEIGHT = cfg.LIFT_HEIGHT - cfg.TRANSPORT_LOWER` jest zdefiniowany jako lokalny w crane.lua.

**Rozwiązanie:** Obliczamy w client.lua: `crane.config.LIFT_HEIGHT - crane.config.TRANSPORT_LOWER`. `crane.config` jest eksportowany.

### Problem 4: Konflikt między sendStatus() na starcie a explicit phase

`sendStatus()` w linii 120 client.lua wysyła STATUS bez phase, co powoduje uruchomienie `inferExecPhase` na panelu.

**Rozwiązanie:** To nie jest problem — panel i tak pokazuje "Moving to pickup point..." ustawiony przez subscribera (`EXEC_LABELS[1]`). Ewentualna krótka migotka (jeśli crane akurat jest w src z sticker ON z poprzedniej operacji) jest pomijalna.

### Problem 5: sendStatus() po ACK może nadpisać fazę

Po zakończeniu komendy, `sendStatus()` (linia 179) wysyła STATUS bez phase po ACK. Jeśli STATUS dotrze do panelu po ACK, `panelState.executing` jest już false → STATUS nie uruchamia `inferExecPhase`. Jeśli przed ACK — może nadpisać fazę.

**Rozwiązanie:** ACK jest wysyłany PRZED sendStatus() w linii 179 (patrz client.lua:169-179). Więc panel dostaje ACK pierwszy, ustawia executing=false, a późniejszy STATUS nie uruchamia inferExecPhase. Żadnego problemu.

### Problem 6: emergency stop między podkrokami

Po rozbiciu pickup() i drop() na sub-steps, każdy podkrok sprawdza `EMERGENCY_STOP` wewnętrznie (w crane.lua). Dodatkowo `isStopped()` między podkrokami zapewnia wcześniejszy abort.

## Pliki do modyfikacji

### 1. client.lua — Rozbicie PICKANDROP na sub-steps z explicit phase

**Obecnie** (linie 132-143):
```lua
elseif command == "PICKANDDROP" then
    crane.gotoXY(params.src.x, params.src.y)
    if crane.isStopped() then aborted = true; return end
    sendStatus()
    crane.pickup()
    if crane.isStopped() then aborted = true; return end
    sendStatus()
    crane.gotoXY(params.dst.x, params.dst.y)
    if crane.isStopped() then aborted = true; return end
    sendStatus()
    crane.drop()
    sendStatus()
```

**Po zmianie:**
```lua
elseif command == "PICKANDDROP" then
    -- Phase 1: Moving to pickup point
    sendStatusWithPhase(1)
    crane.gotoXY(params.src.x, params.src.y)
    if crane.isStopped() then aborted = true; return end

    -- Phase 2: Picking up (lower, sticker grab, raise to transport height)
    sendStatusWithPhase(2)
    crane.lower()
    if crane.isStopped() then aborted = true; return end
    crane.stickerGrab()
    if crane.isStopped() then aborted = true; return end
    local transportHeight = crane.config.LIFT_HEIGHT - crane.config.TRANSPORT_LOWER
    crane.raiseTo(transportHeight)
    if crane.isStopped() then aborted = true; return end

    -- Phase 3: Moving to drop point
    sendStatusWithPhase(3)
    crane.gotoXY(params.dst.x, params.dst.y)
    if crane.isStopped() then aborted = true; return end

    -- Phase 4: Dropping (lower to ground)
    sendStatusWithPhase(4)
    crane.lowerTo(crane.config.LIFT_HEIGHT)
    if crane.isStopped() then aborted = true; return end

    -- Phase 5: Returning (sticker release, raise)
    sendStatusWithPhase(5)
    crane.stickerRelease()
    if crane.isStopped() then aborted = true; return end
    crane.raise()
```

**Nowa funkcja:**
```lua
--- Send STATUS with explicit execution phase number.
local function sendStatusWithPhase(phase)
    local st = crane.getState()
    sendMessage({
        type = "event",
        body = {
            message_type = "STATUS",
            status = {
                position = { st.currentX, st.currentY },
                sticker = st.stickerOn,
                busy = busy,
                phase = phase,
            },
        },
    })
end
```

### 2. kiosk.lua — Aktualizacja EXEC_LABELS i obsługi phase

**EXEC_LABELS** (linie 183-189):
```lua
local EXEC_LABELS = {
    [0] = "Starting...",
    [1] = "Moving to pickup point...",
    [2] = "Picking up...",
    [3] = "Moving to drop point...",
    [4] = "Dropping...",
    [5] = "Returning...",
    [6] = "Done!",
}
```

**STATUS handler** (linie 309-334) — preferuj explicit phase:
```lua
elseif body.message_type == "STATUS" then
    local stBody = body.status or {}
    local newPos = stBody.position or panelState.cranePos
    local newSticker = stBody.sticker == true
    local newBusy = stBody.busy == true
    local newPhase = stBody.phase   -- explicit phase from client (nil for non-PICKANDROP)

    panelState.cranePos = newPos
    panelState.craneSticker = newSticker
    panelState.craneBusy = newBusy

    if panelState.executing then
        local phase
        if newPhase ~= nil then
            -- Use explicit phase from client (PICKANDROP sub-steps)
            phase = newPhase
        else
            -- Fall back to inference for other commands
            local src = st.getState("selectedSource") or { x = 0, y = 0 }
            local dst = st.getState("selectedDest") or { x = 0, y = 0 }
            phase = inferExecPhase(newPos, newSticker, src, dst)
        end
        if phase ~= panelState.execPhase then
            panelState.execPhase = phase
            local label = EXEC_LABELS[phase] or "Executing..."
            st.updateState({ operationStatus = label })
            ui.updateProgress(st.getState())
        end
    end
```

**ACK handler** — ustaw operationStatus na "Done!":
```lua
if ackStatus == "ok" then
    print(timestamp() .. "  " .. (body.command_seq or "?") .. " OK")
    st.updateState({
        operationDone = true,
        operationError = nil,
        operationStatus = "Done!",
        screen = "success",
    })
```

### 3. monitor_ui.lua (opcjonalnie) — success screen z operationStatus

Linia 768: zmienić z hardcoded "Done!" na dynamiczne z `state.operationStatus`:
```lua
if successLine1 then
    successLine1:setText(centerText(state.operationStatus or "Done!", w))
    successLine1.visible = true
end
```

## Weryfikacja

1. Uruchomić client.lua na crane i kiosk.lua na panelu
2. Wybrać source/dest, kliknąć RUN
3. Obserwować sekwencję statusów na monitorze:
   - "Moving to pickup point..." → podczas gotoXY do source
   - "Picking up..." → podczas lower/stickerGrab/raiseTo
   - "Moving to drop point..." → podczas gotoXY do dest
   - "Dropping..." → podczas lowerTo
   - "Returning..." → podczas stickerRelease/raise
   - "Done!" → na ekranie success przez 3s, potem powrót do main
4. Sprawdzić zachowanie przy emergency stop — powinien natychmiast przerwać i pokazać "Emergency stopped"
