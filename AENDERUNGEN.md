# Toast Control 2.3 – Stabilität, Reset, sparsamer Fahrweg & eigene Maße

## Neu in 2.3: Maße beim Installieren einstellen

Auf einer Turtle fragt der Installer nach der Aufgabe gleich die passenden Maße ab
(Enter = Wert in Klammern behalten). Die Turtle steht dabei an ihrer Basis und
schaut nach vorne aufs Feld bzw. in die Mine.

- **Farm:** Länge nach vorne, Breite zur Seite (je 1–32, z. B. 10 × 4),
  Seite rechts/links, Pflanze, Pause zwischen Runden.
- **Wasser muss nicht eingetragen werden:** einzelne Stellen, ganze Reihen oder
  gar kein Wasser – die Turtle erkennt es selbst und überspringt es.
- **Mining:** Ganglänge, Höhe (1–5), Anzahl Gänge, Abstand, Seite rechts/links.
- Beim Update: „Maße ändern? (j/n)“. Neue Minenmaße starten einen neuen Auftrag
  (Turtle muss an der Basis stehen).

Später ändern: Installer erneut ausführen oder `edit /toast.config.lua`
(`farm.width/length/side`, `mine.length/height/tunnels/gap/side`).

## Neu in 2.2: Energiesparender Mining-Fahrweg

## Neu in 2.2: Energiesparender Mining-Fahrweg

- **Oben/unten beim Vorwärtsfahren mit abbauen:** Bei Höhe 3 fährt die Turtle in
  der mittleren Reihe und baut Block darüber und darunter direkt mit ab –
  1 Fuel pro Gangblock statt hoch- und runterzufahren.
- **Schlangenlinie:** Gang 1 hin, am Ende hinüber, Gang 2 zurück. Keine leeren
  Rückwege durch fertige Gänge mehr.
- **Höhe 4–5:** Hinweg unten, Rückweg oben – der nötige Rückweg baut gleich mit ab.
- **Heimfahrt nur wenn nötig** (Inventar voll / Fuel knapp), nicht mehr nach jedem Gang.
  Danach fährt sie auf kürzestem Weg zurück an die Stelle, wo sie aufgehört hat.

Gemessen in der Simulation (4 Gänge à 20, Abstand 2):

| Höhe | alter Fahrweg | neuer Fahrweg | Ersparnis |
|---|---|---|---|
| 1 | 196 Fuel | 96 Fuel | 51 % |
| 2 | 368 Fuel | 96 Fuel | 74 % |
| 3 | 540 Fuel | 98 Fuel | 82 % |
| 4 | 712 Fuel | 182 Fuel | 74 % |
| 5 | 884 Fuel | 190 Fuel | 79 % |

Laufende Aufträge werden übernommen: fertige Gänge bleiben fertig, ein
angefangener Gang wird vom Anfang an neu befahren (dort ist schon frei).

## Seit 2.1

Installieren / Updaten auf jedem Gerät (Config und Fortschritt bleiben erhalten):

    wget run https://raw.githubusercontent.com/dasToast97/toast-control/main/install.lua

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
