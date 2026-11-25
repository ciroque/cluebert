# 8. One setup page, then two screens per game

Date: 2026-11-25

## Status

Accepted.

## Context

The intended game flow is:

1. The host enters the teams and chooses a board.
2. The host starts the game. The play order is randomized and shown, and
   the board appears.
3. The host clicks the clue the current team calls out (ADR 2), hears the
   response, and marks it correct or wrong on that clue.
4. Correct: the tile shows that it was answered, and the same team picks
   again. Wrong: the tile stays open and the next team picks.

The room watches a shared screen, but the host needs to see each clue's
response in order to judge it (ADR 3). The same screen can't serve both
without showing the responses to everyone.

`Cluebert.Game` needs a board before it can hold teams (`Game.new/1` takes the
clue values), but in this flow the host may enter teams before choosing a
board.

## Decision

**Setup is one page, at `/`.** The host adds and removes team names and
chooses a board, in any order. Until the game starts, the names are kept
only in the LiveView. Each name is checked as it is entered by a pure
function in `Cluebert.Game`, the same check `Game.add_team/2` uses, so the
rule stays in one place (ADR 1).

**Start creates a game that is already playing.**
`GameServer.start_game(board_id, team_names)` loads the board, builds the
game, adds the teams, randomizes the order and starts the game in one call.
No one ever sees a half-set-up game. Randomizing at start is still
"randomized during setup, then locked" (ADR 2). There is no separate
Shuffle button.

**Each game has two screens.** They are two views of the same `GameServer`,
kept in sync by its broadcasts (ADR 1):

- `/games/:id/host` (`HostLive`), on the host's device. It shows the board
  with every clue's response, the play order and scores, and the current
  team. The host clicks a clue to open it, then marks it Correct or Wrong on
  that clue. End Game is always available (ADR 3).
- `/games/:id` (`BoardLive`), full-screen on the shared screen. It shows the
  same board and order without responses, with the open clue shown large.
  It is display-only.

**Correctly answered clues stay on the board with a checkmark.** They are not
hidden. `Cluebert.Game` already tracks which clues are answered, so this
needs no rule change. It does not record which team answered.

## Consequences

- Two browser windows per game: usually a laptop with the TV as a second
  display, or a phone plus the TV.
- Several games can run at once, each under its own id. There is no access
  control: anyone with a host URL can run that game.
- `GameServer` loses `add_team/2`, `remove_team/2` and `shuffle_order/2`,
  which the UI no longer needs. `Cluebert.Game` keeps them, and its
  `:setup` phase runs inside `start_game/2`.
- A game can no longer be cancelled during setup, because none exists until
  Start. The host just leaves the page. `Game.end_game/1` still allows it.
- Showing which team answered each clue would need `Cluebert.Game` to
  record it. That can be added later without changing this layout.
