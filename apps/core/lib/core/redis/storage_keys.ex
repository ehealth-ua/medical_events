defmodule Core.Redis.StorageKeys do
  @moduledoc false

  def person_data(user_id, client_id), do: "casher:person_data:#{user_id}:#{client_id}"
end
