defmodule Core.Kafka.Consumer.CreatePackageTest do
  @moduledoc false

  use Core.ModelCase

  alias Core.Kafka.Consumer
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.PackageCreateJob
  import Mox
  import Core.Expectations.DigitalSignature

  @status_processed Job.status(:processed)

  describe "consume create visit event" do
    test "empty content" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      job = insert(:job)
      signature()

      assert :ok =
               Consumer.consume(%PackageCreateJob{
                 _id: job._id,
                 visit: %{"id" => UUID.uuid4(), "period" => %{}},
                 signed_data: Base.encode64("")
               })

      assert {:ok, %Job{status: @status_processed, response_size: 395}} = Jobs.get_by_id(job._id)
    end

    test "empty map" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      job = insert(:job)
      signature()

      assert :ok =
               Consumer.consume(%PackageCreateJob{
                 _id: job._id,
                 visit: %{"id" => UUID.uuid4(), "period" => %{}},
                 signed_data: Base.encode64(Jason.encode!(%{}))
               })

      assert {:ok, %Job{status: @status_processed, response_size: 397}} = Jobs.get_by_id(job._id)
    end

    # TODO: not completed
    test "success create visit" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      expect(IlMock, :get_dictionaries, fn _, _ ->
        {:ok, %{"data" => %{}}}
      end)

      client_id = UUID.uuid4()

      expect(IlMock, :get_employee, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "APPROVED",
             "employee_type" => "DOCTOR",
             "legal_entity" => %{"id" => client_id}
           }
         }}
      end)

      expect(IlMock, :get_division, fn id, _ ->
        {:ok,
         %{
           "data" => %{
             "id" => id,
             "status" => "active",
             "legal_entity_id" => client_id
           }
         }}
      end)

      encounter_id = UUID.uuid4()

      patient = insert(:patient)
      condition = insert(:condition, patient_id: patient._id, inserted_by: patient._id, updated_by: patient._id)
      job = insert(:job)
      signature()
      visit_id = UUID.uuid4()
      episode_id = patient.episodes |> Map.keys() |> hd

      signed_content = %{
        "encounter" => %{
          "id" => encounter_id,
          "status" => "finished",
          "contexts" => [
            %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "visit", "system" => "eHealth/resources"}]},
                "value" => visit_id
              }
            },
            %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "episode", "system" => "eHealth/resources"}]},
                "value" => episode_id
              }
            }
          ],
          "class" => %{"code" => "AMB", "system" => "eHealth/encounter_classes"},
          "type" => %{"coding" => [%{"code" => "AMB", "system" => "eHealth/encounter_types"}]},
          "reasons" => [
            %{"coding" => [%{"code" => "reason", "system" => "eHealth/ICPC2/reasons"}]}
          ],
          "diagnoses" => [
            %{
              "condition" => %{
                "identifier" => %{
                  "type" => %{"coding" => [%{"code" => "condition", "system" => "eHealth/resources"}]},
                  "value" => condition._id
                }
              },
              "role" => %{"coding" => [%{"code" => "chief_complaint", "system" => "eHealth/diagnoses_roles"}]},
              "code" => %{"coding" => [%{"code" => "code", "system" => "eHealth/ICD10/conditions"}]}
            }
          ],
          "actions" => [%{"coding" => [%{"code" => "action", "system" => "eHealth/actions"}]}],
          "division" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "division", "system" => "eHealth/resources"}]},
              "value" => UUID.uuid4()
            }
          },
          "performer" => %{
            "identifier" => %{
              "type" => %{"coding" => [%{"code" => "employee", "system" => "eHealth/resources"}]},
              "value" => UUID.uuid4()
            }
          }
        },
        "conditions" => [
          %{
            "id" => UUID.uuid4(),
            "context" => %{
              "identifier" => %{
                "type" => %{"coding" => [%{"code" => "encounter", "system" => "eHealth/resources"}]},
                "value" => encounter_id
              }
            },
            "code" => %{"coding" => [%{"code" => "legal_entity", "system" => "eHealth/ICPC2/conditions"}]},
            "clinical_status" => "test",
            "verification_status" => "test",
            "onset_date" => Date.to_iso8601(Date.utc_today()),
            "severity" => %{"coding" => [%{"code" => "55604002", "system" => "eHealth/severity"}]},
            "body_sites" => [%{"coding" => [%{"code" => "181414000", "system" => "eHealth/body_sites"}]}],
            "stage" => %{
              "summary" => %{"coding" => [%{"code" => "181414000", "system" => "eHealth/condition_stages"}]}
            },
            "evidences" => [
              %{
                "codes" => [%{"coding" => [%{"code" => "condition", "system" => "eHealth/ICD10/conditions"}]}],
                "details" => [
                  %{
                    "identifier" => %{
                      "type" => %{"coding" => [%{"code" => "observation", "system" => "eHealth/resources"}]},
                      "value" => UUID.uuid4()
                    }
                  }
                ]
              }
            ]
          }
        ]
      }

      user_id = UUID.uuid4()

      assert :ok =
               Consumer.consume(%PackageCreateJob{
                 _id: job._id,
                 visit: %{"id" => visit_id, "period" => %{"start" => DateTime.utc_now(), "end" => DateTime.utc_now()}},
                 patient_id: patient._id,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: Base.encode64(Jason.encode!(signed_content))
               })

      assert {:ok,
              %Core.Job{
                response_size: 273,
                status: @status_processed
              }} = Jobs.get_by_id(job._id)
    end
  end
end
