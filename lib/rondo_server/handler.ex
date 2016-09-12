defmodule Rondo.Server.Handler do
  use Usir.Server.Handler
  alias Usir.Message.Server
  alias Rondo.Server.Application

  def init(%{handler: handler, handler_opts: handler_opts}, protocol_info) do
    :erlang.process_flag(:trap_exit, true)
    {:ok, handler_opts} = handler.setup(handler_opts, protocol_info)
    {:ok, %{instances: %{}, handler: handler, handler_opts: handler_opts}}
  end

  def mount(%{instances: instances, handler: handler, handler_opts: handler_opts} = state, %{instance: instance, path: path, props: props, state: state_token}) do
    instances = update_in(instances, [instance], fn
      (nil) ->
        Application.new(handler, handler_opts, instance, path, props, state_token)
      (app) ->
        Application.mount(app, path, props, state_token)
    end)

    {:noreply, %{state | instances: instances}}
  end

  def unmount(%{instances: instances} = state, %{instance: instance}) do
    case Map.fetch(instances, instance) do
      :error ->
        message = %Server.Unmounted{instance: instance}
        {:ok, message, state}
      {:ok, app} ->
        :ok = Application.unmount(app)
        {:noreply, state}
    end
  end

  def authenticate(%{instances: instances} = state, %{instance: instance, method: method, token: token}) do
    case Map.fetch(instances, instance) do
      :error ->
        message = %Server.AuthenticationInvalid{instance: instance, method: method}
        {:ok, message, state}
      {:ok, app} ->
        app = Application.authenticate(app, method, token)
        {:noreply, %{state | instances: Map.put(instances, instance, app)}}
    end
  end

  def response(%{instances: instances} = state, %{instance: instance, ref: ref, data: data}) do
    case Map.fetch(instances, instance) do
      :error ->
        {:noreply, state}
      {:ok, app} ->
        app = Application.response(app, ref, data)
        {:noreply, %{state | instances: Map.get(instances, instance, app)}}
    end
  end

  def action(%{instances: instances} = state, %{instance: instance, ref: ref, body: body}) do
    case Map.fetch(instances, instance) do
      :error ->
        message = %Server.ActionInvalid{instance: instance, ref: ref, info: ["app not mounted"]}
        {:ok, message, state}
      {:ok, app} ->
        app = Application.action(app, ref, body)
        {:noreply, %{state | instances: Map.put(instances, instance, app)}}
    end
  end

  def handle_info(%{instances: instances} = state, %Application.Message{instance: instance, data: data}) do
    case Map.fetch(instances, instance) do
      :error ->
        {:noreply, state}
      {:ok, _} ->
        {:ok, data, state}
    end
  end
  def handle_info(%{instances: instances} = state, {:EXIT, pid, reason}) when reason in [:normal, :shutdown] do
    case Enum.find(instances, &(elem(&1, 1) == pid)) do
      {instance, _} ->
        {:noreply, %{state | instances: Map.delete(instances, instance)}}
      _ ->
        {:noreply, state}
    end
  end
  def handle_info(state, info) do
    IO.inspect info
    {:noreply, state}
  end
end
