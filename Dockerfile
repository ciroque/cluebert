# Builds a release image for the Helm chart in charts/cluebert.
#
# Runtime secrets (SECRET_KEY_BASE, database credentials) are not build
# args: they're given to the running container from a Kubernetes Secret, so
# they never end up in an image or its build history.

ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.5.0.5
ARG ALPINE_VERSION=3.24.1

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION} AS build

# git: heroicons is a git dependency.
RUN apk add --no-cache build-base git

ENV MIX_ENV=prod \
    LANG=C.UTF-8

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

# Dependencies first, so they're cached until mix.lock or the compile-time
# config changes.
COPY mix.exs mix.lock ./
RUN mix deps.get --only ${MIX_ENV}
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile
RUN mix assets.setup

COPY priv priv
COPY lib lib
COPY assets assets

# Compile before building assets: compiling extracts the colocated hooks
# that app.js imports.
RUN mix compile --warnings-as-errors
RUN mix assets.deploy

# runtime.exs is read at boot, so changing it needs no recompile.
COPY config/runtime.exs config/
RUN mix release

FROM alpine:${ALPINE_VERSION} AS app

RUN apk add --no-cache libstdc++ openssl ncurses-libs ca-certificates

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    PHX_SERVER=true \
    PORT=4000

WORKDIR /app
RUN adduser -D -H app && chown app:app /app
COPY --from=build --chown=app:app /app/_build/prod/rel/cluebert ./

USER app
EXPOSE 4000
CMD ["/app/bin/cluebert", "start"]
