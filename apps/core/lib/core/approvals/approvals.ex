defmodule Core.Approvals do
  @moduledoc false

  alias Core.Approval
  alias Core.Approvals.Renderer, as: ApprovalsRenderer
  alias Core.Approvals.Validations, as: ApprovalsValidations
  alias Core.Jobs
  alias Core.Jobs.ApprovalCreateJob
  alias Core.Jobs.ApprovalResendJob
  alias Core.Mongo
  alias Core.Patients
  alias Core.Patients.Validators
  alias Core.Reference
  alias Core.ServiceRequest
  alias Core.ServiceRequests
  alias Core.Validators.Error
  alias Core.Validators.JsonSchema
  alias Core.Validators.Vex
  alias EView.Views.ValidationError
  require Logger

  @collection Approval.metadata().collection

  @worker Application.get_env(:core, :rpc_worker)

  @create_request_params ~w(
    resources
    service_request
    granted_to
    access_level
  )

  @status_new Approval.status(:new)
  @status_active Approval.status(:active)
  @service_request_status_active ServiceRequest.status(:active)

  @kafka_producer Application.get_env(:core, :kafka)[:producer]
  @otp_verification_api Application.get_env(:core, :microservices)[:otp_verification]

  def produce_create_approval(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:approval_create, Map.take(params, @create_request_params)),
         {:ok, job, approval_create_job} <-
           Jobs.create(
             ApprovalCreateJob,
             Map.merge(params, %{
               "user_id" => user_id,
               "client_id" => client_id,
               "salt" => DateTime.utc_now()
             })
           ),
         :ok <- @kafka_producer.publish_medical_event(approval_create_job) do
      {:ok, job}
    end
  end

  def produce_resend_approval(%{"patient_id_hash" => patient_id_hash, "id" => id} = params, user_id, client_id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, %Approval{}} <- get_by_id(id),
         {:ok, job, approval_resend_job} <-
           Jobs.create(
             ApprovalResendJob,
             Map.merge(params, %{"user_id" => user_id, "client_id" => client_id})
           ),
         :ok <- @kafka_producer.publish_medical_event(approval_resend_job) do
      {:ok, job}
    end
  end

  def consume_create_approval(
        %ApprovalCreateJob{
          patient_id: patient_id,
          patient_id_hash: patient_id_hash,
          resources: resources,
          service_request: service_request,
          access_level: access_level,
          user_id: user_id,
          client_id: client_id
        } = job
      ) do
    with {:ok, episodes} <- get_episodes(resources, service_request),
         {:ok, auth_method} <- get_person_auth_method(patient_id) do
      now = DateTime.utc_now()
      approval_expiration_minutes = Confex.fetch_env!(:core, :approval)[:expire_in_minutes]

      params =
        job
        |> Map.from_struct()
        |> Map.drop(~w(resources service_request)a)
        |> Map.merge(%{
          id: UUID.uuid4(),
          reason: service_request,
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
        |> Enum.map(fn {k, v} -> {to_string(k), v} end)

      approval =
        params
        |> Approval.create()
        |> Map.merge(%{
          granted_resources: episodes,
          patient_id: patient_id_hash,
          expires_at: DateTime.to_unix(now) + approval_expiration_minutes * 60,
          status: @status_new,
          access_level: access_level,
          urgent: hide_number(auth_method),
          inserted_by: user_id,
          updated_by: user_id,
          inserted_at: now,
          updated_at: now
        })
        |> ApprovalsValidations.validate_granted_to(user_id, client_id)
        |> ApprovalsValidations.validate_granted_resources(patient_id_hash)

      case Vex.errors(approval) do
        [] ->
          if Mongo.find_one(
               @collection,
               %{"_id" => Mongo.string_to_uuid(approval._id)},
               projection: %{"_id" => true}
             ) do
            {:error, "Approval with id '#{approval._id}' already exists", 409}
          else
            with :ok <- initialize_otp_verification(auth_method) do
              doc =
                approval
                |> Mongo.prepare_doc()
                |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
                |> Mongo.convert_to_uuid("_id")
                |> Mongo.convert_to_uuid("inserted_by")
                |> Mongo.convert_to_uuid("updated_by")
                |> Mongo.convert_to_uuid("granted_resources", ~w(identifier value)a)
                |> Mongo.convert_to_uuid("granted_to", ~w(identifier value)a)
                |> Mongo.convert_to_uuid("reason", ~w(identifier value)a)

              {:ok, %{inserted_id: _}} = Mongo.insert_one(@collection, doc, [])

              Jobs.produce_update_status(
                job._id,
                job.request_id,
                %{"response_data" => ApprovalsRenderer.render(approval)},
                200
              )
            else
              error ->
                Logger.error("Failed to initialize otp verification: #{inspect(error)}")
                Jobs.produce_update_status(job._id, job.request_id, "Failed to initialize otp verification", 500)
            end
          end

        errors ->
          Jobs.produce_update_status(
            job._id,
            job.request_id,
            ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}),
            422
          )
      end
    else
      {:error, error} ->
        Jobs.produce_update_status(job._id, job.request_id, ValidationError.render("422.json", %{schema: error}), 422)

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
    with {:ok, %Approval{status: @status_new}} <- get_by_id(id),
         {:ok, auth_method} <- get_person_auth_method(patient_id),
         :ok <- initialize_otp_verification(auth_method) do
      Jobs.produce_update_status(job._id, job.request_id, "", 200)
    else
      nil ->
        Jobs.produce_update_status(job._id, job.request_id, "Approval with id '#{id}' is not found", 404)

      {:ok, %Approval{status: status}} ->
        Jobs.produce_update_status(job._id, job.request_id, "Approval in status #{status} can not be resent", 409)

      {_, response, status_code} ->
        Jobs.produce_update_status(job._id, job.request_id, response, status_code)

      error ->
        Logger.error("Failed to initialize otp verification: #{inspect(error)}")
        Jobs.produce_update_status(job._id, job.request_id, "Failed to initialize otp verification", 500)
    end
  end

  def verify(%{"patient_id_hash" => patient_id_hash, "patient_id" => patient_id, "id" => id} = params, user_id) do
    code = Map.get(params, "code")

    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, %Approval{status: @status_new} = approval} <- get_by_id(id),
         :ok <- ApprovalsValidations.validate_patient(approval, patient_id_hash),
         {:ok, auth_method} <- get_person_auth_method(patient_id),
         :ok <- verify_auth(auth_method, code) do
      set =
        %{"status" => @status_active, "updated_by" => user_id, "updated_at" => DateTime.utc_now()}
        |> Mongo.convert_to_uuid("updated_by")

      {:ok, %{matched_count: 1, modified_count: 1}} =
        Mongo.update_one(@collection, %{"_id" => approval._id}, %{"$set" => set})

      get_by_id(UUID.binary_to_string!(approval._id.binary))
    else
      {:ok, %Approval{status: status}} -> {:error, {:conflict, "Approval in status #{status} can not be verified"}}
      err -> err
    end
  end

  def get_by_id(id) do
    @collection
    |> Mongo.find_one(%{"_id" => Mongo.string_to_uuid(id)})
    |> case do
      %{} = approval -> {:ok, Approval.create(approval)}
      _ -> nil
    end
  end

  def get_by_patient_id_granted_to_episode_id(patient_id, employee_ids, episode_id) do
    @collection
    |> Mongo.find(%{
      "patient_id" => Patients.get_pk_hash(patient_id),
      "granted_to.identifier.value" => %{"$in" => Enum.map(employee_ids, &Mongo.string_to_uuid/1)},
      "granted_resources" => %{
        "$elemMatch" => %{
          "identifier.type.coding.code" => "episode_of_care",
          "identifier.value" => Mongo.string_to_uuid(episode_id)
        }
      }
    })
    |> Enum.map(&Approval.create/1)
  end

  defp get_episodes(resources, nil), do: {:ok, Enum.map(resources, &Reference.create/1)}

  defp get_episodes(nil, %{"identifier" => %{"value" => service_request_id}}) do
    with {:ok, %ServiceRequest{status: @service_request_status_active} = service_request} <-
           ServiceRequests.get_by_id(service_request_id),
         {:expiration_date, nil} <- {:expiration_date, validate_expiration_date(service_request)} do
      check_episode_references(service_request.permitted_episodes)
    else
      {:ok, %ServiceRequest{} = _} ->
        {:error, "Service request should be active", 409}

      {:expiration_date, now} ->
        {:error, "Service request expiration date must be a datetime greater than or equal #{now}", 409}

      nil ->
        {:error, "Service request is not found", 409}
    end
  end

  defp validate_expiration_date(%ServiceRequest{expiration_date: nil}), do: nil

  defp validate_expiration_date(%ServiceRequest{expiration_date: expiration_date}) do
    now = DateTime.utc_now()

    case DateTime.compare(expiration_date, now) do
      :lt -> now
      _ -> nil
    end
  end

  defp check_episode_references(nil), do: {:error, "Service request does not contain episode references", 409}
  defp check_episode_references([]), do: check_episode_references(nil)

  defp check_episode_references(permitted_episodes) do
    {:ok,
     Enum.map(permitted_episodes, fn episode_ref ->
       identifier = episode_ref.identifier
       %{episode_ref | identifier: %{identifier | value: to_string(identifier.value)}}
     end)}
  end

  defp get_person_auth_method(person_id) do
    case @worker.run("mpi", MPI.Rpc, :get_auth_method, [person_id]) do
      nil ->
        {:error, "Person is not found", 404}

      {:ok, %{} = auth_method} ->
        {:ok, auth_method}

      _ ->
        {:error, "Failed to get person data", 500}
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

  defp verify_auth(%{"type" => "OTP", "phone_number" => phone_number}, code) do
    case @otp_verification_api.complete(phone_number, %{code: code}, []) do
      {:ok, _} -> :ok
      _error -> Error.dump(%Core.ValidationError{description: "Invalid verification code", path: "$.otp"})
    end
  end

  defp verify_auth(_, _), do: :ok
end
