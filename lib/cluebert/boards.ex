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
  alias Cluebert.Boards.{Board, Category, Clue, Collection}

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

  ## The board editor: categories and clues

  @doc """
  Loads a board for editing: categories and clues in position order (as
  `get_board!/1`), plus its collection.
  """
  @spec get_board_for_editing!(term()) :: Board.t()
  def get_board_for_editing!(id), do: id |> get_board!() |> Repo.preload(:collection)

  @doc "Gets a category by id. Raises `Ecto.NoResultsError` if there is none."
  @spec get_category!(term()) :: Category.t()
  def get_category!(id), do: Repo.get!(Category, id)

  @doc "Gets a clue by id. Raises `Ecto.NoResultsError` if there is none."
  @spec get_clue!(term()) :: Clue.t()
  def get_clue!(id), do: Repo.get!(Clue, id)

  @doc "Returns a changeset for a category's title, for forms."
  @spec change_category(Category.t(), map()) :: Ecto.Changeset.t()
  def change_category(%Category{} = category, attrs \\ %{}),
    do: Category.title_changeset(category, attrs)

  @doc "Adds a category at the end of the board (its rightmost column)."
  @spec create_category(Board.t(), map()) :: {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def create_category(%Board{} = board, attrs) do
    position = next_position(from c in Category, where: c.board_id == ^board.id)

    %Category{board_id: board.id, position: position}
    |> Category.title_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Renames a category."
  @spec update_category(Category.t(), map()) :: {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.title_changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a category with its clues."
  @spec delete_category(Category.t()) :: {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def delete_category(%Category{} = category), do: Repo.delete(category)

  @doc """
  Moves a category one place earlier (`:up`, towards the left of the board)
  or later (`:down`). A category already at that end stays put.
  """
  @spec move_category(Category.t(), :up | :down) :: {:ok, Category.t()}
  def move_category(%Category{} = category, direction),
    do: move(Category, category, :board_id, direction)

  @doc """
  Returns a new clue for `category`, for the add-clue form: its value is
  filled in as 100 times the row it will take, matching the importer.
  """
  @spec new_clue(Category.t()) :: Clue.t()
  def new_clue(%Category{} = category) do
    count = Repo.aggregate(from(c in Clue, where: c.category_id == ^category.id), :count)
    %Clue{category_id: category.id, value: (count + 1) * 100}
  end

  @doc "Returns a changeset for a clue's prompt, response and value, for forms."
  @spec change_clue(Clue.t(), map()) :: Ecto.Changeset.t()
  def change_clue(%Clue{} = clue, attrs \\ %{}), do: Clue.content_changeset(clue, attrs)

  @doc "Adds a clue at the end of the category (the bottom of its column)."
  @spec create_clue(Category.t(), map()) :: {:ok, Clue.t()} | {:error, Ecto.Changeset.t()}
  def create_clue(%Category{} = category, attrs) do
    position = next_position(from c in Clue, where: c.category_id == ^category.id)

    %Clue{category_id: category.id, position: position}
    |> Clue.content_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Changes a clue's prompt, response or value."
  @spec update_clue(Clue.t(), map()) :: {:ok, Clue.t()} | {:error, Ecto.Changeset.t()}
  def update_clue(%Clue{} = clue, attrs) do
    clue
    |> Clue.content_changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a clue."
  @spec delete_clue(Clue.t()) :: {:ok, Clue.t()} | {:error, Ecto.Changeset.t()}
  def delete_clue(%Clue{} = clue), do: Repo.delete(clue)

  @doc """
  Moves a clue one place up or down within its category. A clue already at
  that end stays put. Its value does not change.
  """
  @spec move_clue(Clue.t(), :up | :down) :: {:ok, Clue.t()}
  def move_clue(%Clue{} = clue, direction), do: move(Clue, clue, :category_id, direction)

  defp next_position(query) do
    (Repo.one(from q in query, select: max(q.position)) || -1) + 1
  end

  # Swaps `record` with its nearest neighbour in the given direction within
  # the same parent. Positions may have gaps after deletes; only their order
  # matters. The record parks at a negative position (its own id, so it is
  # unique) while the neighbour takes its place, to satisfy the unique
  # (parent, position) index.
  defp move(schema, record, parent, direction) when direction in [:up, :down] do
    parent_id = Map.fetch!(record, parent)

    neighbour_query =
      from r in schema,
        where: field(r, ^parent) == ^parent_id,
        limit: 1

    neighbour_query =
      case direction do
        :up ->
          from r in neighbour_query,
            where: r.position < ^record.position,
            order_by: [desc: r.position]

        :down ->
          from r in neighbour_query,
            where: r.position > ^record.position,
            order_by: [asc: r.position]
      end

    case Repo.one(neighbour_query) do
      nil ->
        {:ok, record}

      neighbour ->
        Repo.transact(fn ->
          set_position(schema, record.id, -record.id)
          set_position(schema, neighbour.id, record.position)
          set_position(schema, record.id, neighbour.position)
          {:ok, %{record | position: neighbour.position}}
        end)
    end
  end

  defp set_position(schema, id, position) do
    Repo.update_all(from(r in schema, where: r.id == ^id), set: [position: position])
  end
end
