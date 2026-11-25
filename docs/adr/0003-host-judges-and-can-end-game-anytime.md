# 3. The host judges, and can end the game at any time

Date: 2026-11-25

## Status

Accepted. Implemented in `lib/cluebert/game.ex` (PR #1).

## Context

Responses are spoken aloud in the room, so the app cannot check them, and
fuzzy matching of typed answers would add complexity for little benefit.
Because wrong answers leave clues on the board (ADR 2), a game might
otherwise never finish.

## Decision

- A host runs the game and judges each response as correct or wrong.
- The game ends when every clue has been answered, or when the host ends it.
  The host can end it in any phase, including setup (which cancels it).
- If a clue is open when the game ends, it closes with no points. Scores are
  frozen and unanswered clues stay unanswered.

## Consequences

- There is no answer-matching logic.
- No per-clue retire button or attempt limit is needed.
- Only the host view shows answers and the judging controls.
