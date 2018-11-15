defmodule Core.Behaviours.WorkerBehaviour do
  @moduledoc false

  @callback run(module :: atom, function :: atom, args :: list(), attempt :: integer) :: any()
end
