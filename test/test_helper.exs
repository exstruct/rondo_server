defmodule Test.Rondo.Server.Client do
  use Usir.Client.Handler

  def connect(address) do
    {:ok, _} = :application.ensure_all_started(:websocket_client)

    formats = %{"msgpack" => %Usir.Format.MSGPACK{ext: Rondo.Server.Format.MSGPACK}}

    acceptor = Usir.Acceptor.new(Usir.Client, formats, __MODULE__, %{owner: self()})

    Usir.Transport.HTTP.Client.ws(address, acceptor, %{})
  end

  def request(pid, message) do
    send(pid, {:req, message})
    receive do
      {:resp, message} ->
        message
    after
      3000 ->
        throw :timeout
    end
  end

  def close(pid) do
    Usir.Transport.HTTP.Client.close(pid)
  end

  def init(%{owner: owner}, _) do
    {:ok, %{owner: owner, buffer: [], timeout: nil}}
  end

  methods = [:mounted,
             :unmounted,
             :not_found,
             :authentication_required,
             :authentication_invalid,
             :unauthorized,
             :authentication_acknowledged,
             :action_acknowledged,
             :action_invalid,
             :info,
             :call,
             :error]

  for fun <- methods do
    def unquote(fun)(%{timeout: timeout} = handler, message) when not is_nil(timeout) do
      :timer.cancel(timeout)
      unquote(fun)(%{handler | timeout: nil}, message)
    end
    def unquote(fun)(%{buffer: buffer} = handler, message) do
      timeout = :timer.send_after(20, :TIMEOUT)
      {:noreply, %{handler | buffer: [message | buffer], timeout: timeout}}
    end
  end

  def handle_info(%{buffer: []} = handler, :TIMEOUT) do
    {:noreply, handler}
  end
  def handle_info(%{owner: owner, buffer: buffer} = handler, :TIMEOUT) do
    send(owner, {:resp, :lists.reverse(buffer)})
    {:noreply, %{handler | buffer: [], timeout: nil}}
  end
  def handle_info(handler, {:req, message}) do
    {:ok, message, handler}
  end
end

ExUnit.start()
