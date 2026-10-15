# JsFormatter Agent Guide

## Project scope

- This repository is a standalone Elixir library for formatting and linting
  Phoenix LiveView colocated JavaScript and TypeScript.
- Keep it independent from consuming applications and component libraries.
  Do not add application-specific modules, paths, configuration, or examples.
- The package is development tooling. It must not start application processes
  or add runtime behavior to consuming applications.
- Prefer small, pure functions and explicit data flow.
- `demo/` is a real Phoenix consumer fixture. It may contain application-level
  examples solely to exercise this package end to end; keep those examples
  focused on formatter integration.

## Architecture

- `JsFormatter` implements
  `Phoenix.LiveView.HTMLFormatter.TagFormatter`.
- Consumers must continue to use `Phoenix.LiveView.HTMLFormatter` as their Mix
  formatter plugin and configure `tag_formatters: %{script: JsFormatter}`.
  Do not turn `JsFormatter` into a competing HEEx parser or require consumers
  to define formatter modules in their applications.
- `JsFormatter.Source` decides whether a tag is supported and derives its
  language extension and original source location.
- `JsFormatter.TempFile` owns temporary-file creation and cleanup.
- `JsFormatter.Config` resolves named command profiles and their precedence.
- `JsFormatter.Command` owns shared process execution. Diagnostic remapping
  belongs in `JsFormatter.Diagnostic`.
- New formatter/linter integrations should normally be command profiles rather
  than new Elixir modules. A compatible command accepts the temporary source
  path as its final argument, updates the file in place, and uses its exit
  status and output for diagnostics.

## Supported source

- Process only `<script>` tags whose `:type` identifies
  `Phoenix.LiveView.ColocatedHook` or `Phoenix.LiveView.ColocatedJS`, including
  their standard final module-name aliases.
- Skip ordinary script tags.
- Support `js`, `jsx`, `ts`, and `tsx` by default.
- Preserve support for deriving the extension from `manifest` when an
  `extension` attribute is absent.
- Runtime colocated hooks are skipped by default because their bodies are not
  necessarily valid standalone JavaScript modules. Keep any opt-in behavior
  explicit and documented.
- Operate on the source embedded in `.heex` files and `~H` sigils. Never lint
  LiveView's generated `phoenix-colocated` build output.

## Command behavior

- Built-in `:biome`, `:eslint`, and `:prettier` profiles supply safe default
  commands.
- Invoke executables directly with argument lists. Do not accept or construct
  interpolated shell command strings.
- Append the temporary source path as the final command argument.
- Custom profiles must follow the same write-in-place and exit-status contract.

### Biome

- Keep the default Biome integration on a real temporary file using
  `biome check --write`.
- This behavior was verified with Biome 2.5.12. Its stdin check path does not
  provide the same diagnostics and failure status as normal file traversal:
  without `--write`, changed input fails as unfixed; with `--write`, remaining
  lint errors can be omitted while the command returns processed source with a
  successful status.
- `check --write` is intentional because it combines formatting, safe lint
  fixes, and safe assist actions while preserving reliable diagnostics for
  errors that remain.
- Do not replace the real-file flow with stdin, the daemon, LSP, or an
  unsupported library interface without reproducing and documenting equivalent
  formatting, linting, assist, diagnostics, configuration, and exit behavior.

### ESLint

- Use ESLint's fix mode so configured safe fixes are written back before the
  source is returned to LiveView.
- Remember that ESLint is not a general-purpose formatter by itself. Layout
  changes depend on the consuming project's configured fixable rules and
  plugins.
- TypeScript parsing depends on the consuming project's ESLint configuration
  and parser setup; do not bundle or silently impose a TypeScript ESLint stack.

### Prettier

- Use Prettier's real-file `--write` mode so project configuration and plugins
  resolve from the isolated file path.
- Prettier is a formatter, not a linter. Do not describe it as providing lint
  rules, assists, or safe lint fixes.
- Preserve parse and configuration failures as formatter errors with remapped
  original source paths.

## Temporary-file invariants

- Temporary files must be unique across concurrent tasks and OS processes.
- Create files exclusively and always remove them in an `after` block on
  success, tool failure, or exception.
