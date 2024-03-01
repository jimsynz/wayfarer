defmodule Wayfarer.MixProject do
  use Mix.Project

  @moduledoc """
  A runtime-configurable HTTP reverse proxy based on Bandit.
  """

  @version "0.4.0"

  def project do
    [
      app: :wayfarer,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: @moduledoc,
      package: package(),
      source_url: "https://harton.dev/james/wayfarer",
      homepage_url: "https://harton.dev/james/wayfarer",
      aliases: aliases(),
      dialyzer: [plt_add_apps: []],
      docs: [
        main: "Wayfarer",
        formatters: ["html"],
        extra_section: "GUIDES",
        filter_modules: ~r/^Elixir.Wayfarer/,
        source_url_pattern: "https://harton.dev/james/wayfarer/src/branch/main/%{path}#L%{line}",
        spark: [
          extensions: [
            %{
              module: Wayfarer.Dsl,
              name: "Wayfarer.Dsl",
              target: "Wayfarer",
              type: "Wayfarer"
            }
          ]
        ],
        extras:
          ["README.md"]
          |> Enum.concat(Path.wildcard("documentation/**/*.{md,livemd,cheatmd}")),
        groups_for_extras:
          "documentation/*"
          |> Path.wildcard()
          |> Enum.map(fn dir ->
            name =
              dir
              |> Path.split()
              |> List.last()
              |> String.split("_")
              |> Enum.map_join(" ", &String.capitalize/1)

            files =
              dir
              |> Path.join("**.{md,livemd,cheatmd}")
              |> Path.wildcard()

            {name, files}
          end)
      ]
    ]
  end

  defp package do
    [
      name: :wayfarer,
      files: ~w[lib .formatter.exs mix.exs README.md LICENSE.md CHANGELOG.md],
      maintainers: ["James Harton <james@harton.nz>"],
      licenses: ["HL3-FULL"],
      links: %{
        "Source" => "https://harton.dev/james/wayfarer"
      },
      source_url: "https://harton.dev/james/wayfarer"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Wayfarer.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    opts = [only: ~w[dev test]a, runtime: false]

    [
      {:bandit, "~> 1.0"},
      {:castore, "~> 1.0"},
      {:ip, "~> 2.0"},
      {:mint, "~> 1.5"},
      {:nimble_options, "~> 1.0"},
      {:plug, "~> 1.15"},
      {:spark, "~> 2.0"},
      {:telemetry, "~> 1.2"},
      {:websock, "~> 0.5"},

      # Dev/test
      {:credo, "~> 1.7", opts},
      {:dialyxir, "~> 1.3", opts},
      {:doctor, "~> 0.21", opts},
      {:earmark, ">= 0.0.0", opts},
      {:ex_check, "~> 0.16", opts},
      {:ex_doc, ">= 0.0.0", opts},
      {:faker, "~> 0.18", opts},
      {:git_ops, "~> 2.6", opts},
      {:mimic, "~> 1.7", Keyword.delete(opts, :runtime)},
      {:mix_audit, "~> 2.1", opts}
    ]
  end

  defp aliases,
    do: [
      "spark.formatter": "spark.formatter --extensions=Wayfarer.Dsl",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions=Wayfarer.Dsl"
    ]

  defp elixirc_paths(env) when env in ~w[dev test]a, do: ~w[lib test/support]
  defp elixirc_paths(_), do: ~w[lib]
end
