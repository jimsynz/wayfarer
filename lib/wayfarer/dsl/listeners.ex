defmodule Wayfarer.Dsl.Listeners do
  @moduledoc """
  A struct for storing a group of listeners generated by the DSL.
  """

  alias Spark.Dsl.Entity
  alias Wayfarer.Dsl.Listener

  defstruct listeners: []

  @type t :: %__MODULE__{listeners: [Listener.t()]}

  @doc false
  @spec init :: t
  def init, do: %__MODULE__{listeners: []}

  @doc false
  @spec entities :: [Entity.t()]
  def entities do
    [
      %Entity{
        name: :listeners,
        target: __MODULE__,
        entities: [
          listeners: Listener.entities()
        ],
        imports: [IP.Sigil]
      }
    ]
  end
end
