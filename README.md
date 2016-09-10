# rondo_server

Usir server for rondo applications

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `rondo_server` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:rondo_server, "~> 0.1.0"}]
    end
    ```

  2. Ensure `rondo_server` is started before your application:

    ```elixir
    def application do
      [applications: [:rondo_server]]
    end
    ```
