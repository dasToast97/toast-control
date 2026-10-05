-- Toast Farm 2.1 | CC:Tweaked | Mining Turtle + Wireless Modem
-- Feld: Spalten von links nach rechts, Reihen von der Basis nach hinten.
-- Neu: Positions-Wiederherstellung nach Absturz, RESET, Auto-Retry, Mob-Blockaden.
local common = dofile("/farm_common.lua")
local config = common.load()
assert(config.role == "turtle", "Dieses Programm gehoert auf die Turtle.")
local CFG = config.farm
local R = config.recovery or { autoRetry = 3, retryDelay = 30, moveRetries = 8 }
local CROPS = {
    wheat = { block = "minecraft:wheat", seed = "minecraft:wheat_seeds",
        produce = "minecraft:wheat", age = 7, label = "Weizen" },
    carrots = { block = "minecraft:carrots", seed = "minecraft:carrot",
        produce = "minecraft:carrot", age = 7, label = "Karotten" },
    potatoes = { block = "minecraft:potatoes", seed = "minecraft:potato",
        produce = "minecraft:potato", age = 7, label = "Kartoffeln" },
    beetroot = { block = "minecraft:beetroots", seed = "minecraft:beetroot_seeds",
        produce = "minecraft:beetroot", age = 3, label = "Rote Bete" },
}
local PROTOCOL, STATE_FILE = common.protocol, "/toast_farm_state"
local FUEL = { ["minecraft:coal"] = true, ["minecraft:charcoal"] = true, ["minecraft:coal_block"] = true }
local TOOLS = { ["minecraft:diamond_pickaxe"] = true, ["minecraft:netherite_pickaxe"] = true,
    ["minecraft:diamond_hoe"] = true, ["minecraft:netherite_hoe"] = true }
local NO_TOOL = "Kein Werkzeug: Diamant-Spitzhacke oder -Hacke in die Turtle legen"
local CONTAINERS = { ["minecraft:chest"] = true,
    ["minecraft:trapped_chest"] = true, ["minecraft:barrel"] = true }
local args = { ... }
assert(turtle, "Dieses Programm gehoert auf eine Mining Turtle.")
assert(CROPS[CFG.crop], "Unbekannte Pflanzenart in CFG.crop.")
for _, n in ipairs({ CFG.width, CFG.length }) do
    assert(type(n) == "number" and n >= 1 and n <= 32 and n % 1 == 0,
        "Feldmasse muessen ganze Zahlen zwischen 1 und 32 sein.")
end
assert(CFG.interval >= 1 and CFG.seedReserve >= 0 and CFG.seedReserve <= 256,
    "Ungueltige Wartezeit oder Saatgutreserve.")
