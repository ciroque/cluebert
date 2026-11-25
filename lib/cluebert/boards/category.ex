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
    |> cast(attrs, [:title])
    |> put_change(:position, position)
    |> validate_required([:title, :position])
    |> unique_constraint([:board_id, :position])
    |> cast_assoc(:clues, with: &Clue.changeset/3)
  end
end
