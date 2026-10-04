# Toast Control 3.9

## Aufgabe einer Turtle wechseln (z.B. Mine -> Mobs)

- An der Turtle **N** drücken (gestoppt, an der Basis) oder `toast.lua config`
  -> letzter Menüpunkt **Aufgabe** -> neue Aufgabe wählen (Farm, Mine, Holz,
  Mobs, Aushub) -> Werte der neuen Aufgabe prüfen -> Enter.
- Kein Neuinstallieren nötig: Jede Turtle hat jetzt alle Programme an Bord.
- Name, Zentrale und Basis bleiben; der Fortschritt der alten Aufgabe wird
  gelöscht (Turtle muss an der Basis stehen). Passendes Werkzeug einlegen
  (Hacke / Spitzhacke / Axt / Schwert) – die Turtle legt es selbst an.
- Die Zentrale ordnet die Turtle automatisch dem neuen Reiter zu.

# Toast Control 3.8.2

- **Chunkloader-Turtles haben das Modem an, sobald sie nicht abbauen.** Nach zwei
  Schritten ohne Abbau (z.B. Heimweg, Fahrt durch fertige Gänge, Feld ohne reife
  Pflanzen) wird das Endermodem angelegt; die Spitzhacke/Hacke kommt erst beim
  nächsten Abbau automatisch zurück. Die Zentrale sieht die Turtle dadurch auch
  auf langen Wegen durchgehend (Mine und Farm).

# Toast Control 3.8.1

- **Fehler behoben: falsches „Funkverbindung verloren“ mit Chunkloader.**
  Mit Chunkloader + Werkzeug legt die Turtle ihr Modem nur kurz an (alle 10 s
  ein Funkfenster). Bei langen Wegen (z.B. Heimweg aus einer langen Mine) gab es
  über 60 s kein Fenster – die Turtle hielt das fälschlich für Funkverlust.
  Jetzt zählen nur Funkfenster, in denen die Zentrale nicht antwortet
  (Mine und Farm).

# Toast Control 3.8

## Aushub: Wände, Boden und Decke verkleiden

- Neue Einstellung **Wandblock** (z.B. `stone_bricks`, `glass`, `deepslate_tiles`):
  Die Turtle baut beim Aushöhlen alle Außenflächen der Form aus diesem Block –
  einzeln wählbar **Wände**, **Boden**, **Decke**. Vorhandenes Gestein an der
  Wand wird dafür abgebaut und ersetzt; Luft, Wasser und Lava werden gefüllt.
- Den Block legt man in die **Kiste OBEN** (zur Kohle). Die Turtle nimmt bis zu
  256 Stück mit; was nicht passt (z.B. Erde), legt sie zurück.
- Gehen die Blöcke aus, holt sie Nachschub und macht genau dort weiter. Ist die
  Kiste leer, wartet sie an der Basis mit der Meldung „Wandblock fehlt“.
- Kisten, geschonte Erze und Grundgestein in der Wand bleiben stehen.
- Zentrale/Pocket zeigen Wandblock-Vorrat und verkleidete Flächen.

# Toast Control 3.7.1

- **Infoscreen kann das Lager zeigen:** Menü „Anzeige“ -> 7 Lager (Kisten).
  Zeigt alle Lager mit Füllstand; Monitor antippen schaltet zwischen
  **Kisten** und **Inhalt**, ein Item antippen zeigt, wo es liegt.
- Infoscreen-Auswahl jetzt auch „Alle Aushub-Turtles“.

# Toast Control 3.7

## Neu: Lager (Kistenüberwachung)

Neue Rolle für stationäre Computer: **5 Lager**. Der Computer liest alle Kisten,
Fässer, Shulker usw. aus, die direkt an ihm stehen oder per **Netzwerkkabel +
Kabelmodem** angeschlossen sind (Modem rechtsklicken = verbunden).

- **Kisten:** Füllstand je Kiste und gesamt mit Balken. Orange = fast voll
  (einstellbar, Standard ab 90 %), Rot = voll. Stapelgrößen werden beachtet
  (16 Enderperlen = voller Slot).
- **Inhalt:** alle Items zusammengezählt, meiste oben. **Suche** per Tastatur:
  einfach lostippen (z.B. `dia`). Item antippen = **in welchen Kisten es liegt**.
