defmodule Core.Migrations.CreateRequestsCollection do
  @moduledoc false

  alias Core.Mongo

  def change do
    {:ok, _} = Mongo.command(create: "requests", capped: true, max: 1_000_000, size: 1024 * 2 * 1_000_000)
  end
end