- Invoke executables with argument lists, not interpolated shell commands.
  Paths containing spaces must remain safe.
- By default, place the isolated file in the profile's configured `:cd` so
  the tool can discover the project's configuration and path-based overrides.
- Never overwrite the original `.ex`, `.exs`, or `.heex` file from a command.
  LiveView owns reinserting returned content into the original source.
- Any lifecycle change must retain cleanup and concurrency tests.

## Errors and diagnostics

- A formatter or linter error must fail `mix format`; do not log and silently
  return `:skip` after a supported colocated script has been selected.
- Missing executables must produce an actionable error that explains local,
  PATH, and explicit configuration options.
- Replace temporary paths in tool diagnostics with the original Elixir/HEEx
  source path.
- Map snippet line numbers back to the embedded content's source location when
  the original content can be located. Retain a useful formatter-provided
  fallback line when exact matching is unavailable.
- Remap every location row in multi-diagnostic ESLint stylish output, not only
  the first row following the file path.
- Surface recognized warning diagnostics from successful commands by default,
  and preserve the configurable warning-as-error behavior.
- Do not suppress parse errors, remaining lint errors, or tool startup errors.

## Configuration and dependencies

- Read package-wide defaults from `config :js_formatter` application
  configuration. Allow the `:js_formatter` section of `.formatter.exs` to
  override those defaults for formatter-specific cases.
- Preserve named profiles and configurable command, argument list, working
  directory, environment, temporary directory, successful-output policy,
  warning policy, supported extensions, and accepted colocated type names.
- The minimum supported Phoenix LiveView version is 1.2 because that release
  introduced `Phoenix.LiveView.HTMLFormatter.TagFormatter`.
- Do not broaden or tighten dependency constraints in a way that unexpectedly
  upgrades consuming Phoenix applications. Document intentional minimum-version
  changes.
- Keep the dependency suitable for `only: [:dev, :test], runtime: false` use.
- Do not add a long-running application supervision tree for formatter work.

## Testing

- Keep the default test suite self-contained. Use controlled fake executables
  for deterministic command, failure, cleanup, concurrency, and path tests.
- Tests must cover, at minimum:
  - JavaScript and TypeScript formatting
  - safe Biome and ESLint fixes
  - Prettier formatting and parse failures
  - genuine remaining lint failures
  - syntax errors
  - colocated hooks and colocated JavaScript
  - TSX
  - ordinary script tags being skipped
  - `.heex` and `~H` reinsertion through the LiveView formatter
  - original path and line diagnostics
  - multi-error ESLint location mapping
  - successful warnings and warning-as-error behavior
  - cleanup on success and failure
  - concurrent invocations
  - missing executables
  - paths containing spaces
- When changing a built-in profile's CLI contract, also verify it against the
  real supported tool version when practical. Do not make ordinary tests
  download Node packages or depend on globally installed tools.

## Verification

After implementation work:

1. Run `mix compile`.
2. Run `mix format`.
3. Run the complete `mix test` suite; this library's suite is intentionally
   focused and should remain fast.
4. For documentation or public API changes, run `mix docs` and resolve all
   warnings.
5. For dependency, metadata, or release changes, run `mix hex.build` and remove
   the generated tarball after validation.
6. For formatter integration changes, install `demo/assets` dependencies and
   run the demo's `mix precommit` plus `mix assets.build`. Verify
   `JS_FORMATTER_TOOL=biome mix format --check-formatted`,
   `JS_FORMATTER_TOOL=eslint mix format --check-formatted`, and
   `JS_FORMATTER_TOOL=prettier mix format --check-formatted`.

If Mix cannot open its local PubSub socket because of sandbox restrictions,
rerun the same command with the required permission rather than changing the
project to work around the sandbox.

## Documentation

- Keep `README.md` examples copyable and aligned with the real public API.
- Clearly distinguish LiveView's Mix formatter plugin from this package's tag
  formatter role.
- Document tool differences and behavioral limitations instead of implying
  that Biome and ESLint have identical formatter semantics.
- Update the temporary-file and stdin rationale when supported tool behavior
  changes.
