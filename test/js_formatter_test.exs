defmodule JsFormatterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias JsFormatter.{Config, Error, Source}

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "js_formatter_test_#{System.pid()}_#{System.unique_integer([:positive, :monotonic])}"
      )

    working_directory = Path.join(root, "project with spaces")
    File.mkdir_p!(working_directory)
    executable = write_fake_tool!(root)

    on_exit(fn -> File.rm_rf!(root) end)

    %{executable: executable, root: root, working_directory: working_directory}
  end

  test "application configuration supplies defaults and formatter options override it" do
    assert {:ok, config} =
             Config.from_options(
               [
                 default_profile: :eslint,
                 eslint: [command: "eslint", args: ["--fix"], cd: "assets"]
               ],
               args: ["--fix", "--max-warnings=0"],
               env: %{"NODE_ENV" => "test"}
             )

    assert config.profile == :eslint
    assert config.command == "eslint"
    assert config.args == ["--fix", "--max-warnings=0"]
    assert config.cd == Path.expand("assets")
    assert config.temporary_directory == Path.expand("assets")
    assert config.env == %{"NODE_ENV" => "test"}
    assert config.success_output == :warnings
    refute config.error_on_warnings
  end

  test "provides built-in profiles and rejects undefined profiles" do
    assert {:ok, biome} = Config.from_options([], [])
    assert biome.profile == :biome
    assert biome.command == "biome"
    assert biome.args == ["check", "--write", "--colors=off", "--max-diagnostics=none"]

    assert {:ok, eslint} = Config.from_options([default_profile: :eslint], [])
    assert eslint.command == "eslint"
    assert eslint.args == ["--fix", "--format", "stylish"]

    assert {:ok, prettier} = Config.from_options([default_profile: :prettier], [])
    assert prettier.command == "prettier"
    assert prettier.args == ["--write"]

    assert {:error, message} = Config.from_options([default_profile: :custom], [])
    assert message =~ "unknown js_formatter profile :custom"
  end

  test "supports a custom formatter-only profile", context do
    assert {:ok, config} =
             Config.from_options([],
               profile: :custom,
               command: context.executable,
               args: ["--fix"],
               cd: context.working_directory
             )

    assert config.profile == :custom
    assert config.command == context.executable
    assert config.args == ["--fix"]
  end

  test "validates successful output and warning policies" do
    assert {:error, message} = Config.from_options([], success_output: :sometimes)
    assert message =~ "invalid :success_output"

    assert {:error, message} = Config.from_options([], error_on_warnings: :yes)
    assert message =~ "invalid :error_on_warnings"
  end

  test "finds dedented formatter content in its indented Elixir source", context do
    source_file = Path.join(context.working_directory, "indented_component.ex")

    File.write!(source_file, """
    defmodule IndentedComponent do
      def render(assigns) do
        ~H\"\"\"
        <script :type={Phoenix.LiveView.ColocatedHook} extension="ts">
          export default {
            mounted() {
              const answer = 1;
            },
          };
        </script>
        \"\"\"
      end
    end
    """)

    content = """
    export default {
      mounted() {
        const answer = 1;
      },
    };
    """

    assert Source.content_line(source_file, content, 1) == 5
  end

  test "formats TypeScript in a colocated hook", context do
    assert {:ok, "const answer = 1;"} =
             render(
               %{":type" => "Phoenix.LiveView.ColocatedHook", "extension" => "ts"},
               "const answer=1",
               context
             )
  end

  test "applies safe lint fixes to a colocated hook", context do
    assert {:ok, "const safe = true;"} =
             render(
               %{":type" => "ColocatedHook", "extension" => "ts"},
               "let safe = true",
               context
             )
  end

  test "applies safe lint fixes to colocated JavaScript", context do
    assert {:ok, "const safe = true;"} =
             render(
               %{":type" => "ColocatedJS", "extension" => "js"},
               "var safe = true",
               context
             )
  end

  test "supports TSX", context do
    assert {:ok, "const view = <div>Hello</div>;"} =
             render(
               %{":type" => "Phoenix.LiveView.ColocatedJS", "extension" => "tsx"},
               "const view=<div>Hello</div>",
               context
             )
  end

  test "formats TSX through the built-in Prettier profile", context do
    assert {:ok, "const view = <div>Hello</div>;"} =
             render(
               %{":type" => "Phoenix.LiveView.ColocatedJS", "extension" => "tsx"},
               "const view=<div>Hello</div>",
               context,
               profile: :prettier
             )
  end

  test "uses a manifest extension when extension is omitted", context do
    assert {:ok, "const answer = 1;"} =
             render(
               %{":type" => "ColocatedHook", "manifest" => "hooks.ts"},
               "const answer=1",
               context
             )
  end

  test "skips ordinary and unsupported script tags", context do
    assert :skip = render(%{}, "const answer=1", context)

    assert :skip =
             render(
               %{":type" => "Phoenix.LiveView.ColocatedHook", "extension" => "coffee"},
               "answer = 1",
               context
             )
  end

  test "skips runtime colocated hooks by default", context do
    assert :skip =
             render(
               %{":type" => "ColocatedHook", "runtime" => true},
               "{ mounted() {} }",
               context
             )
  end

  test "raises on a genuine lint failure and maps its path and line", context do
    source_file = Path.join(context.working_directory, "sample.ex")
    content = "const LINT_ERROR = console.log('nope')\nconst next = true"

    File.write!(source_file, """
    defmodule Sample do
      def render(assigns) do
        ~H\"\"\"
        <script :type={Phoenix.LiveView.ColocatedHook} extension="ts">
    #{content}
        </script>
        \"\"\"
      end
    end
    """)

    assert_raise Error, ~r/#{Regex.escape(source_file)}:6:3.*noConsole/s, fn ->
      render(
        %{":type" => "Phoenix.LiveView.ColocatedHook", "extension" => "ts"},
        content,
        context,
        file: source_file
      )
    end
  end

  test "maps every ESLint stylish diagnostic line", context do
    source_file = Path.join(context.working_directory, "multiple_errors.ex")
    content = "const MULTIPLE_ERRORS = true\nconsole.log('second')"
    write_source!(source_file, content)

    error =
      assert_raise Error, fn ->
        render(
          %{":type" => "ColocatedHook", "extension" => "js"},
          content,
          context,
          file: source_file
        )
      end

    assert error.message =~ "#{source_file}\n  5:5"
    assert error.message =~ "\n  6:5"
    refute error.message =~ "\n  2:5"
  end

  test "prints successful warning diagnostics with original source locations", context do
    source_file = Path.join(context.working_directory, "warning.ex")
    content = "const LINT_WARNING = true\nconst next = true"
    write_source!(source_file, content)

    output =
      capture_io(:stderr, fn ->
        assert {:ok, ^content} =
                 render(
                   %{":type" => "ColocatedJS", "extension" => "js"},
                   content,
                   context,
                   file: source_file
                 )
      end)

    assert output =~ "JavaScript formatter output"
    assert output =~ "#{source_file}\n  6:7"
    assert output =~ "fake/noUnusedVariables"
    refute output =~ "js_formatter_#{System.pid()}_"
  end

  test "can treat successful warning diagnostics as errors", context do
    source_file = Path.join(context.working_directory, "warning_error.ex")
    content = "const LINT_WARNING = true\nconst next = true"
    write_source!(source_file, content)

    error =
      assert_raise Error, fn ->
        render(
          %{":type" => "ColocatedJS", "extension" => "js"},
          content,
          context,
          file: source_file,
          error_on_warnings: true
        )
      end

    assert error.message =~ "warnings are configured as errors"
    assert error.message =~ "#{source_file}\n  6:7"
  end

  test "raises on syntax errors", context do
    assert_raise Error, ~r/parse error/, fn ->
      render(
        %{":type" => "ColocatedJS", "extension" => "js"},
        "const SYNTAX_ERROR =",
        context
      )
    end
  end

  test "maps Prettier parse locations to the original source", context do
    source_file = Path.join(context.working_directory, "prettier_error.ex")
    content = "const PRETTIER_SYNTAX_ERROR = true\nconst value ="
    write_source!(source_file, content)

    error =
      assert_raise Error, fn ->
        render(
          %{":type" => "ColocatedJS", "extension" => "ts"},
          content,
          context,
          file: source_file,
          profile: :prettier
        )
      end

    assert error.message =~ "#{source_file}:6:14: SyntaxError: Expression expected."
    refute error.message =~ "js_formatter_#{System.pid()}_"
  end

  test "reports a missing executable clearly", context do
    assert_raise Error, ~r/could not find .*missing-biome.* executable/, fn ->
      render(
        %{":type" => "ColocatedJS"},
        "const answer=1",
        context,
        command: Path.join(context.root, "missing-biome")
      )
    end
  end

  test "cleans up temporary files after success and failure", context do
    assert {:ok, _output} =
             render(%{":type" => "ColocatedJS"}, "const answer=1", context)

    assert_raise Error, fn ->
      render(%{":type" => "ColocatedJS"}, "const SYNTAX_ERROR =", context)
    end

    assert [] = Path.wildcard(Path.join(context.working_directory, "js_formatter_*"))
  end

  test "supports concurrent invocations", context do
    results =
      1..8
      |> Task.async_stream(
        fn number ->
          render(
            %{":type" => "ColocatedHook", "extension" => "ts"},
            "const answer=1 // #{number}",
            context
          )
        end,
        max_concurrency: 8,
        timeout: 30_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, fn
             {:ok, {:ok, output}} -> String.starts_with?(output, "const answer = 1;")
             _other -> false
           end)

    assert [] = Path.wildcard(Path.join(context.working_directory, "js_formatter_*"))
  end

  test "integrates with the LiveView HTML formatter", context do
    source_file = Path.join(context.working_directory, "component.ex")

    source = """
    <div id="example" phx-hook=".Example"></div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Example" extension="ts">
      const answer=1
    </script>
    """

    File.write!(source_file, source)

    formatted =
      Phoenix.LiveView.HTMLFormatter.format(source,
        file: source_file,
        line: 1,
        tag_formatters: %{script: JsFormatter},
        js_formatter: formatter_config(context)
      )

    assert formatted =~ "const answer = 1;"
    refute formatted =~ "const answer=1"
  end

  test "formats a colocated hook inside a ~H sigil", context do
    source_file = Path.join(context.working_directory, "component.ex")

    source = """
    defmodule ExampleComponent do
      use Phoenix.Component

      def example(assigns) do
        ~H\"\"\"
        <div id="example" phx-hook=".Example"></div>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".Example" extension="ts">
          const answer=1
        </script>
        \"\"\"
      end
    end
    """

    File.write!(source_file, source)

    formatter_options = [
      file: source_file,
      tag_formatters: %{script: JsFormatter},
      js_formatter: formatter_config(context)
    ]

    formatted =
      source
      |> Code.format_string!(
        file: source_file,
        sigils: [
          H: fn input, sigil_options ->
            Phoenix.LiveView.HTMLFormatter.format(input, sigil_options ++ formatter_options)
          end
        ]
      )
      |> IO.iodata_to_binary()

    assert formatted =~ "const answer = 1;"
    refute formatted =~ "const answer=1"
  end

  defp render(attrs, content, context, overrides \\ []) do
    {formatter_overrides, formatter_opts} =
      Keyword.split(overrides, [
        :profile,
        :command,
        :args,
        :cd,
        :env,
        :temporary_directory,
        :success_output,
        :error_on_warnings,
        :format_runtime,
        :extensions,
        :types
      ])

    JsFormatter.render_tag(
      {"script", attrs, content},
      Keyword.merge(
        [file: Path.join(context.working_directory, "component.ex"), line: 1],
        Keyword.merge(formatter_opts,
          js_formatter: Keyword.merge(formatter_config(context), formatter_overrides)
        )
      )
    )
  end

  defp formatter_config(context) do
    [
      profile: :test,
      command: context.executable,
      args: ["--fix", "--format", "fake"],
      cd: context.working_directory
    ]
  end

  defp write_source!(path, content) do
    File.write!(path, """
    defmodule Fixture do
      def render(assigns) do
        ~H\"\"\"
        <script :type={Phoenix.LiveView.ColocatedJS} extension="js">
    #{content}
        </script>
        \"\"\"
      end
    end
    """)
  end

  defp write_fake_tool!(root) do
    path = Path.join(root, "fake js tool")

    File.write!(path, """
    #!/usr/bin/env elixir
    path = System.argv() |> List.last()
    source = File.read!(path)

    cond do
      String.contains?(source, "MULTIPLE_ERRORS") ->
        IO.puts(
          :stderr,
          "\#{path}\\n  1:5  error  First problem   fake/first\\n  2:5  error  Second problem  fake/second\\n\\n✖ 2 problems (2 errors, 0 warnings)"
        )

        System.halt(1)

      String.contains?(source, "PRETTIER_SYNTAX_ERROR") ->
        IO.puts(:stderr, "[error] \#{path}: SyntaxError: Expression expected. (2:14)")
        System.halt(2)

      String.contains?(source, "SYNTAX_ERROR") ->
        IO.puts(:stderr, "\#{path}:1:7 parse error: expected an expression")
        System.halt(1)

      String.contains?(source, "LINT_ERROR") ->
        IO.puts(:stderr, "\#{path}:2:3 lint/suspicious/noConsole: Don't use console")
        System.halt(1)

      String.contains?(source, "LINT_WARNING") ->
        IO.puts(
          :stderr,
          "\#{path}\\n  2:7  warning  Unused value  fake/noUnusedVariables\\n\\n✖ 1 problem (0 errors, 1 warning)"
        )

      true ->
        formatted =
          source
          |> String.replace("const answer=1", "const answer = 1;")
          |> String.replace("let safe = true", "const safe = true;")
          |> String.replace("var safe = true", "const safe = true;")
          |> String.replace("const view=<div>Hello</div>", "const view = <div>Hello</div>;")

        File.write!(path, formatted)
    end
    """)

    File.chmod!(path, 0o755)
    path
  end
end
