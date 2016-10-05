defmodule Rondo.Server.Application do
  require Record
  Record.defrecord :rec, [:handler, :handler_state, :parent, :instance, :path, :props, :state_token, :store, :app, :entry]
  require Logger

  alias Usir.Message.Server

  defmodule Message do
    defstruct [:instance, :data]
  end

  @call __MODULE__.CALL

  def reload_all do
    :erlang.processes()
    |> Stream.filter(fn(pid) ->
      {_, dict} = Process.info(pid, :dictionary)
      !!dict[Rondo.Server.INFO]
    end)
    |> Enum.each(&call(&1, :reload))
  end

  def new(handler, handler_opts, instance, path, props, state_token) do
    parent = self()
    rec = rec(handler: handler, parent: parent, instance: instance)
    spawn_link(fn ->
      Process.put(Rondo.Server.INFO, %{instance: instance, parent: parent})
      case handler.init(handler_opts) do
        {:ok, store, handler_state} ->
          {:mount, path, props, state_token}
          |> init(rec, store, handler_state)
        {:error, error} ->
          maybe_raise(error)
      end
    end)
  end

  def init(call, rec, store, handler_state) do
    rec(rec, handler_state: handler_state, store: store, app: %Rondo.Application{})
    |> handle_call(call)
    |> maybe_reply()
    |> __loop__()
  catch
    type, error when type in [:error, :throw] ->
      handle_error(rec, type, error, System.stacktrace)
  end

  def mount(pid, path, props, state) do
    call(pid, {:mount, path, props, state})
  end

  def unmount(pid) do
    call(pid, :unmount)
    :ok
  end

  def authenticate(pid, method, token) do
    call(pid, {:authenticate, method, token})
  end

  def action(pid, ref, body) do
    call(pid, {:action, ref, body})
  end

  def response(pid, ref, data) do
    call(pid, {:response, ref, data})
  end

  defp call(pid, message) do
    send(pid, {@call, message})
    pid
  end

  def __loop__(rec) do
    rec
    |> await()
    |> __MODULE__.__loop__()
  end

  defp await(rec) do
    receive do
      {@call, message} ->
        rec
        |> handle_call(message)
        |> maybe_reply()
      info ->
        store = Rondo.State.Store.handle_info(rec(rec, :store), info)
        rec
        |> rec(store: store)
        |> mount()
        |> maybe_reply()
    end
  catch
    type, error when type in [:error, :throw] ->
      handle_error(rec, type, error, System.stacktrace)
  end

  defp handle_error(rec, type, error, stacktrace) do
    rec(handler: handler, path: path, instance: instance) = rec
    info = handler.format_error(type, error, stacktrace)

    Logger.error(Exception.format(type, error, stacktrace))

    {:ok, %Server.Error{path: path, instance: instance, info: info}, rec}
    |> maybe_reply()
  end

  defp maybe_reply({:ok, data, rec(parent: parent, instance: instance) = rec}) do
    send(parent, %Message{instance: instance, data: data})
    rec
  end
  defp maybe_reply({:noreply, rec}) do
    rec
  end

  defp maybe_raise(%{__struct__: _} = error) do
    raise error
  end
  defp maybe_raise(error) do
    throw error
  end

  defp handle_call(rec(handler: handler, handler_state: handler_state) = rec, {:mount, path, props, state_token}) do
    case handler.route(path, props, handler_state) do
      {:ok, entry} ->
        rec
        |> rec(path: path, props: props)
        |> put_entry(entry)
        |> init_store(state_token)
        |> mount()
      {:error, :not_found} ->
        {:ok, %Server.NotFound{instance: rec(rec, :instance), path: path}, rec}
      {:error, error} ->
        maybe_raise(error)
    end
  end
  defp handle_call(rec() = rec, {:authenticate, _method, _token}) do
    # TODO
    {:noreply, rec}
  end
  defp handle_call(rec(app: app, store: store, instance: instance) = rec, {:action, ref, body}) do
    case Rondo.submit_action(app, store, ref, body) do
      {:ok, app, store} ->
        {:ok, %Server.ActionAcknowledged{instance: instance, ref: ref}, rec}
        |> maybe_reply()
        |> rec(app: app, store: store)
        |> send_streams()
        |> mount()
        |> remove_noop()
      {:invalid, errors, app, store} ->
        errors = Enum.reduce(errors, %{}, fn({message, path}, acc) ->
          Map.update(acc, path, [message], &([message | &1]))
        end)
        rec = rec(rec, app: app, store: store)
        {:ok, %Server.ActionInvalid{instance: instance, info: errors, ref: ref}, rec}
      {:error, error, app, store} ->
        rec = rec(rec, app: app, store: store)
        {:ok, %Server.Error{instance: instance, info: error}, rec}
    end
  end
  defp handle_call(rec(instance: instance, state_token: state_token) = rec, :unmount) do
    message = %Server.Unmounted{instance: instance, state: state_token}
    {:ok, message, rec}
    |> maybe_reply()

    exit(:normal)
  end
  defp handle_call(rec(path: path, props: props, state_token: state_token) = rec, :reload) do
    msg = {:mount, path, props, state_token}
    handle_call(rec(rec, app: %Rondo.Application{}), msg)
  end

  defp put_entry(rec(app: app) = rec, entry) do
    rec(rec, app: %{app | entry: entry})
  end

  defp init_store(rec, nil) do
    rec
  end
  defp init_store(rec(store: store) = rec, token) do
    store = Rondo.State.Store.decode_into(store, token)
    rec(rec, store: store)
  end

  defp remove_noop({:ok, %Server.Mounted{body: []}, rec}) do
    {:noreply, rec}
  end
  defp remove_noop(other) do
    other
  end

  defp mount(rec(app: app, store: store) = rec) do
    app
    |> render(store)
    |> prepare_diff(rec)
  end

  defp render(app, store) do
    store = Rondo.State.Store.initialize(store)
    {rendered, store} = Rondo.render(app, store)
    store = Rondo.State.Store.finalize(store)

    diff = Rondo.diff(rendered, app) |> Enum.to_list
    {diff, rendered, store}
  end

  defp prepare_diff({[], app, store}, rec) do
    mount_body([], rec(rec, :state_token), rec(rec, app: app, store: store))
  end
  defp prepare_diff({diff, app, store}, rec) do
    token = Rondo.State.Store.encode(store)
    mount_body(diff, token, rec(rec, app: app, store: store, state_token: token))
  end

  defp mount_body(body, state_token, rec(instance: instance, path: path) = rec) do
    message = %Server.Mounted{instance: instance, path: path, body: body, state: state_token}
    {:ok, message, rec}
  end

  defp send_streams(rec(instance: instance, app: app) = rec) do
    case Rondo.fetch_streams(app) do
      streams when map_size(streams) > 0 ->
        {:ok, %Server.Info{instance: instance, name: "_emit", data: streams}, rec}
        |> maybe_reply()
      _ ->
        rec
    end
  end
end
