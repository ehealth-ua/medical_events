defmodule Core.Kafka.Consumer do
  @moduledoc false

  alias Core.Requests.VisitCreateRequest

  def consume(%VisitCreateRequest{} = request) do
    IO.inspect(request)
    System.halt()
  end
end
