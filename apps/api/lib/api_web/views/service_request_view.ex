defmodule Api.Web.ServiceRequestView do
  @moduledoc false

  use ApiWeb, :view

  import Core.ServiceRequestView, only: [render_service_request: 1]

  def render("index.json", %{service_requests: service_requests}) do
    render_many(service_requests, __MODULE__, "show.json", as: :service_request)
  end

  def render("show.json", %{service_request: service_request}) do
    render_service_request(service_request)
  end
end
