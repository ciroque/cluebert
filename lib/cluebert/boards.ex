defmodule Cluebert.Boards do
  @moduledoc """
  Collections, their boards, and the boards' categories and clues (ADRs 6
  and 9).

  Every board belongs to a collection; boards created without one go into
  `default_collection_name/0`. A game copies a board once when it starts
  (ADR 5), so changing a board here never affects a game in progress.
  """
  import Ecto.Query, warn: false

  alias Cluebert.Repo
  alias Cluebert.Boards.{Board, Collection}

  @default_collection "General"

  @doc "The collection boards go into when none is given."
  @spec default_collection_name() :: String.t()
  def default_collection_name, do: @default_collection

  @doc """
  Returns the collection named `name` (trimmed), creating it if needed.
  Safe to call concurrently for the same name.
  """
  @spec get_or_create_collection(String.t()) ::
          {:ok, Collection.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_collection(name) when is_binary(name) do
    changeset = Collection.changeset(%Collection{}, %{name: name})

    if changeset.valid? do
      name = Ecto.Changeset.get_field(changeset, :name)
      Repo.insert(changeset, on_conflict: :nothing, conflict_target: :name)
      {:ok, Repo.get_by!(Collection, name: name)}
    else
      {:error, %{changeset | action: :insert}}
    end
  end

  @doc """
  Lists all boards with their collection preloaded, ordered by collection
  name and then board name. Categories and clues are not loaded.
  """
  @spec list_boards() :: [Board.t()]
  def list_boards do
    Repo.all(
      from b in Board,
        join: c in assoc(b, :collection),
        order_by: [asc: c.name, asc: b.name],
        preload: [collection: c]
    )
  end

  @doc """
  Creates a board, with its categories and clues, in `collection`. With
  only `attrs`, the board goes into the default collection.

  Categories and clues are given as nested lists; each one's position comes
  from its place in the list.

  ## Example

      create_board(collection, %{
        name: "Science",
        categories: [
          %{title: "Planets", clues: [%{prompt: "...", response: "...", value: 100}]}
        ]
      })

  """
  @spec create_board(Collection.t(), map()) :: {:ok, Board.t()} | {:error, Ecto.Changeset.t()}
  def create_board(%Collection{} = collection, attrs) do
    %Board{collection_id: collection.id}
    |> Board.changeset(attrs)
    |> Repo.insert()
  end

  @spec create_board(map()) :: {:ok, Board.t()} | {:error, Ecto.Changeset.t()}
  def create_board(attrs) do
    {:ok, collection} = get_or_create_collection(@default_collection)
    create_board(collection, attrs)
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
