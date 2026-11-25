# 6. Boards have any shape, defined through seeds for now

Date: 2026-11-25

## Status

Accepted. Implemented in `lib/cluebert/boards.ex` (PR #4). Partly superseded
by ADR 9: boards are also imported from JSON and managed in the app, and
belong to collections.

## Context

Boards should support any number of categories and any number of clues per
category, not a fixed 6×5 grid. Writing boards will eventually need an
editing screen, but nothing else depends on one.

## Decision

Schema:

- `boards`: `name`.
- `categories`: `board_id`, `title`, `position`.
- `clues`: `category_id`, `prompt`, `response`, `value`, `position`.

`value` is stored per clue (not computed from the row), and categories may
have different numbers of clues. The board grid has as many columns as
categories and as many rows as the largest category; shorter categories show
empty cells.

Boards are created through `priv/repo/seeds.exs` for now. There is no
board-editing UI.

## Consequences

- Any board shape works without code changes.
- Adding or changing a board means editing seeds and re-running them.
- A board-editing UI can be added later on the same schema.
