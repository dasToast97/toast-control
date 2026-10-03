# Toast Control 3.0

Farm-, Mining-, Holz- und Mob-Turtles, Zentrale, Pocket und Infoscreens für CC:Tweaked (Minecraft Fabric 1.20.1).

## Installieren / Updaten

Auf jedem Gerät (zuerst auf der Zentrale) ausführen:

```
wget run https://raw.githubusercontent.com/dasToast97/toast-control/main/install.lua
```

- **1 Update:** löscht alles Alte, behält Config und Turtle-Fortschritt.
- **2 Komplett neu:** löscht ALLES (mit `LOESCHEN` bestätigen). Turtle vorher an die Basis stellen.
- Stationärer Computer: Auswahl **1 Zentrale / 2 Repeater / 3 Infoscreen** (ohne Monitor ist Repeater vorgewählt).
- Turtle: Auswahl **1 Farm / 2 Mining / 3 Holz / 4 Mobs** (Mobfarm, Wache oder Wächter im Gelände).
- Direkt: `... install.lua clean`, `... install.lua farm|mining|tree|mob|repeater`

## Bedienung (Pocket / Zentrale)

Antippen oder Tasten: **↑↓** Turtle wählen · **Enter** Details · **←** zurück ·
**Tab / ←→** Reiter · **S** Start · **X** Stop · **E** 1x · **R** Reset (2x) ·
**H** Hilfe · **Q** beenden.

Einstellungen später ändern: auf dem Gerät `toast.lua config` eingeben.

`install.lua` enthält alle Programme – es wird nichts weiter heruntergeladen.
Quelltexte liegen in `src/`, die Simulationstests in `tests/`. Änderungen: siehe `AENDERUNGEN.md`.
