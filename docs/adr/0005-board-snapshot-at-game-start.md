# 5. The board is copied when a game starts

Date: 2026-11-25

## Status

Accepted. `Cluebert.Game` side implemented (PR #1); loading from the database
is not yet implemented.

## Context

Boards are stored in Postgres (ADR 6). If a running game read clues from the
database as it went, editing a board would change games in progress.

## Decision

When a game is created, the board is loaded once from the database and held
by the `GameServer`:

- `Cluebert.Game` receives only `%{clue_id => value}`. The rules need nothing
  else.
- The full board (category titles and order, clue prompts and responses) is
  kept alongside it in the server for rendering.

## Consequences

- Editing or deleting a board never affects a running game.
- The rules module stays independent of Ecto.
- Loading the board is a single query with preloads, done once per game.
