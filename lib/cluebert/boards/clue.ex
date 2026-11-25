defmodule Cluebert.Boards.Clue do
  @moduledoc """
  A single clue. `value` is stored per clue rather than derived from its row
  (ADR 6); `position` orders clues within their category.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Cluebert.Boards.Category

  @type t :: %__MODULE__{}

  schema "clues" do
    field :prompt, :string
    field :response, :string
    field :value, :integer
    field :position, :integer

    belongs_to :category, Category

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for a clue at `position`.

  `position` is set from the clue's place in its category's list, not cast
  from `attrs`. `value` must be a non-negative integer, as `Cluebert.Game`
  requires.
  """
  def changeset(clue, attrs, position) do
    clue
    |> content_changeset(attrs)
    |> put_change(:position, position)
    |> validate_required([:position])
  end

  @doc """
  Builds a changeset for a clue's prompt, response and value only. Text is
  trimmed. Position is left alone; the board editor moves clues with
  `Cluebert.Boards.move_clue/2`.
  """
  def content_changeset(clue, attrs) do
    clue
    |> cast(attrs, [:prompt, :response, :value])
    |> update_change(:prompt, &(&1 && String.trim(&1)))
    |> update_change(:response, &(&1 && String.trim(&1)))
    |> validate_required([:prompt, :response, :value])
    |> validate_number(:value, greater_than_or_equal_to: 0)
    |> check_constraint(:value, name: :value_must_be_non_negative)
    |> unique_constraint([:category_id, :position])
  end
end
