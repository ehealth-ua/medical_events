defmodule Core.Schema do
  @moduledoc false

  alias Core.Metadata

  defmacro __using__(_) do
    quote do
      import Core.Schema

      def create_datetime(nil), do: nil
      def create_datetime(%DateTime{} = value), do: value

      def create_datetime(%Date{} = value) do
        {Date.to_erl(value), {0, 0, 0}} |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
      end

      def create_datetime(value) when is_binary(value) do
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _} ->
            DateTime.truncate(datetime, :millisecond)

          _ ->
            case Date.from_iso8601(value) do
              {:ok, date} ->
                create_datetime(date)

              _ ->
                nil
            end
        end
      end
    end
  end

  defmacro schema(collection, do: block) do
    quote do
      Module.put_attribute(__MODULE__, :__metadata__, %Metadata{
        collection: to_string(unquote(collection)),
        primary_key: Module.get_attribute(__MODULE__, :primary_key)
      })

      unquote(block)
      metadata = Module.get_attribute(__MODULE__, :__metadata__)

      defstruct metadata.fields
                |> Map.keys()
                |> Keyword.new(fn x -> {x, nil} end)
                |> Keyword.put(:__meta__, metadata)
                |> Keyword.put(:__validations__, metadata.fields)

      defimpl Vex.Extract, for: __MODULE__ do
        def settings(%{__validations__: field_validations}) do
          Enum.reduce(field_validations, %{}, fn {k, %{"validations" => validations}}, acc ->
            Map.put(acc, k, validations)
          end)
        end

        def attribute(map, [root_attr | path]) do
          get_in(Map.get(map, root_attr), path)
        end

        def attribute(map, name) do
          Map.get(map, name)
        end
      end

      def metadata, do: @__metadata__
    end
  end

  defmacro embedded_schema(do: block) do
    quote do
      Module.put_attribute(__MODULE__, :__metadata__, %Metadata{})

      unquote(block)
      metadata = Module.get_attribute(__MODULE__, :__metadata__)

      defstruct metadata.fields
                |> Map.keys()
                |> Keyword.new(fn x -> {x, nil} end)
                |> Keyword.put(:__meta__, metadata)
                |> Keyword.put(:__validations__, metadata.fields)

      defimpl Vex.Extract, for: __MODULE__ do
        def settings(%{__validations__: field_validations}) do
          Enum.reduce(field_validations, %{}, fn {k, %{"validations" => validations}}, acc ->
            Map.put(acc, k, validations)
          end)
        end

        def attribute(map, [root_attr | path]) do
          get_in(Map.get(map, root_attr), path)
        end

        def attribute(map, name) do
          Map.get(map, name)
        end
      end

      def metadata, do: @__metadata__
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
      field(:inserted_by, presence: true, mongo_uuid: true)
      field(:updated_by, presence: true, mongo_uuid: true)
    end
  end

  def add_validations(%{__validations__: document_validations} = document, field, validations)
      when is_list(validations) do
    field_value = Map.get(document_validations, field)
    field_validations = Map.get(field_value, "validations") ++ validations

    %{
      document
      | __validations__:
          Map.put(
            document_validations,
            field,
            Map.put(field_value, "validations", field_validations)
          )
    }
  end
end

defimpl Vex.Blank, for: DateTime do
  def blank?(%DateTime{}), do: false
  def blank?(_), do: true
end

defimpl Vex.Blank, for: Date do
  def blank?(%Date{}), do: false
  def blank?(_), do: true
end

defimpl Vex.Blank, for: BSON.ObjectId do
  def blank?(%BSON.ObjectId{}), do: false
  def blank?(_), do: true
end

defimpl Vex.Blank, for: NaiveDateTime do
  def blank?(%NaiveDateTime{}), do: false
  def blank?(_), do: true
end

defimpl Vex.Blank, for: BSON.Binary do
  def blank?(%BSON.Binary{}), do: false
  def blank?(_), do: true
end

defimpl String.Chars, for: BSON.ObjectId do
  def to_string(value), do: BSON.ObjectId.encode!(value)
end

defimpl String.Chars, for: BSON.Binary do
  def to_string(%BSON.Binary{binary: value, subtype: :uuid}), do: UUID.binary_to_string!(value)
end
