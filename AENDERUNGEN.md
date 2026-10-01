# Toast Control 2.1 – Stabilität & Reset

Diese Dateien auf deinem Server (`/control/`) ersetzen, danach auf jedem Gerät
den Installer erneut ausführen (Config und Fortschritt bleiben erhalten):

    wget run https://toast-farm-cc-0930.eismann-db.chatgpt.site/control/install.lua

Geänderte Dateien: toast.lua, toast_common.lua, toast_control.lua, toast_model.lua,
toast_ui.lua, toast_pocket.lua, farm_turtle.lua, mine_turtle.lua, toast.config.lua, install.lua.
Unverändert: farm_common.lua, mine_common.lua, repeater.lua.

## Neu

**RESET-Knopf** (Zentrale + Pocket, Taste `4`): löscht Fehler, Turtle fährt heim
und lädt ab. Danach mit START weitermachen. Wirkt auf Gruppe oder einzelne Turtle.

**Automatischer Neustart:** Stürzt ein Programm ab, startet `toast.lua` es nach
5 s neu (max. 5× in 10 min). Fehler stehen in `/toast/fehler.log`.
Taste drücken während des Countdowns = Neustart abbrechen.

**Auftrag läuft nach Server-/Chunk-Neustart weiter.** Lief die Turtle vorher,
setzt sie den Auftrag selbst fort. STOP, Q, RESET, `--dock` und `--new` heben das auf.

**Weniger „Position unklar“:** Wird die Turtle mitten in einer Bewegung
unterbrochen, prüft sie am Fuelstand, ob der Schritt passiert ist, und rechnet
die Position selbst richtig. `--dock` ist nur noch nach einer unterbrochenen
Drehung oder bei Turtles mit unbegrenztem Fuel nötig.

**Auto-Retry:** Bei behebbaren Fehlern (Weg blockiert, Funkverlust, Kies usw.)
versucht es die Turtle nach 30 s erneut, bis zu 3×. Bei Bedrock und
geschützten Blöcken nie – dort bleibt sie stehen, bis du RESET drückst.

**Mobs im Weg:** Turtle greift an, wartet kurz und versucht es bis zu 8× erneut,
statt sofort mit Fehler stehenzubleiben.

**Mining baut alles ab:** Wasser und Lava werden einfach durchfahren (Turtles
nehmen keinen Schaden). Kisten, Öfen, Spawner usw. werden mit abgebaut. Nicht
abgebaut werden nur unzerstörbare Blöcke (Bedrock, Barriere, Portale) und
andere Turtles. Eigene Ausnahmen: `mine.protectedBlocks` in der Config.
Beim Update wird die alte Standard-Schutzliste automatisch geleert.

**Spitzhacke wird selbst angelegt:** Fehlt das Werkzeug („No tool to dig with“),
zeigt die Turtle „Keine Spitzhacke“. Liegt eine Diamant-Spitzhacke im Inventar,
legt sie sie selbst an (auf der Seite ohne Modem) und arbeitet weiter.
Die Spitzhacke wird nie in die Kiste abgeladen.

## Behoben

- Halb geschriebene Zustandsdatei (`.tmp`) nach Absturz blockierte den Start
  („Zustand beschädigt“). Jetzt wird die letzte gute Datei genommen.
- Zentrale lagte bei vielen Turtles: jede Statusmeldung zeichnete den ganzen
  Monitor neu. Jetzt höchstens 4× pro Sekunde.
- Monitor abgebaut / Chunk entladen → Zentrale stürzte ab. Jetzt Wechsel auf
  den Computerbildschirm, neuer Monitor wird automatisch übernommen.
- Zentrale-Absturz schickte STOP an alle Turtles. Jetzt nur noch beim
  bewussten Beenden (Q / Ctrl+T) – dann aber mehrfach gesendet.
- Installer legte bei jedem Update neue `.backup2`, `.backup3`… an und füllte
  die Festplatte. Jetzt genau eine Sicherung je Datei; 3 Download-Versuche.
- Turtles funkten alle 0,5 s zusätzlich zum Poll → jetzt alle 2 s (weniger Last
  für Repeater und Zentrale).
- Farm: ein Feld ohne Acker (Weg, Erde) brach die ganze Runde ab. Jetzt wird
  es übersprungen und im Status gezählt.
- Mining tankt jetzt in einem Zug statt Kohle für Kohle, nimmt auch
  Kohleblöcke und legt Überschuss zurück in die Kohlekiste (nicht ins Lager).
- Falsches Item in Kohle-/Saatgutkiste wird zurückgelegt statt im Inventar zu bleiben.

## Config (optional, `edit /toast.config.lua`)

Fehlt der Block, gelten diese Standardwerte:

    recovery = {
        autoRestart = true, restartDelay = 5, maxRestarts = 5,
        autoRetry = 3, retryDelay = 30, moveRetries = 8,
    },

## Geprüft

Lua-Simulation mit nachgebauter CraftOS-Umgebung (Welt, Dateisystem, Timer, Funk):
normaler Abbau, Absturz mitten im Schritt + Neustart + Fortsetzen, Mob kurz und
lange im Weg, Lava/Wasser/Kiste durchfahren, Bedrock + RESET, andere Turtle geschützt, Funkverlust + automatisches Weitermachen, kaputte
.tmp-Datei, STOP, Farmrunde mit Absturz; Zentrale-Modell + Anzeige in 4 Größen.
Kein Test in einer echten Minecraft-Welt – nach dem Update zuerst 1 GANG / 1 RUNDE.
