defmodule Test.Rondo.Server do
  use ExUnit.Case
  alias __MODULE__.Client
  alias Usir.Message

  defmodule Hello do
    use Rondo.Component

    def render(%{"name" => name}) do
      el("Text", nil, [name])
    end
  end

  defmodule Counter do
    defmodule Count do
      use Rondo.Action

      def affordance(_) do
        %{
          "type" => "number"
        }
      end

      def action(_, prev, input) do
        prev + input
      end
    end

    use Rondo.Component

    def state(_, _) do
      %{
        counter: create_store(0)
      }
    end

    def render(%{counter: counter}) do
      el("Container", nil, [
        el("Display", nil, [counter]),
        el("Modify", %{on_submit: ref([:counter]) |> action(Count)})
      ])
    end
  end

  defmodule SendInfo do
    defmodule UpdateAndSendInfo do
      use Rondo.Action

      def affordance(_) do
        %{
          "type" => "string"
        }
      end

      def action(_, _, input) do
        Rondo.Server.info("foo", %{"value" => input})
        input
      end
    end

    use Rondo.Component

    def state(_, _) do
      %{
        value: create_store(nil)
      }
    end

    def render(%{value: value}) do
      el("Form", %{on_submit: ref([:value]) |> action(UpdateAndSendInfo)}, [value])
    end
  end

  defmodule Stream do
    defmodule SendEvent do
      use Rondo.Action

      def affordance(_) do
        %{
          "type" => "array"
        }
      end

      def action(_, prev, input) do
        Elixir.Stream.concat(prev, input)
      end
    end

    use Rondo.Component

    def state(_, _) do
      %{
        events: create_stream()
      }
    end

    def render(%{events: events}) do
      el("Form", %{
        events: events,
        on_submit: ref([:events]) |> action(SendEvent)
      })
    end
  end

  defmodule Handler do
    use Rondo.Server

    def setup(%{acceptor: true}, _) do
      {:ok, %{proto: true}}
    end

    def init(%{proto: true}) do
      {:ok, Rondo.Test.Store.init(%{}), %{state: true}}
    end

    def route("/hello", props, _) do
      {:ok, el(Hello, props)}
    end
    def route("/counter", props, _) do
      {:ok, el(Counter, props)}
    end
    def route("/send-info", props, _) do
      {:ok, el(SendInfo, props)}
    end
    def route("/stream", props, _) do
      {:ok, el(Stream, props)}
    end
    def route(_, _, %{state: true}) do
      {:error, :not_found}
    end

    def authenticate(_method, _token, _state) do

    end
  end

  test "hello" do
    start(fn(client) ->
      [%Message.Server.Mounted{body: [%{value: %{type: "Text", children: ["Joe"]}}]}] =
        mount(client, 1, "/hello", %{"name" => "Joe"})
      [%Message.Server.Mounted{body: []}] =
        mount(client, 1, "/hello", %{"name" => "Joe"})
      [%Message.Server.Mounted{body: [%{value: "Robert"}]}] =
        mount(client, 1, "/hello", %{"name" => "Robert"})
    end)
  end

  test "no found" do
    start(fn(client) ->
      [%Message.Server.NotFound{}] =
        mount(client, 1, "/not-found")
    end)
  end

  test "app error" do
    start(fn(client) ->
      [%Message.Server.Mounted{body: [_]}] =
        mount(client, 1, "/hello", %{"name" => "Robert"})
      [%Message.Server.Error{}] =
        mount(client, 1, "/hello", %{"nf" => "Joe"})
      [%Message.Server.Mounted{body: []}] =
        mount(client, 1, "/hello", %{"name" => "Robert"})
    end)
  end

  test "app error on mount" do
    start(fn(client) ->
      [%Message.Server.Error{}] =
        mount(client, 1, "/hello", %{"nf" => "Joe"})
      [%Message.Server.Mounted{body: [_]}] =
        mount(client, 1, "/hello", %{"name" => "Robert"})
    end)
  end

  test "unmount" do
    start(fn(client) ->
      [%Message.Server.Mounted{}] =
        mount(client, 1, "/hello", %{"name" => "Robert"})
      [%Message.Server.Unmounted{}] =
        unmount(client, 1)
    end)
  end

  test "unmount unmounted" do
    start(fn(client) ->
      [%Message.Server.Unmounted{}] =
        unmount(client, 1)
    end)
  end

  test "action" do
    start(fn(client) ->
      [%Message.Server.Mounted{body: body}] =
        mount(client, 1, "/counter", %{})

      [%{value: %{children: [
                     %{children: [0]},
                     %{props: %{"on_submit" => %{ref: action_ref}}}
                   ]}} | _] = body

      [%Message.Server.ActionAcknowledged{},
       %Message.Server.Mounted{body: [%{value: 7}]}] =
        action(client, 1, action_ref, 7)

      [%Message.Server.ActionAcknowledged{}] =
        action(client, 1, action_ref, 0)

      [%Message.Server.ActionAcknowledged{},
       %Message.Server.Mounted{body: [%{value: 10}]}] =
        action(client, 1, action_ref, 3)

      [%Message.Server.ActionInvalid{}] =
        action(client, 1, action_ref, "Invalid data")

      [%Message.Server.ActionAcknowledged{},
       %Message.Server.Mounted{body: [%{value: 12}], state: state}] =
        action(client, 1, action_ref, 2)

      [%Message.Server.Mounted{body: [%{value: %{children: [%{children: [12]} | _]}} | _]}] =
        mount(client, 2, "/counter", %{}, state)
    end)
  end

  test "unmounted action" do
    start(fn(client) ->
      [%Message.Server.ActionInvalid{}] =
        action(client, 1, 123, "Hello!")
    end)
  end

  test "send info" do
    start(fn(client) ->
      [%Message.Server.Mounted{body: body}] =
        mount(client, 1, "/send-info", %{})

      [%{value: %{props: %{"on_submit" => %{ref: action_ref}}}} | _] = body

      [%Message.Server.Info{name: "foo", data: %{"value" => "Hello!"}},
       %Message.Server.ActionAcknowledged{},
       %Message.Server.Mounted{}] =
        action(client, 1, action_ref, "Hello!")
    end)
  end

  test "streams" do
    start(fn(client) ->
      [%Message.Server.Mounted{body: body}] =
        mount(client, 1, "/stream", %{})

      [%{value: %{props: %{"on_submit" => %{ref: action_ref}}}} | _] = body

      [%Message.Server.ActionAcknowledged{},
       %Message.Server.Info{name: "_emit", data: _}] =
        action(client, 1, action_ref, ["Hello", "World!"])
    end)
  end

  defp start(fun) do
    acceptor = Rondo.Server.acceptor(Handler, %{acceptor: true})
    {:ok, ref} = Usir.Transport.HTTP.Server.http(acceptor, %{}, [port: 0])
    {_, port} = :ranch.get_addr(ref)
    address = 'ws://localhost:#{port}'
    {:ok, client} = Client.connect(address)
    close = fn() ->
      Client.close(client)
      Usir.Transport.HTTP.Server.close(ref)
    end
    try do
      fun.(client)
      close.()
    rescue
      e ->
        close.()
        reraise e, System.stacktrace
    catch
      :throw, error ->
        close.()
        throw error
    end
  end

  defp mount(client, instance, path, props \\ %{}, state \\ nil) do
    Client.request(client, [%Message.Client.Mount{instance: instance, path: path, props: props, state: state}])
  end

  defp unmount(client, instance) do
    Client.request(client, [%Message.Client.Unmount{instance: instance}])
  end

  defp action(client, instance, ref, data) do
    Client.request(client, [%Message.Client.Action{instance: instance, ref: ref, body: data}])
  end
end
