# Board format

Cluebert imports boards from JSON (ADR 9). This document is the contract for
anything that writes board files, by hand or generated.

## Example

```json
{
  "collection": "Primary Lessons",
  "name": "Lesson 12: Plants",
  "categories": [
    {
      "title": "Parts of a Plant",
      "clues": [
        { "prompt": "This part soaks up water from the soil", "response": "The roots" },
        { "prompt": "Leaves use this from the Sun to make food", "response": "Sunlight", "value": 200 }
      ]
    },
    {
      "title": "Seeds",
      "clues": [
        { "prompt": "A tiny plant that sprouts from a seed", "response": "A seedling" }
      ]
    }
  ]
}
```

A file can hold one board object, as above, or a list of them:

```json
[
  { "collection": "Primary Lessons", "name": "Lesson 12: Plants", "categories": [] },
  { "collection": "Primary Lessons", "name": "Lesson 13: Weather", "categories": [] }
]
```

## Fields

| Field | Required | Notes |
| --- | --- | --- |
| `collection` | no | The group the board belongs to, e.g. `"Primary Lessons"`. Created if it doesn't exist. Defaults to `"General"`. |
| `name` | yes | The board's name. Unique within its collection. |
| `categories` | no | The board's columns, left to right. |
| `categories[].title` | yes | The column heading. |
| `categories[].clues` | no | The column's clues, top to bottom. |
| `clues[].prompt` | yes | What is read out and shown on the player screen. |
| `clues[].response` | yes | The expected answer. Only the host sees it. |
| `clues[].value` | no | Points, a whole number of 0 or more. Defaults to 100 × the clue's row: 100, 200, 300, and so on. |

Other fields are ignored. Leading and trailing spaces are trimmed from
collection and board names.

## Rules

- **Any shape.** Categories may have different numbers of clues (ADR 6). The
  board has as many rows as its longest category.
- **Order is position.** Categories and clues appear in the order they are
  listed. There is no `position` field.
- **A board needs at least one clue to be played.** A board with no clues
  imports, but a game can't be started with it.
- **All or nothing.** If any board in a file is invalid, nothing in the file
  is imported.
- **Existing boards.** Importing a board whose name already exists in its
  collection fails, unless the import is run with replace. Replace deletes
  the old board and creates the new one. Games already running keep the old
  version (ADR 5).

## Importing

- Development: `mix cluebert.import path/to/file.json [more.json ...] [--replace]`
- Seeds: every `*.json` file in `priv/boards/` is imported, with replace, by
  `mix run priv/repo/seeds.exs`.
- In the app: `/boards/import` (Boards → Import JSON). Paste JSON or choose
  `.json` files, with an option to replace existing boards.

## Errors

Errors name the board by its position in the file (starting at 1), and the
category and clue within it, so a generator can fix exactly what is wrong.
For example:

```text
board 2 ("Lesson 13: Weather"), category 1, clue 3: prompt can't be blank
board 2 ("Lesson 13: Weather"), category 2: title can't be blank
board 1: "Lesson 12: Plants" already exists in collection "Primary Lessons"; import with replace to overwrite it
```
