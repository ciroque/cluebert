# 4. Game state lives only in memory

Date: 2026-11-25

## Status

Accepted. Not yet implemented (`GameServer`).

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
- Revisit if games become long-running, or if results need to be kept. The
  smallest next step would be saving final scores when a game reaches
  `:done`, not a full event log.
