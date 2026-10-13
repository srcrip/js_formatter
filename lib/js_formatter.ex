defmodule JsFormatter do
  @moduledoc """
  Formats and lints Phoenix LiveView colocated JavaScript.

  This module implements `Phoenix.LiveView.HTMLFormatter.TagFormatter` and is
  intended to be configured as the formatter for `<script>` tags. Ordinary
  script tags are ignored; only `Phoenix.LiveView.ColocatedHook` and
  `Phoenix.LiveView.ColocatedJS` tags are passed to the configured JavaScript
  tool.

  See the project README for installation and configuration examples.
  """

  @behaviour Phoenix.LiveView.HTMLFormatter.TagFormatter

  alias JsFormatter.{Command, Config, Diagnostic, Error, Source, TempFile}

  @impl true
  def render_tag({"script", attrs, content}, opts) do
    with {:ok, config} <- Config.from_formatter_options(opts),
         {:ok, extension} <- Source.extension(attrs, config) do
      source = String.trim(content)
      context = Source.context(source, extension, opts, config)

      TempFile.with_file(source, context, config, fn temporary_path ->
        case Command.run(temporary_path, config) do
          {:ok, %{source: output, output: command_output}} ->
            handle_successful_output(
              output,
              command_output,
              temporary_path,
              context,
              config
            )

          {:error, diagnostic} ->
            message = Diagnostic.format(diagnostic, temporary_path, context, config)
            raise Error, message: message
        end
      end)
    else
      :skip -> :skip
      {:error, message} -> raise Error, message: message
    end
  end

  def render_tag({_tag, _attrs, _content}, _opts), do: :skip

  defp handle_successful_output(source, output, temporary_path, context, config) do
    case Diagnostic.successful_output(output, temporary_path, context, config) do
      :ok ->
        {:ok, String.trim(source)}

      {:warning, message} ->
        IO.puts(:stderr, message)
        {:ok, String.trim(source)}

      {:error, message} ->
        raise Error, message: message
    end
  end
end
