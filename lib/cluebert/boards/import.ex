defmodule Cluebert.Boards.Import do
  @moduledoc """
  Imports boards from JSON (ADR 9). The format is documented in
  `docs/board-format.md`.

  A file holds one board object or a list of them. The whole file is
  imported in one transaction: every board in it, or none. A board whose
  name already exists in its collection is an error unless `replace: true`
  is given, in which case the old board is deleted and the new one created.
  Running games keep their own copy of a board (ADR 5), so replacing a board
  never affects them.

  Errors are returned as data; `format_error/1` turns them into a message
  that names the board, category and clue at fault.
  """
  import Ecto.Query, warn: false

  alias Cluebert.Boards
  alias Cluebert.Boards.Board
  alias Cluebert.Repo

  @type imported :: %{board: Board.t(), collection: String.t(), replaced?: boolean()}

  @type error ::
          {:invalid_json, String.t()}
          | :not_a_board_list
          | {:not_an_object, pos_integer()}
          | {:invalid_collection, pos_integer(), String.t() | nil}
          | {:duplicate_in_file, pos_integer(), String.t(), String.t()}
          | {:already_exists, pos_integer(), String.t(), String.t()}
          | {:invalid_board, pos_integer(), String.t() | nil, Ecto.Changeset.t()}

  @doc """
  Imports the boards in `json`.

  Options:

    * `:replace` - replace boards that already exist in their collection
      instead of failing (default `false`)

  Returns `{:ok, imported}` with one entry per board, in file order, or
  `{:error, error}` with nothing imported.
  """
  @spec import_json(String.t(), keyword()) :: {:ok, [imported()]} | {:error, error()}
  def import_json(json, opts \\ []) when is_binary(json) do
    replace? = Keyword.get(opts, :replace, false)

    with {:ok, decoded} <- decode(json),
         {:ok, entries} <- entries(decoded),
         :ok <- check_duplicates(entries) do
      Repo.transact(fn -> import_all(entries, replace?) end)
    end
  end

  @doc "Turns an import error into a readable message."
  @spec format_error(error()) :: String.t()
  def format_error({:invalid_json, message}), do: "not valid JSON: #{message}"

  def format_error(:not_a_board_list),
    do: "expected a board object, or a list of board objects, at the top level"

  def format_error({:not_an_object, index}), do: "board #{index}: expected an object"

  def format_error({:invalid_collection, index, _}),
    do: "board #{index}: \"collection\" must be a non-blank string"

  def format_error({:duplicate_in_file, index, collection, name}),
    do: "board #{index}: \"#{name}\" appears more than once in collection \"#{collection}\""

  def format_error({:already_exists, index, collection, name}),
    do:
      "board #{index}: \"#{name}\" already exists in collection \"#{collection}\"; " <>
        "import with replace to overwrite it"

  def format_error({:invalid_board, index, name, changeset}) do
    label = if name, do: "board #{index} (\"#{name}\")", else: "board #{index}"

    changeset
    |> Ecto.Changeset.traverse_errors(&translate/1)
    |> flatten([label])
    |> Enum.join("\n")
  end

  ## Decoding and normalizing

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_json, Exception.message(error)}}
    end
  end

  defp entries(board) when is_map(board), do: entries([board])

  defp entries(boards) when is_list(boards) do
    boards
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {board, index}, {:ok, acc} ->
      case entry(board, index) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp entries(_other), do: {:error, :not_a_board_list}

  defp entry(board, index) when is_map(board) do
    case Map.get(board, "collection", Boards.default_collection_name()) do
      collection when is_binary(collection) ->
        if String.trim(collection) == "" do
          {:error, {:invalid_collection, index, collection}}
        else
          {:ok, %{index: index, collection: String.trim(collection), attrs: board_attrs(board)}}
        end

      other ->
        {:error, {:invalid_collection, index, other}}
    end
  end

  defp entry(_board, index), do: {:error, {:not_an_object, index}}

  # Fills in each clue's value from its row (100, 200, ...) when it is
  # missing or null; everything else is left for the changesets to validate.
  defp board_attrs(board) do
    case Map.get(board, "categories") do
      categories when is_list(categories) ->
        Map.put(board, "categories", Enum.map(categories, &category_attrs/1))

      _ ->
        board
    end
  end

  defp category_attrs(%{"clues" => clues} = category) when is_list(clues) do
    clues =
      clues
      |> Enum.with_index(1)
      |> Enum.map(fn
        {%{} = clue, row} ->
          if(clue["value"] == nil, do: Map.put(clue, "value", row * 100), else: clue)

        {clue, _row} ->
          clue
      end)

    %{category | "clues" => clues}
  end

  defp category_attrs(category), do: category

  defp check_duplicates(entries) do
    entries
    |> Enum.reduce_while(MapSet.new(), fn entry, seen ->
      key = {entry.collection, normalized_name(entry.attrs)}

      cond do
        elem(key, 1) == nil -> {:cont, seen}
        MapSet.member?(seen, key) -> {:halt, {:error, duplicate(entry)}}
        true -> {:cont, MapSet.put(seen, key)}
      end
    end)
    |> case do
      {:error, _} = error -> error
      _seen -> :ok
    end
  end

  defp duplicate(entry),
    do: {:duplicate_in_file, entry.index, entry.collection, normalized_name(entry.attrs)}

  defp normalized_name(%{"name" => name}) when is_binary(name), do: String.trim(name)
  defp normalized_name(_attrs), do: nil

  ## Importing

  defp import_all(entries, replace?) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      case import_one(entry, replace?) do
        {:ok, imported} -> {:cont, {:ok, [imported | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp import_one(entry, replace?) do
    {:ok, collection} = Boards.get_or_create_collection(entry.collection)
    name = normalized_name(entry.attrs)
    existing = name && Repo.get_by(Board, collection_id: collection.id, name: name)

    if existing && not replace? do
      {:error, {:already_exists, entry.index, collection.name, name}}
    else
      if existing, do: Repo.delete!(existing)

      case Boards.create_board(collection, entry.attrs) do
        {:ok, board} ->
          {:ok, %{board: board, collection: collection.name, replaced?: existing != nil}}

        {:error, changeset} ->
          {:error, {:invalid_board, entry.index, name, changeset}}
      end
    end
  end

  ## Error formatting

  defp translate({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  @labels %{categories: "category", clues: "clue"}

  defp flatten(errors, path) do
    Enum.flat_map(errors, fn {field, value} ->
      if Map.has_key?(@labels, field) and Enum.all?(value, &is_map/1) do
        value
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {child, i} -> flatten(child, path ++ ["#{@labels[field]} #{i}"]) end)
      else
        Enum.map(value, &"#{Enum.join(path, ", ")}: #{field} #{&1}")
      end
    end)
  end
end
