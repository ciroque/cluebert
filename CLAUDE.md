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
| [0006](docs/adr/0006-any-board-shape-defined-by-seeds.md) | Boards have any shape, defined through seeds for now | Accepted, implemented |
| [0007](docs/adr/0007-lean-scaffold.md) | Lean scaffold | Accepted, implemented |
| [0008](docs/adr/0008-setup-page-and-two-screens.md) | One setup page, then two screens per game | Accepted |

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
     offers New game, which goes to setup with the finished game's id.
   - `/games/:id` (`BoardLive`): the player screen, display only. A grid
     with one column per category and rows up to the largest category.
     Correctly answered clues show a checkmark. The play order, current
     team and scores are visible, and the open clue is shown large. When
     the host starts a new game from game over, it switches to that game.

## Working agreements

- Keep changes small and independently checkable. Prefer the simplest thing
  that fits the ADRs; don't build ahead of the plan.
- Write tests for behavior, with doc comments on public functions.
- Run `mix precommit` before considering a change done.
- Use `git switch` (for example `git switch -c <branch>`), not
  `git checkout`, for branches.
- Work on a branch and open a PR; don't push to `main`.
