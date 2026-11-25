# Boards are defined here for now (ADR 6). Run with:
#
#     mix run priv/repo/seeds.exs
#
# Re-running is safe: a board with the same name is deleted (with its
# categories and clues) and recreated. Games already running keep their own
# copy of the board (ADR 5).
#
# Categories and clues are positioned in the order they are listed.
# Categories may have different numbers of clues.

import Ecto.Query

alias Cluebert.Boards
alias Cluebert.Boards.Board
alias Cluebert.Repo

clues = fn pairs ->
  pairs
  |> Enum.with_index(1)
  |> Enum.map(fn {{prompt, response}, row} ->
    %{prompt: prompt, response: response, value: row * 100}
  end)
end

boards = [
  %{
    name: "Sampler",
    categories: [
      %{
        title: "Space",
        clues:
          clues.([
            {"The planet closest to the Sun", "Mercury"},
            {"The name of our galaxy", "The Milky Way"},
            {"The largest planet in our solar system", "Jupiter"},
            {"In 1969 he became the first person to walk on the Moon", "Neil Armstrong"},
            {"In 2006 this former planet was reclassified as a dwarf planet", "Pluto"}
          ])
      },
      %{
        title: "Animals",
        clues:
          clues.([
            {"The largest animal known to have ever lived", "The blue whale"},
            {"A group of crows is called this", "A murder"},
            {"The only mammal capable of true sustained flight", "The bat"},
            {"The number of hearts an octopus has", "Three"}
          ])
      },
      %{
        title: "Food & Drink",
        clues:
          clues.([
            {"The main ingredient in guacamole", "Avocado"},
            {"The cheese traditionally used on a pizza Margherita", "Mozzarella"},
            {"Saffron comes from this part of the crocus flower", "The stigma"}
          ])
      },
      %{
        title: "Words",
        clues:
          clues.([
            {"A word that reads the same forwards and backwards", "A palindrome"},
            {"The opposite of an antonym", "A synonym"},
            {"The Q in FAQ", "Question"},
            {"A word formed from initials and pronounced as a word, like scuba", "An acronym"},
            {"A word for a word that imitates the sound it describes, like buzz", "Onomatopoeia"}
          ])
      },
      %{
        title: "Geography",
        clues:
          clues.([
            {"The capital of Australia", "Canberra"},
            {"The longest river in South America", "The Amazon"}
          ])
      }
    ]
  }
]

for %{name: name} = attrs <- boards do
  {:ok, _board} =
    Repo.transact(fn ->
      Repo.delete_all(from b in Board, where: b.name == ^name)
      Boards.create_board(attrs)
    end)
end
