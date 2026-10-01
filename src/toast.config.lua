-- Toast Control 2.1: eine Config pro Geraet. Start mit toast.lua.
-- role=auto erkennt Computer, Pocket und Turtle; Repeater bewusst einstellen.
return {
    role = "auto",
    job = "auto",                     -- Turtle: farm oder mining
    controllerId = 4,
    label = "",                      -- eigener Turtle-Name
    autoDiscover = true,              -- Zentrale lernt meldende Turtles
    autoPairPockets = true,           -- neue Toast-Pockets automatisch anmelden
    devices = {                      -- optional: feste/offline bekannte Geraete
        -- [5] = { job = "farm", label = "Weizen Nord" },
        -- [12] = { job = "mining", label = "Mine Nord" },
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
    farm = {
        width = 9, length = 9, crop = "wheat", interval = 60,
        seedReserve = 64, radioTimeout = 60,
        water = { { column = 5, row = 5 } },
    },
    mine = {
        length = 100, height = 3, tunnels = 5, gap = 2,
        fuelTarget = 2000, radioTimeout = 60, freeSlots = 2, digRetries = 16,
        protectedBlocks = {
            "minecraft:bedrock", "minecraft:chest", "minecraft:trapped_chest",
            "minecraft:barrel", "minecraft:ender_chest", "minecraft:hopper",
            "minecraft:spawner", "minecraft:furnace", "minecraft:blast_furnace", "minecraft:smoker",
        },
    },
}
