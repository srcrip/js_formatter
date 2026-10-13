defmodule JsFormatter.TempFile do
  @moduledoc false

  alias JsFormatter.{Config, Error}

  def with_file(content, context, %Config{} = config, fun) do
    directory = config.temporary_directory
    :ok = ensure_directory(directory)
    path = unique_path(directory, context)

    case File.write(path, content, [:write, :exclusive, :binary]) do
      :ok ->
        try do
          fun.(path)
        after
          File.rm(path)
        end

      {:error, reason} ->
        raise Error,
          message:
            "could not create temporary JavaScript file #{path}: #{:file.format_error(reason)}"
    end
  end

  defp ensure_directory(directory) do
    case File.mkdir_p(directory) do
      :ok ->
        :ok

      {:error, reason} ->
        raise File.Error, action: "create directory", path: directory, reason: reason
    end
  end

  defp unique_path(directory, context) do
    pid = System.pid()
    unique = System.unique_integer([:monotonic, :positive])
    basename = context.source_file |> Path.basename() |> Path.rootname() |> sanitize()
    Path.join(directory, "js_formatter_#{pid}_#{unique}_#{basename}.#{context.extension}")
  end

  defp sanitize(name), do: String.replace(name, ~r/[^a-zA-Z0-9_-]/u, "_")
end
