# JsFormatter Phoenix demo

This is a real Phoenix 1.8 application that consumes the parent `js_formatter`
package through a development/test-only path dependency. Its home LiveView
contains all of the primary integration cases:

- a TypeScript `Phoenix.LiveView.ColocatedHook`;
- a TypeScript `Phoenix.LiveView.ColocatedJS` custom element; and
- a TSX `Phoenix.LiveView.ColocatedJS` module.

The formatter defaults to the named `:biome` command profile.
`config/config.exs` defines the `:biome`, `:eslint`, and `:prettier` profiles,
while `.formatter.exs` only registers the tag formatter. Select another profile
with `JS_FORMATTER_TOOL=eslint` or `JS_FORMATTER_TOOL=prettier`.

## Set up

```console
mix deps.get
cd assets && bun install && cd ..
```

The generated application still uses Phoenix's default PostgreSQL setup. Run
`mix setup` instead of `mix deps.get` when you also want to create its database
and launch the application.

## Exercise the formatter

```console
# Format and check with Biome
mix format
mix format --check-formatted

# Format and check with ESLint
JS_FORMATTER_TOOL=eslint mix format
JS_FORMATTER_TOOL=eslint mix format --check-formatted

# Format and check with Prettier
JS_FORMATTER_TOOL=prettier mix format
JS_FORMATTER_TOOL=prettier mix format --check-formatted
```

Both commands process the JavaScript/TypeScript inside the original
`formatter_demo_live.ex` source. They do not lint Phoenix's generated
`phoenix-colocated` bundle.

The integration tests invoke formatter commands as child OS processes. They
verify the generated consumer application's actual application configuration,
`.formatter.exs`, path dependency, local tool executables, successful source
rewrites, lint failures, and original source locations:

```console
mix test test/js_formatter_integration_test.exs
```

To exercise the browser bundle too:

```console
mix assets.build
```

The demo is a validation fixture, not part of the published Hex package.
