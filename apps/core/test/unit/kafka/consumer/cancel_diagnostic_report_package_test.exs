defmodule Core.Kafka.Consumer.CancelDiagnosticReportPackageTest do
  @moduledoc false

  use Core.ModelCase

  import Mox
  import Core.Expectations.DigitalSignatureExpectation
  import Core.Expectations.IlExpectations
  import Core.TestViews.CancelDiagnosticReportPackageView

  alias Core.Job
  alias Core.Jobs.DiagnosticReportPackageCancelJob
  alias Core.Kafka.Consumer
  alias Core.Patients

  @entered_in_error "entered_in_error"

  setup :verify_on_exit!

  describe "consume cancel package event" do
    test "success" do
      expect(MediaStorageMock, :save, fn _, _, _, _ -> :ok end)
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      client_id = UUID.uuid4()

      user_id = prepare_signature_expectations()

      job = insert(:job)

      diagnostic_report = build(:diagnostic_report)
      diagnostic_report_id = UUID.binary_to_string!(diagnostic_report.id.binary)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        diagnostic_reports: %{
          diagnostic_report_id => diagnostic_report
        }
      )

      observation =
        insert(:observation,
          patient_id: patient_id_hash,
          diagnostic_report:
            build(:reference,
              identifier:
                build(:identifier,
                  value: Mongo.string_to_uuid(diagnostic_report_id),
                  type: codeable_concept_coding(code: "diagnostic_report")
                )
            )
        )

      signed_data =
        %{
          "observations" => render(:observations, [%{observation | status: @entered_in_error}]),
          "diagnostic_report" => render(:diagnostic_report, %{diagnostic_report | status: @entered_in_error})
        }
        |> Jason.encode!()
        |> Base.encode64()

      expect(WorkerMock, :run, fn _, _, :transaction, args ->
        assert %{
                 "actor_id" => _,
                 "operations" => [
                   %{"collection" => "patients", "operation" => "update_one", "set" => patient_set},
                   %{"collection" => "observations", "operation" => "update_one", "filter" => observation_filter},
                   %{"collection" => "jobs", "operation" => "update_one", "filter" => filter, "set" => set}
                 ]
               } = Jason.decode!(args)

        patient_set =
          patient_set
          |> Base.decode64!()
          |> BSON.decode()

        diagnostic_reports_status = "diagnostic_reports.#{diagnostic_report_id}.status"
        diagnostic_reports_explanatory_letter = "diagnostic_reports.#{diagnostic_report_id}.explanatory_letter"
        diagnostic_reports_cancellation_reason = "diagnostic_reports.#{diagnostic_report_id}.cancellation_reason"

        assert %{
                 "$set" => %{
                   ^diagnostic_reports_status => @entered_in_error,
                   ^diagnostic_reports_cancellation_reason => %{
                     "coding" => [%{"system" => "eHealth/cancellation_reasons", "code" => "misspelling"}]
                   },
                   ^diagnostic_reports_explanatory_letter => "some explanations"
                 }
               } = patient_set

        assert %{"_id" => observation._id} == observation_filter |> Base.decode64!() |> BSON.decode()
        assert %{"_id" => job._id} == filter |> Base.decode64!() |> BSON.decode()

        set_bson = set |> Base.decode64!() |> BSON.decode()

        status = Job.status(:processed)

        assert %{
                 "$set" => %{
                   "status" => ^status,
                   "status_code" => 200,
                   "response" => %{}
                 }
               } = set_bson

        :ok
      end)

      assert :ok =
               Consumer.consume(%DiagnosticReportPackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_data
               })
    end

    test "failed when no entities with entered_in_error status" do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      client_id = UUID.uuid4()

      user_id = prepare_signature_expectations()

      job = insert(:job)

      diagnostic_report = build(:diagnostic_report)
      diagnostic_report_id = UUID.binary_to_string!(diagnostic_report.id.binary)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        diagnostic_reports: %{
          diagnostic_report_id => diagnostic_report
        }
      )

      observation =
        insert(:observation,
          patient_id: patient_id_hash,
          diagnostic_report:
            build(:reference,
              identifier:
                build(:identifier,
                  value: Mongo.string_to_uuid(diagnostic_report_id),
                  type: codeable_concept_coding(code: "diagnostic_report")
                )
            )
        )

      signed_data =
        %{
          "observations" => render(:observations, [observation]),
          "diagnostic_report" => render(:diagnostic_report, diagnostic_report)
        }
        |> Jason.encode!()
        |> Base.encode64()

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{"error" => ~s(At least one entity should have status "entered_in_error")},
        409
      )

      assert :ok =
               Consumer.consume(%DiagnosticReportPackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_data
               })
    end

    test "faild when entity has alraady entered_in_error status" do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      client_id = UUID.uuid4()

      user_id = prepare_signature_expectations()

      job = insert(:job)

      diagnostic_report = build(:diagnostic_report, status: @entered_in_error)
      diagnostic_report_id = UUID.binary_to_string!(diagnostic_report.id.binary)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        diagnostic_reports: %{
          diagnostic_report_id => diagnostic_report
        }
      )

      signed_data =
        %{
          "diagnostic_report" => render(:diagnostic_report, diagnostic_report)
        }
        |> Jason.encode!()
        |> Base.encode64()

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{"error" => "Invalid transition for diagnostic_report - already entered_in_error"},
        409
      )

      assert :ok =
               Consumer.consume(%DiagnosticReportPackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_data
               })
    end

    test "fail on signed content" do
      expect(KafkaMock, :publish_mongo_event, 2, fn _event -> :ok end)

      client_id = UUID.uuid4()

      user_id = prepare_signature_expectations()

      job = insert(:job)

      diagnostic_report = build(:diagnostic_report)
      diagnostic_report_id = UUID.binary_to_string!(diagnostic_report.id.binary)

      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(
        :patient,
        _id: patient_id_hash,
        diagnostic_reports: %{
          diagnostic_report_id => diagnostic_report
        }
      )

      observation =
        insert(:observation,
          patient_id: patient_id_hash,
          diagnostic_report:
            build(:reference,
              identifier:
                build(:identifier,
                  value: Mongo.string_to_uuid(diagnostic_report_id),
                  type: codeable_concept_coding(code: "diagnostic_report")
                )
            )
        )

      signed_data =
        %{
          "observations" =>
            render(:observations, [%{observation | status: @entered_in_error, comment: "different comment"}]),
          "diagnostic_report" => render(:diagnostic_report, %{diagnostic_report | status: @entered_in_error})
        }
        |> Jason.encode!()
        |> Base.encode64()

      expect_job_update(
        job._id,
        Job.status(:failed),
        %{
          "error" =>
            "Submitted signed content does not correspond to previously created content: observations.0.comment"
        },
        409
      )

      assert :ok =
               Consumer.consume(%DiagnosticReportPackageCancelJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 user_id: user_id,
                 client_id: client_id,
                 signed_data: signed_data
               })
    end
  end

  defp prepare_signature_expectations(expect_employee_users \\ true)

  defp prepare_signature_expectations(true) do
    user_id = UUID.uuid4()
    drfo = "1111111111"
    expect_signature(drfo)
    expect_employee_users(drfo, user_id)

    user_id
  end

  defp prepare_signature_expectations(false) do
    user_id = UUID.uuid4()
    drfo = "1111111111"
    expect_signature(drfo)

    user_id
  end
end
