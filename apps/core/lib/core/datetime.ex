defmodule Core.DateTime do
  @moduledoc false

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
