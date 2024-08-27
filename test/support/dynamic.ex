defmodule Support.Dynamic do
  @moduledoc """
  An empty server for testing dynamic proxy configuration.
  """
  use Wayfarer.Server, targets: [], listeners: [], routing_table: []
end
