defmodule Core.Mongo.Transaction do
  @moduledoc false

  @worker Application.get_env(:core, :rpc_worker)

  defstruct operations: []

  def add_operation(%__MODULE__{} = transaction, collection, :insert, value) do
    value_bson =
      value
      |> BSON.Encoder.encode()
      |> do_bson_encode("")
      |> Base.encode64()

    operation = %{"set" => value_bson, "operation" => "insert", "collection" => collection}
    %{transaction | operations: transaction.operations ++ [operation]}
  end

  def add_operation(%__MODULE__{} = transaction, collection, :update, filter, set) do
    filter_bson =
      filter
      |> BSON.Encoder.encode()
      |> do_bson_encode("")
      |> Base.encode64()

    set_bson =
      set
      |> BSON.Encoder.encode()
      |> do_bson_encode("")
      |> Base.encode64()

    operation = %{"filter" => filter_bson, "set" => set_bson, "operation" => "update_one", "collection" => collection}
    %{transaction | operations: transaction.operations ++ [operation]}
  end

  def add_operation(%__MODULE__{} = transaction, collection, :delete, filter) do
    filter_bson =
      filter
      |> BSON.Encoder.encode()
      |> do_bson_encode("")
      |> Base.encode64()

    operation = %{"filter" => filter_bson, "operation" => "delete_one", "collection" => collection}
    %{transaction | operations: transaction.operations ++ [operation]}
  end

  def flush(%__MODULE__{} = transaction) do
    @worker.run("me_transactions", Core, :transaction, Jason.encode!(transaction.operations))
  end

  defp do_bson_encode(value, acc) when is_binary(value), do: acc <> value
  defp do_bson_encode(value, acc) when is_integer(value), do: acc <> <<value>>
  defp do_bson_encode([h | tail], acc), do: acc <> do_bson_encode(h, acc) <> do_bson_encode(tail, "")
  defp do_bson_encode([], acc), do: acc
end
