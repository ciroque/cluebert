defmodule Cluebert.Boards.Collection do
  @moduledoc """
  A named group of boards, such as "Primary Lessons" (ADR 9). Every board
  belongs to exactly one collection. Names are unique.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Cluebert.Boards.Board

  @type t :: %__MODULE__{}

  schema "collections" do
    field :name, :string

    has_many :boards, Board, preload_order: [asc: :name]

    timestamps(type: :utc_datetime)
  end

  @doc "Builds a changeset for a collection. Names are trimmed."
  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:name])
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> validate_required([:name])
    |> unique_constraint(:name, message: "is already a collection")
  end

  @doc "Builds a changeset for deleting a collection, which must have no boards."
  def delete_changeset(collection) do
    collection
    |> change()
    |> no_assoc_constraint(:boards, message: "still has boards; move or delete them first")
  end
end
