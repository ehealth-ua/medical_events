defmodule Core.Approvals.Consumer do
  @moduledoc false

  alias Core.Approval
  alias Core.Approvals
  alias Core.Approvals.Renderer, as: ApprovalsRenderer
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.ApprovalCreateJob
  alias Core.Jobs.ApprovalResendJob
  alias Core.Mongo.Transaction
  alias Core.ServiceRequest
  alias Core.ServiceRequests
  alias Core.Validators.DateTime, as: DateTimeValidations
  alias Core.Validators.Error
  alias Ecto.Changeset
  alias EView.Views.ValidationError
  require Logger

  @collection Approval.collection()

  @status_new Approval.status(:new)
  @service_request_status_active ServiceRequest.status(:active)
  @otp_verification_api Application.get_env(:core, :microservices)[:otp_verification]

  def consume_create_approval(
        %ApprovalCreateJob{
          patient_id: patient_id,
          patient_id_hash: patient_id_hash,
          resources: resources,
          access_level: access_level,
          user_id: user_id,
          client_id: client_id
        } = job
      ) do
    with {:ok, granted_resources} <-
           get_granted_resources(resources, job.service_request),
         {:ok, auth_method} <- Approvals.get_person_auth_method(patient_id) do
      now = DateTime.utc_now()
      approval_expiration_minutes = Confex.fetch_env!(:core, :approval)[:expire_in_minutes]

      params =
        job
        |> Map.from_struct()
        |> Map.drop(~w(resources service_request)a)
        |> Map.merge(%{
          _id: UUID.uuid4(),
          reason: job.service_request,
          patient_id: patient_id_hash,
          expires_at: DateTime.from_unix!(DateTime.to_unix(now) + approval_expiration_minutes * 60),
          status: @status_new,
          access_level: access_level,
          urgent: hide_number(auth_method),
          inserted_by: user_id,
          updated_by: user_id,
          inserted_at: now,
          updated_at: now,
          granted_resources: granted_resources,
          granted_by: %{
            "identifier" => %{
              "type" => %{
                "coding" => [
                  %{
                    "system" => "eHealth/resources",
                    "code" => "mpi-hash"
                  }
                ]
              },
              "value" => patient_id_hash
            }
          }
        })

      changeset = Approval.create_changeset(%Approval{}, params, patient_id_hash, user_id, client_id)

      case changeset do
        %Changeset{valid?: false} ->
          Jobs.produce_update_status(
            job._id,
            job.request_id,
            ValidationError.render("422.json", changeset),
            422
          )

        _ ->
          approval = Changeset.apply_changes(changeset)

          case Approvals.get_by_id(approval._id) do
            {:ok, _} ->
              {:error, "Approval with id '#{approval._id}' already exists", 409}

            _ ->
              with :ok <- initialize_otp_verification(auth_method) do
                result =
                  %Transaction{actor_id: user_id}
                  |> Transaction.add_operation(@collection, :insert, approval, approval._id)
                  |> Jobs.update(
                    job._id,
                    Job.status(:processed),
                    %{"response_data" => ApprovalsRenderer.render(approval)},
                    200
                  )
                  |> Transaction.flush()

                case result do
                  :ok ->
                    :ok

                  {:error, reason} ->
                    Jobs.produce_update_status(job._id, job.request_id, reason, 500)
                end
              else
                error ->
                  Logger.error("Failed to initialize otp verification: #{inspect(error)}")

                  Jobs.produce_update_status(
                    job._id,
                    job.request_id,
                    "Failed to initialize otp verification",
                    500
                  )
              end
          end
      end
    else
      {:error, error} ->
        Jobs.produce_update_status(
          job._id,
          job.request_id,
          ValidationError.render("422.json", %{schema: error}),
          422
        )

      {_, response, status_code} ->
        Jobs.produce_update_status(job._id, job.request_id, response, status_code)
    end
  end

  def consume_resend_approval(
        %ApprovalResendJob{
          patient_id: patient_id,
          id: id
        } = job
      ) do
    with {:ok, %Approval{status: @status_new}} <- Approvals.get_by_id(id),
         {:ok, auth_method} <- Approvals.get_person_auth_method(patient_id),
         :ok <- initialize_otp_verification(auth_method) do
      Jobs.produce_update_status(job._id, job.request_id, %{"response_data" => ""}, 200)
    else
      nil ->
        Jobs.produce_update_status(
          job._id,
          job.request_id,
          "Approval with id '#{id}' is not found",
          404
        )

      {:ok, %Approval{status: status}} ->
        Jobs.produce_update_status(
          job._id,
          job.request_id,
          "Approval in status #{status} can not be resent",
          409
        )

      {_, response, status_code} ->
        Jobs.produce_update_status(job._id, job.request_id, response, status_code)

      error ->
        Logger.error("Failed to initialize otp verification: #{inspect(error)}")

        Jobs.produce_update_status(
          job._id,
          job.request_id,
          "Failed to initialize otp verification",
          500
        )
    end
  end

  defp get_granted_resources(resources, nil), do: {:ok, resources}

  defp get_granted_resources(nil, %{"identifier" => %{"value" => service_request_id}}) do
    with {:ok, %ServiceRequest{status: @service_request_status_active} = service_request} <-
           ServiceRequests.get_by_id(service_request_id),
         {:ok, _} <-
           {DateTimeValidations.validate(service_request.expiration_date,
              greater_than_or_equal_to: DateTime.utc_now(),
              message: "Service request is expired"
            ), :expiration_date} do
      case service_request.permitted_resources do
        [] ->
          {:error, "Service request does not contain resources references", 409}

        permitted_resources ->
          {:ok,
           Enum.map(permitted_resources, fn permitted_resource ->
             identifier = permitted_resource.identifier

             %{
               display_value: permitted_resource.display_value,
               identifier: %{
                 type: %{
                   coding: Enum.map(identifier.type.coding, &Map.from_struct/1),
                   text: identifier.type.text
                 },
                 value: identifier.value
               }
             }
           end)}
      end
    else
      {:ok, %ServiceRequest{} = _} ->
        {:error, "Service request should be active", 409}

      nil ->
        {:error, "Service request is not found", 409}

      {{:error, message}, :expiration_date} ->
        Error.dump(%Core.ValidationError{
          description: message,
          path: "$.service_request"
        })
    end
  end

  defp hide_number(%{
         "type" => "OTP",
         "phone_number" => <<code::bytes-size(6), _hidden::bytes-size(5), last_digits::bytes-size(2)>>
       }) do
    %{"type" => "OTP", "phone_number" => "#{code}*****#{last_digits}"}
  end

  defp hide_number(auth_method), do: auth_method

  defp initialize_otp_verification(%{"type" => "OTP", "phone_number" => phone_number}) do
    case @otp_verification_api.initialize(phone_number, []) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  defp initialize_otp_verification(_), do: :ok
end
