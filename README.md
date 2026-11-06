# Go Dojo

Learn your Go openings (josekis, fusekis, pet openings) from SGF files.

Go Dojo is free and open source, made by a Go player for Go players: no ads, no subscription, nothing to buy, and your data is never sold. Web version: https://noxl.github.io/GoDojo/

- **Library**: a folder of `.sgf` files (default `Documents\Go Dojo Library`, scanned recursively). Search, filter by color and board size, import, rename, duplicate or delete.
- **Editor**: build the opening tree for 9×9, 13×13 or 19×19, studied as Black or White.
  - Tools: play moves, add black or white stones, erase, triangle, square, circle, X, letter and number labels, tenuki (key T: the move is played elsewhere, no stone on this board; stored as a pass).
  - Move marks: Bad (BM); unmarked moves are good. Comments.
  - Next moves in the tree are shown on the board as letters A, B, C… (colored by their mark).
  - Variations are numbered and can be named (field in the editor, or right-click in the tree).
  - Large zoomable tree view (Ctrl+wheel): click to navigate, move variation up or down, delete branch.
  - KataGo analysis (button "Analyze" or the key set in Settings, "&" by default): best moves on the board with their score loss (hover one to see the sequence), winrate and score, loss of the selected move with a one-click Bad mark, and "Add top moves" to add the engine's suggestions as variations.
  - Undo/redo; keyboard: ← → (back/forward), ↑ ↓ (variations), Home/End, Ctrl+S, Ctrl+Z, Ctrl+Y.
- **Trainer**: you play your color, the app answers with moves from the tree.
  - The board is zoomed on the part the joseki uses, in all its lines (the whole board for an opening).
  - When you play a move marked Bad, its punishment is played automatically, then you are asked for the right move; moves not in the tree are flagged.
  - Tenuki button (key T) when the tree expects you to play elsewhere.
  - Opponent moves marked Bad are played sometimes (adjustable rate), so you practise punishing them.
  - Lines are chosen at random, unseen lines first; optional automatic next line and random start point; hints, accuracy, coverage.
- **Global** tab (also "Train all joseki" in the Library): the side list shows every joseki with the % learned, lines known, lines to fix and new lines; click one to train only it. The global trainer plays every line of every joseki and trick (openings optional), as Black, White or both, at random.
  - A line with a mistake (or a hint) comes back a few lines later, until you play it cleanly; "Mistakes to fix" lists the lines missed last time.
  - A line is **known** after 3 clean runs in a row; a file is known when all its lines are. Known lines come back for review after 2, 5, 12, then 30 days.
  - Choice of lines: smart mix (mistakes, new lines and reviews first), only my mistakes, or only lines not known yet.
  - The progress is saved in `training_progress.json` (app data folder). A line is identified by its start position and moves, so renaming or moving a file keeps it.

## Web version

The same app runs in a browser (phone, tablet, PC), without KataGo.

- Files and progress are kept **in the browser**. On iPhone, add the site to the home screen (Safari > Share > Add to Home Screen) so Safari keeps the data.
- Library > backup button: **Back up library and progress** downloads one JSON file; **Restore a backup** reads it. This also moves your SGF files and progress between the PC and the web.
- **Starter files**: the `.sgf` files of `assets/starter/` (the joseki "44 approach") are added to the library of every browser that opens the site (once each), and to every new account at its first sync (PC and web).

Publishing on GitHub Pages: push to the `main` branch of a GitHub repository, then in the repository Settings > Pages, set Source to **GitHub Actions**. The workflow `.github/workflows/pages.yml` tests, builds and publishes the site at `https://<user>.github.io/<repository>/` after every push.

Local web build: `flutter build web --base-href /<repository>/` (from Git Bash, prefix with `MSYS_NO_PATHCONV=1`).

## SGF conventions

Files are standard SGF (FF[4]) and open in any other SGF editor. Extra data:

| Property | Meaning |
|---|---|
| `OC[B]` / `OC[W]` (root) | Color the opening is studied for |
| `GK[joseki]` / `GK[tricks]` (root) | The file is a joseki or a trick: root `AB`/`AW` is the start position, `PL` who plays first, the color is chosen when training |
| `N[...]` on the first move of a variation | Variation name (standard SGF node name) |
| `BM` on an opponent move | A mistake the trainer will sometimes play so you learn to punish it |
| `BM` on your move | A mistake: the trainer shows its punishment, then asks for the right move |
| `DO` (old files) | Read as `BM` |

## KataGo

Put KataGo (e.g. the OpenCL Windows release) and a network (`.bin.gz`) in a `KataGo` folder next to the project, or choose any folder in Settings. The app runs `katago analysis` with the `analysis_example.cfg` found there. The first launch tunes the GPU and takes a few minutes.

## Building (Windows)

Prerequisites:

1. Visual Studio 2022 with the **Desktop development with C++** workload.
2. Windows **Developer Mode** (`start ms-settings:developers`), required for plugin symlinks.

```
flutter pub get
flutter run -d windows
flutter build windows   # release build in build\windows\x64\runner\Release
```

Tests: `flutter test`. Android and iOS targets are already scaffolded for later.

## Code layout

```
lib/
  go/        board rules (captures, ko, suicide), points, stones
  sgf/       SGF node tree, parser and writer
  storage/   files on disk (PC) or in the browser (web)
  model/     opening document (editing + undo), trainer session, global trainer (drill), library, annotations
  ui/        board widget, tree widget, library / editor / trainer pages
```
