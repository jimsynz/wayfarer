defmodule Wayfarer.Error.Listener.NoSuchListener do
  @moduledoc """
  An exception which is returned when requesting information about a listener
  which no longer exists.
  """

  use Splode.Error, fields: [:listener], class: :listener

  @doc false
  @impl true
  def message(error) do
    """
    # No Such Listener

    #{@moduledoc}

    ## Listener requested:

    ```elixir
    #{inspect(error.listener)}
    ```
    """
  end
end