- Anzeige auf dem eigenen Monitor und am Computer. In **Zentrale und Pocket**
  gibt es dafür den Reiter **Lager** (alle Lager zusammen).
- Eigene Namen für Kisten im Menü `toast.lua config` -> Lager.
- Läuft auch als GPS-Sender mit und wird beim Update mit aktualisiert.

# Toast Control 3.6.5

- Normale Arbeit wie „Graebt“ oder „Sucht Baeume“ wird nicht mehr orange als
  **Problem** angezeigt. Orange nur noch bei echten Problemen (Kiste voll,
  Treibstoff fehlt, kein Füllmaterial, Weg blockiert …).
- Pocket: Reiter mit Kurznamen und Anzahl (`F1 M3 H1 A1`), damit sie lesbar bleiben.

# Toast Control 3.6.4

- Updates laden die Datei jetzt über die **Commit-Kennung** (fester Link) statt
  über `main`. Damit liefert GitHub nie mehr eine alte Datei aus dem
  Zwischenspeicher. Klappt das nicht, wird der normale Link genommen.
- Ein Gerät stuft sich nie mehr auf eine ältere Version zurück.

# Toast Control 3.6.3

- **Fehler behoben:** Farm-Turtles mit 3.6.1/3.6.2 stürzten beim Update-Befehl ab
  (`farm_turtle.lua:580: attempt to index global 'b'`). Betroffene Farmen einmal
  von Hand aktualisieren: `wget run https://raw.githubusercontent.com/dasToast97/toast-control/main/install.lua auto`
- Neuer Test: Update-Befehl an jede Turtle-Art (Farm, Mine, Holz, Mobs, Aushub).

# Toast Control 3.6.2

- Zentrale/Infoscreen/Repeater ohne GPS-Position: klarer Hinweis am Computer,
  wie man die Koordinaten von Hand einträgt (`toast.lua config` -> GPS).

# Toast Control 3.6.1

- **Uhr oben rechts** überall: Zentrale, Pocket, Infoscreen-Übersicht und
  Infoscreen-Detailseite einer Turtle. Auf dem Pocket kürzer („5/6 14:05“).
- Update sicherer: Die Zentrale schickt die erwartete Version mit. Liefert
  GitHub kurz nach einem neuen Stand noch die alte Datei aus dem Zwischenspeicher,
  lädt das Gerät bis zu 3x nach und installiert die alte Version nicht.
  Nachzügler werden von der Zentrale automatisch nochmal angestoßen.

# Toast Control 3.6

## Neu in 3.6: Aushub-Turtle (Räume, Schächte, Kugeln …)

Neue Aufgabe **5 Aushub** (Spitzhacke). Hebt eine Form direkt **vor** der Basis aus:

- **Formen:** Quader (Raum oder Schacht, z.B. 3 x 3 x 60), Zylinder (runder
  Schacht/Turm), Kugel, Halbkugel (nach oben = Kuppel, nach unten = Schale).
- **Richtung:** nach **unten** (Grube, Schacht) oder nach **oben** (Halle, Kuppel).
- **Wände zubauen:** aus / nur Wasser und Lava / alles dicht (auch Höhlen und
  Löcher). Nimmt dafür Bruchstein, Erde, Netherrack usw. aus dem Abbau
  (64 davon werden beim Abladen behalten).
- **Unter Wasser / in Lava:** „Raum trockenlegen“ entfernt Wasser und Lava im
  Raum (Block reinsetzen, wieder abbauen). Zusammen mit „Wände zubauen“ bleibt
  der Raum trocken.
- **Erze schonen:** alle Erze oder nur bestimmte (z.B. `diamond,emerald`)
  bleiben stehen; die Turtle gräbt drumherum. Später von Hand mit Glück-Spitzhacke
  abbauen. Grundgestein usw. wird ebenso umgangen.
- Volles Inventar: fährt durch den fertigen Teil zur Basis, lädt ab, tankt und
  macht genau dort weiter. Gefundene Kohle wird auf Wunsch direkt verbrannt.
- Nach Absturz/Neustart macht sie dort weiter, wo sie war.
- Zentrale/Pocket: eigener Reiter **Aushub** mit Fortschrittsbalken, Form,
  stehen gelassenen Erzen, zugebauten Stellen und Füllmaterial.

# Toast Control 3.5

## Neu in 3.5: Rückmeldung nach dem Update

