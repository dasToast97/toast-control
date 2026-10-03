# Toast Control 2.9

## Neu in 2.9 – Bedienung mit Tastatur (Pocket in der Hand, Zentrale)

Pocket und Zentrale lassen sich komplett mit den Tasten steuern, Antippen
geht weiterhin. Die gewählte Turtle ist grau hinterlegt mit ►.

| Taste | Wirkung |
|---|---|
| ↑ / ↓ (oder Mausrad) | Turtle wählen – in den Details: vorige/nächste Turtle |
| Enter / Leertaste | Details der gewählten Turtle |
| ← / Backspace | zurück zur Liste |
| ← / → / Tab | in der Liste: Reiter Alle / Farm / Mine |
| Bild ↑ / Bild ↓, Pos1 / Ende | blättern, zum Anfang/Ende |
| S / X / E | Start / Stop / 1 Runde bzw. 1 Gang |
| R | Reset – **zweimal** drücken (Sicherheitsabfrage, 5 s) |
| H oder ? | Hilfe mit allen Tasten |
| Q | beenden |

Die Zahlen 1–4 und A/F/M funktionieren weiter.

- **Reset fragt nach**: erst „SICHER?“, nochmal drücken/tippen = Reset. Auch
  beim Antippen am Monitor.
- **Probleme oben**: Turtles mit Fehler/Problem stehen ganz oben in der Liste,
  dann die arbeitenden, dann der Rest.
- Die Hinweiszeile zeigt die passenden Tasten, an der Zentrale sobald eine
  Taste gedrückt wurde.

## Neu in 2.8

**Neue Oberfläche für Zentrale und Pocket** – passt sich der Bildschirmgröße an:
Kopfzeile mit Verbindung, Reiter Alle / Farm / Mine mit Anzahl, Übersicht je
Gruppe (Farm: Ertrag, Mine: Abgebaut), Liste aller Turtles mit farbigem Punkt
und Zustand in Worten (grün arbeitet, blau Heimweg, türkis wartet, orange
Problem, rot Fehler, grau offline). Antippen zeigt Details mit
Fortschrittsbalken – nur die passenden Werte: Farm = Runden, Geerntet
(Pflanzen), Ertrag (Items), Saatgut; Mine = Gänge, Abgebaut (Blöcke),
Abgeladen (Items), freie Slots. „Beute“ gibt es nicht mehr.

**Infoscreens** – eigene Station (Computer + Monitor(e)), irgendwo aufgebaut,
nur Anzeige, keine Steuerung. Im Installer „3 Infoscreen“, unter „Anzeige“
wählen, was er zeigt (`show` in der Config):
- `"all"` / `"farm"` / `"mining"`: Übersicht der Kategorie mit Kacheln,
  „pro Stunde“-Werten, Problemliste und allen Turtles (blättert selbst).
- Turtle-ID, z. B. `12`: große Detailseite dieser einen Turtle (Zustand,
  Fortschritt, alle Werte, pro Stunde).

**Monitorgröße in Blöcken:** `display.size = "3x4"` (Höhe x Breite, Standard
3x4, max 6x8, oder `"auto"`). Die Schrift wird so gewählt, dass alles passt –
z. B. 3x4 → 39 x 19 Zeichen, 4x8 → 82 x 26. Einstellbar im Menü unter „Monitor“.

## Neu in 2.7

**Neues Einstellungsmenü** – im Installer und jederzeit mit `toast.lua config`:
eine Übersicht mit Nummern (Name, Zentrale, Mine/Feld, Chunks, Funk bzw.
Monitor/Geräte bei der Zentrale). Nummer = ändern, Enter = weiter/speichern,
q = abbrechen. Passt auch auf den kleinen Turtle-Bildschirm.

**Saubere Config:** `/toast.config.lua` wird geordnet und kommentiert geschrieben
und enthält nur, was das Gerät braucht (Mining-Turtle: Mine, Chunks, Stabilität;
Zentrale: Bildschirm, Geräte, Funk ...). Fehlende Einträge werden mit
Standardwerten ergänzt; alte Configs werden beim Update übernommen und neu
geschrieben.

