defmodule Api.Web.JobControllerTest do
  @moduledoc false

  use ApiWeb.ConnCase
  alias Core.Job

  setup %{conn: conn} do
    {:ok, conn: put_consumer_id_header(conn)}
  end

  describe "get job by id" do
    test "status: pending", %{conn: conn} do
      job = insert(:job, status: Job.status(:pending))

      response =
        conn
        |> get(job_path(conn, :show, job._id))
        |> json_response(200)
        |> Map.get("data")
        |> assert_json_schema("jobs/job_details.json")

      assert Job.status_to_string(job.status) == response["status"]
      assert [] == response["links"]
      assert Map.has_key?(response, "eta")
    end

    test "status: processed", %{conn: conn} do
      job_response = %{
        "links" => [
          %{
            "entity" => "visit",
            "href" => "/visits/90a9e15b-b71b-4caf-8f2e-ff247e8a5600"
          },
          %{
            "entity" => "encounter",
            "href" => "/encounters/90a9e15b-b71b-4caf-8f2e-ff247e8a5600"
          }
        ]
      }

      job =
        insert(:job,
          status: Job.status(:processed),
          status_code: 203,
          response: job_response
        )

      response =
        conn
        |> get(job_path(conn, :show, job._id))
        |> json_response(203)
        |> Map.get("data")
        |> assert_json_schema("jobs/job_details.json")

      assert Job.status_to_string(job.status) == response["status"]
      assert Map.has_key?(response, "eta")
      assert Map.has_key?(response, "links")
      assert is_list(response["links"])
    end

    test "status: processed with failed validation", %{conn: conn} do
      job =
        insert(:job,
          status: Job.status(:processed),
          status_code: 422,
          response: [%{"type" => "invalid"}]
        )

      response =
        conn
        |> get(job_path(conn, :show, job._id))
        |> json_response(200)
        |> Map.get("data")
        |> assert_json_schema("jobs/job_details_error.json")

      assert Job.status_to_string(job.status) == response["status"]
      assert 422 == response["status_code"]
      assert Map.has_key?(response, "eta")
      assert Map.has_key?(response, "errors")
    end

    test "status: failed", %{conn: conn} do
      job =
        insert(:job,
          status: Job.status(:failed),
          status_code: 404,
          response: "Can't get request by id bd33b561-2616-4268-898d-4fc4e07e3481"
        )

      response =
        conn
        |> get(job_path(conn, :show, job._id))
        |> json_response(200)
        |> Map.get("data")
        |> assert_json_schema("jobs/job_details_error.json")

      assert Job.status_to_string(job.status) == response["status"]
      assert 404 == response["status_code"]
      assert Map.has_key?(response, "eta")
      assert Map.has_key?(response, "errors")
    end

    test "not found", %{conn: conn} do
      conn
      |> get(job_path(conn, :show, "b489367b-182e-492f-80c5-caa71ba8e8c4"))
      |> json_response(404)
    end
  end
end
