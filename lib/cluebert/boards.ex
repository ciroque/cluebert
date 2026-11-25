defmodule Cluebert.Boards do
  @moduledoc """
  Boards, their categories and their clues (ADR 6).

  Boards are created through `priv/repo/seeds.exs` for now; there is no
  editing UI. A game copies a board once when it starts (ADR 5), so
  changing a board here never affects a game in progress.
  """
  import Ecto.Query, warn: false

  alias Cluebert.Repo
  alias Cluebert.Boards.Board

  @doc """
  Lists all boards by name, without their categories or clues.
  """
  @spec list_boards() :: [Board.t()]
  def list_boards do
    Repo.all(from b in Board, order_by: [asc: b.name])
  end

  @doc """
  Creates a board together with its categories and clues.

  Categories and clues are given as nested lists; each one's position comes
  from its place in the list.

  ## Example

      create_board(%{
        name: "Science",
        categories: [
          %{title: "Planets", clues: [%{prompt: "...", response: "...", value: 100}]}
        ]
      })

  """
  @spec create_board(map()) :: {:ok, Board.t()} | {:error, Ecto.Changeset.t()}
  def create_board(attrs) do
    %Board{}
    |> Board.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Loads a board with its categories and their clues preloaded, both in
  position order, in a single query (ADR 5).

  Raises `Ecto.NoResultsError` if there is no such board.
  """
  @spec get_board!(term()) :: Board.t()
  def get_board!(id) do
    query =
      from b in Board,
        where: b.id == ^id,
        left_join: c in assoc(b, :categories),
        left_join: cl in assoc(c, :clues),
        order_by: [asc: c.position, asc: cl.position],
        preload: [categories: {c, clues: cl}]

    Repo.one!(query)
  end
end
