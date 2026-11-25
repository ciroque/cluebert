defmodule CluebertWeb.HomeLive do
  @moduledoc """
  The landing page at `/`.

  A placeholder for now; step 4 of the build plan turns it into the page
  where the host chooses a board and starts a game.
  """
  use CluebertWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Home")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="home" class="py-16 text-center">
        <h1 class="text-4xl font-bold tracking-tight text-zinc-900 sm:text-5xl">Cluebert</h1>
        <p class="mt-4 text-lg text-zinc-600">
          Trivia for a room full of people. Boards and games are on the way.
        </p>
      </section>
    </Layouts.app>
    """
  end
end