- Jedes Gerät meldet nach dem Neustart seine **Version** an die Zentrale
  (Turtles im Status, Pockets/Infoscreens beim Anmelden, Repeater und
  GPS-Sender im 10-s-Signal).
- Die Zentrale zeigt den Fortschritt live: „Update: 4/6 fertig (v3.5)“.
- Sobald **alle** die neue Version melden, aktualisiert sich die Zentrale
  sofort selbst – kein pauschales Warten mehr. Höchstens 3 Minuten, falls
  ein Gerät hängt.
- Nachzügler (waren offline, kommen später zurück) mit älterer Version
  bekommen ihr Update automatisch einzeln nachgereicht.

## 3.4.1
- `… install.lua auto` auf einem **neuen** Gerät (ohne Config) startet jetzt die
  normale Einrichtung mit Fragen, statt mit Fehler abzubrechen.
- `wget run <link> auto` von Hand: installiert ohne Fragen **und startet Toast
  danach wieder** (vorher blieb das Gerät nach dem Update an der Eingabe stehen).

## Neu in 3.4: Repeater und GPS-Sender im Netz

- Neuer Reiter **Netz** in Zentrale und Pocket: alle Repeater, GPS-Sender,
  Infoscreens und Pockets mit Online-Status, **Koordinaten** und **Version**.
  Antippen zeigt Details (GPS-Anfragen, weitergeleitete Nachrichten).
- Repeater und GPS-Sender melden sich alle 10 s selbst bei der Zentrale
  (keine Einstellung nötig) und werden beim **Update** (Knopf oder automatisch)
  mit aktualisiert.
- Ihre Position kommt aus den eingetragenen GPS-Koordinaten oder per GPS.
- Knöpfe wieder **eckig** (die runden Enden sahen im Spiel ausgefranst aus),
  schlicht einfarbig mit Abstand dazwischen.


## Neu in 3.3: Automatische Updates und GPS auf jedem Computer

**Automatisches Update** (Zentrale, `autoUpdate`, Standard an; Menü „Geraete“):
Die Zentrale schaut alle 5 Minuten auf GitHub nach (kleine Datei
`version.txt`, ohne die Anzeige zu blockieren). Gibt es eine neuere Version,
startet sie das Update für alle Geräte – genau wie der Update-Knopf. Turtles
machen danach dort weiter, wo sie waren.

**GPS nebenbei**: Zentrale, Infoscreens und Repeater beantworten GPS-Anfragen
mit – so braucht man weniger eigene GPS-Computer (insgesamt mind. 4 Sender,
nicht alle auf derselben Höhe).
- Koordinaten: beim Start selbst per GPS (wenn schon 4 andere laufen) oder im
  Menü unter **GPS** eintragen (F3 auf den Computer, „Targeted Block“).
- Abschaltbar im selben Menüpunkt.


## Neu in 3.2: Update für alle Geräte per Knopf

Oben in der Zentrale (und auf dem Pocket) gibt es den Knopf **Update**
(Taste **U**). Zweimal tippen (Sicherheitsabfrage), dann:
1. Alle Turtles, Pockets und Infoscreens laden sich die neue Version selbst
   von GitHub und installieren sie **ohne Fragen** – Config, Fortschritt und
   Autostart bleiben.
2. Turtles machen das an einem **sicheren Punkt zwischen zwei Schritten**,
   starten neu und **arbeiten genau dort weiter**, wo sie waren (Position und
   Auftrag sind gespeichert). Sie müssen dafür nicht zur Basis.
3. Offline-Turtles bekommen den Befehl, sobald sie sich innerhalb von 3 Minuten melden.
4. Zum Schluss aktualisiert sich die Zentrale selbst.
- In den Details steht die **Version** jedes Geräts (mit Hinweis, wenn sie
  älter als die der Zentrale ist).
- Voraussetzung: HTTP ist im Spiel/Server erlaubt (Standard bei CC:Tweaked).
- Repeater und GPS-Sender sind nicht dabei (die haben keinen Funkkanal zur
  Zentrale) – dort bei Bedarf den Installer von Hand ausführen.
- Von Hand ohne Fragen: `wget run <link> auto`.


## Update 3.1.3: Knöpfe schlicht und modern

