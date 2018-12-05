defmodule Api.Web.FallbackController do
  @moduledoc false

  use ApiWeb, :controller

  alias Api.Web.JobController
  alias EView.Views.Error
  alias EView.Views.ValidationError

  def call(conn, {:job_exists, job_id}) do
    JobController.show(conn, %{"id" => job_id})
  end

  def call(conn, {:error, {:access_denied, reason}}) do
    conn
    |> put_status(:forbidden)
    |> render(Error, :"403", %{message: reason})
  end

  def call(conn, {:error, errors}) when is_list(errors) do
    conn
    |> put_status(422)
    |> render(ValidationError, "422.json", %{schema: errors})
  end

  def call(conn, nil) do
    conn
    |> put_status(:not_found)
    |> render(Error, :"404")
  end

  def call(conn, {:error, {:not_found, message}}) do
    conn
    |> put_status(:not_found)
    |> render(Error, :"404", %{message: message})
  end

  def call(conn, {:error, {:conflict, reason}}) when is_binary(reason) do
    call(conn, {:error, {:conflict, %{message: reason}}})
  end

  def call(conn, {:error, {:conflict, reason}}) when is_map(reason) do
    conn
    |> put_status(:conflict)
    |> render(Error, :"409", reason)
  end

  def call(conn, {:error, {:not_implemented, reason}}) when is_binary(reason) do
    conn
    |> put_status(:not_implemented)
    |> render(Error, :"501", reason)
  end

  def call(conn, {:error, {:"422", error}}) do
    conn
    |> put_status(422)
    |> render(Error, :"400", %{message: error})
  end
end
