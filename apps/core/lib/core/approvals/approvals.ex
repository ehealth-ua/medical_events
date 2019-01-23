defmodule Core.Approvals do
  @moduledoc false

  alias Core.Approval
  alias Core.Approvals.Validations, as: ApprovalsValidations
  alias Core.Jobs
  alias Core.Jobs.ApprovalCreateJob
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

  @collection Approval.metadata().collection

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
  @mpi_api Application.get_env(:core, :microservices)[:mpi]
  @otp_verification_api Application.get_env(:core, :microservices)[:otp_verification]

  def produce_create_approval(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:approval_create, Map.take(params, @create_request_params)),
         {:ok, job, approval_create_job} <-
           Jobs.create(
             ApprovalCreateJob,
             Map.merge(params, %{"user_id" => user_id, "client_id" => client_id})
           ),
         :ok <- @kafka_producer.publish_medical_event(approval_create_job) do
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
         {:ok, person} <- get_person(patient_id),
         {authentication_method_current, urgent_data} <- get_person_authentication_method_current(person) do
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
          urgent: urgent_data,
          inserted_by: user_id,
          updated_by: user_id,
          inserted_at: now,
          updated_at: now
        })
        |> ApprovalsValidations.validate_granted_to(user_id, client_id)
        |> ApprovalsValidations.validate_granted_resources(patient_id_hash, client_id)

      case Vex.errors(approval) do
        [] ->
          if Mongo.find_one(
               @collection,
               %{"_id" => Mongo.string_to_uuid(approval._id)},
               projection: %{"_id" => true}
             ) do
            {:error, "Approval with id '#{approval._id}' already exists", 409}
          else
            with :ok <- initialize_otp_verification(authentication_method_current) do
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

              links = [
                %{
                  "entity" => "approval",
                  "id" => to_string(approval._id)
                }
              ]

              Jobs.produce_update_status(job._id, job.request_id, %{"links" => links}, 200)
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

  def verify(%{"patient_id_hash" => patient_id_hash, "patient_id" => patient_id, "id" => id} = params, user_id) do
    code = Map.get(params, "code")

    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, %Approval{status: @status_new} = approval} <- get_by_id(id),
         :ok <- ApprovalsValidations.validate_patient(approval, patient_id_hash),
         {:ok, person} <- get_person(patient_id),
         {authentication_method_current, _} <- get_person_authentication_method_current(person),
         :ok <- verify_auth(authentication_method_current, code) do
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

  defp get_episodes(resources, nil), do: {:ok, Enum.map(resources, &Reference.create/1)}

  defp get_episodes(nil, %{"identifier" => %{"value" => service_request_id}}) do
    case ServiceRequests.get_by_id(service_request_id) do
      {:ok, %ServiceRequest{status: @service_request_status_active} = service_request} ->
        check_episode_references(service_request.permitted_episodes)

      {:ok, %ServiceRequest{} = _} ->
        {:error, "Service request should be active", 409}

      _ ->
        {:error, "Service request is not found", 409}
    end
  end

  defp check_episode_references(nil), do: {:error, "Service request does not contain episode references", 409}
  defp check_episode_references(permitted_episodes), do: {:ok, permitted_episodes}

  defp get_person(person_id) do
    case @mpi_api.person(%{id: person_id}, []) do
      {:ok, %{"data" => nil}} ->
        {:error, "Person is not found", 404}

      {:ok, %{"data" => person}} ->
        {:ok, person}

      _ ->
        {:error, "Failed to get person data", 500}
    end
  end

  defp get_person_authentication_method_current(%{"authentication_methods" => authentication_methods}) do
    authentication_method_current = List.first(authentication_methods)
    filtered_authentication_method_current = filter_authentication_method(authentication_method_current)

    {authentication_method_current,
     %{
       "authentication_method_current" => filtered_authentication_method_current
     }}
  end

  defp filter_authentication_method(nil), do: %{}

  defp filter_authentication_method(%{"phone_number" => number} = method) when not is_nil(number) do
    Map.put(method, "phone_number", hide_number(number))
  end

  defp filter_authentication_method(method), do: method

  defp hide_number(<<code::bytes-size(6), _hidden::bytes-size(5), last_digits::bytes-size(2)>>) do
    "#{code}*****#{last_digits}"
  end

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
