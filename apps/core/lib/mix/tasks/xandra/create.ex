defmodule Mix.Tasks.Xandra.Create do
  @moduledoc false

  use Mix.Task
  import Core.Keyspaces.Events, only: [get_struct: 0]

  def run(_) do
    Triton.Setup.Keyspace.setup(Enum.into(get_struct(), %{}))
    IO.puts([IO.ANSI.green(), "Keyspace created"])
    IO.puts([IO.ANSI.default_color(), ""])
  end
end
