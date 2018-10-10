defmodule Core.DateView do
  @moduledoc false

  def render_date(nil), do: nil
  def render_date(date) when is_binary(date), do: date
  def render_date(%Date{} = date), do: to_string(date)
  def render_date(%DateTime{} = date_time), do: date_time |> DateTime.to_date() |> to_string()

  def render_datetime(nil), do: nil
  def render_datetime(date_time) when is_binary(date_time), do: date_time
  def render_datetime(%DateTime{} = date_time), do: DateTime.to_iso8601(date_time)
end
