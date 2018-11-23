defmodule Core.Kafka.Consumer.CreateServiceRequestTest do
  @moduledoc false

  use Core.ModelCase

  import Core.Expectations.DigitalSignatureExpectation
  import Core.Expectations.IlExpectations
  import Mox

  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.ServiceRequestCreateJob
  alias Core.Kafka.Consumer
  alias Core.Patients
  alias Core.ServiceRequest

  @status_processed Job.status(:processed)

  describe "consume create service_request event" do
    test "empty content" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      job = insert(:job)
      user_id = prepare_signature_expectations()

      assert :ok =
               Consumer.consume(%ServiceRequestCreateJob{
                 _id: to_string(job._id),
                 signed_data: Base.encode64(""),
                 user_id: user_id,
                 client_id: UUID.uuid4()
               })

      assert {:ok, %Job{status: @status_processed, response_size: 361}} = Jobs.get_by_id(to_string(job._id))
    end

    test "empty map" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      job = insert(:job)
      user_id = prepare_signature_expectations()

      assert :ok =
               Consumer.consume(%ServiceRequestCreateJob{
                 _id: to_string(job._id),
                 signed_data: Base.encode64(Jason.encode!(%{})),
                 user_id: user_id,
                 client_id: UUID.uuid4()
               })

      assert {:ok, %Job{status: @status_processed, response_size: 1131}} = Jobs.get_by_id(to_string(job._id))
    end

    test "success create service_request" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(MediaStorageMock, :save, fn _, _, _, _ -> :ok end)
      client_id = UUID.uuid4()
      user_id = prepare_signature_expectations()
      job = insert(:job)

      service_request_id = UUID.uuid4()
      employee_id = UUID.uuid4()

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      patient = insert(:patient, _id: patient_id_hash)
      encounter_id = patient.encounters |> Map.keys() |> hd()
      episode_id = patient.episodes |> Map.keys() |> hd()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 2, fn
        _, _, :employees_by_user_id_client_id, _ -> [employee_id]
        _, _, :tax_id_by_employee_id, _ -> "1111111111"
      end)

      signed_content = %{
        "id" => service_request_id,
        "requisition" => "AX654654T",
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "409063005", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{"coding" => [%{"code" => "128004", "system" => "eHealth/SNOMED/procedure_codes"}]},
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "performer_type" => %{
          "coding" => [%{"code" => "psychiatrist", "system" => "eHealth/SNOMED/service_request_performer_roles"}]
        },
        "supporting_info" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          }
        ],
        "permitted_episodes" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          }
        ]
      }

      assert :ok =
               Consumer.consume(%ServiceRequestCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })

      assert {:ok,
              %Core.Job{
                response_size: 154,
                status: @status_processed
              }} = Jobs.get_by_id(to_string(job._id))
    end

    test "fail on invalid drfo" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      expect(MediaStorageMock, :save, fn _, _, _, _ -> :ok end)
      client_id = UUID.uuid4()
      user_id = prepare_signature_expectations()
      job = insert(:job)

      service_request_id = UUID.uuid4()
      employee_id = UUID.uuid4()

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)
      patient = insert(:patient, _id: patient_id_hash)
      encounter_id = patient.encounters |> Map.keys() |> hd()
      episode_id = patient.episodes |> Map.keys() |> hd()

      authored_on = DateTime.to_iso8601(DateTime.utc_now())

      expect(WorkerMock, :run, 2, fn
        _, _, :employees_by_user_id_client_id, _ -> [employee_id]
        _, _, :tax_id_by_employee_id, _ -> "1111111112"
      end)

      signed_content = %{
        "id" => service_request_id,
        "requisition" => "AX654654T",
        "status" => ServiceRequest.status(:active),
        "intent" => ServiceRequest.intent(:order),
        "category" => %{
          "coding" => [%{"code" => "409063005", "system" => "eHealth/SNOMED/service_request_categories"}]
        },
        "code" => %{"coding" => [%{"code" => "128004", "system" => "eHealth/SNOMED/procedure_codes"}]},
        "context" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
            "value" => encounter_id
          }
        },
        "authored_on" => authored_on,
        "requester" => %{
          "identifier" => %{
            "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
            "value" => employee_id
          }
        },
        "performer_type" => %{
          "coding" => [%{"code" => "psychiatrist", "system" => "eHealth/SNOMED/service_request_performer_roles"}]
        },
        "supporting_info" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          }
        ],
        "permitted_episodes" => [
          %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "episode_of_care", "system" => "eHealth/resources"}]},
              "value" => episode_id
            }
          }
        ]
      }

      assert :ok =
               Consumer.consume(%ServiceRequestCreateJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })

      assert {:ok,
              %Core.Job{
                response_size: 401,
                status: @status_processed
              }} = Jobs.get_by_id(to_string(job._id))
    end
  end

  defp prepare_signature_expectations do
    user_id = UUID.uuid4()
    drfo = "1111111111"
    expect_signature(drfo)
    expect_employee_users(drfo, user_id)

    user_id
  end
end
