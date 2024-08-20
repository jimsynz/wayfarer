defmodule Wayfarer.Telemetry do
  @moduledoc """
  Wayfarer emits a number of telemetry events and spans on top of the excellent
  telemetry events emitted by `Bandit.Telemetry`.
  """

  alias Plug.Conn
  alias Wayfarer.{Router, Target.Check, Target.Selector}

  @typedoc """
  Information about the target a request has been routed to.
  """
  @type target ::
          %{
            scheme: :http | :https | :ws | :wss,
            address: :inet.ip_address(),
            port: :socket.port_number()
          }
          | %{scheme: :plug, module: module, options: any}

  @typedoc """
  Information about the listener that received the request.
  """
  @type listener ::
          %{
            scheme: :http | :https,
            module: module(),
            port: :socket.port_number(),
            address: :inet.ip_address()
          }

  @typedoc """
  The time that the event was emitted, in `:native` time units.

  This is sources from `System.monotonic_time/0` which has some caveats but in
  general is better for calculating durations as it should never go backwards.
  """
  @type monotonic_time :: integer()

  @typedoc """
  The time passed since the beginning of the span, in `:native` time units.

  The difference between the current `monotonic_time` and the first
  `monotonic_time` at the start of the span.
  """
  @type duration :: integer()

  @typedoc "The HTTP protocol version of the request"
  @type transport :: :http1 | :http2

  @typedoc "A unique identifier for the span"
  @type telemetry_span_context :: reference()

  @typedoc "A convenience type for describing telemetry events"
  @opaque event(measurements, metadata) :: {measurements, metadata}

  @typedoc """
  The `[:wayfarer, :request, :start]` event.

  This event signals the start of a request span tracking a client request to
  completion.

  You can use the `telemetry_span_context` metadata value to correlate
  subsequent events within the same span.
  """
  @type request_start ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:wallclock_time) => DateTime.t()
            },
            %{
              required(:conn) => Conn.t(),
              required(:listener) => listener(),
              required(:transport) => transport(),
              required(:telemetry_span_context) => telemetry_span_context()
            }
          )

  @typedoc """
  The `[:wayfarer, :request, :routed]` event.

  This event signals that the routing process has completed and a target has
  been chosen to serve the request.
  """
  @type request_routed ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:duration) => duration(),
              required(:wallclock_time) => DateTime.t()
            },
            %{
              required(:conn) => Conn.t(),
              required(:listener) => listener(),
              required(:transport) => transport(),
              required(:telemetry_span_context) => telemetry_span_context(),
              required(:target) => target(),
              required(:algorithm) => Selector.algorithm()
            }
          )

  @typedoc """
  The `[:wayfarer, :request, :exception]` event.

  This event signals that something went wrong while processing the event.  You
  will likely still receive other events (eg `:stop`) for this span however.
  """
  @type request_exception ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:duration) => duration(),
              required(:wallclock_time) => DateTime.t()
            },
            %{
              required(:conn) => Conn.t(),
              required(:listener) => listener(),
              required(:transport) => transport(),
              required(:telemetry_span_context) => telemetry_span_context(),
              optional(:target) => target(),
              optional(:algorithm) => Selector.algorithm(),
              required(:kind) => :throw | :exit | :error | :exception,
              required(:reason) => any,
              required(:stacktrace) => Exception.stacktrace()
            }
          )

  @typedoc """
  The `[:wayfarer, :request, :stop]` event.

  This event signals that the request has completed.

  The measurements will contain any incrementing counters accumulated during the
  course of the request.
  """
  @type request_stop ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:duration) => duration(),
              required(:wallclock_time) => DateTime.t(),
              required(:status) => nil | 100..599,
              optional(:req_body_bytes) => non_neg_integer(),
              optional(:resp_body_bytes) => non_neg_integer(),
              optional(:client_frame_bytes) => non_neg_integer(),
              optional(:client_frame_count) => non_neg_integer(),
              optional(:server_frame_bytes) => non_neg_integer(),
              optional(:server_frame_count) => non_neg_integer()
            },
            %{
              required(:conn) => Conn.t(),
              required(:listener) => listener(),
              required(:transport) => transport(),
              required(:telemetry_span_context) => telemetry_span_context(),
              optional(:target) => target(),
              optional(:algorithm) => Selector.algorithm(),
              optional(:status) => nil | 100..599,
              optional(:kind) => :throw | :exit | :error | :exception,
              optional(:reason) => any,
              optional(:stacktrace) => Exception.stacktrace()
            }
          )

  @typedoc """
  The `[:wayfarer, :request, :received_status]` event.

  This event signals that an HTTP status code has been received from the
  upstream target.
  """
  @type request_received_status ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:duration) => duration(),
              required(:wallclock_time) => DateTime.t(),
              required(:status) => nil | 100..599,
              optional(:req_body_bytes) => non_neg_integer()
            },
            %{
              required(:conn) => Conn.t(),
              required(:listener) => listener(),
              required(:transport) => transport(),
              required(:telemetry_span_context) => telemetry_span_context(),
              required(:target) => target(),
              required(:algorithm) => Selector.algorithm(),
              required(:status) => nil | 100..599
            }
          )

  @typedoc """
  The `[:wayfarer, :request, :req_body_chunk]` event.

  This event is emitted while streaming the request body from the client to the
  target.  Under the hood `Plug.Conn.read_body/2` is being called with the
  default options, meaning that each chunk is likely to be up to 8MB in size.

  If there is no request body then this event will not be emitted and the
  `req_body_bytes` and `req_body_chunks` counters will both be set to zero for
  this request.
  """
  @type request_req_body_chunk ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:duration) => duration(),
              required(:wallclock_time) => DateTime.t(),
              required(:status) => nil | 100..599,
              required(:req_body_bytes) => non_neg_integer(),
              required(:req_body_chunks) => non_neg_integer(),
              required(:chunk_bytes) => non_neg_integer()
            },
            %{
              required(:conn) => Conn.t(),
              required(:listener) => listener(),
              required(:transport) => transport(),
              required(:telemetry_span_context) => telemetry_span_context(),
              required(:target) => target(),
              required(:algorithm) => Selector.algorithm(),
              required(:status) => nil | 100..599
            }
          )

  @typedoc """
  The `[:wayfarer, :request, :resp_started]` event.

  This event indicates that the HTTP status and headers have been received from
  the target and the response will now start being sent to the target.
  """
  @type request_resp_started ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:duration) => duration(),
              required(:wallclock_time) => DateTime.t(),
              required(:status) => nil | 100..599,
              optional(:req_body_bytes) => non_neg_integer(),
              optional(:req_body_chunks) => non_neg_integer()
            },
            %{
              required(:conn) => Conn.t(),
              required(:listener) => listener(),
              required(:transport) => transport(),
              required(:telemetry_span_context) => telemetry_span_context(),
              required(:target) => target(),
              required(:algorithm) => Selector.algorithm(),
              required(:status) => nil | 100..599
            }
          )

  @typedoc """
  The `[:wayfarer, :request, :resp_body_chunk]` event.

  This event is emitted every time a chunk of response body is received from the
  target for streaming to the client.  Under the hood, these are emitted every
  time `Mint.HTTP.stream/2` returns a data frame.
  """
  @type request_resp_body_chunk ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:duration) => duration(),
              required(:wallclock_time) => DateTime.t(),
              optional(:req_body_bytes) => non_neg_integer(),
              optional(:req_body_chunks) => non_neg_integer(),
              required(:resp_body_bytes) => non_neg_integer(),
              required(:resp_body_chunks) => non_neg_integer(),
              required(:chunk_bytes) => non_neg_integer()
            },
            %{
              required(:conn) => Conn.t(),
              required(:listener) => listener(),
              required(:transport) => transport(),
              required(:telemetry_span_context) => telemetry_span_context(),
              required(:target) => target(),
              required(:algorithm) => Selector.algorithm(),
              required(:status) => nil | 100..599
            }
          )

  @typedoc """
  The `[:wayfarer, :request, :upgraded]` event.

  This event is emitted when a client connection is upgraded to a WebSocket
  connection.
  """
  @type request_upgraded ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:duration) => duration(),
              required(:wallclock_time) => DateTime.t()
            },
            %{
              required(:conn) => Conn.t(),
              required(:listener) => listener(),
              required(:transport) => transport(),
              required(:telemetry_span_context) => telemetry_span_context(),
              required(:target) => target(),
              required(:algorithm) => Selector.algorithm(),
              required(:status) => nil | 100..599
            }
          )

  @typedoc """
  The `[:wayfarer, :request, :client_frame]` event.

  This event is emitted any time a WebSocket frame is received from the client
  for transmission to the target.
  """
  @type request_client_frame ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:duration) => duration(),
              required(:wallclock_time) => DateTime.t(),
              required(:frame_size) => non_neg_integer(),
              required(:client_frame_bytes) => non_neg_integer(),
              required(:client_frame_count) => non_neg_integer(),
              optional(:server_frame_bytes) => non_neg_integer(),
              optional(:server_frame_count) => non_neg_integer()
            },
            %{
              required(:conn) => Conn.t(),
              required(:listener) => listener(),
              required(:transport) => transport(),
              required(:telemetry_span_context) => telemetry_span_context(),
              required(:target) => target(),
              required(:algorithm) => Selector.algorithm(),
              required(:status) => nil | 100..599,
              required(:opcode) => :text | :binary | :ping | :pong | :close
            }
          )

  @typedoc """
  The `[:wayfarer, :request, :server_frame]` event.

  This event is emitted any time a WebSocket frame is received from the target
  for transmission to the client.
  """
  @type request_server_frame ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:duration) => duration(),
              required(:wallclock_time) => DateTime.t(),
              required(:frame_size) => non_neg_integer(),
              required(:server_frame_bytes) => non_neg_integer(),
              required(:server_frame_count) => non_neg_integer(),
              optional(:client_frame_bytes) => non_neg_integer(),
              optional(:client_frame_count) => non_neg_integer()
            },
            %{
              required(:conn) => Conn.t(),
              required(:listener) => listener(),
              required(:transport) => transport(),
              required(:telemetry_span_context) => telemetry_span_context(),
              required(:target) => target(),
              required(:algorithm) => Selector.algorithm(),
              required(:status) => nil | 100..599
            }
          )

  @typedoc """
  All the event types that make up the `[:wayfarer, :request, :*]` span.
  """
  @type request_span ::
          request_start
          | request_routed
          | request_exception
          | request_stop
          | request_received_status
          | request_req_body_chunk
          | request_resp_started
          | request_resp_body_chunk
          | request_upgraded
          | request_client_frame
          | request_server_frame

  @typedoc """
  The `[:wayfarer, :health_check, :start]` event.

  This event signals the start of a health check span.

  You can use the `telemetry_span_context` metadata value to correlate
  subsequent events within the same span.
  """
  @type health_check_start ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:wallclock_time) => DateTime.t()
            },
            %{
              required(:telemetry_span_context) => telemetry_span_context(),
              required(:hostname) => String.t(),
              required(:uri) => URI.t(),
              required(:target) => target(),
              required(:method) => String.t()
            }
          )

  @typedoc """
  The `[:wayfarer, :health_check, :connect]` event.

  This event signals that the outgoing TCP connection has been made to the
  target.
  """
  @type health_check_connect ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:wallclock_time) => DateTime.t(),
              required(:duration) => duration()
            },
            %{
              required(:telemetry_span_context) => telemetry_span_context(),
              required(:hostname) => String.t(),
              required(:uri) => URI.t(),
              required(:target) => target(),
              required(:method) => String.t(),
              required(:transport) => transport()
            }
          )
  @typedoc """
  The `[:wayfarer, :health_check, :request]` event.

  This event signals that the HTTP or WebSocket request has been sent.
  """
  @type health_check_request ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:wallclock_time) => DateTime.t(),
              required(:duration) => duration()
            },
            %{
              required(:telemetry_span_context) => telemetry_span_context(),
              required(:hostname) => String.t(),
              required(:uri) => URI.t(),
              required(:target) => target(),
              required(:method) => String.t(),
              required(:transport) => transport()
            }
          )

  @typedoc """
  The `[:wayfarer, :health_check, :pass]` event.

  This event signals that the HTTP status code returned by the target matches
  one of the configured success codes.

  It also signals the end of the span.
  """
  @type health_check_pass ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:wallclock_time) => DateTime.t(),
              required(:duration) => duration(),
              required(:status) => 100..599
            },
            %{
              required(:telemetry_span_context) => telemetry_span_context(),
              required(:hostname) => String.t(),
              required(:uri) => URI.t(),
              required(:target) => target(),
              required(:method) => String.t(),
              required(:transport) => transport()
            }
          )

  @typedoc """
  The `[:wayfarer, :health_check, :fail]` event.

  This event signals that the HTTP status code returned by the target did not
  match any of the configured success codes.

  It also signals the end of the span.
  """
  @type health_check_fail ::
          event(
            %{
              required(:monotonic_time) => monotonic_time(),
              required(:wallclock_time) => DateTime.t(),
              required(:duration) => duration(),
              required(:reason) => any
            },
            %{
              required(:telemetry_span_context) => telemetry_span_context(),
              required(:hostname) => String.t(),
              required(:uri) => URI.t(),
              required(:target) => target(),
              required(:method) => String.t(),
              required(:transport) => transport()
            }
          )

  @typedoc """
  All the event types that make up the `[:wayfarer, :health_check, :*]` span.
  """
  @type health_check_span ::
          health_check_start | health_check_request | health_check_pass | health_check_fail

  @typedoc """
  All the spans that can be emitted by Wayfarer.
  """
  @type spans :: request_span | health_check_span

  @doc false
  @spec request_start(Conn.t()) :: Conn.t()
  def request_start(conn) do
    telemetry_span_context = make_ref()

    metadata =
      conn
      |> Map.get(:private, %{})
      |> Map.get(:wayfarer, %{})
      |> Map.merge(%{telemetry_span_context: telemetry_span_context, conn: conn})

    conn
    |> execute_request_span_event(:start, %{}, metadata)
  end

  @doc false
  @spec request_routed(Conn.t(), Router.target(), Router.algorithm()) :: Conn.t()
  def request_routed(conn, target, algorithm) do
    target =
      case target do
        {scheme, address, port, _transport} -> %{scheme: scheme, address: address, port: port}
        {:plug, {module, opts}} -> %{scheme: :plug, module: module, options: opts}
        {:plug, module} -> %{scheme: :plug, module: module, options: []}
      end

    conn
    |> execute_request_span_event(:routed, %{}, %{
      target: target,
      algorithm: algorithm
    })
  end

  @doc false
  @spec request_exception(Conn.t(), kind :: any, reason :: any, stacktrace :: list | nil) ::
          Conn.t()
  def request_exception(conn, kind, reason, stacktrace \\ nil) do
    conn
    |> execute_request_span_event(:exception, %{}, %{
      kind: kind,
      reason: reason,
      stacktrace: stacktrace || Process.info(self(), :current_stacktrace)
    })
  end

  @doc false
  def request_stop(conn) do
    conn
    |> execute_request_span_event(:stop, %{status: conn.status}, %{})
  end

  @doc false
  @spec request_received_status(Conn.t(), non_neg_integer()) :: Conn.t()
  def request_received_status(conn, status) do
    conn
    |> execute_request_span_event(:received_status, %{status: status}, %{status: status})
  end

  @doc false
  @spec request_req_body_chunk(Conn.t(), non_neg_integer()) :: Conn.t()
  def request_req_body_chunk(conn, chunk_bytes) do
    conn
    |> execute_request_span_event(:req_body_chunk, %{chunk_bytes: chunk_bytes}, %{})
  end

  @doc false
  @spec request_resp_started(Conn.t()) :: Conn.t()
  def request_resp_started(conn) do
    metric = %{status: conn.status}

    conn
    |> execute_request_span_event(:resp_started, metric, metric)
  end

  @doc false
  @spec request_resp_body_chunk(Conn.t(), non_neg_integer()) :: Conn.t()
  def request_resp_body_chunk(conn, chunk_bytes) do
    conn
    |> execute_request_span_event(:resp_body_chunk, %{chunk_bytes: chunk_bytes}, %{})
  end

  @doc false
  @spec request_upgraded(Conn.t()) :: Conn.t()
  def request_upgraded(conn) do
    conn
    |> execute_request_span_event(:upgraded, %{}, %{})
  end

  @doc false
  @spec request_client_frame(Conn.t(), non_neg_integer(), atom) :: Conn.t()
  def request_client_frame(conn, bytes, opcode) do
    conn
    |> execute_request_span_event(:client_frame, %{frame_size: bytes}, %{opcode: opcode})
  end

  @doc false
  @spec request_server_frame(Conn.t(), non_neg_integer(), atom) :: Conn.t()
  def request_server_frame(conn, bytes, opcode) do
    conn
    |> execute_request_span_event(:server_frame, %{frame_size: bytes}, %{opcode: opcode})
  end

  @doc false
  @spec set_metrics(Conn.t(), %{atom => number}) :: Conn.t()
  def set_metrics(conn, metrics) do
    update_metrics(conn, &Map.merge(&1, metrics))
  end

  @doc false
  @spec increment_metrics(Conn.t(), %{atom => number}) :: Conn.t()
  def increment_metrics(conn, to_increment) do
    update_metrics(conn, fn metrics ->
      Enum.reduce(to_increment, metrics, fn {metric_name, increment_by}, metrics ->
        Map.update(metrics, metric_name, increment_by, &(&1 + increment_by))
      end)
    end)
  end

  @doc false
  @spec health_check_start(Check.state()) :: Check.state()
  def health_check_start(check) do
    execute_check_span_event(check, :start, %{}, %{})
  end

  @doc false
  @spec health_check_connect(Check.state(), atom) :: Check.state()
  def health_check_connect(check, transport) do
    execute_check_span_event(check, :connect, %{}, %{transport: transport})
  end

  @doc false
  @spec health_check_request(Check.state()) :: Check.state()
  def health_check_request(check) do
    execute_check_span_event(check, :request, %{}, %{})
  end

  @doc false
  @spec health_check_fail(Check.state(), any) :: Check.state()
  def health_check_fail(check, reason) do
    execute_check_span_event(check, :fail, %{}, %{reason: reason})
  end

  @doc false
  @spec health_check_pass(Check.state(), 100..599) :: Check.state()
  def health_check_pass(check, status) do
    execute_check_span_event(check, :pass, %{}, %{status: status})
  end

  defp update_metrics(conn, callback) do
    private =
      conn
      |> Map.get(:private, %{})
      |> Map.get(:wayfarer, %{})

    metrics =
      private
      |> Map.get(:metrics, %{})
      |> callback.()

    private = Map.put(private, :metrics, metrics)

    conn
    |> Conn.put_private(:wayfarer, private)
  end

  defp execute_request_span_event(conn, event, measurements, metadata) do
    monotonic_time = System.monotonic_time()
    now = DateTime.utc_now()

    private =
      conn
      |> Map.get(:private, %{})
      |> Map.get(:wayfarer, %{})

    span_info =
      private
      |> Map.get(:request_span, %{})

    metrics =
      private
      |> Map.get(:metrics, %{})

    measurements =
      if Map.has_key?(span_info, :start_time) do
        %{
          monotonic_time: monotonic_time,
          duration: monotonic_time - span_info.start_time,
          wallclock_time: now
        }
      else
        %{
          monotonic_time: monotonic_time,
          wallclock_time: now
        }
      end
      |> Map.merge(metrics)
      |> Map.merge(measurements)

    metadata =
      span_info
      |> Map.get(:metadata, %{})
      |> Map.merge(metadata)

    :telemetry.execute([:wayfarer, :request, event], measurements, Map.put(metadata, :conn, conn))

    span_info =
      span_info
      |> Map.put(:metadata, metadata)
      |> Map.put_new(:start_time, monotonic_time)

    private =
      private
      |> Map.put(:request_span, span_info)

    conn
    |> Conn.put_private(:wayfarer, private)
  end

  defp execute_check_span_event(check, event, measurements, metadata) do
    monotonic_time = System.monotonic_time()
    now = DateTime.utc_now()
    span_info = Map.get(check, :span, %{})

    metrics = Map.get(span_info, :metrics, %{})

    measurements =
      if Map.has_key?(span_info, :start_time) do
        %{
          monotonic_time: monotonic_time,
          duration: monotonic_time - span_info.start_time,
          wallclock_time: now
        }
      else
        %{
          monotonic_time: monotonic_time,
          wallclock_time: now
        }
      end
      |> Map.merge(metrics)
      |> Map.merge(measurements)

    metadata =
      span_info
      |> Map.get(:metadata, %{})
      |> Map.merge(metadata)

    :telemetry.execute([:wayfarer, :health_check, event], measurements, metadata)

    span_info =
      span_info
      |> Map.put(:metadata, metadata)
      |> Map.put_new(:start_time, monotonic_time)

    Map.put(check, :span, span_info)
  end
end
