# Decisions — gestione cartelle e annidamento (modello 1a)

decided: 2026-08-29 · rivisto 2×: Q2 piatto → albero collassabile; forma di gestione unificata su richiesta
disegnato in: `03 Vault - modelli di navigazione.dc.html` → turno **2** (`2a` desktop, `2b`–`2d` telefono)

## Il principio: una sola ricetta

Una superficie **Manage folders**, identica a ogni larghezza — stesso albero,
stesso *New folder*, stesso `•••` per riga (*Rename · Move… · Delete*), stesse
conferme di oggi (FR-006, stringhe da riprendere verbatim dal codice). Cambia
solo il contenitore:

| Larghezza | Contenitore | Ingresso |
| --- | --- | --- |
| ≥ 941 (colonna visibile) | **dialog centrato** sopra il vault | *Manage* nell'intestazione della colonna |
| < 704 (telefono) | schermata spinta nella tab Vault | *Manage* in testa al foglio *Folders* |
| 704–940 | come desktop (dialog) | dal commutatore cartelle sul rail — artboard da disegnare |

Un solo ingresso per larghezza, sempre nell'header della superficie cartelle.
Niente menu aggiuntivi nell'header del telefono; niente azioni sulle righe
della colonna o sui chip: filtri e basta. Il dialog non aggiunge colonne, quindi
l'aritmetica di `decisions-vault-columns.md` non cambia.

## Annidamento: albero collassabile

- **Colonna desktop** e **foglio telefono** mostrano lo stesso albero: chevron
  solo sui nodi con figli, un livello di indentazione, **stato di apertura
  condiviso e persistito** per database.
- **Chip telefono = solo primo livello.** Il primo chip è *Folders* e apre il
  foglio; scegliere una cartella (anche profonda) filtra, chiude e diventa il
  chip attivo.
- **La superficie di gestione mostra l'albero sempre tutto espanso** (lì serve
  vedere tutto), senza sottotitoli: la posizione la dà l'indentazione.
- **Conteggi inclusivi delle sottocartelle**, dichiarato nella lista
  (`52 items · incl. subfolders`); le voci di una sottocartella portano
  `· in CI secrets` nella riga secondaria.
- Selezionare un nodo filtra nodo + discendenti; il chevron è un target
  separato: espandere/collassare non cambia il filtro.
- **Il genitore si cambia solo da `Move…`.**

## Stile unificato

- Riga selezionata: **quella della colonna desktop** ovunque —
  `--color-accent-200` di fondo, testo `--color-accent-800`, semibold.
  Niente tile-icona quadrati: icona cartella semplice in linea.
- Menu `•••`: una sola ricetta (Rename / Move… / Delete, Delete su
  `--color-accent-100`), identica su dialog, schermata e ovunque ricompaia.

## Follow-up

- Disegnare lo stato 704–940 (colonna collassata, commutatore sul rail).
- Riprendere verbatim le stringhe di Rename / Move… / Delete e delle conferme.
- Propagare chip di primo livello + foglio *Folders* a `04-06` e `07-09`.
