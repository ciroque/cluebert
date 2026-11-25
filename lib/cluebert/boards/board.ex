defmodule Cluebert.Boards.Board do
  @moduledoc """
  A named board: an ordered list of categories, each with its own clues.

  Boards can have any shape (ADR 6). Names are unique.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Cluebert.Boards.Category

  @type t :: %__MODULE__{}

  schema "boards" do
    field :name, :string

    has_many :categories, Category, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for a board and, optionally, its nested categories.

  Categories are positioned in the order they are given.
  """
  def changeset(board, attrs) do
    board
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> cast_assoc(:categories, with: &Category.changeset/3)
  end
end
