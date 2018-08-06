defmodule Core.Behaviours.DigitalSignatureBehaviour do
  @moduledoc false

  @callback decode(signed_content :: binary, headers :: list) ::
              {:ok, result :: term}
              | {:error, reason :: term}
end
