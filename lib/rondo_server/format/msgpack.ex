types = %{
  Rondo.Affordance => 33,
  Rondo.Component.Pointer => 34,
  Rondo.Element => 31,
  Rondo.Path => 32,
  Rondo.Patch => 35,
  Rondo.Schema => 36,
  Rondo.Stream.Subscription => 37
}

defmodule Rondo.Server.Format.MSGPACK do
  @msgpax_opts %{ext: __MODULE__}

  def __transform__(list, struct) do
    bin = list |> Msgpax.Packer.transform() |> :erlang.iolist_to_binary()
    struct
    |> struct_to_ext()
    |> Msgpax.Ext.new(bin)
    |> Msgpax.Packer.transform()
  end

  for {struct, num} <- types do
    defp struct_to_ext(unquote(struct)) do
      unquote(num)
    end

    def unpack(unquote(num), data) do
      case Msgpax.Unpacker.unpack(data, @msgpax_opts) do
        {:ok, value, ""} ->
          value = Msgpax.Packer.unquote(struct).unpack(value)
          {:ok, value}
        {:error, error} ->
          {:error, error}
      end
    end
  end
  def unpack(id, bin) do
    Usir.Format.MSGPACK.unpack(id, bin, %{ext: __MODULE__})
  end
end

alias Rondo.Server.Format.MSGPACK

defimpl Msgpax.Packer, for: Rondo.Affordance do
  def transform(%{ref: nil}) do
    Msgpax.Packer.transform(nil)
  end
  def transform(%{ref: ref, schema_id: schema_id}) do
    [ref, schema_id]
    |> MSGPACK.__transform__(@for)
  end

  def unpack([ref, schema_id]) do
    %@for{ref: ref, schema_id: schema_id}
  end
end

defimpl Msgpax.Packer, for: Rondo.Component do
  def transform(%{tree: %{root: root}}) do
    Msgpax.Packer.transform(root)
  end
end

defimpl Msgpax.Packer, for: Rondo.Component.Pointer do
  def transform(%{path: path}) do
    path
    |> Rondo.Path.to_list()
    |> MSGPACK.__transform__(@for)
  end

  def unpack(list) do
    path = Rondo.Path.from_list(list)
    %@for{path: path}
  end
end

defimpl Msgpax.Packer, for: Rondo.Element do
  def transform(%{type: type, props: props, children: children}) when is_list(children) do
    [type, props | children]
    |> MSGPACK.__transform__(@for)
  end

  def unpack([type]) do
    %@for{type: type}
  end
  def unpack([type, props]) do
    %@for{type: type, props: props}
  end
  def unpack([type, props | children]) do
    %@for{type: type, props: props, children: children}
  end
end

defimpl Msgpax.Packer, for: Rondo.Path do
  def transform(path) do
    path
    |> Rondo.Path.to_list()
    |> MSGPACK.__transform__(@for)
  end

  def unpack(path) do
    Rondo.Path.from_list(path)
  end
end

defimpl Msgpax.Packer, for: Rondo.Patch do
  def transform(%{doc: doc}) do
    doc
    |> MSGPACK.__transform__(@for)
  end

  def unpack(doc) do
    %@for{doc: doc, empty?: map_size(doc) == 0}
  end
end

defimpl Msgpax.Packer, for: Rondo.Schema do
  def transform(%{schema: schema}) do
    schema
    |> MSGPACK.__transform__(@for)
  end

  def unpack(schema) do
    %@for{schema: schema}
  end
end

defimpl Msgpax.Packer, for: Rondo.Stream.Subscription do
  def transform(%{id: id}) do
    id
    |> MSGPACK.__transform__(@for)
  end

  def unpack(id) do
    %@for{id: id}
  end
end
