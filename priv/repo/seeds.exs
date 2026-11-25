# Imports every board file in priv/boards/ (ADR 9). Run with:
#
#     mix run priv/repo/seeds.exs
#
# Files are imported in name order, each all-or-nothing, replacing any board
# of the same name in the same collection, so re-running is safe. Games
# already running keep their own copy of a board (ADR 5).
#
# The file format is documented in docs/board-format.md.

alias Cluebert.Boards.Import

dir = Application.app_dir(:cluebert, "priv/boards")

for path <- dir |> Path.join("*.json") |> Path.wildcard() |> Enum.sort() do
  case Import.import_json(File.read!(path), replace: true) do
    {:ok, imported} ->
      for %{board: board, collection: collection} <- imported do
        IO.puts("Seeded \"#{board.name}\" in \"#{collection}\" from #{Path.basename(path)}")
      end

    {:error, error} ->
      raise "#{Path.basename(path)}: #{Import.format_error(error)}"
  end
end
