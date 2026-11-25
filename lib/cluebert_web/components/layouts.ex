defmodule CluebertWeb.Layouts do
  @moduledoc """
  Layouts for Cluebert pages.

  `root.html.heex` holds the HTML skeleton; `app/1` wraps every LiveView.
  """
  use CluebertWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the app layout: a header, the page content and the flash group.

  With `full_screen`, there is no header and the content fills the whole
  window, for the player screen shown on a TV (ADR 8).

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :full_screen, :boolean, default: false, doc: "drop the header and fill the window"

  slot :inner_block, required: true

  def app(%{full_screen: true} = assigns) do
    ~H"""
    <main class="min-h-screen">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  def app(assigns) do
    ~H"""
    <header class="border-b border-zinc-200 bg-white px-4 sm:px-6 lg:px-8">
      <div class="mx-auto flex h-14 max-w-5xl items-center justify-between">
        <.link
          navigate={~p"/"}
          class="text-lg font-bold tracking-tight text-zinc-900 transition-colors hover:text-blue-700"
        >
          Cluebert
        </.link>
        <nav id="main-nav" class="flex items-center gap-1 text-sm font-medium">
          <.link
            navigate={~p"/"}
            id="nav-new-game"
            class="rounded-md px-3 py-1.5 text-zinc-600 transition-colors hover:bg-zinc-100 hover:text-zinc-900"
          >
            New game
          </.link>
          <.link
            navigate={~p"/boards"}
            id="nav-boards"
            class="rounded-md px-3 py-1.5 text-zinc-600 transition-colors hover:bg-zinc-100 hover:text-zinc-900"
          >
            Boards
          </.link>
        </nav>
      </div>
    </header>

    <main class="px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-5xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
