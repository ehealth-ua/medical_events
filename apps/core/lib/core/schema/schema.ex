defmodule Core.Schema do
  alias Core.Metadata

  defmacro __using__(_) do
    quote do
      @derive {Jason.Encoder, except: [:__meta__]}

      import Core.Schema
    end
  end

  defmacro schema(collection, do: block) do
    quote do
      Module.put_attribute(__MODULE__, :__metadata__, %Metadata{
        collection: unquote(collection),
        primary_key: Module.get_attribute(__MODULE__, :primary_key)
      })

      unquote(block)
      metadata = Module.get_attribute(__MODULE__, :__metadata__)

      defstruct metadata.fields
                |> Map.keys()
                |> Keyword.new(fn x -> {x, nil} end)
                |> Keyword.put(:__meta__, metadata)

      defimpl Vex.Extract, for: __MODULE__ do
        def settings(%{__meta__: metadata}) do
          Enum.reduce(metadata.fields, %{}, fn {k, %{"validations" => validations}}, acc ->
            Map.put(acc, k, validations)
          end)
        end

        def attribute(map, [root_attr | path]) do
          Map.get(map, root_attr) |> get_in(path)
        end

        def attribute(map, name) do
          Map.get(map, name)
        end
      end
    end
  end

  defmacro field(name, validations \\ []) do
    quote do
      metadata = Module.get_attribute(__MODULE__, :__metadata__)
      primary_key = metadata.primary_key
      validations = unquote(validations)
      name = unquote(name)
      validations = if name == primary_key, do: Keyword.put(validations, :presence, true), else: validations

      Module.put_attribute(__MODULE__, :__metadata__, %{
        metadata
        | fields: Map.put(metadata.fields, name, %{"validations" => validations})
      })
    end
  end

  defmacro timestamps do
    quote do
      field(:inserted_at, presence: true)
      field(:updated_at, presence: true)
    end
  end

  defmacro changed_by do
    quote do
      field(:inserted_by, presence: true)
      field(:updated_by, presence: true)
    end
  end
end

defimpl Vex.Blank, for: DateTime do
  def blank?(%DateTime{}), do: false
  def blank?(value), do: true
end
