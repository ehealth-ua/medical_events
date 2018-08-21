defmodule Core.Behaviours.IlBehaviour do
  @moduledoc false

  @callback get_dictionaries(params :: map, headers :: list) ::
              {:ok, result :: term}
              | {:error, reason :: term}

  @callback get_employee(id :: binary, headers :: list) ::
              {:ok, result :: term}
              | {:error, reason :: term}
end
