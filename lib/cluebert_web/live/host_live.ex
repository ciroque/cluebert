defmodule CluebertWeb.HostLive do
  @moduledoc """
  The host screen for a game, at `/games/:id/host` (ADR 8).

  For now it only shows the play order; the board, responses and judging
  come in the next step of the build plan.
  """
  use CluebertWeb, :live_view

  alias Cluebert.GameServer

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case GameServer.get(id) do
      {:ok, %{game: game, board: board}} ->
        {:ok,
         socket
         |> assign(:page_title, board.name)
         |> assign(:game_id, id)
         |> assign(:board, board)
         |> assign(:game, game)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That game no longer exists.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@board.name}
        <:subtitle>Play order</:subtitle>
      </.header>

      <ol id="play-order" class="space-y-2">
        <li
          :for={{team_id, index} <- Enum.with_index(@game.team_order, 1)}
          id={"play-order-#{team_id}"}
          class="flex items-center gap-3 rounded-lg bg-white px-4 py-3 shadow-sm ring-1 ring-zinc-200"
        >
          <span class="flex size-7 items-center justify-center rounded-full bg-blue-600 text-sm font-bold text-white">
            {index}
          </span>
          <span class="font-medium">{@game.teams[team_id].name}</span>
        </li>
      </ol>
    </Layouts.app>
    """
  end
end
