spark_locals_without_parens = [
  algorithm: 1,
  certfile: 1,
  check: 0,
  check: 1,
  check: 2,
  cipher_suite: 1,
  config: 0,
  config: 1,
  config: 2,
  connect_timeout: 1,
  health_checks: 0,
  health_checks: 1,
  host_patterns: 0,
  host_patterns: 1,
  hostname: 1,
  http: 2,
  http: 3,
  http_1_options: 1,
  http_2_options: 1,
  https: 2,
  https: 3,
  interval: 1,
  keyfile: 1,
  listeners: 0,
  listeners: 1,
  method: 1,
  name: 1,
  path: 1,
  pattern: 1,
  pattern: 2,
  plug: 1,
  plug: 2,
  response_timeout: 1,
  scheme: 1,
  success_codes: 1,
  targets: 0,
  targets: 1,
  thousand_island_options: 1,
  threshold: 1,
  transport: 1,
  websocket_options: 1,
  ws: 2,
  ws: 3,
  wss: 2,
  wss: 3
]

[
  import_deps: [:spark],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter],
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ]
]
