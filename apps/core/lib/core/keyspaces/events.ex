defmodule Core.Keyspaces.Events do
  @moduledoc false

  use Triton.Keyspace

  keyspace :events, conn: Triton.Conn do
    with_options(replication: "{'class' : 'SimpleStrategy', 'replication_factor': 1}")
  end

  def get_conn do
    Keyword.get(@keyspace, :__conn__)
  end

  def get_struct, do: @keyspace
end
