# Wayfarer

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)

Wayfarer is a runtime-configurable HTTP reverse proxy using
[Bandit](https://hex.pm/packages/bandit) and
[Mint](https://hex.pm/packages/mint).

## Status

Wayfarer is able to proxy HTTP/1, HTTP/2 and WebSocket requests. There are
probably still edge cases and bugs, but it can be used.

## Installation

Wayfarer is [available in Hex](https://hex.pm/packages/wayfarer), the package
can be installed by adding `wayfarer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:wayfarer, "~> 0.4.1"}
  ]
end
```

Documentation for the latest release can be found on
[HexDocs](https://hexdocs.pm/wayfarer).

## Github Mirror

This repository is mirrored [on Github](https://github.com/jimsynz/wayfarer)
from it's primary location [on my Forgejo instance](https://harton.dev/james/wayfarer).
Feel free to raise issues and open PRs on Github.

## License

This software is licensed under the terms of the
[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0), see the
`LICENSE` file included with this package for the terms.
