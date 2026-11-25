defmodule Cluebert.Boards.Category do
  @moduledoc """
  A column on a board. `position` orders categories within their board.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Cluebert.Boards.{Board, Clue}

  @type t :: %__MODULE__{}

  schema "categories" do
    field :title, :string
    field :position, :integer

    belongs_to :board, Board
    has_many :clues, Clue, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for a category at `position` and its nested clues.

  `position` is set from the category's place in its board's list, not cast
  from `attrs`. Clues are positioned in the order they are given.
  """
  def changeset(category, attrs, position) do
    category
    |> title_changeset(attrs)
    |> put_change(:position, position)
    |> validate_required([:position])
    |> cast_assoc(:clues, with: &Clue.changeset/3)
  end

  @doc """
  Builds a changeset for a category's title only. The title is trimmed.
  Position and clues are left alone; the board editor moves categories with
  `Cluebert.Boards.move_category/2`.
  """
  def title_changeset(category, attrs) do
    category
    |> cast(attrs, [:title])
    |> update_change(:title, &(&1 && String.trim(&1)))
    |> validate_required([:title])
    |> unique_constraint([:board_id, :position])
  end
end
