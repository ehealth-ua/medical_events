defmodule Core.Kafka.Consumer.ResendApprovalTest do
  @moduledoc false

  use Core.ModelCase

  alias Core.Approval
  alias Core.Job
  alias Core.Jobs.ApprovalResendJob
  alias Core.Kafka.Consumer
  alias Core.Patients

  import Mox
  import Core.Expectations.MPIExpectations
  import Core.Expectations.OTPVerificationExpectations

  setup :verify_on_exit!

  describe "consume resend approval event" do
    test "success approval resend" do
      stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      user_id = UUID.uuid4()
      client_id = UUID.uuid4()
      patient_id = UUID.uuid4()
      patient_id_hash = Patients.get_pk_hash(patient_id)

      insert(:patient, _id: patient_id_hash)

      approval = insert(:approval, patient_id: patient_id_hash)
      approval_id = to_string(approval._id)

      expect_person(patient_id)
      expect_otp_verification_initialize()

      job = insert(:job)

      expect_job_update(job._id, %{"response_data" => ""}, 200)

      assert :ok =
               Consumer.consume(%ApprovalResendJob{
                 _id: to_string(job._id),
                 patient_id: patient_id,
                 patient_id_hash: patient_id_hash,
                 id: approval_id,
                 user_id: user_id,
                 client_id: client_id
               })
    end
  end

  test "success approval resend when person's auth method is not OTP" do
    stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

    user_id = UUID.uuid4()
    client_id = UUID.uuid4()
    patient_id = UUID.uuid4()
    patient_id_hash = Patients.get_pk_hash(patient_id)

    insert(:patient, _id: patient_id_hash)

    approval = insert(:approval, patient_id: patient_id_hash)
    approval_id = to_string(approval._id)

    expect_person_offline_auth_method(patient_id)

    job = insert(:job)

    expect_job_update(job._id, %{"response_data" => ""}, 200)

    assert :ok =
             Consumer.consume(%ApprovalResendJob{
               _id: to_string(job._id),
               patient_id: patient_id,
               patient_id_hash: patient_id_hash,
               id: approval_id,
               user_id: user_id,
               client_id: client_id
             })
  end

  test "failed when approval status is not NEW" do
    stub(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

    user_id = UUID.uuid4()
    client_id = UUID.uuid4()
    patient_id = UUID.uuid4()
    patient_id_hash = Patients.get_pk_hash(patient_id)

    insert(:patient, _id: patient_id_hash)

    approval = insert(:approval, patient_id: patient_id_hash, status: Approval.status(:active))
    approval_id = to_string(approval._id)

    job = insert(:job)

    expect_job_update(job._id, Job.status(:failed), "Approval in status active can not be resent", 409)

    assert :ok =
             Consumer.consume(%ApprovalResendJob{
               _id: to_string(job._id),
               patient_id: patient_id,
               patient_id_hash: patient_id_hash,
               id: approval_id,
               user_id: user_id,
               client_id: client_id
             })
  end
end