- **Runde Knöpfe** (abgerundete Enden), eine Zeile hoch, mit Abstand dazwischen.
- Beschriftung schlicht: Start / Stopp / Einmal (bzw. 1 Runde, 1 Gang).
- **Reiter**: nur der aktive ist hinterlegt, die anderen als ruhiger Text.
- **Nur was geht, ist aktiv**: STARTEN ist grau, wenn alle Ziele schon laufen;
  STOPPEN ist grau, wenn nichts läuft.
- **Reset** als dezenter grauer Knopf in der Mitte: „Fehler loeschen + heim“
  (orange Schrift, wenn es Fehler gibt) oder „Reset (Stopp + heim)“.
  Weiterhin mit Sicherheitsabfrage.
- Detailansicht: runder „← Zurueck  Name“-Knopf oben.
- Meldungen verständlicher: „Start an 3 Turtles gesendet …“, „Befehl bestätigt“,
  „Keine Antwort von 1 Turtle (Funk/Chunk?)“.

## Update 3.1.2: GPS-Sender per Installer

Stationärer Computer im Installer: **4 GPS-Sender**.
- Mit Funk- oder (besser) Endermodem. Man braucht **mindestens 4**, die nicht
  alle auf derselben Höhe/Ebene stehen (z. B. einer 4 Blöcke höher).
- **Koordinaten**: Laufen schon 4 andere GPS-Sender, findet er seine Position
  selbst (wird angeboten). Für die ersten 4 geht das nicht – dann F3 auf den
  Computer, „Targeted Block“ X Y Z eintragen. Änderbar mit `toast.lua config`.
- Bildschirm zeigt Position und wie viele Anfragen beantwortet wurden.
- Autostart wie bei allen Toast-Geräten.

## Update 3.1.1: GPS jede Sekunde, Dimension

- **Koordinaten live (jede Sekunde)**: Nach zwei GPS-Messungen an verschiedenen
  Stellen kennt die Turtle ihre Basis und Blickrichtung selbst. Danach rechnet
  sie die Koordinaten bei jeder Statusmeldung (jede Sekunde) aus ihrer eigenen
  Bewegung – ohne Funkverzögerung, auch wenn das Modem gerade gegen die
  Spitzhacke getauscht ist. GPS prüft alle 10 s nach; wurde die Turtle von Hand
  versetzt, kalibriert sie sich neu. Unter „Basis“ muss dafür nichts eingetragen sein.
- **Dimension** in den Details: wird an den Blöcken um die Turtle erkannt
  (Netherrack = Nether, Endstein = End, Stein/Erde = Oberwelt). Zusätzlich im
  Menü unter „Basis“ einstellbar (Standard: automatisch). Weicht die Erkennung
  vom Eintrag ab, steht beides da.

## Update 3.1: Neuer Auftrag ohne Neuinstallation, Position jeder Turtle

**Neuer Auftrag** (z. B. Mine fertig, neue Maße) – drei Wege, nichts löschen:
1. An der Turtle **N** drücken (wenn sie gestoppt/fertig an der Basis steht):
   das Einstellungsmenü öffnet sich, Werte ändern, **Enter = Auftrag starten**.
   Alter Fortschritt wird gelöscht, Config und Programme bleiben.
2. `toast.lua neu` eingeben – dasselbe.
3. Im Installer gibt es auf Turtles die Option **3 Neuer Auftrag**.

**Wo ist meine Turtle?** In den Details (Zentrale, Pocket, Infoscreen):
- **Position**: z. B. „12 vor 3 li 5 hoch“ – von der Basis aus gesehen.
- **Koordinaten**: echte Weltkoordinaten, wenn
  - im Menü unter **Basis** die F3-Koordinaten der Turtle an der Basis und
    ihre Blickrichtung eingetragen sind, oder
  - im Spiel GPS-Computer stehen (dann mit „GPS“ markiert, wird automatisch genutzt).

## Update 3.0.4: Mob-Turtles nur nachts, Holzfäller dreht sich nicht mehr im Kreis

- **Nur nachts** (`mob.nightOnly`, Menü „Mobs“ → „Nur nachts?“): Tagsüber
  (Spielzeit 5:30 bis 18:30) macht die Mob-Turtle Pause („Tagpause“). Der
  Wächter fährt dafür zur Basis und lädt ab, Wache und Mobfarm bleiben an
  ihrer Stelle. Sobald es dunkel wird, geht es von selbst weiter.
