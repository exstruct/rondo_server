# rondo_server [![Build Status](https://travis-ci.org/exstruct/rondo_server.svg?branch=master)](https://travis-ci.org/exstruct/rondo_server) [![Hex.pm](https://img.shields.io/hexpm/v/rondo_server.svg?style=flat-square)](https://hex.pm/packages/rondo_server) [![Hex.pm](https://img.shields.io/hexpm/dt/rondo_server.svg?style=flat-square)](https://hex.pm/packages/rondo_server)

[Usir](https://github.com/usir) server for [rondo](https://github.com/extruct/rondo) applications

## Installation

`Rondo.Server` is [available in Hex](https://hex.pm/docs/publish) and can be installed as:

  1. Add `rondo_server` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:rondo_server, "~> 0.1.0"}]
end
```

## Usage

Start by creating the rondo component we want to render:

```
defmodule MyApp.Hello do
  use Rondo.Component

  def render(%{"name" => name}) do
    el("Text", nil, [name])
  end
end
```

Next define a handler.

```
defmodule MyApp.Handler do
  use Rondo.Server

  # The setup method is called for every connection.
  # The return value is the options to be fed to application initialization
  def setup(_opts, _protocol_info) do
    {:ok, %{}}
  end

  # Called per app. Returns the store and internal state
  def init(app_opts) do
    {:ok, Rondo.Test.Store.init(%{}), app_opts}
  end

  # Here we define how the usir paths route to rondo components
  def route("/" = _path, props, _state) do
    {:ok, el(MyApp.Hello, props)}
  end
  def route(_, _, _) do
    {:error, :not_found}
  end

  # This method handles authentication. In this example we won't set it up.
  def authenticate(_method, _token, _state) do
    :error
  end
end
```

Now we can create an acceptor from the handler and start a usir transport:

```
acceptor = Rondo.Server.acceptor(MyApp.Handler, %{})
Usir.Transport.HTTP.Server.http(acceptor)
```

Now mount the application at `/` with a usir client and we're in business.
