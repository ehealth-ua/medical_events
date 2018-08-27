defmodule Core.Mongo do
  @moduledoc false

  alias Core.Mongo.AuditLog
  alias DBConnection.Poolboy
  alias Mongo, as: M

  defdelegate start_link(opts), to: M
  defdelegate object_id, to: M

  defp execute(fun, args) do
    opts =
      args
      |> List.last()
      |> Keyword.put(:pool, Poolboy)

    enriched_args =
      args
      |> List.replace_at(Enum.count(args) - 1, opts)
      |> List.insert_at(0, :mongo)

    M
    |> apply(fun, enriched_args)
    |> AuditLog.log_operation(fun, args)
  end

  def aggregate(coll, pipeline, opts \\ []) do
    execute(:aggregate, [coll, pipeline, opts])
  end

  def command(query, opts \\ []) do
    execute(:command, [query, opts])
  end

  def command!(query, opts \\ []) do
    execute(:command!, [query, opts])
  end

  def count(coll, filter, opts \\ []) do
    execute(:count, [coll, filter, opts])
  end

  def count!(coll, filter, opts \\ []) do
    execute(:count!, [coll, filter, opts])
  end

  def delete_many(coll, filter, opts \\ []) do
    execute(:delete_many, [coll, filter, opts])
  end

  def delete_many!(coll, filter, opts \\ []) do
    execute(:delete_many!, [coll, filter, opts])
  end

  def delete_one(coll, %{"_id" => _} = filter, opts \\ []) do
    execute(:delete_one, [coll, filter, opts])
  end

  def delete_one!(coll, %{"_id" => _} = filter, opts \\ []) do
    execute(:delete_one!, [coll, filter, opts])
  end

  def distinct(coll, field, filter, opts \\ []) do
    execute(:distinct, [coll, field, filter, opts])
  end

  def distinct!(coll, field, filter, opts \\ []) do
    execute(:distinct!, [coll, field, filter, opts])
  end

  def find(coll, filter, opts \\ []) do
    execute(:find, [coll, filter, opts])
  end

  def find_one(coll, filter, opts \\ []) do
    execute(:find_one, [coll, filter, opts])
  end

  def find_one_and_delete(coll, %{"_id" => _} = filter, opts \\ []) do
    execute(:find_one_and_delete, [coll, filter, opts])
  end

  def find_one_and_replace(coll, %{"_id" => _} = filter, replacement, opts \\ []) do
    execute(:find_one_and_replace, [coll, filter, replacement, opts])
  end

  def find_one_and_update(coll, %{"_id" => _} = filter, update, opts \\ []) do
    execute(:find_one_and_update, [coll, filter, update, opts])
  end

  def insert_many(coll, docs, opts \\ []) do
    execute(:insert_many, [coll, docs, opts])
  end

  def insert_many!(coll, docs, opts \\ []) do
    execute(:insert_many!, [coll, docs, opts])
  end

  def insert_one(%{__meta__: metadata} = doc, opts \\ []) do
    case Vex.errors(doc) do
      [] ->
        insert_one(metadata.collection, prepare_doc(doc), opts)

      errors ->
        {:error, Enum.map(errors, &vex_to_json/1)}
    end
  end

  def insert_one(coll, doc, opts) do
    execute(:insert_one, [coll, doc, opts])
  end

  def insert_one!(%{__meta__: metadata} = doc, opts \\ []) do
    case Vex.errors(doc) do
      [] ->
        insert_one!(metadata.collection, prepare_doc(doc), opts)

      errors ->
        {:error, errors}
    end
  end

  def insert_one!(coll, doc, opts) do
    execute(:insert_one!, [coll, doc, opts])
  end

  def replace_one(coll, %{"_id" => _} = filter, replacement, opts \\ []) do
    execute(:replace_one, [coll, filter, replacement, opts])
  end

  def replace_one!(coll, %{"_id" => _} = filter, replacement, opts \\ []) do
    execute(:replace_one!, [coll, filter, replacement, opts])
  end

  def update_many(coll, filter, update, opts \\ []) do
    execute(:update_many, [coll, filter, update, opts])
  end

  def update_many!(coll, filter, update, opts \\ []) do
    execute(:update_many!, [coll, filter, update, opts])
  end

  def update_one(coll, %{"_id" => _} = filter, update, opts \\ []) do
    execute(:update_one, [coll, filter, update, opts])
  end

  def update_one!(coll, %{"_id" => _} = filter, update, opts \\ []) do
    execute(:update_one!, [coll, filter, update, opts])
  end

  def vex_to_json({:error, field, :presence, message}) do
    {%{
       description: message,
       params: [],
       rule: :required
     }, "$.#{field}"}
  end

  def vex_to_json({:error, field, _, message}) do
    {%{
       description: message,
       params: [],
       rule: :invalid
     }, "$.#{field}"}
  end

  defp prepare_doc(%{__meta__: _} = doc) do
    doc
    |> Map.from_struct()
    |> Map.drop(~w(__meta__ __validations__)a)
    |> Enum.into(%{}, fn {k, v} -> {k, prepare_doc(v)} end)
  end

  defp prepare_doc(%DateTime{} = doc), do: doc

  defp prepare_doc(%{} = doc) do
    Enum.into(doc, %{}, fn {k, v} -> {k, prepare_doc(v)} end)
  end

  defp prepare_doc(doc), do: doc

  def add_to_set(set, %{__struct__: module, __meta__: _} = value, path) do
    fields = Map.keys(module.metadata().fields)

    Enum.reduce(fields, set, fn field, acc ->
      add_to_set(acc, Map.get(value, field), "#{path}.#{field}")
    end)
  end

  def add_to_set(set, [%{__struct__: _module, __meta__: _} | _] = values, path) do
    Map.put(set, path, Enum.map(values, fn value -> prepare_doc(value) end))
  end

  def add_to_set(set, value, path), do: Map.put(set, path, value)
end
