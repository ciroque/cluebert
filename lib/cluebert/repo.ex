defmodule Cluebert.Repo do
  use Ecto.Repo,
    otp_app: :cluebert,
    adapter: Ecto.Adapters.Postgres
end
