# 1. Pure rules module with a thin GenServer

Date: 2026-11-25

## Status

Accepted. Implemented in `lib/cluebert/game.ex` (PR #1).

## Context

A live game has state that many clients watch (host screen, shared board) and
rules that must never be violated: turn order, scoring, which clues can be
selected. Putting the rules inside a GenServer's callbacks makes them hard to
test without starting processes and couples them to messaging concerns.

## Decision

All game rules live in `Cluebert.Game`, a pure module: a struct plus functions
that return `{:ok, game}` or `{:error, reason}`. The rules and their
invariants are documented in its moduledoc.

A `Cluebert.GameServer` GenServer (one per live game, under a
`DynamicSupervisor`, addressed via a `Registry`) only holds the struct, calls
`Cluebert.Game`, and broadcasts the new state over `Phoenix.PubSub` on
`"game:<id>"` after every successful change. It contains no rules.

## Consequences

- Every rule and invariant is tested with plain ExUnit, including randomized
  action sequences.
- Changing a rule touches one module.
- The GenServer stays small enough that its tests only need to cover
  lifecycle, lookup and broadcasting.
- LiveViews never mutate state directly; they call the server and render
  what is broadcast.
