defmodule Core.Rpc.Worker do
  @moduledoc false

  use Confex, otp_app: :core
  require Logger

  @behaviour Core.Behaviours.WorkerBehaviour

  def run(basename, module, function, args, attempt \\ 0) do
    if attempt >= config()[:max_attempts] do
      {:error, :badrpc}
    else
      do_run(basename, module, function, args, attempt)
    end
  end

  defp do_run(basename, module, function, args, attempt) do
    servers = Node.list() |> Enum.filter(&String.starts_with?(to_string(&1), basename))

    case servers do
      # Invalid basename or all servers are down
      [] ->
        run(basename, module, function, args, attempt + 1)

      _ ->
        case :rpc.call(Enum.random(servers), module, function, args) do
          # try a different server
          {:badrpc, :nodedown} ->
            run(basename, module, function, args, attempt + 1)

          {:badrpc, error} ->
            Logger.error(inspect(error))
            {:error, :badrpc}

          {:EXIT, error} ->
            Logger.error(inspect(error))
            {:error, :badrpc}

          response ->
            response
        end
    end
  end
end
