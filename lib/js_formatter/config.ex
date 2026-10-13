defmodule JsFormatter.Config do
  @moduledoc """
  Normalized command profile used for a formatter invocation.

  Consumers define named profiles with `config :js_formatter`. A profile
  selects an executable plus its arguments and execution environment. Options
  in the `:js_formatter` section of `.formatter.exs` may select or override the
  configured profile.
  """

  @default_extensions ~w(js jsx ts tsx)
  @default_types ~w(ColocatedHook ColocatedJS)

  @built_in_profiles [
    biome: [
      command: "biome",
      args: ["check", "--write", "--colors=off", "--max-diagnostics=none"]
    ],
    eslint: [command: "eslint", args: ["--fix", "--format", "stylish"]]
  ]

  @type t :: %__MODULE__{
          profile: atom(),
          command: String.t(),
          args: [String.t()],
          cd: Path.t(),
          env: %{optional(String.t()) => String.t()},
          temporary_directory: Path.t(),
          success_output: :ignore | :warnings | :always,
          error_on_warnings: boolean(),
          format_runtime: boolean(),
          extensions: [String.t()],
          types: [String.t()]
        }

  defstruct profile: :biome,
            command: "biome",
            args: [],
            cd: nil,
            env: %{},
            temporary_directory: nil,
            success_output: :warnings,
            error_on_warnings: false,
            format_runtime: false,
            extensions: @default_extensions,
            types: @default_types

  def from_formatter_options(opts) do
    application_options = Application.get_all_env(:js_formatter)
    formatter_options = Keyword.get(opts, :js_formatter, [])

    from_options(application_options, formatter_options)
  end

  @doc false
  def from_options(application_options, formatter_options) do
    profile =
      Keyword.get(
        formatter_options,
        :profile,
        Keyword.get(application_options, :default_profile, :biome)
      )

    with :ok <- validate_profile(profile),
         {:ok, profile_options} <-
           profile_options(application_options, formatter_options, profile) do
      values =
        profile_options
        |> Keyword.merge(Keyword.delete(formatter_options, :profile))
        |> Keyword.put(:profile, profile)

      normalize(values)
    end
  end

  def executable(%__MODULE__{} = config) do
    config.command
    |> executable_candidates(config.cd)
    |> Enum.find(&executable?/1)
    |> case do
      nil ->
        {:error,
         "could not find the #{inspect(config.command)} executable for the #{inspect(config.profile)} " <>
           "js_formatter profile. Install it in node_modules, place it on PATH, or configure " <>
           ":command with an executable path"}

      executable ->
        {:ok, executable}
    end
  end

  defp validate_profile(profile) do
    if is_atom(profile),
      do: :ok,
      else: {:error, "invalid js_formatter profile #{inspect(profile)}; expected an atom"}
  end

  defp profile_options(application_options, formatter_options, profile) do
    built_in_options = Keyword.get(@built_in_profiles, profile, [])
    configured_options = Keyword.get(application_options, profile, [])
    formatter_defines_command? = Keyword.has_key?(formatter_options, :command)

    if built_in_options == [] and configured_options == [] and not formatter_defines_command? do
      {:error,
       "unknown js_formatter profile #{inspect(profile)}. Define it with config :js_formatter, " <>
         "#{profile}: [command: \"...\", args: [...]]"}
    else
      {:ok, Keyword.merge(built_in_options, configured_options)}
    end
  end

  defp normalize(values) do
    cwd = File.cwd!()
    cd = values |> Keyword.get(:cd, cwd) |> Path.expand(cwd)
    command = Keyword.get(values, :command)
    args = Keyword.get(values, :args, [])
    env = Keyword.get(values, :env, %{})
    success_output = Keyword.get(values, :success_output, :warnings)
    error_on_warnings = Keyword.get(values, :error_on_warnings, false)

    with :ok <- validate_command(command),
         :ok <- validate_args(args),
         :ok <- validate_env(env),
         :ok <- validate_success_output(success_output),
         :ok <- validate_error_on_warnings(error_on_warnings) do
      {:ok,
       struct!(__MODULE__,
         profile: Keyword.fetch!(values, :profile),
         command: command,
         args: args,
         cd: cd,
         env: env,
         temporary_directory: temporary_directory(values, cd),
         success_output: success_output,
         error_on_warnings: error_on_warnings,
         format_runtime: Keyword.get(values, :format_runtime, false),
         extensions: normalize_extensions(Keyword.get(values, :extensions, @default_extensions)),
         types: Keyword.get(values, :types, @default_types)
       )}
    end
  end

  defp validate_command(command) do
    if is_binary(command) and command != "",
      do: :ok,
      else: {:error, "invalid :command #{inspect(command)}; expected a non-empty executable name"}
  end

  defp validate_args(args) do
    if is_list(args) and Enum.all?(args, &is_binary/1),
      do: :ok,
      else: {:error, "invalid :args #{inspect(args)}; expected a list of strings"}
  end

  defp validate_env(env) do
    valid? =
      is_map(env) and
        Enum.all?(env, fn {key, value} -> is_binary(key) and is_binary(value) end)

    if valid?,
      do: :ok,
      else: {:error, "invalid :env #{inspect(env)}; expected a map of string keys and values"}
  end

  defp validate_success_output(success_output) do
    if success_output in [:ignore, :warnings, :always],
      do: :ok,
      else:
        {:error,
         "invalid :success_output #{inspect(success_output)}; expected :ignore, :warnings, or :always"}
  end

  defp validate_error_on_warnings(error_on_warnings) do
    if is_boolean(error_on_warnings),
      do: :ok,
      else:
        {:error, "invalid :error_on_warnings #{inspect(error_on_warnings)}; expected a boolean"}
  end

  defp temporary_directory(values, cd) do
    values
    |> Keyword.get(:temporary_directory, cd)
    |> Path.expand(cd)
  end

  defp normalize_extensions(extensions) do
    Enum.map(extensions, &(&1 |> to_string() |> String.trim_leading(".") |> String.downcase()))
  end

  defp executable_candidates(command, cd) do
    if Path.type(command) == :relative and not String.contains?(command, ["/", "\\"]) do
      [
        Path.join([cd, "node_modules", ".bin", command]),
        Path.join([File.cwd!(), "node_modules", ".bin", command]),
        Path.join([File.cwd!(), "assets", "node_modules", ".bin", command]),
        System.find_executable(command)
      ]
    else
      [Path.expand(command, cd)]
    end
  end

  defp executable?(nil), do: false
  defp executable?(path), do: File.regular?(path)
end