local crop = CROPS[CFG.crop]
assert(CFG.side == nil or CFG.side == "right" or CFG.side == "left", "farm.side: right oder left.")
local MIRROR = CFG.side == "left"
CFG.water = CFG.water or {}
-- Saatgut aus der Ernte wird behalten und wieder gepflanzt.
-- seedReserve = 0 (Standard): automatisch so viel, wie das Feld Pflanzstellen hat
-- (mind. 16, max. 3 Stapel). Die Saatgutkiste hinten wird dann nur noch gebraucht,
-- wenn die Turtle gar kein Saatgut mehr hat.
local RESERVE = CFG.seedReserve
if RESERVE == 0 then
    RESERVE = math.max(16, math.min(192, CFG.width * CFG.length - #CFG.water))
end
-- CCChunkloader: Chunkloader bleibt angebaut, Werkzeug <-> Modem werden getauscht.
local TC = dofile("/toast_common.lua")
local CL = TC.chunkConfig(config.chunkload)
local GEAR
local lastRadio=os.clock()    -- letztes Funkfenster (Chunkloader)
if CL.enabled then
    local why
    GEAR, why = TC.gear(CL, TOOLS)
    assert(GEAR, why)
    assert(GEAR.radio(), "Chunkloader: Funk-/Endermodem ins Turtle-Inventar legen.")
end
local drainPerSec = CL.enabled and TC.chunkCostPerTick(CL.radius) * 20 or 0
local budget = CFG.width * CFG.length + CFG.width + CFG.length + 20
    + math.ceil(drainPerSec * (CFG.width * CFG.length * 1.5 + math.max(CFG.interval, CFG.maxInterval or 0) + 90))

local function readTable(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local ok, s = pcall(textutils.unserialize, f.readAll())
    f.close()
    if ok and type(s) == "table" and type(s.x) == "number" and type(s.z) == "number"
        and type(s.dir) == "number" then return s end
end
local function loadState()
    -- Halb geschriebene .tmp-Datei ignorieren und die letzte gute Datei nehmen.
    local s = readTable(STATE_FILE .. ".tmp") or readTable(STATE_FILE)
    if s then return s end
    if fs.exists(STATE_FILE) or fs.exists(STATE_FILE .. ".tmp") then
        error("Farmzustand beschaedigt. Turtle an Basis setzen: toast.lua --dock", 0)
    end
    return { x = 0, z = 0, dir = 0, total = 0, harvested = 0, rounds = 0 }
end
local st = loadState()
local function save()
    local f = assert(fs.open(STATE_FILE .. ".tmp", "w"), "Farmzustand nicht schreibbar.")
    f.write(textutils.serialize(st))
    f.close()
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
    fs.move(STATE_FILE .. ".tmp", STATE_FILE)
end
local function clearPending() st.pending, st.after, st.pendingFuel, st.pendingDrain = nil, nil, nil, nil end
-- Unterbrochene Bewegung ueber den Fuelstand aufloesen.
local function resolvePending()
    if not st.pending then return true end
    local fuel = turtle.getFuelLevel()
    if st.pending ~= "turn" and type(fuel) == "number" and type(st.pendingFuel) == "number"
        and type(st.after) == "table" then
        if fuel == st.pendingFuel then clearPending(); save(); return true end
        -- Chunkloader zieht nebenbei Fuel ab: dann ist "1 weniger" nicht eindeutig.
        if st.pendingDrain then return false end
        if fuel == st.pendingFuel - 1 then
            st.x, st.z, st.dir = st.after.x, st.after.z, st.after.dir
            clearPending(); save(); return true
        end
    end
    return false
end
local resolvedAtStart = st.pending ~= nil and resolvePending()
for _, arg in ipairs(args) do
    if arg == "--dock" then
        print("Turtle muss an der Basis stehen und zum Feld schauen.")
        write("Zum Bestaetigen DOCK eingeben: ")
        assert(read() == "DOCK", "Positionsreset abgebrochen.")
        st.x, st.z, st.dir = 0, 0, 0
        clearPending()
        st.lastMode = nil
    else
        error("Start: toast.lua [--dock]. IDs in toast.config.lua einstellen.", 0)
    end
end
st.controller = config.controllerId
local layout = CFG.width .. ":" .. CFG.length .. ":" .. CFG.crop .. (MIRROR and ":L" or "")
for _,cell in ipairs(CFG.water) do layout = layout .. ":" .. cell.column .. "," .. cell.row end
assert(not st.layout or st.layout == layout or (st.x == 0 and st.z == 0 and not st.pending),
    "Feldparameter nur an der Basis aendern. Bei versetzter Turtle --dock verwenden.")
st.layout = layout
assert(st.controller and st.controller >= 0 and st.controller % 1 == 0
    and st.controller ~= os.getComputerID(), "Ungueltige Computer-ID.")
save()
common.modem()
local run = { mode = "off", status = "Bereit", detail = "START am Touchscreen druecken.",
    scanned = 0, roundYield = 0, roundPlants = 0, waitUntil = 0,
    lastContact = os.clock(), fault = nil, recovery = st.pending ~= nil,
    lastMode = nil, retries = 0, retryAt = nil }
if run.recovery then
    run.status = "Position unklar"
    run.detail = "An Basis setzen; toast.lua --dock starten."
elseif resolvedAtStart then
    run.detail = "Position nach Neustart wiederhergestellt."
end
-- Nach Absturz/Serverneustart den laufenden Auftrag selbst fortsetzen.
if not run.recovery and (st.lastMode == "auto" or st.lastMode == "once") then
    run.mode, run.lastMode = st.lastMode, st.lastMode
    run.status, run.detail = "Fortsetzen", "Auftrag nach Neustart fortgesetzt."
end
local function status(title, detail)
    run.status, run.detail = title, detail or ""
end
local function retryable(fault)
    if type(fault) ~= "string" then return false end
    for _, w in ipairs({ "Geschuetzt", "Position unklar" }) do
        if fault:find(w, 1, true) then return false end
    end
    return true
end
local function fail(why) run.mode, run.fault, run.retryAt = "off", why, nil end
local function finish()
    run.mode, run.lastMode = "off", nil
    if st.lastMode then st.lastMode = nil; save() end
end
local function count(name)
    local n = 0
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == name then n = n + item.count end
    end
    return n
end
local function freeSlots()
    local n = 0
    for i = 1, 16 do if turtle.getItemCount(i) == 0 then n = n + 1 end end
    return n
end
local function findSlot(name)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == name then return i end
    end
end
local function receiveSlot(name)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == name and turtle.getItemSpace(i) > 0 then return i end
    end
    for i = 1, 16 do if turtle.getItemCount(i) == 0 then return i end end
end
local function equipTool()
    if GEAR then return GEAR.tool() end
    for i = 1, 16 do
        local it = turtle.getItemDetail(i)
        if it and TOOLS[it.name] then
            turtle.select(i)
            for _, side in ipairs({ "left", "right" }) do
                if peripheral.getType(side) ~= "modem" then
                    local fn = side == "left" and turtle.equipLeft or turtle.equipRight
                    if fn() then return true end
                end
            end
        end
    end
    return false
end
local function isHome() return st.x == 0 and st.z == 0 end
local function maybeUpdate()
    if not run.updateReq then return end
    local want = type(run.updateReq) == "string" and run.updateReq or nil
    run.updateReq = false
    local ok, why = TC.selfUpdate(function(a, b) run.status, run.detail = a, b end, want)
    if not ok then run.status, run.detail = "Update fehlgeschlagen", tostring(why); TC.log("Update: " .. tostring(why)) end
end
local function active()
    maybeUpdate()
    -- radioTimeout = 0: auch ohne Zentrale weiterarbeiten.
    -- Mit Chunkloader: nur Funkfenster ohne Antwort zaehlen (siehe radioWindow).
    if run.mode ~= "off" and CFG.radioTimeout > 0 then
        if GEAR then
            if os.clock() - run.lastContact < 3 then run.radioMiss = 0 end
            if (run.radioMiss or 0) >= math.max(3, math.ceil(CFG.radioTimeout / math.max(1, CL.report))) then
                fail("Funkverbindung verloren")
            end
        elseif os.clock() - run.lastContact > CFG.radioTimeout then
            fail("Funkverbindung verloren")
        end
    end
    return run.mode ~= "off" and not run.recovery
end
-- Vor Bewegungen werden Marker, Zielposition und Fuelstand gespeichert.
-- Nach einem Neustart klaert der Fuelstand, ob der Schritt ausgefuehrt wurde.
local function action(kind, fn, update)
    local x, z, dir = st.x, st.z, st.dir
    update()
    st.after = { x = st.x, z = st.z, dir = st.dir }
    st.x, st.z, st.dir = x, z, dir
    st.pending, st.pendingFuel = kind, turtle.getFuelLevel()
    st.pendingDrain = GEAR ~= nil and GEAR.radius > 0 or nil
    save()
    local ok, why = fn()
    if ok then update() end
    clearPending()
    save()
    return ok, why
end
local function face(dir)
    while st.dir ~= dir do
        local left = (st.dir - dir) % 4 == 1
        -- side="left": Feld liegt links -> alle Drehungen gespiegelt.
        local ok, why = action("turn", (left ~= MIRROR) and turtle.turnLeft or turtle.turnRight,
            function() st.dir = (st.dir + (left and 3 or 1)) % 4 end)
        if not ok then return false, why or "Drehen fehlgeschlagen" end
    end
    return true
end
local DX, DZ = { [0] = 0, 1, 0, -1 }, { [0] = 1, 0, -1, 0 }
-- Mit Chunkloader: Modem statt Werkzeug, solange nicht geerntet wird
-- (2 Schritte ohne Ernte). Das Werkzeug kommt beim naechsten Ernten zurueck.
local freeMoves = 0
local function forward()
    local last
    freeMoves = freeMoves + 1
    if GEAR and freeMoves >= 2 and GEAR.radio() then lastRadio = os.clock() end
    -- Tiere/Spieler im Weg: angreifen, kurz warten, erneut versuchen.
    for attempt = 1, R.moveRetries do
        local ok, why = action("move", turtle.forward, function()
            st.x, st.z = st.x + DX[st.dir], st.z + DZ[st.dir]
        end)
        if ok then return true end
        last = why
        if tostring(why):lower():find("fuel", 1, true) then break end
        if attempt < R.moveRetries then pcall(turtle.attack); sleep(0.5) end
    end
    return false, "Weg blockiert: " .. tostring(last)
end
-- Chunks nur laden, solange die Turtle unterwegs ist / arbeitet / auf neuen Versuch wartet.
local function chunkTick()
    if not GEAR then return end
    local need = run.mode ~= "off" or not isHome() or (run.fault ~= nil and run.retryAt ~= nil) or CL.idle
    GEAR.set(need and CL.radius or 0)
end
local function goTo(x, z, interruptible)
    while st.x ~= x or st.z ~= z do
        if interruptible and not active() then return false, "stopped" end
        local dir
        if st.z ~= z then dir = st.z < z and 0 or 2
        else dir = st.x < x and 1 or 3 end
        local ok, why = face(dir)
        if not ok then return false, why end
        if interruptible and not active() then return false, "stopped" end
        chunkTick()
        ok, why = forward()
        if not ok then return false, why end
    end
    return true
end
local function home()
    status("Rueckkehr", run.fault or "Fahre zur Basis.")
    local ok, why = goTo(0, 0, false)
    if ok then ok, why = face(0) end
    return ok, why
end
local function container(inspect)
    local ok, block = inspect()
    return ok and CONTAINERS[block.name] == true
end
local function unload()
    if not container(turtle.inspectDown) then
        return false, "Lager fehlt", "Kiste oder Fass direkt UNTER die Basis setzen."
    end
    local keep = RESERVE
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and not FUEL[item.name] and not TOOLS[item.name] and not TC.MODEM_ITEMS[item.name] then
            local amount = item.count
            if item.name == crop.seed then
                local retained = math.min(keep, amount)
                keep, amount = keep - retained, amount - retained
            end
            if amount > 0 then
                turtle.select(i)
                local before = turtle.getItemCount(i)
                turtle.dropDown(amount)
                if before - turtle.getItemCount(i) < amount then
                    return false, "Lager voll", "Ausgabekiste leeren oder erweitern."
                end
            end
        end
    end
    return true
end
local function refuel()
    local function sufficient()
        local fuel = turtle.getFuelLevel()
        return fuel == "unlimited" or fuel >= budget
    end
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and FUEL[item.name] then
            turtle.select(i)
            while turtle.getItemCount(i) > 0 and not sufficient() do
                if not turtle.refuel(1) then break end
            end
        end
    end
    if sufficient() then return true end
    if not container(turtle.inspectUp) then
        return false, "Treibstoff fehlt", "Kohlekiste direkt UEBER die Basis setzen."
    end
    local slot = receiveSlot("minecraft:coal") or receiveSlot("minecraft:charcoal")
    if not slot then return false, "Inventar voll", "Turtle-Inventar pruefen." end
    turtle.select(slot)
    if not turtle.suckUp(math.max(1, math.ceil((budget - turtle.getFuelLevel()) / 80))) then
        return false, "Treibstoff fehlt", "Kiste oben mit Kohle / Holzkohle fuellen."
    end
    local item = turtle.getItemDetail(slot)
    if not item or not FUEL[item.name] then
        turtle.dropUp()
        return false, "Falscher Brennstoff", "In die obere Kiste nur Kohle / Holzkohle legen."
    end
    while turtle.getItemCount(slot) > 0 and not sufficient() do
        if not turtle.refuel(1) then break end
    end
    if sufficient() then return true end
    return false, "Treibstoff fehlt", "Mehr Kohle / Holzkohle in die obere Kiste legen."
end
local function refillSeeds()
    if count(crop.seed) >= RESERVE then return true end
    local ok, why = face(2)
    if not ok then return false, "Drehen fehlgeschlagen", why end
    local exists = container(turtle.inspect)
    local badItem = false
    if exists then
        while count(crop.seed) < RESERVE do
            local slot = receiveSlot(crop.seed)
            if not slot then break end
            turtle.select(slot)
            if not turtle.suck(math.min(64, RESERVE - count(crop.seed))) then break end
            local item = turtle.getItemDetail(slot)
            if not item or item.name ~= crop.seed then turtle.drop(); badItem = true; break end
        end
    end
    ok, why = face(0)
    if not ok then return false, "Drehen fehlgeschlagen", why end
    if badItem then
        return false, "Saatgutkiste pruefen", "Hinten nur passendes Saatgut einfuellen."
    end
    if count(crop.seed) > 0 then return true end
    return false, "Saatgut fehlt", "Kiste HINTER der Basis mit Saatgut fuellen."
end
local function prepare()
    if not isHome() then
        local ok, why = home()
        if not ok then fail(why); return false, why end
    end
    while active() do
        local ok, title, detail = unload()
        if ok then ok, title, detail = refuel() end
        if ok then ok, title, detail = refillSeeds() end
        if ok then return true end
        status(title, detail)
        if GEAR then GEAR.radio() end
        for _ = 1, 10 do if not active() then return false, "stopped" end; sleep(0.2) end
    end
    return false, "stopped"
end
local function waterCell(x, z)
    for _, cell in ipairs(CFG.water) do
        if cell.column == x + 1 and cell.row == z then return true end
    end
    return false
end
local function visit(x, z)
    if waterCell(x, z) then return true end
    local exists, block = turtle.inspectDown()
    if exists and block.name ~= crop.block then return true end
    if exists and tonumber((block.state or {}).age) ~= crop.age then return true end
    if count(crop.seed) == 0 then return false, "resupply" end
    if exists and freeSlots() < 2 then return false, "resupply" end
    local before = count(crop.produce)
    -- Samen extra zaehlen (Weizen/Rote Bete: Frucht + Samen; Karotte/Kartoffel: beides dasselbe)
    local seedBefore = crop.seed ~= crop.produce and count(crop.seed) or 0
    if exists then
        status("Ernte", "Reife Pflanzen werden geerntet und neu gepflanzt.")
        local dug, why = turtle.digDown()
        if not dug and tostring(why):find("No tool", 1, true) then
            if not equipTool() then return false, NO_TOOL end
            dug, why = turtle.digDown()
        end
        if not dug then
            return false, tostring(why):find("No tool", 1, true) and NO_TOOL or "Pflanze nicht abbaubar"
        end
        st.harvested, run.roundPlants = (st.harvested or 0) + 1, run.roundPlants + 1
        freeMoves = 0
    else
        status("Pflanzen", "Leere Ackerstellen werden bepflanzt.")
    end
    local slot = findSlot(crop.seed)
    if not slot then return false, "Saatgut fehlt" end
    turtle.select(slot)
    local planted = turtle.placeDown()
    local net = math.max(0, count(crop.produce) - before)
    -- Ueberschuessige Samen (nach dem Neupflanzen) gehoeren zum Ertrag
    local seedNet = 0
    if exists and crop.seed ~= crop.produce then seedNet = math.max(0, count(crop.seed) - seedBefore) end
    st.seedsGained = (st.seedsGained or 0) + seedNet
    net = net + seedNet
    st.total, run.roundYield = (st.total or 0) + net, run.roundYield + net
    save()
    -- Kein Acker (z.B. Weg/Erde) blockiert nicht mehr die ganze Runde.
    if not planted then run.skipped = (run.skipped or 0) + 1 end
    return true
end
local sendStatus
lastRadio=os.clock()
-- Mit Chunkloader: alle reportEvery Sekunden kurz Modem anlegen und funken.
-- Das Werkzeug kommt beim naechsten Ernten automatisch zurueck.
local function radioWindow()
    if not GEAR or os.clock() - lastRadio < CL.report then return end
    if GEAR.radio() then
        local t0 = os.clock()
        sendStatus(); sleep(2.2)
        if run.lastContact >= t0 then run.radioMiss = 0 else run.radioMiss = (run.radioMiss or 0) + 1 end
    end
    lastRadio = os.clock()
end
local function scan()
    run.scanned, run.roundYield, run.roundPlants, run.waitUntil, run.skipped = 0, 0, 0, 0, 0
    if not prepare() then return false end
    for index = 1, CFG.width * CFG.length do
        if not active() then return false end
        local row = math.floor((index - 1) / CFG.width) + 1
        local x = (index - 1) % CFG.width
        if row % 2 == 0 then x = CFG.width - 1 - x end
        local done = false
        while not done and active() do
            radioWindow()
            local fuel = turtle.getFuelLevel()
            local dist = math.abs(st.x - x) + math.abs(st.z - row) + x + row
            local need = dist * (1 + drainPerSec * 0.6) + 8 + math.ceil(drainPerSec * 90)
            if fuel ~= "unlimited" and fuel < need then
                if not prepare() then return false end
            end
            status("Feld pruefen", "Reihe " .. row .. " / " .. CFG.length)
            local ok, why = goTo(x, row, true)
            if not ok then
                if why ~= "stopped" then fail(why) end
                return false
            end
            if not active() then return false end
            ok, why = visit(x, row)
            if ok then done = true
            elseif why == "resupply" then
                if not prepare() then return false end
            else
                fail(why)
                return false
            end
        end
        if not done then return false end
        run.scanned = index
    end
    st.rounds = (st.rounds or 0) + 1
    run.retries = 0
    save()
    local ok, why = home()
    if not ok then fail("Rueckweg blockiert: " .. tostring(why)); return false end
    while active() do
        local ok2, title, detail = unload()
        if ok2 then return true end
        status(title, detail)
        if GEAR then GEAR.radio() end
        for _ = 1, 10 do if not active() then return false end; sleep(0.2) end
    end
    return false
end
local function idle()
    if not isHome() or st.dir ~= 0 then
        local ok, why = home()
        if not ok then status("Rueckweg blockiert", why); return end
    end
    local ok, title, detail = unload()
    if not ok then status(title, detail); return end
    if run.fault then
        local now = os.clock()
        if run.lastMode and retryable(run.fault) and run.retries < R.autoRetry then
            run.retryAt = run.retryAt or now + R.retryDelay
            local contact = CFG.radioTimeout == 0 or now - run.lastContact < CFG.radioTimeout
            if now >= run.retryAt and contact then
                run.retries, run.retryAt, run.fault, run.mode = run.retries + 1, nil, nil, run.lastMode
                status("Neuer Versuch", "Automatisch " .. run.retries .. "/" .. R.autoRetry)
            else
                status(run.fault, contact and ("Neuer Versuch in " .. math.max(0, math.ceil(run.retryAt - now))
                    .. "s (" .. (run.retries + 1) .. "/" .. R.autoRetry .. ") | RESET: abbrechen")
                    or "Warte auf Funkkontakt fuer neuen Versuch")
            end
        else
            status(run.fault, "Problem beheben; RESET loescht Fehler, START startet neu.")
        end
    else
        status("Bereit", "START: Dauerbetrieb | 1 RUNDE: einmal ernten.")
    end
    if GEAR then GEAR.radio() end
    chunkTick()
end
-- Spar-Pause: Pflanzen brauchen ~5-30 min. Waren beim letzten Durchgang nur
-- wenige reif, wird die Pause laenger (bis maxInterval), bei fast allen reif
-- wieder kuerzer (bis interval). Spart viele unnoetige Runden = Fuel.
local function nextPause()
    local maxI = CFG.maxInterval or 0
    if maxI <= CFG.interval then return CFG.interval end
    local cells = CFG.width * CFG.length - #CFG.water - (run.skipped or 0)
    local f = cells > 0 and (run.roundPlants or 0) / cells or 1
    local p = st.pause or CFG.interval
    if f < 0.25 then p = p * 2 elseif f < 0.6 then p = p * 1.4 elseif f > 0.9 then p = p * 0.7 end
    p = math.floor(math.max(CFG.interval, math.min(maxI, p)))
    st.pause, st.lastRipe = p, math.floor(f * 100 + 0.5)
    save()
    return p
end
local function worker()
    while true do
        if run.recovery then
            sleep(0.2)
        elseif active() then
            local complete = scan()
            if complete and run.mode == "once" then finish() end
            if complete and active() then
                local pause = nextPause()
                run.waitUntil = os.clock() + pause
                if GEAR then GEAR.radio() end
                while active() and run.waitUntil > os.clock() do
                    chunkTick()
                    local left = math.max(0, math.ceil(run.waitUntil - os.clock()))
                    status("Warten", "Naechste Runde in " .. (left >= 120 and (math.ceil(left / 60) .. " min") or (left .. " s"))
                        .. (st.lastRipe and (", zuletzt " .. st.lastRipe .. "% reif") or "")
                        .. ((run.skipped or 0) > 0 and (". " .. run.skipped .. " Felder ohne Acker.") or ""))
                    sleep(0.2)
                end
                run.waitUntil = 0
            end
        else
            idle()
            sleep(0.5)
        end
    end
end
local function snapshot()
    return { kind = "status", version = 2, id = os.getComputerID(), crop = crop.label,
        width = CFG.width, length = CFG.length, status = run.status, detail = run.detail,
        mode = run.mode, recovery = run.recovery, ack = st.commandSerial or 0,
        fault = run.fault, retries = run.retries,
        contactAge = math.max(0, math.floor(os.clock() - run.lastContact)),
        fuel = turtle.getFuelLevel(), budget = budget, seeds = count(crop.seed),
        chunks = GEAR and (GEAR.radius > 0 and CL.chunks or 0) or nil,
        chunkFuel = GEAR and math.floor(GEAR.perSecond() * 3600 + 0.5) or nil,
        freeSlots = freeSlots(), x = st.x, z = st.z, total = st.total or 0,
        harvested = st.harvested or 0, rounds = st.rounds or 0, seedsGained = st.seedsGained or 0,
        roundYield = run.roundYield, roundPlants = run.roundPlants,
        scanned = run.scanned, cells = CFG.width * CFG.length,
        wait = math.max(0, math.ceil(run.waitUntil - os.clock())), pause = st.pause, lastRipe = st.lastRipe }
end
local lastSent = -1e9
sendStatus = function() lastSent = os.clock(); pcall(rednet.send, st.controller, snapshot(), PROTOCOL) end
local function reset()
    run.mode, run.fault, run.lastMode, run.retries, run.retryAt, run.waitUntil = "off", nil, nil, 0, nil, 0
    st.lastMode = nil
    if run.recovery and resolvePending() then run.recovery = false end
    if run.recovery then status("Position unklar", "RESET reicht nicht: an Basis setzen, toast.lua --dock")
    else status("Reset", "Fehler geloescht; Turtle faehrt zur Basis.") end
end
local function listener()
    while true do
        local event, sender, message, protocol = os.pullEvent()
        if (event == "key" and sender == keys.q) or (event == "char" and (sender == "q" or sender == "Q")) then
            finish(); run.fault = nil
        elseif event == "char" and (sender == "n" or sender == "N") and run.mode == "off" and isHome() then
            error("TOAST_NEUER_AUFTRAG", 0)
        elseif event == "peripheral" or event == "peripheral_detach" then common.refreshModems(); sendStatus()
        elseif event == "rednet_message" and sender == st.controller and protocol == PROTOCOL
            and type(message) == "table" then
            if message.kind == "poll" then
                run.lastContact = os.clock()
                if os.clock() - lastSent > 2.5 then sendStatus() end
            elseif message.kind == "command" and common.serial(message.serial)
                and ({ start = true, stop = true, once = true, reset = true, update = true })[message.action] then
                run.lastContact = os.clock()
                if message.serial > (st.commandSerial or 0) then
                    st.commandSerial = message.serial
                    if message.action == "update" then
                        run.updateReq = type(message.target) == "string" and message.target or true; run.status, run.detail = "Update", "Wird gleich installiert ..."
                    elseif message.action == "stop" then
                        finish(); run.fault, run.retries, run.retryAt = nil, 0, nil
                    elseif message.action == "reset" then reset()
                    elseif not run.recovery then
                        run.mode = message.action == "once" and "once" or "auto"
                        run.lastMode = run.mode
                        st.lastMode = run.mode
                        run.fault, run.waitUntil, run.retries, run.retryAt = nil, 0, 0, nil
                    end
                    save()
                end
                sendStatus()
            end
        end
    end
end
local function heartbeat()
    while true do common.refreshModems(); sendStatus(); sleep(2) end
end
if not GEAR then pcall(equipTool) end
term.clear(); term.setCursorPos(1, 1)
print("TOAST FARM v" .. TC.version .. " - Turtle #" .. os.getComputerID())
print("Zentrale #" .. st.controller .. " | " .. crop.label)
if GEAR then print("Chunkloader: " .. CL.chunks .. " Chunk(s), ca. " .. TC.chunkFuelPerHour(CL.chunks) .. " Fuel/h beim Arbeiten") end
print("Q: Stopp + Heimfahrt. N: neuer Auftrag (gestoppt, an Basis).")
if run.recovery then printError(run.detail) elseif resolvedAtStart then print(run.detail) end
local ok, why = pcall(function() parallel.waitForAll(worker, listener, heartbeat) end)
if not ok then
    run.mode = "off"
    run.recovery = st.pending ~= nil and not resolvePending()
    status(run.recovery and "Position unklar" or "Programm beendet", tostring(why))
    sendStatus()
    if why ~= "Terminated" then error(why, 0) end
    printError("Abgebrochen.")
    if run.recovery then print("Vor Neustart: Basisposition mit --dock neu bestaetigen.") end
end
