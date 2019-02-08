defmodule Core.Application do
  @moduledoc false

  use Application
  alias Core.Redis

  def start(_type, _args) do
    import Supervisor.Spec

    redix_config = Redis.config()

    redix_workers =
      for i <- 0..(redix_config[:pool_size] - 1) do
        worker(
          Redix,
          [
            [
              host: redix_config[:host],
              port: redix_config[:port],
              password: redix_config[:password],
              database: redix_config[:database]
            ],
            [name: :"redix_#{i}"]
          ],
          id: {Redix, i}
        )
      end

    # List all child processes to be supervised

    children =
      redix_workers ++
        [
          worker(Core.Validators.Cache, []),
          worker(Mongo, [[name: :mongo, url: Application.get_env(:core, :mongo)[:url], pool: DBConnection.Poolboy]]),
          worker(
            Mongo,
            [
              [
                name: :mongo_audit_log,
                url: Application.get_env(:core, :mongo_audit_log)[:url],
                pool: DBConnection.Poolboy
              ]
            ],
            id: :mongo_audit_log
          )
        ]

    opts = [strategy: :one_for_one, name: Core.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
