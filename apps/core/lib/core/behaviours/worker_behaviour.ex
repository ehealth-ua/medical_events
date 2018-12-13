defmodule Core.Behaviours.WorkerBehaviour do
  @moduledoc false

  @callback run(basename :: binary, module :: atom, function :: atom, args :: list()) :: any()
end
