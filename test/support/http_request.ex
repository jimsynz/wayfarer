defmodule Support.HttpRequest do
  @moduledoc false
  alias Mint.HTTP
  import Wayfarer.Utils

  defmacro __using__(_) do
    quote do
      import Support.HttpRequest
      import IP.Sigil
    end
  end

  @type headers :: [{String.t(), String.t()}]

  @type options :: [
          host: String.t(),
          method: String.t(),
          path: String.t(),
          headers: headers,
          body: iodata,
          options: Keyword.t()
        ]

  @doc """
  Perform an HTTP request.

  This is a little more annoying than most of the Elixir HTTP clients (Tesla,
  Finch, etc) can handle easily because you need to make a potentially SNI SSL
  request to an arbitrary address without resolving it via DNS.
  """
  @spec request(
          :http | :https,
          :inet.ip_address() | String.t() | IP.Address.t(),
          :inet.port_number(),
          options
        ) ::
          {:ok, %{status: nil | non_neg_integer(), headers: headers, body: iodata()}}
          | {:error, any}
  def request(scheme, address, port, options \\ []) do
    host = Keyword.get(options, :host, "example.com")
    method = Keyword.get(options, :method, "GET")
    path = Keyword.get(options, :path, "/")
    headers = Keyword.get(options, :headers, [])
    body = Keyword.get(options, :body, [])

    options =
      options
      |> Keyword.get(:options, [])
      |> Keyword.put_new(:hostname, host)

    Task.async(fn ->
      with {:ok, address} <- sanitise_ip_address(address),
           {:ok, mint} <- HTTP.connect(scheme, address, port, options),
           {:ok, mint, req} <- HTTP.request(mint, method, path, headers, body) do
        handle_response(mint, req, %{status: nil, headers: [], body: []})
      end
    end)
    |> Task.await()
  end

  defp handle_response(mint, req, state) do
    receive do
      message ->
        case HTTP.stream(mint, message) do
          :unknown -> {:error, {:unknown_message, message}}
          {:ok, mint, responses} -> handle_responses(responses, mint, req, state)
          {:error, _, reason, _} -> {:error, reason}
        end
    end
  end

  defp handle_responses([], mint, req, state), do: handle_response(mint, req, state)

  defp handle_responses([{:status, req, status} | responses], mint, req, state),
    do: handle_responses(responses, mint, req, %{state | status: status})

  defp handle_responses([{:headers, req, headers} | responses], mint, req, state),
    do:
      handle_responses(
        responses,
        mint,
        req,
        Map.update!(state, :headers, &Enum.concat(&1, headers))
      )

  defp handle_responses([{:data, req, body} | responses], mint, req, state),
    do:
      handle_responses(
        responses,
        mint,
        req,
        Map.update!(state, :body, &Enum.concat(&1, [body]))
      )

  defp handle_responses([{:done, req} | _], _mint, req, state), do: {:ok, state}
  defp handle_responses([{:error, req, reason}], _mint, req, _state), do: {:error, reason}
end
