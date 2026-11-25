# 2. Turn-based play without buzzers

Date: 2026-11-25

## Status

Accepted. Implemented in `lib/cluebert/game.ex` (PR #1).

## Context

Classic Jeopardy uses buzzers, which brings in fairness and network-latency
problems (who pressed first, clock skew, spam lockouts). The intended use is
a group playing together with no clickers.

## Decision

Play is turn-based:

- Teams are defined during setup. An individual player is a team of one.
- The play order is randomized (and can be re-randomized) during setup, then
  locked when the game starts.
- The current team selects any clue that has not been answered.
- **Correct:** the team scores the clue's value, the clue leaves the board,
  and the same team selects again.
- **Wrong:** no points, no penalty, the clue stays on the board, and the turn
  passes to the next team in order. A clue can be selected any number of
  times until it is answered.

## Consequences

- No buzzer endpoint, timing, or fairness logic is needed.
- Players do not need their own devices.
- A clue nobody can answer can keep cycling; ADR 3 covers how the game ends.
- Penalties, Daily Doubles and Final Jeopardy are out of scope. The rules are
  isolated in one module (ADR 1), so adding them later does not require
  restructuring.
