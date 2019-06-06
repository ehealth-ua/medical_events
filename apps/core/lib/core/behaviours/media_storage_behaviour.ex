defmodule Core.Behaviours.MediaStorageBehaviour do
  @moduledoc false

  @callback save(id :: binary, content :: binary, bucket :: binary, resource_name :: binary) ::
              :ok | :error
end
