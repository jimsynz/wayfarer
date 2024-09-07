defmodule Wayfarer.Error do
  @moduledoc """
  The main error aggregator for Wayfarer errors.
  """

  use Splode,
    error_classes: [
      listener: __MODULE__.Listener,
      target: __MODULE__.Target,
      server: __MODULE__.Server,
      unknown: __MODULE__.Unknown
    ],
    unknown_error: __MODULE__.Unknown
end
