# JsFormatter

`JsFormatter` formats and, when supported by the selected tool, lints JavaScript
and TypeScript embedded in Phoenix LiveView colocated hooks and colocated
JavaScript. It includes sensible command profiles for
[Biome](https://biomejs.dev/), [ESLint](https://eslint.org/), and
[Prettier](https://prettier.io/). Custom profiles can run other compatible tools
without adding an Elixir module.

It operates on the source inside `.heex` files and `~H` sigils. It does not
inspect LiveView's generated `phoenix-colocated` output.

## Requirements

- Elixir 1.15 or later
- Phoenix LiveView 1.2 or later (the first release with
  `Phoenix.LiveView.HTMLFormatter.TagFormatter`)
- A project-local or PATH-installed JavaScript tool

## Installation

Add the package as a development/test-only dependency. `runtime: false` keeps
it out of application runtime behavior:

```elixir
def deps do
  [
    {:js_formatter, "~> 0.2.0", only: [:dev, :test], runtime: false}
  ]
end
```

The package requires LiveView 1.2 but does not declare or run an application
process. If the consuming project is still on LiveView 1.1, upgrade LiveView
deliberately before adding this formatter.

Install and configure a JavaScript tool in the consuming project. For example:

```console
cd assets
npm install --save-dev @biomejs/biome
# or
npm install --save-dev eslint
# or
npm install --save-dev --save-exact prettier
```

`JsFormatter` does not bundle these executables or impose a JavaScript parser
or rule set. TypeScript support with ESLint therefore requires the consuming
project's ESLint configuration to select an appropriate TypeScript parser.

## Configuration

Configure named command profiles in the consuming application's
`config/config.exs`:

```elixir
import Config

assets_directory = Path.expand("../assets", __DIR__)

config :js_formatter,
  default_profile: :biome,
  biome: [
    command: "biome",
    args: [
      "check",
      "--write",
      "--colors=off",
      "--max-diagnostics=none",
      "--config-path",
      Path.join(assets_directory, "biome.json")
    ],
    cd: assets_directory
  ],
  eslint: [
    command: "eslint",
    args: [
      "--fix",
      "--format",
      "stylish",
      "--config",
      Path.join(assets_directory, "eslint.config.mjs")
    ],
    cd: assets_directory
  ],
  prettier: [
    command: "prettier",
    args: [
      "--write",
      "--config",
      Path.join(assets_directory, "prettier.config.mjs")
    ],
    cd: assets_directory
  ]
```

Then keep `Phoenix.LiveView.HTMLFormatter` as the Mix formatter plugin and
register `JsFormatter` as its formatter for script tags:

```elixir
# .formatter.exs
[
  import_deps: [:phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"],
  tag_formatters: %{script: JsFormatter}
]
```

No formatter module needs to be defined in the consuming application.
`JsFormatter` reads application configuration without starting an application
process, so it remains suitable for a development/test-only dependency with
`runtime: false`.

The complete profile definitions above make every command option visible, but
`:biome`, `:eslint`, and `:prettier` are built in. When the tools can discover
their normal project configuration, this smaller setup is equivalent:

```elixir
config :js_formatter,
  default_profile: :biome,
  biome: [cd: Path.expand("../assets", __DIR__)],
  eslint: [cd: Path.expand("../assets", __DIR__)],
  prettier: [cd: Path.expand("../assets", __DIR__)]
```

The built-in Biome arguments are `biome check --write --colors=off
--max-diagnostics=none`. The built-in ESLint arguments are `eslint --fix
--format stylish`. The built-in Prettier arguments are `prettier --write`.
Supplying `:args` in a named profile replaces that built-in argument list.

Biome formats, lints, and applies safe assists. ESLint lints and applies the
fixes supplied by the consuming project's rules and plugins. Prettier formats
and reports parse or configuration errors, but it does not lint. Warning
diagnostics returned by Biome or ESLint with a successful exit status are
remapped to the original Elixir/HEEx source and written to standard error by
default.

### Selecting and overriding profiles

Application configuration selects the package-wide default. The optional
`:js_formatter` section of `.formatter.exs` can select a different profile or
override values for that formatter:

```elixir
[
  plugins: [Phoenix.LiveView.HTMLFormatter],
  tag_formatters: %{script: JsFormatter},
  js_formatter: [profile: :eslint]
]
```

Configuration precedence is:

1. the built-in `:biome`, `:eslint`, or `:prettier` profile;
2. the selected named profile from `config :js_formatter`;
3. overrides in `.formatter.exs` under `:js_formatter`.

`:profile` in `.formatter.exs` takes precedence over `:default_profile`.

### Profile options

- `:command` — executable name or path. Executable discovery checks
  `node_modules/.bin` below `:cd`, the formatter invocation directory,
  `assets/node_modules/.bin`, and then `PATH`.
- `:args` — a list of command arguments. `JsFormatter` appends the isolated
  source path as the final argument.
- `:cd` — command working directory and the default temporary-file directory;
  defaults to the directory in which `mix format` runs.
- `:env` — a map of string environment-variable names to string values added
  to the command environment; defaults to `%{}`.
- `:temporary_directory` — where isolated source files are created; defaults
  to `:cd` so normal configuration discovery and path overrides apply.
- `:success_output` — controls output from commands that exit successfully.
  `:warnings` (the default) prints recognized Biome and ESLint warning output
  while suppressing routine success summaries; `:always` prints all nonempty
  output; `:ignore` discards it.
- `:error_on_warnings` — fail formatting when a successful command reports
  warnings; defaults to `false`. This recognizes the standard warning output
  produced by the built-in Biome and ESLint profiles.
- `:extensions` — extensions to process; defaults to `js`, `jsx`, `ts`, and
  `tsx`.
- `:types` — accepted `:type` names; defaults to `ColocatedHook` and
  `ColocatedJS`. Fully qualified names and those standard final module segments
  are accepted. Add a custom alias such as `"Hook"` explicitly.
- `:format_runtime` — opt into processing runtime colocated hooks. It defaults
  to `false` because runtime hook bodies are expressions rather than ordinary
  JavaScript modules and are not always valid as standalone files.

`default_profile` is an application-level option rather than a profile option.
It defaults to `:biome`.

Commands are invoked directly with `System.cmd/3`; they are not interpreted by
a shell. Keep the executable and arguments separate instead of configuring a
single value such as `"biome check --write"`. This prevents quoting problems
and keeps source paths containing spaces safe. If a tool requires shell
features such as a pipeline, point `:command` at a project-owned wrapper
executable.

### Custom profiles

A custom profile needs no Elixir integration module. Its command must accept
the isolated source path as its final argument, update that file in place, exit
with status 0 when successful, and print diagnostics plus return a nonzero
status when errors remain:

```elixir
config :js_formatter,
  default_profile: :project_js,
  project_js: [
    command: "scripts/check-colocated-js",
    args: ["--fix"],
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_ENV" => "development"}
  ]
```

The profile can also be defined entirely in `.formatter.exs` by providing
`:profile`, `:command`, and any desired options there.

### Biome `files.includes` troubleshooting

Biome applies `files.includes` to the isolated file that `JsFormatter` creates,
not to the original `.ex` or `.heex` path. A restrictive include list can
therefore produce `No files were processed` even though the colocated script is
valid.

Place the isolated file inside a directory already accepted by the Biome
configuration. In Phoenix projects, setting `:cd` to `assets` is often enough
because it is also the default temporary-file directory:

```elixir
assets_directory = Path.expand("../assets", __DIR__)

config :js_formatter,
  biome: [
    cd: assets_directory
  ]
```

If the command must run from a different directory, set
`:temporary_directory` independently to a directory matched by
`files.includes`:

```elixir
config :js_formatter,
  biome: [
    cd: Path.expand("..", __DIR__),
    temporary_directory: Path.expand("../assets/js", __DIR__)
  ]
```

Alternatively, expand the Biome include patterns to accept the configured
temporary directory. Temporary files use a `js_formatter_` prefix and retain
the colocated source's `js`, `jsx`, `ts`, or `tsx` extension. They are removed
after success, command failure, or exception.

## Supported tags

Both forms are supported, including `js`, `jsx`, `ts`, and `tsx` extensions:

```heex
<script :type={Phoenix.LiveView.ColocatedHook} name=".Example" extension="ts">
  export default {
    mounted() {
      console.log(this.el)
    }
  }
</script>

<script :type={Phoenix.LiveView.ColocatedJS} name="ExampleElement" extension="ts">
  export default class ExampleElement extends HTMLElement {}
</script>
```

An extension on `manifest`, such as `manifest="hooks.ts"`, is also recognized
for compatibility with early LiveView 1.2 examples. Ordinary `<script>` tags
are returned unchanged.

## Why commands receive a temporary file

LiveView's tag formatter gives a formatter the script text, attributes, and
original formatter file metadata. It does not create a JavaScript file.

Biome's `--stdin-file-path` is useful for formatting, but Biome's stdin path is
not equivalent to normal file traversal for combined check diagnostics and
failure status. This was verified against Biome 2.5.12: without `--write`, a
valid input that needs changes fails with “The contents aren't fixed”; with
`--write`, a configured `noConsole` error returns processed source with status
0 and no traversal diagnostics. The JSON reporter is also not applied to that
stdin path. A supported library API is not exposed by the native executable,
while the daemon and LSP protocols are designed for long-lived editor
integrations rather than deterministic `mix format` calls.

For that reason the built-in Biome profile runs one `biome check --write`
against an isolated real file. That single command applies formatting, safe
lint fixes, and safe assist actions, then returns reliable diagnostics and a
nonzero status for errors that remain. The built-in ESLint profile uses the
equivalent `eslint --fix` file path, and the Prettier profile uses
`prettier --write`. This keeps all three tools on the same simple and testable
lifecycle.

Temporary names include the OS process and a VM-monotonic unique value, so
concurrent formatter processes do not share files. Creation is exclusive, the
command is invoked with an argument list, and the file is removed in an
`after` block on success, tool failure, or exception. Diagnostics replace the
temporary path with the original Elixir/HEEx path and map snippet line numbers
from the located script body when possible.

## Architecture

`Phoenix.LiveView.HTMLFormatter` continues to parse and rewrite HEEx. It invokes
`JsFormatter` only through the configured `tag_formatters` entry. `JsFormatter`
filters colocated scripts, determines the source extension, creates the
isolated file, and invokes the selected command profile. The command either
updates the isolated file for LiveView to put back into the original template
or fails with `JsFormatter.Error` and remapped diagnostics.

## Phoenix integration demo

The [`demo`](demo/README.md) directory is a generated Phoenix application that
uses this repository as a path dependency. It provides an end-to-end consumer
fixture with real TypeScript and TSX examples and runs `mix format` against
project-local, pinned Biome, ESLint, and Prettier installations. It is
intentionally kept outside the published package files.
