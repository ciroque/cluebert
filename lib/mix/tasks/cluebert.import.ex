defmodule Mix.Tasks.Cluebert.Import do
  @shortdoc "Imports boards from JSON files"

  @moduledoc """
  Imports boards from JSON files (ADR 9). The format is documented in
  `docs/board-format.md`.

      $ mix cluebert.import priv/boards/plants.json
      $ mix cluebert.import lessons/*.json --replace

  Each file is imported on its own and all-or-nothing: a file with any
  invalid board imports nothing, and the error names the board, category
  and clue at fault. Every file is attempted, and the task exits with an
  error if any of them failed.

  ## Options

    * `--replace` - replace boards that already exist in their collection
      instead of failing
  """
  use Mix.Task

  alias Cluebert.Boards.Import

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, files} = OptionParser.parse!(args, strict: [replace: :boolean])

    if files == [] do
      Mix.raise("Usage: mix cluebert.import FILE... [--replace]")
    end

    failed = Enum.reject(files, &import_file(&1, opts))

    if failed != [] do
      Mix.raise("#{length(failed)} of #{length(files)} file(s) failed to import")
    end
  end

  defp import_file(path, opts) do
    with {:ok, json} <- read(path),
         {:ok, imported} <- Import.import_json(json, replace: Keyword.get(opts, :replace, false)) do
      for %{board: board, collection: collection, replaced?: replaced?} <- imported do
        verb = if replaced?, do: "Replaced", else: "Imported"
        Mix.shell().info("#{verb} \"#{board.name}\" in \"#{collection}\" (#{path})")
      end

      true
    else
      {:error, {:file, reason}} ->
        Mix.shell().error("#{path}: #{:file.format_error(reason)}")
        false

      {:error, error} ->
        Mix.shell().error("#{path}:\n" <> indent(Import.format_error(error)))
        false
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:file, reason}}
    end
  end

  defp indent(message), do: message |> String.split("\n") |> Enum.map_join("\n", &("  " <> &1))
end
