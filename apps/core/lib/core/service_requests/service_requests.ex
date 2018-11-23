defmodule Core.ServiceRequests do
  @moduledoc false

  alias Core.Jobs
  alias Core.Jobs.ServiceRequestCreateJob
  alias Core.Jobs.ServiceRequestUseJob
  alias Core.Mongo
  alias Core.Patients
  alias Core.Patients.Validators
  alias Core.Reference
  alias Core.ServiceRequest
  alias Core.ServiceRequests.Validations, as: ServiceRequestsValidations
  alias Core.Validators.JsonSchema
  alias Core.Validators.Signature
  alias Core.Validators.Vex
  alias EView.Views.ValidationError

  @collection ServiceRequest.metadata().collection
  @digital_signature Application.get_env(:core, :microservices)[:digital_signature]
  @kafka_producer Application.get_env(:core, :kafka)[:producer]
  @media_storage Application.get_env(:core, :microservices)[:media_storage]

  def get_by_id(id) do
    @collection
    |> Mongo.find_one(%{"_id" => Mongo.string_to_uuid(id)})
    |> case do
      %{} = service_request -> {:ok, ServiceRequest.create(service_request)}
      _ -> nil
    end
  end

  def produce_create_service_request(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:service_request_create, Map.take(params, ~w(signed_data))),
         {:ok, job, service_request_create_job} <-
           Jobs.create(
             ServiceRequestCreateJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(service_request_create_job) do
      {:ok, job}
    end
  end

  def produce_use_service_request(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:service_request_use, Map.take(params, ~w(used_by))),
         {:ok, %ServiceRequest{}} <- get_by_id(params["service_request_id"]),
         {:ok, job, service_request_use_job} <-
           Jobs.create(
             ServiceRequestUseJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(service_request_use_job) do
      {:ok, job}
    end
  end

  def consume_create_service_request(
        %ServiceRequestCreateJob{
          patient_id: patient_id,
          patient_id_hash: patient_id_hash,
          user_id: user_id,
          client_id: client_id
        } = job
      ) do
    with {:ok, data} <- decode_signed_data(job.signed_data),
         {:ok, %{"content" => content, "signer" => signer}} <- validate_signed_data(data),
         :ok <- JsonSchema.validate(:service_request_create_signed_content, content) do
      now = DateTime.utc_now()

      service_request =
        content
        |> ServiceRequest.create()
        |> Map.merge(%{
          subject: patient_id_hash,
          inserted_by: user_id,
          updated_by: user_id,
          inserted_at: now,
          updated_at: now,
          status_history: []
        })
        |> ServiceRequestsValidations.validate_signatures(signer, user_id, client_id)
        |> ServiceRequestsValidations.validate_context(patient_id_hash)
        |> ServiceRequestsValidations.validate_occurence()
        |> ServiceRequestsValidations.validate_authored_on()
        |> ServiceRequestsValidations.validate_supporting_info(patient_id_hash)
        |> ServiceRequestsValidations.validate_reason_reference(patient_id_hash)
        |> ServiceRequestsValidations.validate_permitted_episodes(patient_id_hash)

      case Vex.errors(%{service_request: service_request}, service_request: [reference: [path: "service_request"]]) do
        [] ->
          if Mongo.find_one(
               ServiceRequest.metadata().collection,
               %{"_id" => Mongo.string_to_uuid(service_request._id)},
               projection: %{"_id" => true}
             ) do
            {:error, "Service request with id '#{service_request._id}' already exists", 409}
          else
            resource_name = "#{service_request._id}/create"
            files = [{'signed_content.txt', job.signed_data}]
            {:ok, {_, compressed_content}} = :zip.create("signed_content.zip", files, [:memory])

            with :ok <-
                   @media_storage.save(
                     patient_id,
                     compressed_content,
                     Confex.fetch_env!(:core, Core.Microservices.MediaStorage)[:service_request_bucket],
                     resource_name
                   ) do
              doc =
                %{service_request | signed_content_links: [resource_name]}
                |> Mongo.prepare_doc()
                |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
                |> Mongo.convert_to_uuid("_id")
                |> Mongo.convert_to_uuid("inserted_by")
                |> Mongo.convert_to_uuid("updated_by")
                |> Mongo.convert_to_uuid("requester", ~w(identifier value)a)
                |> Mongo.convert_to_uuid("context", ~w(identifier value)a)
                |> Mongo.convert_to_uuid("supporting_info", ~w(identifier value)a)
                |> Mongo.convert_to_uuid("permitted_episodes", ~w(identifier value)a)

              {:ok, %{inserted_id: _}} = Mongo.insert_one(@collection, doc, [])

              links = [
                %{
                  "entity" => "service_request",
                  "href" => "/api/patients/#{patient_id}/service_requests/#{service_request._id}"
                }
              ]

              {:ok, %{"links" => links}, 200}
            end
          end

        errors ->
          {:ok, ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}), 422}
      end
    else
      {:error, error} ->
        {:ok, ValidationError.render("422.json", %{schema: error}), 422}

      error ->
        error
    end
  end

  def consume_use_service_request(
        %ServiceRequestUseJob{
          patient_id: patient_id,
          user_id: user_id,
          client_id: client_id,
          service_request_id: id,
          used_by: used_by
        } = job
      ) do
    now = DateTime.utc_now()

    with {:ok, %ServiceRequest{} = service_request} <- get_by_id(id),
         {true, _} <- {service_request.status == ServiceRequest.status(:active), :status},
         {true, _} <- {is_nil(service_request.used_by), :used_by} do
      changes = %{"used_by" => Reference.create(used_by)}

      service_request =
        %{service_request | updated_by: user_id, updated_at: now}
        |> Map.merge(Enum.into(changes, %{}, fn {k, v} -> {String.to_atom(k), v} end))
        |> ServiceRequestsValidations.validate_used_by(client_id)

      case Vex.errors(service_request) do
        [] ->
          set =
            %{"updated_by" => service_request.updated_by, "updated_at" => now}
            |> Mongo.add_to_set(service_request.used_by, "service_request.used_by")
            |> Mongo.convert_to_uuid("service_request.used_by.identifier.value")
            |> Mongo.convert_to_uuid("updated_by")

          {:ok, %{matched_count: 1, modified_count: 1}} =
            Mongo.update_one(@collection, %{"_id" => service_request._id}, %{"$set" => set})

          %BSON.Binary{binary: id} = service_request._id

          {:ok,
           %{
             "links" => [
               %{
                 "entity" => "service_request",
                 "href" => "/api/patients/#{patient_id}/service_requests/#{UUID.binary_to_string!(id)}"
               }
             ]
           }, 200}

        errors ->
          {:ok, ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}), 422}
      end
    else
      {_, :status} -> {:error, "Can't use inactive service request", 409}
      {_, :used_by} -> {:error, "Service request already used", 409}
    end
  end

  defp decode_signed_data(signed_data) do
    with {:ok, %{"data" => data}} <- @digital_signature.decode(signed_data, []) do
      {:ok, data}
    else
      {:error, %{"error" => _} = error} -> {:ok, error, 422}
      error -> {:ok, error, 500}
    end
  end

  defp validate_signed_data(signed_data) do
    with {:ok, %{"content" => _, "signer" => _}} = validation_result <- Signature.validate(signed_data) do
      validation_result
    else
      {:error, error} -> {:error, error, 422}
    end
  end
end
