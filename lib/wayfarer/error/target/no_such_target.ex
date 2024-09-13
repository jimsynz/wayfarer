defmodule Wayfarer.Error.Target.NoSuchTarget do
  @moduledoc """
  An exception which is returned when requesting information about a target
  which no longer exists.
  """

  use Splode.Error, fields: [:target], class: :target

  @doc false
  @impl true
  def message(error) do
    """
    # No Such Listener

    #{@moduledoc}

    ## Target requested:

    ```elixir
    #{inspect(error.target)}
    ```
    """
  end
end
