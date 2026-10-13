# Changelog

## 0.1.0

- Add a Phoenix LiveView tag formatter for colocated JavaScript and TypeScript.
- Support Biome formatting, linting, assists, and safe fixes.
- Support ESLint linting and configured formatting fixes.
- Support colocated hooks, colocated JavaScript, JavaScript, TypeScript, JSX,
  and TSX.
- Add named command profiles in application configuration with optional
  `.formatter.exs` selection and overrides.
- Map diagnostics to the original Elixir or HEEx source and clean up isolated
  temporary files safely across concurrent formatter runs.
- Remap every ESLint stylish diagnostic and surface successful Biome and ESLint
  warnings, with optional warning-as-error behavior.
