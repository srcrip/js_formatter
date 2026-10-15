defmodule JsFormatter.MixProject do
  use Mix.Project

  def project do
    [
      app: :js_formatter,
      version: "0.2.0",
      elixir: "~> 1.15",
      description:
        "Format and lint Phoenix LiveView colocated JavaScript and TypeScript with project tools",
      package: package(),
      deps: deps(),
      docs: [main: "readme", extras: ["README.md", "CHANGELOG.md"]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    []
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix_live_view, "~> 1.2", runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE"],
      links: %{
        "GitHub" => "https://github.com/srcrip/js_formatter",
        "Changelog" => "https://github.com/srcrip/js_formatter/blob/main/CHANGELOG.md",
        "Biome" => "https://biomejs.dev/",
        "ESLint" => "https://eslint.org/",
        "Prettier" => "https://prettier.io/",
        "Phoenix LiveView TagFormatter" =>
          "https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.HTMLFormatter.TagFormatter.html"
      }
    ]
  end
end
