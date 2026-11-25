defmodule CluebertWeb.HealthController do
  @moduledoc """
  `GET /health`, for Kubernetes' liveness and readiness probes.

  It answers `ok` as long as the endpoint is serving, and deliberately does
  not touch the database: games live only in this node's memory (ADR 4), so
  restarting the pod because the database blinked would end every game in
  progress.
  """
  use CluebertWeb, :controller

  @doc "Responds `200 ok` in plain text."
  def show(conn, _params), do: text(conn, "ok")
end
