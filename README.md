# Disponera

Calendar + Todo + Quick-Notes in einer App — CalDAV-backed, Markdown-first,
Obsidian-style Verlinkung. Eigenständiges Projekt, wird mit
[velumeron](https://github.com/vredix-openvuture/velumeron) ausgeliefert.

## Konzept

Drei Panes, eine Datenbasis:

- **Calendar** — VEVENT-Kalender via CalDAV (Nextcloud, Vikunja, …). Monats- und
  Agenda-Ansicht.
- **Todos** — VTODO-Listen derselben Accounts (Vikunja-Projekte tauchen als
  Listen auf).
- **Notes** — lokale Markdown-Quick-Notes mit `[[wikilinks]]`; Notizen können
  Events/Todos referenzieren (Obsidian-style Graph kommt später).

Das CalDAV-Fundament ist velumerons `caldav-client.py` (stdlib-only, ein
JSON-Cache-Kontrakt für load/sync/Mutationen) — Disponera spricht denselben
Kontrakt über `disponera.caldav` und bleibt damit account-kompatibel zur
Shell (gleiche `caldav-accounts.json`).

## Status

**Skeleton.** Fenster startet, Panes sind Platzhalter, Backend-Wrapper stehen.

```
src/disponera/
  app.py      QML-Loader (PySide6)
  caldav.py   Wrapper um velumerons caldav-client.py (JSON-Kontrakt)
  notes.py    Markdown-Store (XDG_DATA/disponera/notes)
qml/
  Main.qml    3-Pane-Gerüst (Calendar / Todos / Notes)
```

## Entwicklung

```bash
python -m venv .venv && . .venv/bin/activate.fish
pip install -e .
disponera
```

Benötigt PySide6; CalDAV-Accounts werden (noch) in velumeron gepflegt
(Settings → Calendar).

## Roadmap

- [ ] Monatsansicht rendert Events aus dem Cache
- [ ] Todo-Liste mit toggle/add (Kontrakt existiert schon)
- [ ] Notes: Editor + wikilink-Vervollständigung
- [ ] Eigene Account-Verwaltung (aus velumeron herauslösen)
- [ ] Verlinkung Notes ↔ Events/Todos
