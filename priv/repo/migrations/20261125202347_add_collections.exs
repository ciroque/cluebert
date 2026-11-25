defmodule Cluebert.Repo.Migrations.AddCollections do
  use Ecto.Migration

  # Every board belongs to a collection (ADR 9). Existing boards move into
  # "General", the default collection.
  def up do
    create table(:collections) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:collections, [:name])

    alter table(:boards) do
      add :collection_id, references(:collections, on_delete: :restrict)
    end

    execute """
    INSERT INTO collections (name, inserted_at, updated_at)
    SELECT 'General', now(), now() WHERE EXISTS (SELECT 1 FROM boards)
    """

    execute """
    UPDATE boards SET collection_id = (SELECT id FROM collections WHERE name = 'General')
    """

    execute "ALTER TABLE boards ALTER COLUMN collection_id SET NOT NULL"

    drop unique_index(:boards, [:name])
    create unique_index(:boards, [:collection_id, :name])
  end

  def down do
    drop unique_index(:boards, [:collection_id, :name])
    create unique_index(:boards, [:name])

    alter table(:boards) do
      remove :collection_id
    end

    drop table(:collections)
  end
end
