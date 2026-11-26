# 4. Game state lives only in memory

Date: 2026-11-25

## Status

Accepted. Implemented in `lib/cluebert/game_server.ex` (PR #5). Game
processes are `:temporary`, so a crashed game is gone rather than restarted
empty. Since step 7 of the build plan, a finished game stops itself an hour
after it reaches `:done`, and both screens monitor their game to notice when
it is gone.

## Context

A game lasts one session in one room. Persisting every state change (for
example as an event log that can be replayed) would let a game survive a
crash or deploy, but adds schema, write paths and recovery code.

## Decision

Live game state exists only in the `GameServer` process. Nothing about a game
in progress is written to the database.

## Consequences

- If the server process or node goes down, the game in progress is lost.
- No event schema, replay or recovery code.
- The deployment runs exactly one pod and replaces it with `Recreate`
  (ADR 11), so every upgrade ends the games in progress.
- Finished games must not stay in memory forever. They stop an hour after
  they end: long enough for New game to read their teams and hand the player
  screen on (ADR 8), and then they are gone.
- Revisit if games become long-running, or if results need to be kept. The
  smallest next step would be saving final scores when a game reaches
  `:done`, not a full event log.
