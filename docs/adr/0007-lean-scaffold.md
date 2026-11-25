# 7. Lean scaffold

Date: 2026-11-25

## Status

Proposed. The keep list is still to be confirmed.

## Context

`mix phx.new` generated a welcome page, a mailer, a JSON API pipeline,
daisyUI and example comments. Cluebert uses none of these, and the generated
`AGENTS.md` already says not to use daisyUI.

## Decision

Remove:

- `PageController`, `PageHTML`, `page_html/home.html.heex`,
  `priv/static/images/logo.svg`, and the page controller test.
- The mailer: `lib/cluebert/mailer.ex`, the `:swoosh` dependency, its config
  in `config/*.exs`, and the `/dev/mailbox` route.
- The `:api` pipeline, `ErrorJSON` and its test.
- daisyUI: the `:daisyui` dependency in `mix.exs` and the `@plugin` entries
  in `assets/css/app.css`. Style with plain Tailwind.
- Generated example comments in the router and config files.

Keep:

- LiveDashboard and `CluebertWeb.Telemetry` (dev-only, useful).
- Gettext, because `core_components.ex` uses it for form error messages.
- `core_components.ex` and `layouts.ex`, restyled with plain Tailwind because
  their generated markup uses daisyUI classes (`btn`, `alert`, `input`, ...).

`/` routes to a LiveView instead of a controller.

## Consequences

- Less code to read, no unused dependencies.
- Removing daisyUI is not just a deletion: the kept components must be
  restyled in the same change, or buttons, inputs and flash messages render
  unstyled.
- If email or a JSON API is ever needed, regenerate the pieces with the
  Phoenix generators.
