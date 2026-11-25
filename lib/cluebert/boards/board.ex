defmodule Cluebert.Boards.Board do
  @moduledoc """
  A named board: an ordered list of categories, each with its own clues.

  Boards can have any shape (ADR 6). Each board belongs to one collection,
  and names are unique within it (ADR 9).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Cluebert.Boards.{Category, Collection}

  @type t :: %__MODULE__{}

  schema "boards" do
    field :name, :string

    belongs_to :collection, Collection
    has_many :categories, Category, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for a board and, optionally, its nested categories.

  Categories are positioned in the order they are given. The collection is
  set by the caller on the struct, never cast from `attrs`.
  """
  def changeset(board, attrs) do
    board
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :collection_id])
    |> assoc_constraint(:collection)
    |> unique_constraint(:name,
      name: :boards_collection_id_name_index,
      message: "has already been taken in this collection"
    )
    |> cast_assoc(:categories, with: &Category.changeset/3)
  end
end