**Seitlich mitabbauen** (`mine.sideDig = true`, nur bei Abstand 0): Fahrspuren
im Plus-Muster, links/rechts wird durch Drehen mitabgebaut (Drehen kostet kein
Fuel). Die Turtle prüft selbst, ob das bei den Maßen weniger Spuren braucht,
sonst nimmt sie das normale Verfahren. Simulation (Fuel gespart / mehr Aktionen):
Höhe 1: 62 % / +26 %, Höhe 2: 29 % / +39 %, Höhe 3: kein Vorteil,
Höhe 4: 36 % / +35 %, Höhe 6: 11 % / +49 %, Höhe 9–30: 15–29 % / +29–41 %.

**Chunkloader „an der Basis wach“** wird beim Einschalten standardmäßig
vorgeschlagen: sonst schläft eine Turtle an der Basis ein, sobald kein Spieler
in der Nähe ist (z. B. Nether), und hört kein START mehr.

## Neu in 2.6: Rückweg und Hinweg beim Mining neu

**Behoben: Turtle blieb auf dem Rückweg hängen** („Rückweg blockiert / Inventar
voll“). Zwei Ursachen:
- Mit vollem Inventar wurde auf dem Rückweg nichts abgebaut – genau dann fährt
  sie aber zurück. Jetzt räumt sie auf dem Rückweg **immer** frei (passt nichts
  mehr ins Inventar, fällt der Block als Item auf den Boden), wartet länger auf
  nachrutschenden Kies/Sand und wartet, wenn eine andere Turtle im Weg steht.
- Der Rückweg lief immer unten/vorne entlang – bei hohen Gängen (jeder zweite
  Gang wird von oben nach unten abgebaut) mitten durch noch festen Stein.

**Neuer Wegplaner:** Die Turtle weiß, welche Felder schon frei sind (fertige
Schritte, Querwege zwischen den Gängen, alle selbst gefahrenen Strecken) und
vergleicht für Hin- und Rückweg mehrere Wege: durch die fertigen Gänge zurück,
über den vorderen Querweg, oder eine Mischung. Freiräumen kostet kein Fuel,
zählt also kaum; mit fast vollem Inventar bevorzugt sie freie Wege, damit
nichts verloren geht.

Simulation mit schnell vollem Inventar (viele Heimfahrten):

| Mine (Höhe × Länge × Gänge) | 2.5 | 2.6 |
|---|---|---|
| 3 × 30 × 3 | fertig, 798 Fuel | fertig, 806 Fuel |
| 6 × 25 × 3 | **hängt** | fertig, 1.288 Fuel |
| 9 × 20 × 4 | **hängt** | fertig, 1.900 Fuel |
| 20 × 15 × 3 | **hängt** | fertig, 2.758 Fuel |
| 64 × 8 × 3 | **hängt** | fertig, 8.176 Fuel |
| 4 × 30 × 2 | **hängt** | fertig, 704 Fuel |
| Kies im Rückweg + volles Inventar | – | fertig |

Außerdem: Im Leerlauf an der Basis wird der Zustand nicht mehr ständig neu
gespeichert (weniger Festplattenzugriffe).

## Neu in 2.5: Chunks laden mit CCChunkloader

Farm- und Mining-Turtles können mit dem Mod **CCChunkloader** ihren Chunk selbst
geladen halten und arbeiten weiter, auch wenn kein Spieler in der Nähe ist.

**Anbau:** Chunkloader-Upgrade + Werkzeug (Spitzhacke/Hacke) an die Turtle,
das **Funk-/Endermodem ins Inventar**. Die Turtle tauscht Werkzeug und Modem
selbst: zum Abbauen das Werkzeug, alle 10 s kurz das Modem zum Funken, beim
Warten an der Basis dauerhaft das Modem. Werkzeug und Modem werden nie abgeladen.

**Config** (`chunkload` in `/toast.config.lua`, oder beim Installieren abgefragt):

| chunks | geladen | Fuel pro Stunde | Kohle pro Stunde |
|---|---|---|---|
| 1 | nur eigener Chunk (wandert mit) | ~2.400 | ~30 |
| 9 | 3 × 3 | ~47.000 | ~590 |
| 21 | Radius 2,5 | ~176.000 | ~2.200 |

