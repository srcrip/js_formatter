defmodule JsFormatter.Command do
  @moduledoc false

  alias JsFormatter.Config

  def run(path, %Config{} = config) do
    with {:ok, executable} <- Config.executable(config),
         {:ok, output} <- execute(executable, config.args ++ [path], config),
         {:ok, formatted} <- File.read(path) do
      {:ok, %{source: formatted, output: output}}
    else
      {:error, message} when is_binary(message) ->
        {:error, %{output: message, status: :not_found}}

      {:error, %{output: _output, status: _status} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, %{output: :file.format_error(reason), status: :file_error}}
    end
  end

  defp execute(executable, args, config) do
    options = [
      cd: config.cd,
      env: Enum.to_list(config.env),
      stderr_to_stdout: true
    ]

    try do
      case System.cmd(executable, args, options) do
        {output, 0} -> {:ok, output}
        {output, status} -> {:error, %{output: output, status: status}}
      end
    rescue
      error in ErlangError ->
        {:error, %{output: Exception.message(error), status: :command_failed}}
    end
  end
end
