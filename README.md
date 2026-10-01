# Toast Control 2.3

Farm- und Mining-Turtles, Zentrale und Pocket für CC:Tweaked (Minecraft Fabric 1.20.1).

## Installieren / Updaten

Auf jedem Gerät (zuerst auf der Zentrale) ausführen:

```
wget run https://raw.githubusercontent.com/dasToast97/toast-control/main/install.lua
```

- **1 Update:** löscht alles Alte, behält Config und Turtle-Fortschritt.
- **2 Komplett neu:** löscht ALLES (mit `LOESCHEN` bestätigen). Turtle vorher an die Basis stellen.
- Stationärer Computer: Auswahl **1 Zentrale / 2 Repeater** (ohne Monitor ist Repeater vorgewählt).
- Direkt: `... install.lua clean`, `... install.lua farm`, `... install.lua mining`, `... install.lua repeater`

`install.lua` enthält alle Programme – es wird nichts weiter heruntergeladen.
Quelltexte liegen in `src/`, die Simulationstests in `tests/`. Änderungen: siehe `AENDERUNGEN.md`.
