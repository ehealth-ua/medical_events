defmodule Core.Mongo.Transaction do
  @moduledoc false

  alias Core.Mongo

  @worker Application.get_env(:core, :rpc_worker)

  @derive Jason.Encoder
  defstruct operations: [], actor_id: "", patient_id: ""

  def add_operation(%__MODULE__{} = transaction, collection, :insert, value, id) do
    value_bson =
      value
      |> Mongo.prepare_doc()
      |> BSON.Encoder.encode()
      |> do_bson_encode("")
      |> Base.encode64()

    operation = %{"set" => value_bson, "operation" => "insert", "collection" => collection, "id" => to_string(id)}
    %{transaction | operations: transaction.operations ++ [operation]}
  end

  def add_operation(%__MODULE__{} = transaction, collection, :delete, filter, id) do
    filter_bson =
      filter
      |> BSON.Encoder.encode()
      |> do_bson_encode("")
      |> Base.encode64()

    operation = %{
      "filter" => filter_bson,
      "operation" => "delete_one",
      "collection" => collection,
      "id" => to_string(id)
    }

    %{transaction | operations: transaction.operations ++ [operation]}
  end

  def add_operation(%__MODULE__{} = transaction, collection, :upsert, filter, set, id) do
    filter_bson =
      filter
      |> BSON.Encoder.encode()
      |> do_bson_encode("")
      |> Base.encode64()

    set_bson =
      set
      |> Mongo.prepare_doc()
      |> BSON.Encoder.encode()
      |> do_bson_encode("")
      |> Base.encode64()

    operation = %{
      "filter" => filter_bson,
      "set" => set_bson,
      "operation" => "upsert_one",
      "collection" => collection,
      "id" => to_string(id)
    }

    %{transaction | operations: transaction.operations ++ [operation]}
  end

  def add_operation(%__MODULE__{} = transaction, collection, :update, filter, set, id) do
    filter_bson =
      filter
      |> BSON.Encoder.encode()
      |> do_bson_encode("")
      |> Base.encode64()

    set_bson =
      set
      |> Mongo.prepare_doc()
      |> BSON.Encoder.encode()
      |> do_bson_encode("")
      |> Base.encode64()

    operation = %{
      "filter" => filter_bson,
      "set" => set_bson,
      "operation" => "update_one",
      "collection" => collection,
      "id" => to_string(id)
    }

    %{transaction | operations: transaction.operations ++ [operation]}
  end

  def flush(%__MODULE__{} = transaction) do
    @worker.run("me_transactions", Core, :transaction, Jason.encode!(transaction))
  end

  defp do_bson_encode(value, acc) when is_binary(value), do: acc <> value
  defp do_bson_encode(value, acc) when is_integer(value), do: acc <> <<value>>
  defp do_bson_encode([h | tail], acc), do: acc <> do_bson_encode(h, acc) <> do_bson_encode(tail, "")
  defp do_bson_encode([], acc), do: acc
end
