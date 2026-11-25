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
  Lists every collection by name, with its boards preloaded by name. Each
  board's `clue_count` is filled in, so boards that can't be played yet (no
  clues) can be pointed out. Categories and clues are not loaded.
  """
  @spec list_collections_with_boards() :: [Collection.t()]
  def list_collections_with_boards do
    counts =
      Repo.all(
        from b in Board,
          left_join: c in assoc(b, :categories),
          left_join: cl in assoc(c, :clues),
          group_by: b.id,
          select: {b.id, count(cl.id)}
      )
      |> Map.new()

    Collection
    |> order_by(asc: :name)
    |> preload(:boards)
    |> Repo.all()
    |> Enum.map(fn collection ->
      boards = Enum.map(collection.boards, &%{&1 | clue_count: Map.get(counts, &1.id, 0)})
      %{collection | boards: boards}
    end)
  end

  @doc "Gets a collection by id. Raises `Ecto.NoResultsError` if there is none."
  @spec get_collection!(term()) :: Collection.t()
  def get_collection!(id), do: Repo.get!(Collection, id)

  @doc "Returns a changeset for creating or renaming a collection, for forms."
  @spec change_collection(Collection.t(), map()) :: Ecto.Changeset.t()
  def change_collection(%Collection{} = collection, attrs \\ %{}),
    do: Collection.changeset(collection, attrs)

  @doc "Creates a collection. Names are trimmed and must be unique."
  @spec create_collection(map()) :: {:ok, Collection.t()} | {:error, Ecto.Changeset.t()}
  def create_collection(attrs) do
    %Collection{}
    |> Collection.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Renames a collection."
  @spec update_collection(Collection.t(), map()) ::
          {:ok, Collection.t()} | {:error, Ecto.Changeset.t()}
  def update_collection(%Collection{} = collection, attrs) do
    collection
    |> Collection.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a collection. Only an empty collection can be deleted; one that
  still has boards returns an error changeset on `:boards`.
  """
  @spec delete_collection(Collection.t()) :: {:ok, Collection.t()} | {:error, Ecto.Changeset.t()}
  def delete_collection(%Collection{} = collection) do
    collection
    |> Collection.delete_changeset()
    |> Repo.delete()
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
  Gets a board without its categories, with its collection preloaded.
  Raises `Ecto.NoResultsError` if there is none.
  """
  @spec get_board_summary!(term()) :: Board.t()
  def get_board_summary!(id), do: Board |> Repo.get!(id) |> Repo.preload(:collection)

  @doc "Returns a changeset for naming a board, for forms."
  @spec change_board_name(Board.t(), map()) :: Ecto.Changeset.t()
  def change_board_name(%Board{} = board, attrs \\ %{}), do: Board.name_changeset(board, attrs)

  @doc "Renames a board. Its categories and clues are unchanged."
  @spec rename_board(Board.t(), map()) :: {:ok, Board.t()} | {:error, Ecto.Changeset.t()}
  def rename_board(%Board{} = board, attrs) do
    board
    |> Board.name_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Moves a board into another collection. Fails if that collection already
  has a board with the same name.
  """
  @spec move_board(Board.t(), Collection.t()) :: {:ok, Board.t()} | {:error, Ecto.Changeset.t()}
  def move_board(%Board{} = board, %Collection{} = collection) do
    board
    |> Board.name_changeset(%{})
    |> Ecto.Changeset.put_change(:collection_id, collection.id)
    |> Repo.update()
  end

  @doc """
  Deletes a board with its categories and clues. Games already running keep
  their own copy (ADR 5).
  """
  @spec delete_board(Board.t()) :: {:ok, Board.t()} | {:error, Ecto.Changeset.t()}
  def delete_board(%Board{} = board), do: Repo.delete(board)

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
