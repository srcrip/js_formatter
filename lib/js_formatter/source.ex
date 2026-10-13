defmodule JsFormatter.Source do
  @moduledoc false

  alias JsFormatter.Config

  def extension(attrs, %Config{} = config) do
    cond do
      not colocated?(attrs, config.types) -> :skip
      Map.has_key?(attrs, "runtime") and not config.format_runtime -> :skip
      true -> supported_extension(attrs, config.extensions)
    end
  end

  def context(content, extension, opts, %Config{}) do
    source_file = opts |> Keyword.get(:file, "nofile") |> Path.expand()
    fallback_line = Keyword.get(opts, :line, 1)
    source_line = content_line(source_file, content, fallback_line)

    %{
      extension: extension,
      source_file: source_file,
      source_line: source_line
    }
  end

  def content_line(_source_file, "", fallback_line), do: fallback_line

  def content_line(source_file, content, fallback_line) do
    with {:ok, source} <- File.read(source_file),
         nil <- exact_content_line(source, content, fallback_line) do
      normalized_content_line(source, content, fallback_line)
    else
      line when is_integer(line) -> line
      _error -> fallback_line
    end
  end

  defp exact_content_line(source, content, fallback_line) do
    source
    |> :binary.matches(content)
    |> Enum.map(fn {offset, _length} -> line_at_offset(source, offset) end)
    |> Enum.find(&(&1 >= fallback_line))
  end

  defp normalized_content_line(source, content, fallback_line) do
    source_lines = source |> String.split("\n") |> Enum.map(&String.trim/1)
    content_lines = significant_lines(content)
    first_index = max(fallback_line, 1) - 1
    last_index = length(source_lines) - length(content_lines)

    matching_line(source_lines, content_lines, first_index, last_index, fallback_line)
  end

  defp significant_lines(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
  end

  defp matching_line(_source_lines, [], _first_index, _last_index, fallback_line),
    do: fallback_line

  defp matching_line(_source_lines, _content_lines, first_index, last_index, fallback_line)
       when first_index > last_index,
       do: fallback_line

  defp matching_line(source_lines, content_lines, first_index, last_index, fallback_line) do
    Enum.find_value(first_index..last_index, fallback_line, fn index ->
      if Enum.slice(source_lines, index, length(content_lines)) == content_lines,
        do: index + 1
    end)
  end

  defp colocated?(%{":type" => type}, types) do
    type_name = type |> String.split(".") |> List.last()
    type in types or type_name in types
  end

  defp colocated?(_attrs, _types), do: false

  defp supported_extension(attrs, supported) do
    case Map.get(attrs, "extension", extension_from_manifest(attrs)) do
      extension when is_binary(extension) ->
        extension = extension |> String.trim_leading(".") |> String.downcase()
        if extension in supported, do: {:ok, extension}, else: :skip

      _other ->
        :skip
    end
  end

  defp extension_from_manifest(%{"manifest" => manifest}) do
    case Path.extname(manifest) do
      "" -> "js"
      extension -> extension
    end
  end

  defp extension_from_manifest(_attrs), do: "js"

  defp line_at_offset(source, offset) do
    source
    |> binary_part(0, offset)
    |> String.split("\n")
    |> length()
  end
end
