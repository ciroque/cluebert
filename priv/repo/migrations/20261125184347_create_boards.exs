defmodule Cluebert.Repo.Migrations.CreateBoards do
  use Ecto.Migration

  def change do
    create table(:boards) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:boards, [:name])

    create table(:categories) do
      add :board_id, references(:boards, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:categories, [:board_id, :position])

    create table(:clues) do
      add :category_id, references(:categories, on_delete: :delete_all), null: false
      add :prompt, :text, null: false
      add :response, :text, null: false
      add :value, :integer, null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:clues, [:category_id, :position])
    create constraint(:clues, :value_must_be_non_negative, check: "value >= 0")
  end
end
