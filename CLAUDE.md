# Cluebert

A Jeopardy-style trivia game for a group in one room, built with Phoenix
LiveView. A host runs the game on one screen; everyone watches a shared board.
Teams take turns; there are no buzzers.

@AGENTS.md

## Design decisions

The architecture decision records in `docs/adr/` are the source of truth. Read
the relevant ones before changing behavior, and link to them from PRs.

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](docs/adr/0001-pure-rules-module-with-thin-genserver.md) | Pure rules module with a thin GenServer | Accepted, implemented |
| [0002](docs/adr/0002-turn-based-play-without-buzzers.md) | Turn-based play without buzzers | Accepted, implemented |
| [0003](docs/adr/0003-host-judges-and-can-end-game-anytime.md) | The host judges, and can end the game at any time | Accepted, implemented |
| [0004](docs/adr/0004-in-memory-game-state.md) | Game state lives only in memory | Accepted, implemented |
| [0005](docs/adr/0005-board-snapshot-at-game-start.md) | The board is copied when a game starts | Accepted, implemented |
| [0006](docs/adr/0006-any-board-shape-defined-by-seeds.md) | Boards have any shape, defined through seeds for now | Accepted, implemented; partly superseded by ADR 9 |
| [0007](docs/adr/0007-lean-scaffold.md) | Lean scaffold | Accepted, implemented |
| [0008](docs/adr/0008-setup-page-and-two-screens.md) | One setup page, then two screens per game | Accepted, implemented |
| [0009](docs/adr/0009-collections-json-import-and-board-management.md) | Boards are grouped into collections, imported from JSON, and managed in the app | Accepted, implemented |

If a change would contradict an ADR, stop and say so instead of working around
it. New decisions get a new ADR (Nygard format: Status, Context, Decision,
Consequences); superseded ones are marked as such, not deleted.

## Game rules

`lib/cluebert/game.ex` (`Cluebert.Game`) holds every rule and documents the
invariants in its moduledoc. `test/cluebert/game_test.exs` tests each
invariant and runs randomized action sequences against all of them. Do not
put rules anywhere else (ADR 1). If a rule changes, update the moduledoc, the
tests and the relevant ADR together.

## Build plan

One small PR per step, each independently reviewable.

1. **Lean scaffold** (ADR 7). Remove the generated boilerplate listed in the
   ADR, restyle `core_components.ex` and `layouts.ex` with plain Tailwind, and
   route `/` to a placeholder LiveView.
2. **Board data** (ADR 6). `Cluebert.Boards` context with `Board`, `Category`
   and `Clue` schemas and migrations, a function that loads a board with
   categories and clues preloaded in position order, and `seeds.exs` with one
   sample board whose categories have different numbers of clues.
3. **Game runtime** (ADRs 1, 4, 5). `Cluebert.GameServer` plus a `Registry`
   and `DynamicSupervisor` in the application tree. Starting a game loads the
   board once, builds `Cluebert.Game` from `%{clue_id => value}`, and keeps
   the full board for rendering. Every successful change is broadcast on
   `"game:<id>"`. Tests use `start_supervised!`.
4. **UI** (ADR 8). One PR per page.
   - `/` (setup): add and remove team names and choose a board, in any
     order. Names are checked by `Cluebert.Game`. Start calls
     `GameServer.start_game(board_id, team_names)`, which creates, shuffles
     and starts the game in one step, then goes to the host screen.
   - `/games/:id/host` (`HostLive`): the board, the play order, scores and
     the current team. The host clicks the clue the current team calls out
     (teams have no devices, ADR 2). The open clue's prompt and response
     show in a panel with Correct and Incorrect at its bottom right. End
     Game is always available. A link opens the player screen in one
     named window, which the host moves to the shared display. Game over
     offers New game, which goes to setup with the finished game's id; setup
     fills in that game's teams, with Clear all for a new group.
   - `/games/:id` (`BoardLive`): the player screen, display only. A grid
     with one column per category and rows up to the largest category.
     Correctly answered clues show a checkmark. The play order, current
     team and scores are visible, and the open clue is shown large.
     Answered tiles are dimmed to a 30% gray. A button makes the window
     full screen. When
     the host starts a new game from game over, it switches to that game.

### Next

Steps 1–7 are done. The next PRs, in order:

5. **Collections and JSON import** (ADR 9). `Collection` schema; boards are
   unique by name within a collection, defaulting to "General".
   `Cluebert.Boards.Import` (format in `docs/board-format.md`),
   `mix cluebert.import`, and seeds from `priv/boards/*.json`.
6. **Board management UI** (ADR 9), in three PRs:
   - 6a. `/boards` (`ManageBoardsLive`): collections and their boards.
     Create, rename and delete collections (only when empty); add, rename,
     move and delete boards. Header navigation.
   - 6b. `/boards/:id`: the board editor. Add, edit, delete and reorder
     (up/down buttons) categories and clues.
   - 6c. `/boards/import`: paste or upload JSON, with an option to replace
     existing boards. No export.
7. **Polish and cleanup.** Stop finished games an hour after they end
   (later than the team carry-over and player-screen hand-off need).
   Pre-select a different board than the one just played, add a
   full-screen button on the player screen, and have the player screen
   notice when its game process is gone.
8. **ADR 10: no access control yet.** Record the decision and what would
   make us revisit it.
9. **Helm chart** for the existing Kubernetes cluster, following the
   charts in the sibling repos. Exactly one replica, because game state is
   in memory (ADR 4).

## Working agreements

- Keep changes small and independently checkable. Prefer the simplest thing
  that fits the ADRs; don't build ahead of the plan.
- Write tests for behavior, with doc comments on public functions.
- Run `mix precommit` before considering a change done.
- Use `git switch` (for example `git switch -c <branch>`), not
  `git checkout`, for branches.
- Work on a branch and open a PR; don't push to `main`.
