defmodule Core.CacheHelper do
  @moduledoc false

  def get_cache_key do
    self()
    |> inspect()
    |> String.replace_leading("#PID", "message_cache_")
    |> String.to_atom()
  end
end
