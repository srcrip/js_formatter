defmodule Demo.JsFormatterIntegrationTest do
  use ExUnit.Case, async: false

  @project_directory Path.expand("..", __DIR__)

  test "the real Phoenix project is formatted with Biome" do
    assert_formatter_succeeds("biome")
  end

  test "the real Phoenix project is formatted with ESLint" do
    assert_formatter_succeeds("eslint")
  end

  test "the real Phoenix project is formatted with Prettier" do
    assert_formatter_succeeds("prettier")
  end

  test "Biome rewrites a colocated block in the original Elixir file" do
    path = write_fixture!(unformatted_fixture())

    assert {_output, 0} = run_formatter("biome", path)
    assert File.read!(path) =~ "export const answer = 1;"
  end

  test "ESLint rewrites a colocated block in the original Elixir file" do
    path = write_fixture!(unformatted_fixture())

    assert {_output, 0} = run_formatter("eslint", path)
    assert File.read!(path) =~ "export const answer = 1;"
  end

  test "Prettier rewrites a colocated block in the original Elixir file" do
    path = write_fixture!(unformatted_fixture())

    assert {_output, 0} = run_formatter("prettier", path)
    assert File.read!(path) =~ "export const answer = 1;"
  end

  test "Prettier formats TSX using the colocated extension" do
    path = write_fixture!(unformatted_tsx_fixture())

    assert {_output, 0} = run_formatter("prettier", path)
    assert File.read!(path) =~ "export const view = <div>Hello</div>;"
  end

  test "Biome fails with a diagnostic mapped to the original Elixir line" do
    path = write_fixture!(biome_lint_failure_fixture())

    assert {output, status} = run_formatter("biome", path)
    assert status != 0
    assert output =~ "lint/suspicious/noDebugger"
    assert output =~ "#{path}:6:"
  end

  test "ESLint fails with a diagnostic mapped to the original Elixir line" do
    path = write_fixture!(eslint_lint_failure_fixture())

    assert {output, status} = run_formatter("eslint", path)
    assert status != 0
    assert output =~ "Expected '===' and instead saw '=='"
    assert output =~ ~r/#{Regex.escape(path)}\n\s+6:\d+/
    assert output =~ ~r/\n\s+7:\d+/
  end

  test "Biome reports a successful warning at the original Elixir line" do
    path = write_fixture!(warning_fixture())

    assert {output, 0} = run_formatter("biome", path)
    assert output =~ "lint/correctness/noUnusedVariables"
    assert output =~ "#{path}:7:9"
  end

  test "ESLint reports a successful warning at the original Elixir line" do
    path = write_fixture!(warning_fixture())

    assert {output, 0} = run_formatter("eslint", path)
    assert output =~ "@typescript-eslint/no-unused-vars"
    assert output =~ ~r/#{Regex.escape(path)}\n\s+7:9/
  end

  test "Prettier fails on syntax errors with the original Elixir path" do
    path = write_fixture!(syntax_error_fixture())

    assert {output, status} = run_formatter("prettier", path)
    assert status != 0
    assert output =~ "#{path}:6:19"
    assert output =~ "SyntaxError"
    refute output =~ "js_formatter_"
  end

  defp assert_formatter_succeeds(tool) do
    {output, status} = run_formatter(tool, "--check-formatted")
    assert status == 0, output
  end

  defp run_formatter(tool, path_or_option) do
    executable = System.find_executable("mix")

    System.cmd(executable, ["format", path_or_option],
      cd: @project_directory,
      env: [{"JS_FORMATTER_TOOL", tool}],
      stderr_to_stdout: true
    )
  end

  defp write_fixture!(source) do
    directory =
      Path.join(
        System.tmp_dir!(),
        "js formatter demo #{System.pid()} #{System.unique_integer([:positive, :monotonic])}"
      )

    path = Path.join(directory, "formatter_fixture.ex")
    File.mkdir_p!(directory)
    File.write!(path, source)
    on_exit(fn -> File.rm_rf!(directory) end)
    path
  end

  defp unformatted_fixture do
    ~S'''
    defmodule Demo.UnformattedFixture do
      def render(assigns) do
        ~H"""
        <script :type={Phoenix.LiveView.ColocatedJS} extension="ts">
          export const answer=1
        </script>
        """
      end
    end
    '''
  end

  defp unformatted_tsx_fixture do
    ~S'''
    defmodule Demo.UnformattedTsxFixture do
      def render(assigns) do
        ~H"""
        <script :type={Phoenix.LiveView.ColocatedJS} extension="tsx">
          export const view=<div>Hello</div>
        </script>
        """
      end
    end
    '''
  end

  defp biome_lint_failure_fixture do
    ~S'''
    defmodule Demo.BiomeLintFailureFixture do
      def render(assigns) do
        ~H"""
        <script :type={Phoenix.LiveView.ColocatedJS} extension="ts">
          export function broken() {
            debugger;
          }
        </script>
        """
      end
    end
    '''
  end

  defp syntax_error_fixture do
    ~S'''
    defmodule Demo.SyntaxErrorFixture do
      def render(assigns) do
        ~H"""
        <script :type={Phoenix.LiveView.ColocatedJS} extension="ts">
          export function broken() {
            const value = ;
          }
        </script>
        """
      end
    end
    '''
  end

  defp eslint_lint_failure_fixture do
    ~S'''
    defmodule Demo.ESLintLintFailureFixture do
      def render(assigns) do
        ~H"""
        <script :type={Phoenix.LiveView.ColocatedJS} extension="ts">
          export function isMissing(value: string | null) {
            const missing = value == null;
            return missing == false;
          }
        </script>
        """
      end
    end
    '''
  end

  defp warning_fixture do
    ~S'''
    defmodule Demo.WarningFixture do
      def render(assigns) do
        ~H"""
        <script :type={Phoenix.LiveView.ColocatedJS} extension="ts">
          /* eslint @typescript-eslint/no-unused-vars: "warn" */
          export function warning() {
            const unused = 1;
          }
        </script>
        """
      end
    end
    '''
  end
end
