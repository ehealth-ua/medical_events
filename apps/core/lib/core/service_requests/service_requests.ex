defmodule Core.ServiceRequests do
  @moduledoc false

  alias Core.Episode
  alias Core.Jobs
  alias Core.Jobs.ServiceRequestCreateJob
  alias Core.Jobs.ServiceRequestRecallJob
  alias Core.Jobs.ServiceRequestReleaseJob
  alias Core.Jobs.ServiceRequestUseJob
  alias Core.Mongo
  alias Core.Paging
  alias Core.Patients
  alias Core.Patients.Encounters
  alias Core.Patients.Episodes
  alias Core.Patients.Validators
  alias Core.Reference
  alias Core.Search
  alias Core.ServiceRequest
  alias Core.ServiceRequests.Validations, as: ServiceRequestsValidations
  alias Core.ServiceRequestView
  alias Core.Validators.JsonSchema
  alias Core.Validators.Signature
  alias Core.Validators.Vex
  alias EView.Views.ValidationError
  alias Scrivener.Page
  require Logger

  @worker Application.get_env(:core, :rpc_worker)
  @collection ServiceRequest.metadata().collection
  @digital_signature Application.get_env(:core, :microservices)[:digital_signature]
  @kafka_producer Application.get_env(:core, :kafka)[:producer]
  @media_storage Application.get_env(:core, :microservices)[:media_storage]

  @active ServiceRequest.status(:active)

  def list(%{"patient_id_hash" => patient_id_hash, "episode_id" => episode_id} = params) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, %Episode{}} <- Episodes.get_by_id(patient_id_hash, episode_id),
         encounters <- Encounters.get_episode_encounters(patient_id_hash, Mongo.string_to_uuid(episode_id)),
         true <-
           Enum.any?(encounters, fn %{"episode_id" => encounter_episode_id} ->
             to_string(encounter_episode_id) == episode_id
           end) do
      paging_params = Map.take(params, ["page", "page_size"])

      with [_ | _] = pipeline <-
             search_service_requests_pipe(params, Enum.map(encounters, &Map.get(&1, "encounter_id"))),
           %Page{entries: service_requests} = page <-
             Paging.paginate(
               :aggregate,
               @collection,
               pipeline,
               paging_params
             ) do
        {:ok, %Page{page | entries: Enum.map(service_requests, &ServiceRequest.create/1)}}
      else
        _ -> {:ok, Paging.create()}
      end
    else
      false -> nil
      error -> error
    end
  end

  def search(params) do
    search_params = Map.take(params, ~w(requisition status))
    paging_params = Map.take(params, ~w(page page_size))

    with :ok <- JsonSchema.validate(:service_request_search, search_params),
         [_ | _] = pipeline <- search_service_requests_search_pipe(params),
         %Page{entries: service_requests} = page <-
           Paging.paginate(
             :aggregate,
             @collection,
             pipeline,
             paging_params
           ) do
      {:ok, %Page{page | entries: Enum.map(service_requests, &ServiceRequest.create/1)}}
    end
  end

  defp search_service_requests_pipe(%{"patient_id_hash" => patient_id_hash} = params, encounters) do
    %{"$match" => %{"subject" => patient_id_hash, "context.identifier.value" => %{"$in" => encounters}}}
    |> Search.add_param(params["status"], ["$match", "status"])
    |> List.wrap()
    |> Enum.concat([%{"$sort" => %{"inserted_at" => -1}}])
  end

  defp search_service_requests_search_pipe(%{"requisition" => requisition} = params) do
    %{"$match" => %{"requisition" => requisition}}
    |> Search.add_param(params["status"], ["$match", "status"])
    |> List.wrap()
    |> Enum.concat([%{"$sort" => %{"inserted_at" => -1}}])
  end

  def get_by_episode_id(patient_id_hash, episode_id, id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, %Episode{}} <- Episodes.get_by_id(patient_id_hash, episode_id),
         {:ok, %ServiceRequest{} = service_request} <- get_by_id(id),
         encounters <- Encounters.get_episode_encounters(patient_id_hash, Mongo.string_to_uuid(episode_id)),
         true <-
           Enum.any?(encounters, fn %{"episode_id" => encounter_episode_id} ->
             to_string(encounter_episode_id) == episode_id
           end),
         true <-
           Enum.any?(encounters, fn %{"encounter_id" => encounter_id} ->
             to_string(encounter_id) == to_string(service_request.context.identifier.value)
           end) do
      {:ok, service_request}
    else
      false -> nil
      error -> error
    end
  end

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

  def produce_release_service_request(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         {:ok, %ServiceRequest{}} <- get_by_id(params["service_request_id"]),
         {:ok, job, service_request_release_job} <-
           Jobs.create(
             ServiceRequestReleaseJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(service_request_release_job) do
      {:ok, job}
    end
  end

  def produce_recall_service_request(%{"patient_id_hash" => patient_id_hash} = params, user_id, client_id) do
    with %{} = patient <- Patients.get_by_id(patient_id_hash),
         :ok <- Validators.is_active(patient),
         :ok <- JsonSchema.validate(:service_request_recall, Map.take(params, ~w(signed_data))),
         {:ok, %ServiceRequest{}} <- get_by_id(params["service_request_id"]),
         {:ok, job, service_request_recall_job} <-
           Jobs.create(
             ServiceRequestRecallJob,
             params |> Map.put("user_id", user_id) |> Map.put("client_id", client_id)
           ),
         :ok <- @kafka_producer.publish_medical_event(service_request_recall_job) do
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
        |> ServiceRequestsValidations.validate_occurrence()
        |> ServiceRequestsValidations.validate_authored_on()
        |> ServiceRequestsValidations.validate_supporting_info(patient_id_hash)
        |> ServiceRequestsValidations.validate_reason_reference(patient_id_hash)
        |> ServiceRequestsValidations.validate_permitted_episodes(patient_id_hash)

      service_request =
        with {:ok, number} <-
               @worker.run("number_generator", NumberGenerator.Rpc, :number, [
                 "service_request",
                 service_request._id,
                 user_id
               ]) do
          %{service_request | requisition: number}
        end

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

          Jobs.produce_update_status(
            job._id,
            job.request_id,
            %{
              "links" => [
                %{
                  "entity" => "service_request",
                  "href" => "/api/patients/#{patient_id}/service_requests/#{UUID.binary_to_string!(id)}"
                }
              ]
            },
            200
          )

        errors ->
          Jobs.produce_update_status(
            job._id,
            job.request_id,
            ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}),
            422
          )
      end
    else
      {_, :status} ->
        Jobs.produce_update_status(job._id, job.request_id, "Can't use inactive service request", 409)

      {_, :used_by} ->
        Jobs.produce_update_status(job._id, job.request_id, "Service request already used", 409)
    end
  end

  def consume_release_service_request(
        %ServiceRequestReleaseJob{
          patient_id: patient_id,
          user_id: user_id,
          service_request_id: id
        } = job
      ) do
    now = DateTime.utc_now()

    with {:ok, %ServiceRequest{} = service_request} <- get_by_id(id),
         {true, _} <- {service_request.status == ServiceRequest.status(:active), :status} do
      changes = %{"used_by" => nil}

      service_request =
        %{service_request | updated_by: user_id, updated_at: now}
        |> Map.merge(Enum.into(changes, %{}, fn {k, v} -> {String.to_atom(k), v} end))

      case Vex.errors(service_request) do
        [] ->
          set = %{"updated_by" => service_request.updated_by, "updated_at" => now, "used_by" => nil}

          {:ok, %{matched_count: 1, modified_count: 1}} =
            Mongo.update_one(@collection, %{"_id" => service_request._id}, %{"$set" => set})

          %BSON.Binary{binary: id} = service_request._id

          Jobs.produce_update_status(
            job._id,
            job.request_id,
            %{
              "links" => [
                %{
                  "entity" => "service_request",
                  "href" => "/api/patients/#{patient_id}/service_requests/#{UUID.binary_to_string!(id)}"
                }
              ]
            },
            200
          )

        errors ->
          Jobs.produce_update_status(
            job._id,
            job.request_id,
            ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}),
            422
          )
      end
    else
      {_, :status} ->
        Jobs.produce_update_status(job._id, job.request_id, "Can't use inactive service request", 409)
    end
  end

  def consume_recall_service_request(
        %ServiceRequestRecallJob{
          patient_id: patient_id,
          user_id: user_id,
          client_id: client_id
        } = job
      ) do
    with {:ok, data} <- decode_signed_data(job.signed_data),
         {:ok, %{"content" => content, "signer" => signer}} <- validate_signed_data(data),
         :ok <- JsonSchema.validate(:service_request_recall_signed_content, content) do
      now = DateTime.utc_now()

      with {:ok, service_request} <- get_by_id(content["id"]),
           {:status, @active} <- {:status, service_request.status},
           :ok <- compare_with_db(service_request, content) do
        changes = %{"status" => ServiceRequest.status(:entered_in_error)}

        service_request =
          %{service_request | updated_by: user_id, updated_at: now}
          |> Map.merge(Enum.into(changes, %{}, fn {k, v} -> {String.to_atom(k), v} end))
          |> ServiceRequestsValidations.validate_signatures(signer, user_id, client_id)

        case Vex.errors(%{service_request: service_request}, service_request: [reference: [path: "service_request"]]) do
          [] ->
            resource_name = "#{service_request._id}/recall"
            files = [{'signed_content.txt', job.signed_data}]
            {:ok, {_, compressed_content}} = :zip.create("signed_content.zip", files, [:memory])

            with :ok <-
                   @media_storage.save(
                     patient_id,
                     compressed_content,
                     Confex.fetch_env!(:core, Core.Microservices.MediaStorage)[:service_request_bucket],
                     resource_name
                   ) do
              set = %{
                "updated_by" => service_request.updated_by,
                "updated_at" => service_request.updated_at,
                "signed_content_links" => service_request.signed_content_links ++ [resource_name],
                "status" => service_request.status
              }

              id = to_string(service_request._id)

              {:ok, %{matched_count: 1, modified_count: 1}} =
                Mongo.update_one(@collection, %{"_id" => service_request._id}, %{"$set" => set})

              Jobs.produce_update_status(
                job._id,
                job.request_id,
                %{
                  "links" => [
                    %{
                      "entity" => "service_request",
                      "href" => "/api/patients/#{patient_id}/service_requests/#{id}"
                    }
                  ]
                },
                200
              )
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
        {:status, status} ->
          Jobs.produce_update_status(
            job._id,
            job.request_id,
            "Service request in status #{status} cannot be recalled",
            409
          )

        {:error, message, status_code} ->
          Jobs.produce_update_status(job._id, job.request_id, message, status_code)
      end
    else
      {:error, error} ->
        Jobs.produce_update_status(job._id, job.request_id, ValidationError.render("422.json", %{schema: error}), 422)

      {_, response, status_code} ->
        Jobs.produce_update_status(job._id, job.request_id, response, status_code)
    end
  end

  defp compare_with_db(%ServiceRequest{} = service_request, content) do
    db_content =
      service_request
      |> ServiceRequestView.render_service_request()
      |> Jason.encode!()
      |> Jason.decode!()
      |> Map.drop(~w(status_reason explanatory_letter))

    content = Map.drop(content, ~w(status_reason explanatory_letter))

    if content != db_content do
      {:error, "Signed content doesn't match with previously created service request", 422}
    else
      :ok
    end
  end

  defp decode_signed_data(signed_data) do
    with {:ok, %{"data" => data}} <- @digital_signature.decode(signed_data, []) do
      {:ok, data}
    else
      {:error, %{"error" => _} = error} ->
        Logger.info(inspect(error))
        {:error, "Invalid signed content", 422}

      error ->
        Logger.error(inspect(error))
        {:ok, "Failed to decode signed content", 500}
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
