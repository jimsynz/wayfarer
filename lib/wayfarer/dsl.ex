defmodule Wayfarer.Dsl do
  alias Spark.Dsl.{Extension, Section}
  alias Wayfarer.Dsl.{Config, Transformer}

  @sections [
    %Section{
      name: :wayfarer,
      top_level?: true,
      entities: Config.entities()
    }
  ]

  @moduledoc """
  The Wayfarer DSL for defining static proxy configurations.

  ## DSL options

  #{Extension.doc(@sections)}
  """

  use Extension, sections: @sections, transformers: [Transformer]
end
