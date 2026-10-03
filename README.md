# Toast Control 3.4

Farm-, Mining-, Holz- und Mob-Turtles, Zentrale, Pocket und Infoscreens für CC:Tweaked (Minecraft Fabric 1.20.1).

## Installieren / Updaten

Auf jedem Gerät (zuerst auf der Zentrale) ausführen:

```
wget run https://raw.githubusercontent.com/dasToast97/toast-control/main/install.lua
```

- **1 Update:** löscht alles Alte, behält Config und Turtle-Fortschritt.
- **2 Komplett neu:** löscht ALLES (mit `LOESCHEN` bestätigen). Turtle vorher an die Basis stellen.
- Stationärer Computer: Auswahl **1 Zentrale / 2 Repeater / 3 Infoscreen / 4 GPS-Sender** (ohne Monitor ist Repeater vorgewählt).
- Computer: Auswahl **1 Zentrale / 2 Repeater / 3 Infoscreen / 4 GPS-Sender / 5 Lager** (Kisten: Füllstand + Inhalt mit Suche).
- Turtle: Auswahl **1 Farm / 2 Mining / 3 Holz / 4 Mobs / 5 Aushub** (Mobs: Mobfarm, Wache oder Wächter im Gelände; Aushub: Raum, Schacht, Zylinder, Kugel, Halbkugel nach oben oder unten).
- Direkt: `... install.lua clean`, `... install.lua farm|mining|tree|mob|dig|repeater`

## Bedienung (Pocket / Zentrale)

Antippen oder Tasten: **↑↓** Turtle wählen · **Enter** Details · **←** zurück ·
**Tab / ←→** Reiter · **S** Start · **X** Stop · **E** 1x · **R** Reset (2x) ·
**H** Hilfe · **Q** beenden.

**Update für alle**: an der Zentrale oben **Update** (2x tippen) – alle Geräte
aktualisieren sich selbst und machen weiter, wo sie waren. Die Zentrale prüft
außerdem alle 5 min selbst, ob es eine neue Version gibt.

**GPS**: Zentrale, Infoscreens und Repeater arbeiten nebenbei als GPS-Sender
(Koordinaten im Menü unter „GPS“). Zusammen mind. 4 Sender. Alle Netzgeräte (Repeater, GPS-Sender, Infoscreens, Pockets) stehen in der Zentrale im Reiter „Netz“ mit Position und Version.

Neuer Auftrag (z. B. Mine fertig): an der Turtle **N** drücken oder `toast.lua neu`
– neue Werte eingeben, Enter startet. Position jeder Turtle steht in den Details
(mit echten Koordinaten, wenn unter „Basis“ eingetragen oder GPS vorhanden).

Einstellungen später ändern: auf dem Gerät `toast.lua config` eingeben.

`install.lua` enthält alle Programme – es wird nichts weiter heruntergeladen.
Quelltexte liegen in `src/`, die Simulationstests in `tests/`. Änderungen: siehe `AENDERUNGEN.md`.
