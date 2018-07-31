defmodule ApiWeb.Router do
  @moduledoc false

  use ApiWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", ApiWeb do
    pipe_through(:api)

    post("visits", VisitController, :create)
  end
end
