defmodule Core.Mongo do
  alias Mongo, as: M

  defp execute(fun, args) do
    args =
      args
      |> Keyword.values()
      |> List.insert_at(0, :mongo)

    opts =
      args
      |> List.last()
      |> Keyword.put(:pool, DBConnection.Poolboy)

    args = List.replace_at(args, Enum.count(args) - 1, opts)

    apply(M, fun, args)
  end

  def aggregate(coll, pipeline, opts \\ []) do
    execute(:aggregate, binding())
  end

  def command(query, opts \\ []) do
    execute(:command, binding())
  end

  def command!(query, opts \\ []) do
    execute(:command!, binding())
  end

  def count(coll, filter, opts \\ []) do
    execute(:count, binding())
  end

  def count!(coll, filter, opts \\ []) do
    execute(:count!, binding())
  end

  def delete_many(coll, filter, opts \\ []) do
    execute(:delete_many, binding())
  end

  def delete_many!(coll, filter, opts \\ []) do
    execute(:delete_many!, binding())
  end

  def delete_one(coll, filter, opts \\ []) do
    execute(:delete_one, binding())
  end

  def delete_one!(coll, filter, opts \\ []) do
    execute(:delete_one!, binding())
  end

  def distinct(coll, field, filter, opts \\ []) do
    execute(:distinct, binding())
  end

  def distinct!(coll, field, filter, opts \\ []) do
    execute(:distinct!, binding())
  end

  def find(coll, filter, opts \\ []) do
    execute(:find, binding())
  end

  def find_one(coll, filter, opts \\ []) do
    execute(:find_one, binding())
  end

  def find_one_and_delete(coll, filter, opts \\ []) do
    execute(:find_one_and_delete, binding())
  end

  def find_one_and_replace(coll, filter, replacement, opts \\ []) do
    execute(:find_one_and_replace, binding())
  end

  def find_one_and_update(coll, filter, update, opts \\ []) do
    execute(:find_one_and_update, binding())
  end

  def insert_many(coll, docs, opts \\ []) do
    execute(:insert_many, binding())
  end

  def insert_many!(coll, docs, opts \\ []) do
    execute(:insert_many!, binding())
  end

  def insert_one(%{__meta__: metadata} = doc, opts \\ []) do
    case Vex.errors(doc) do
      [] -> insert_one(to_string(metadata.collection), doc |> Jason.encode!() |> Jason.decode!(), opts)
      errors -> {:error, errors}
    end
  end

  def insert_one(coll, doc, opts) do
    execute(:insert_one, binding())
  end

  def insert_one!(%{__meta__: metadata} = doc, opts \\ []) do
    case Vex.errors(doc) do
      [] -> insert_one!(to_string(metadata.collection), doc |> Jason.encode!() |> Jason.decode!(), opts)
      errors -> {:error, errors}
    end
  end

  def insert_one!(coll, doc, opts) do
    execute(:insert_one!, binding())
  end

  def replace_one(coll, filter, replacement, opts \\ []) do
    execute(:replace_one, binding())
  end

  def replace_one!(coll, filter, replacement, opts \\ []) do
    execute(:replace_one!, binding())
  end

  def update_many(coll, filter, update, opts \\ []) do
    execute(:update_many, binding())
  end

  def update_many!(coll, filter, update, opts \\ []) do
    execute(:update_many!, binding())
  end

  def update_one(coll, filter, update, opts \\ []) do
    execute(:update_one, binding())
  end

  def update_one!(coll, filter, update, opts \\ []) do
    execute(:update_one!, binding())
  end
end
