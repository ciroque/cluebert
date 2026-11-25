# Cluebert

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Deploying

Cluebert runs as a single pod in Kubernetes, from the Helm chart in
[`charts/cluebert`](charts/cluebert/README.md); see ADR 11. The image is
built from the `Dockerfile` by the *Build image* workflow when a PR is
merged into main.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
