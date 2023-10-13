defmodule Switch.MixProject do
  use Mix.Project

  @moduledoc """
  A runtime-configurable HTTP reverse proxy based on Bandit.
  """

  @version "0.1.0"

  def project do
    [
      app: :switch,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: @moduledoc,
      package: package(),
      source_url: "https://code.harton.nz/bivouac/switch",
      homepage_url: "https://code.harton.nz/bivouac/switch",
      aliases: aliases(),
      dialyzer: [plt_add_apps: []],
      docs: [
        main: "Switch",
        extras: ["README.md"],
        formatters: ["html"]
      ]
    ]
  end

  defp package do
    [
      name: :switch,
      files: ~w[lib .formatter.exs mix.exs README.md LICENSE.md CHANGELOG.md],
      licenses: ["HL3-FULL"],
      links: %{
        "Source" => "https://code.harton.nz/bivouac/switch"
      },
      source_url: "https://code.harton.nz/bivouac/switch"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Switch.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    opts = [only: ~w[dev test]a, runtime: false]

    [
      # Dev/test
      {:credo, "~> 1.7", opts},
      {:dialyxir, "~> 1.3", opts},
      {:doctor, "~> 0.21", opts},
      {:earmark, ">= 0.0.0", opts},
      {:ex_check, "~> 0.15", opts},
      {:ex_doc, ">= 0.0.0", opts},
      {:faker, "~> 0.17", opts},
      {:git_ops, "~> 2.6", opts},
      {:mix_audit, "~> 2.1", opts}
    ]
  end

  defp aliases, do: []

  defp elixirc_paths(env) when env in ~w[dev test]a, do: ~w[lib test/support]
  defp elixirc_paths(_), do: ~w[lib]
end
