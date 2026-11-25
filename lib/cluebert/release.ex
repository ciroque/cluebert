defmodule Cluebert.Release do
  @moduledoc """
  Tasks for a built release, where `mix` isn't available. The Helm chart's
  migrate Job runs them with `eval`:

      bin/cluebert eval "Cluebert.Release.migrate()"
      bin/cluebert eval "Cluebert.Release.seed()"
  """
  @app :cluebert

  @doc "Runs every pending migration."
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc """
  Runs `priv/repo/seeds.exs`, which imports every board in `priv/boards/`
  and replaces boards of the same name (ADR 9). Meant for a first install;
  run again, it would undo edits made in the app to those boards.
  """
  def seed do
    load_app()
    seeds = Application.app_dir(@app, "priv/repo/seeds.exs")

    {:ok, _, _} = Ecto.Migrator.with_repo(Cluebert.Repo, fn _repo -> Code.eval_file(seeds) end)
    :ok
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    # Releases may not start :ssl before the Repo needs it.
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