- **Holzfäller nach Fehler**: drehte sich an der Basis ständig zur hinteren
  Kiste und zurück (Setzlinge nachsehen). Im Leerlauf wird jetzt nur noch
  abgeladen; Tanken und Setzlinge holen passiert erst beim nächsten START.

## Update 3.0.3: Holzfäller im Gelände, Bäume stehen beliebig

Die Holzfarm mit fester Baumreihe ist durch den **Holzfäller** ersetzt:
- Gebiet vor der Basis (Länge x Breite, rechts/links). Die Turtle fährt es in
  Bahnen ab (alle 3 Blöcke) und schaut an jedem Feld links und rechts nach
  Bäumen – die Bäume dürfen **irgendwo** stehen.
- **Gelände** wie beim Wächter: klettert über Hügel (bis „max. Höhe“),
  steigt in Senken, gräbt sich durch Blätterdächer nach unten, baut sonst
  **nur Holz und Blätter** ab (Mauern, Häuser usw. bleiben stehen).
- Bäume werden komplett gefällt – auch wenn der Stamm tiefer oder höher
  anfängt als die Turtle steht. Danach pflanzt sie (wenn eingeschaltet) einen
  Setzling auf den Boden unter dem Stamm.
- Inventar voll oder Fuel knapp: über die eigene Spur zur Basis, abladen,
  tanken, zurück und an derselben Stelle weitermachen.
- Absturz mitten im Stamm: nach Neustart wird der Rest gefällt.
- Wächter und Holzfäller nutzen jetzt dieselbe Gelände-Steuerung.

## Update 3.0.2: Mining holt Kisten und Fackeln aus der oberen Kiste

Die **obere Kiste** an der Basis ist jetzt die Nachschubkiste für alles:
Kohle, Kisten und Fackeln dürfen gemischt drin liegen (auch anderes stört
nicht mehr). Die Turtle holt sich bei jedem Basisbesuch:
- Fuel bis „an der Basis bis hierhin tanken“,
- je **1 Stapel Kisten** (wenn „Kisten unterwegs“ an) und **1 Stapel Fackeln**
  (wenn Fackeln an),
- und legt alles andere wieder zurück.

## Update 3.0.1: Wächter fährt im Gelände zufällig umher

Die bisherige „Patrouille“ (nur außen im Rechteck, nur auf glattem Boden) ist
durch den **Wächter** ersetzt:
- Fährt im Gebiet (Länge x Breite ab der Basis) **zufällige Ziele** an, nicht
  nur den Rand. An jedem Ziel schaut er sich in alle Richtungen um.
- **Gelände**: klettert über Hügel und Mauern (bis „max. Höhe“, Standard 8),
  steigt in Senken und Gräben ab, bleibt am Boden. Zu hohe Hindernisse und
  unerreichbare Stellen merkt er sich und umfährt sie. Baut **nie** etwas ab.
- Fährt so lange, bis das Fuel **fast leer** ist, dann zurück zur Basis:
  tanken (Kiste oben), Drops abladen (Kiste unten), kurze Pause, weiter.
  1x = eine Tankfüllung. Je mehr er tankt („Tanken bis“), desto länger bleibt er draußen.
- Der Heimweg läuft seine eigene Spur rückwärts (Schleifen gekürzt) – der Weg
  ist sicher frei und er weiß genau, wie viel Fuel er dafür braucht.
  Klappt das nicht (z. B. neuer Block im Weg), sucht er sich einen Weg.
- Nach Absturz/Serverneustart findet er über die gespeicherte Spur heim.
- Fortschrittsbalken = verbrauchter Tank bis zur nächsten Rückkehr.

## Neu in 3.0: Holzfarm, Mob-Turtles, Kisten und Fackeln beim Minen

Im Installer gibt es jetzt vier Aufgaben: **1 Farm, 2 Mining, 3 Holz, 4 Mobs**.
Alle erscheinen in Zentrale, Pocket und Infoscreens (eigener Reiter, eigene
Kachel, eigene Detailwerte) und hören auf START / STOP / 1x / RESET.

### Holzfarm (Axt) – ab 3.0.3 als Holzfäller im Gelände (siehe oben)
Erste Version: Fahrspur nach vorne, Bäume daneben.
- Gewachsene Bäume werden komplett gefällt (Stamm bis „max. Höhe“), sofort
  wird ein neuer Setzling gesetzt. Leere Plätze werden bepflanzt.
