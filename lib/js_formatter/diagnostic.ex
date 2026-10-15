defmodule JsFormatter.Diagnostic do
  @moduledoc false

  def format(%{output: output, status: status}, temporary_path, context, _config) do
    output = remap(output, temporary_path, context)

    failure_message(output, status, context)
  end

  def successful_output(output, temporary_path, context, config) do
    output = remap(output, temporary_path, context)
    warning? = warning_output?(output)

    cond do
      config.error_on_warnings and warning? ->
        {:error, warning_error_message(output, context)}

      display_success_output?(config.success_output, output, warning?) ->
        {:warning, warning_message(output, context)}

      true ->
        :ok
    end
  end

  defp failure_message(output, status, context) do
    """
    #{context.source_file}:#{context.source_line}: JavaScript formatting/linting failed for a colocated .#{context.extension} script (exit #{inspect(status)}).

    #{String.trim(output)}
    """
    |> String.trim()
  end

  defp warning_error_message(output, context) do
    """
    #{context.source_file}:#{context.source_line}: JavaScript formatting/linting failed for a colocated .#{context.extension} script because warnings are configured as errors.

    #{String.trim(output)}
    """
    |> String.trim()
  end

  defp warning_message(output, context) do
    """
    #{context.source_file}:#{context.source_line}: JavaScript formatter output for a colocated .#{context.extension} script:

    #{String.trim(output)}
    """
    |> String.trim()
  end

  defp display_success_output?(:ignore, _output, _warning?), do: false
  defp display_success_output?(:warnings, _output, warning?), do: warning?
  defp display_success_output?(:always, output, _warning?), do: String.trim(output) != ""

  defp warning_output?(output) do
    Regex.match?(~r/\b[1-9]\d*\s+warnings?\b|::warning\b|^\s+\d+:\d+\s+warning\s/imu, output)
  end

  defp remap(output, temporary_path, context) do
    location = ~r/#{Regex.escape(temporary_path)}:(\d+):(\d+)/
    basename_location = ~r/#{Regex.escape(Path.basename(temporary_path))}:(\d+):(\d+)/

    output
    |> remap_prettier_location(temporary_path, context)
    |> remap_prettier_location(Path.basename(temporary_path), context)
    |> remap_stylish_location(temporary_path, context)
    |> remap_stylish_location(Path.basename(temporary_path), context)
    |> then(fn output ->
      Regex.replace(location, output, fn _match, line, column ->
        mapped_location(context, line, column)
      end)
    end)
    |> then(fn output ->
      Regex.replace(basename_location, output, fn _match, line, column ->
        mapped_location(context, line, column)
      end)
    end)
    |> String.replace(temporary_path, context.source_file)
    |> String.replace(Path.basename(temporary_path), Path.basename(context.source_file))
  end

  defp remap_prettier_location(output, path, context) do
    location =
      ~r/(\[error\]\s+)#{Regex.escape(path)}:\s+([^\r\n]*?)\s+\((\d+):(\d+)\)/

    Regex.replace(location, output, fn _match, prefix, message, line, column ->
      "#{prefix}#{mapped_location(context, line, column)}: #{message}"
    end)
  end

  defp remap_stylish_location(output, path, context) do
    header = ~r/(^|\r?\n)#{Regex.escape(path)}\r?\n/

    if Regex.match?(header, output) do
      output = String.replace(output, path, context.source_file)

      Regex.replace(~r/^(\s+)(\d+):(\d+)(?=\s)/m, output, fn
        _match, whitespace, line, column ->
          mapped_line = context.source_line + String.to_integer(line) - 1
          "#{whitespace}#{mapped_line}:#{column}"
      end)
    else
      output
    end
  end

  defp mapped_location(context, line, column) do
    source_line = context.source_line + String.to_integer(line) - 1
    "#{context.source_file}:#{source_line}:#{column}"
  end
end
