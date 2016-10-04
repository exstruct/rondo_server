defmodule Rondo.Server do
  use Behaviour

  defmacro __using__(_) do
    quote do
      @behaviour Rondo.Server
      import Rondo.Element

      case Mix.env do
        :prod ->
          def format_error(_, _, _) do
            "Internal Server Error"
          end
        _ ->
          def format_error(type, error, stacktrace) do
            Exception.format(type, error, stacktrace)
          end
      end

      defoverridable [format_error: 3]
    end
  end

  defmodule CallResponse do
    defstruct [:data]
  end

  @formats %{
    "msgpack" => %Usir.Format.MSGPACK{ext: __MODULE__.Format.MSGPACK}
  }

  defcallback setup(protocol_opts :: map, protocol_info :: map) :: {:ok, any} | {:error, reason :: term}
  defcallback init(opts :: any) :: {:ok, Rondo.State.Store.t, any} | {:error, reason :: term}
  defcallback route(path :: binary, props :: map, state :: any) :: {:ok, Rondo.Element.Mountable.t} | {:error, reason :: term}
  defcallback authenticate(method :: term, token :: binary, state :: any) :: {:ok, data :: term} | {:error, error :: term}
  defcallback format_error(type :: atom, error :: term, stacktrace :: list) :: binary

  def acceptor(handler, opts \\ %{}) do
    Usir.Acceptor.new(Usir.Server, @formats, __MODULE__.Handler, %{handler: handler, handler_opts: opts})
  end

  def reload() do
    Rondo.Server.Application.reload_all()
  end

  def authenticate(_methods, _timeout \\ :infinity) do
    throw :not_implemented
  end

  def call(name, data, timeout \\ 5_000) do
    %Usir.Message.Server.Call{name: name, data: data}
    |> send_message()

    receive do
      %CallResponse{data: data} ->
        {:ok, data}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  def info(name, data) do
    %Usir.Message.Server.Info{name: name, data: data}
    |> send_message()
  end

  defp send_message(message) do
    %{parent: parent, instance: instance} = Process.get(__MODULE__.INFO)
    message = %Rondo.Server.Application.Message{instance: instance, data: %{message | instance: instance}}
    send(parent, message)
    :ok
  end
end