- Optional Knochenmehl: direkt nach dem Pflanzen, wächst der Baum, wird er
  gleich gefällt.
- Liegende Setzlinge/Äpfel auf der Spur sammelt sie ein. Blätter im Weg
  räumt sie weg – andere Blöcke baut sie **nie** ab (Fehler „Weg blockiert“).
- Basis: Kiste **unten** = Holz, Kiste **oben** = Kohle, Kiste **hinten** =
  Setzlinge (+ Knochenmehl). Setzlinge behält sie selbst (Standard 32).
- Kein Fuel mehr in der Kiste: verbrennt im Notfall eigenes Holz.
- Absturz mitten im Stamm: nach Neustart wird der Stamm fertig gefällt.
- Am besten Birke oder Fichte (1x1). Eiche geht, Äste bleiben hängen.

### Mobs (Schwert) – drei Arten
- **Mobfarm**: steht an der Tötungsstelle, schlägt zu, sammelt Drops und
  liefert sie in die Kiste **unter** sich. Braucht kein Fuel.
- **Wache**: steht an einer Stelle (Tor, Gang) und wehrt alles ab, was davor
  steht. 1x = bis 8 s Ruhe ist.
- **Wächter** (siehe 3.0.1): fährt im Gebiet zufällig umher, folgt dem
  Gelände und greift an, was im Weg steht. Basis: unten Drops, oben Kohle.
- Optional auch oben/unten angreifen.
- Achtung: Eine Turtle kann Mobs und Spieler **nicht** unterscheiden.
  Die Patrouille wartet erst kurz, bevor sie zuschlägt.
- Standard: läuft auch ohne Funkkontakt weiter (radioTimeout 0).

### Mining: Kisten unterwegs und Fackeln (beides optional)
- **Kisten unterwegs** (`mine.placeChests`): Kisten ins Turtle-Inventar legen.
  Ist das Inventar voll, setzt sie eine Kiste in den Boden unter der
  untersten Reihe (dort wird nie gegraben) und lädt hinein – kein Heimweg.
  In hohen Gängen fährt sie dafür kurz in der freien Spalte nach unten.
  Sind keine Kisten mehr da, fährt sie wie bisher zur Basis.
- **Fackeln** (`mine.torches` = Abstand, 0 = aus): Fackeln ins Inventar legen.
  Alle x Blöcke eine Fackel auf den Boden der untersten Reihe (ab Ganghöhe 3).
- Kisten und Fackeln werden an der Basis nicht abgeladen. In den Details:
  „Kisten 2 gesetzt, 5 dabei“, „Fackeln 12 gesetzt, 20 dabei“.

## Neu: Kohle als Fuel (Mine) und Saatgut automatisch (Farm)

**Mine – gefundene Kohle direkt verbrennen** (`mine.useCoal`, Standard: an).
Im Menü unter „Mine“: „Gefundene Kohle als Fuel nutzen?“.
- An: Baut die Turtle Kohleerz ab, wandert die Kohle sofort in den Tank,
  solange er Platz hat (max. 20.000 Fuel). Spart Fahrten zur Brennstoffkiste.
  Übrige Kohle wird vor dem Abladen ebenfalls verbrannt.
- Aus: Kohle landet wie bisher in der Ausgabekiste.
- In den Details steht „Kohle verbrannt“ mit der Menge.

**Farm – Saatgut aus der Ernte behalten** (`farm.seedReserve`, Standard jetzt 0 = auto).
Geerntetes Saatgut wird direkt wieder gepflanzt. Beim Abladen behält die
Turtle automatisch so viel, wie das Feld Pflanzstellen hat (mind. 16,
max. 192); nur der Rest kommt in die Kiste. Die Saatgutkiste hinten braucht
es nur noch, wenn die Turtle gar kein Saatgut mehr hat. Eigener Wert
(1–256) weiterhin im Menü unter „Feld“ möglich.

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
- **Grüne Fortschrittsbalken** vor den Prozentangaben in der Hauptübersicht
  der Zentrale (ab 3x4) und der Infoscreens (Turtle-Liste und „Fortschritt“
  der Mine-Kachel). Breite passt sich dem Bildschirm an. Die Balken füllen nur
  die oberen 2/3 der Zeile, so berühren sich Balken untereinander nicht; der
  leere Teil ist dunkelgrau (fast schwarz) statt hellgrau.
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
