-- Toast Control 2.1: eine Config pro Geraet. Start mit toast.lua.
-- role=auto erkennt Computer, Pocket und Turtle; Repeater bewusst einstellen.
return {
    role = "auto",
    job = "auto",                     -- Turtle: farm oder mining
    controllerId = 4,
    name = "",                       -- NAME dieses Geraets, z.B. "Weizen Nord" (Zentrale, Pocket, Turtle)
    autoDiscover = true,              -- Zentrale lernt meldende Turtles
    autoPairPockets = true,           -- neue Toast-Pockets automatisch anmelden
    devices = {                      -- optional: feste/offline bekannte Geraete
        -- Nur an der Zentrale: Namen hier ueberschreiben den Namen der Turtle.
        -- [5] = { job = "farm", name = "Weizen Nord" },
        -- [12] = { job = "mining", name = "Mine Nord" },
    },
    pocketIds = {},                   -- bekannte Pockets; eigene ID erkennt Installer
    display = { monitor = "auto", textScale = 0.5, pageSize = 0 },
    network = { pollInterval = 1, staleAfter = 15, commandTimeout = 10, maxDevices = 256 },
    -- Stabilitaet / Reset nach Fehlern (fehlt der Block, gelten diese Werte):
    recovery = {
        autoRestart = true,           -- Programm nach Absturz selbst neu starten
        restartDelay = 5,             -- Sekunden bis zum Neustart
        maxRestarts = 5,              -- hoechstens so oft in 10 Minuten
        autoRetry = 3,                -- Turtle: Auftrag nach Fehler so oft neu versuchen
        retryDelay = 30,              -- Sekunden Pause vor neuem Versuch
        moveRetries = 8,              -- Versuche, wenn Mob/Spieler den Weg blockiert
    },
    -- Turtle steht an der Basis und schaut aufs Feld / in die Mine.
    -- length = Bloecke nach vorne, width/tunnels = zur Seite (side = right/left).
    farm = {
        width = 9, length = 9, side = "right", crop = "wheat", interval = 60,
        seedReserve = 64,
        radioTimeout = 60,            -- Sekunden ohne Zentrale bis Stopp; 0 = trotzdem weiterarbeiten
        water = {},                   -- Wasser wird automatisch erkannt (egal wo, auch ganze Reihen)
    },
    mine = {
        length = 100, height = 3, tunnels = 5, gap = 2, side = "right",
        fuelTarget = 2000, freeSlots = 2, digRetries = 16,
        radioTimeout = 60,            -- Sekunden ohne Zentrale bis Stopp; 0 = trotzdem weiterarbeiten
        -- Alles wird abgebaut, Wasser/Lava werden durchfahren.
        -- Hier Bloecke eintragen, die die Turtle NICHT abbauen soll, z.B.
        -- "minecraft:chest", "minecraft:spawner". Andere Turtles sind immer geschuetzt.
        protectedBlocks = {},
    },
}