1 Chunk reicht: Er wandert mit der Turtle mit. Geladen wird nur, solange die
Turtle arbeitet, unterwegs ist oder auf einen neuen Versuch wartet – an der
Basis ist er aus (außer `idle = true`). `wakeOnWorldLoad = true`: nach einem
Serverneustart läuft sie von selbst weiter.

**Anzeige:** Zentrale und Pocket zeigen pro Turtle „Chunks 1 -2400/h“ und in der
Übersicht den Gesamtverbrauch. Der Fuelbedarf (Rückweg, Tankziel) rechnet den
Chunkloader mit ein.

**Absturz mitten im Schritt:** Weil der Chunkloader nebenbei Fuel abzieht, prüft
die Mining-Turtle zusätzlich den Block vor sich. Ist es nicht eindeutig, meldet
sie lieber „Position unklar“ (dann `toast.lua --dock`) als falsch weiterzufahren.

## Neu in 2.4: Ganghöhe bis 64

Die Mining-Turtle baut jetzt Gänge bis 64 Blöcke hoch. Sie arbeitet in
Schichten zu je 3 Blöcken: in der Mitte fahren, oben und unten mitabbauen.
Die Schichten sind in Schlangenlinie verbunden (vor, hoch, zurück, hoch ...),
der nächste Gang beginnt oben und arbeitet sich nach unten.

Am sparsamsten sind Vielfache von 3 (3, 6, 9 ... 63): etwa 0,5 Fuel pro
abgebautem Block. Bis Höhe 3 ist der Fahrweg genau wie in 2.2; laufende
Aufträge mit Höhe 4–5 werden übernommen (angefangener Gang wird neu befahren).

## Neu: Weiterarbeiten ohne Zentrale

`farm.radioTimeout = 0` bzw. `mine.radioTimeout = 0` in der Config: Die Turtle
arbeitet weiter, auch wenn die Zentrale nicht erreichbar ist (z. B. weil ihr
Chunk entladen ist). Standard bleibt 60 s (dann Stopp + Heimfahrt).
Hinweis: Endermodems haben unbegrenzte Reichweite, aber Geräte in entladenen
Chunks laufen nicht – dafür Chunks mit `/forceload` geladen halten.

## Neu: Repeater über denselben Link

Auf einem stationären Computer fragt der Installer „1 Zentrale / 2 Repeater“.
Ohne angeschlossenen Monitor ist **Repeater vorgewählt** (einfach Enter).
Ender- und normale Funkmodems werden automatisch genutzt. Ein vorhandener
Repeater bleibt beim Update Repeater (Fehler behoben: seine Config wurde beim
Update fälschlich verworfen).

## Neu in 2.3: Namen und Maße beim Installieren einstellen

**Namen:** In `/toast.config.lua` steht oben `name = "..."`. Der Installer fragt
danach. Der Name erscheint an Zentrale und Pocket und wird auch im Spiel als
Computer-Name gesetzt. An der Zentrale können Namen unter
`devices = { [5] = { job = "farm", name = "Weizen Nord" } }` überschrieben werden.

Auf einer Turtle fragt der Installer nach der Aufgabe gleich die passenden Maße ab
(Enter = Wert in Klammern behalten). Die Turtle steht dabei an ihrer Basis und
schaut nach vorne aufs Feld bzw. in die Mine.

- **Farm:** Länge nach vorne, Breite zur Seite (je 1–32, z. B. 10 × 4),
  Seite rechts/links, Pflanze, Pause zwischen Runden.
- **Wasser muss nicht eingetragen werden:** einzelne Stellen, ganze Reihen oder
  gar kein Wasser – die Turtle erkennt es selbst und überspringt es.
- **Mining:** Ganglänge, Höhe (1–64), Anzahl Gänge, Abstand, Seite rechts/links.
- Beim Update: „Maße ändern? (j/n)“. Neue Minenmaße starten einen neuen Auftrag
  (Turtle muss an der Basis stehen).

Später ändern: Installer erneut ausführen oder `edit /toast.config.lua`
(`farm.width/length/side`, `mine.length/height/tunnels/gap/side`).

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
