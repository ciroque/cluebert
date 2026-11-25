defmodule CluebertWeb.PageController do
  use CluebertWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
