defmodule Wayfarer.Error.Unknown do
  @moduledoc """
  An unknown error.
  """

  use Splode.Error, fields: [:error, :message], class: :unknown

  @doc false
  @impl true
  def message(error), do: error.message
end
