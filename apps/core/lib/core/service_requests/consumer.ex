defmodule Core.ServiceRequests.Consumer do
  @moduledoc false

  use Confex, otp_app: :core

  alias Core.CodeableConcept
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.ServiceRequestCancelJob
  alias Core.Jobs.ServiceRequestCloseJob
  alias Core.Jobs.ServiceRequestCreateJob
  alias Core.Jobs.ServiceRequestRecallJob
  alias Core.Jobs.ServiceRequestReleaseJob
  alias Core.Jobs.ServiceRequestUseJob
  alias Core.Mongo
  alias Core.Mongo.Transaction
  alias Core.Patients.Encounters
  alias Core.Reference
  alias Core.ServiceRequest
  alias Core.ServiceRequests
  alias Core.ServiceRequests.Validations, as: ServiceRequestsValidations
  alias Core.ServiceRequestView
  alias Core.StatusHistory
  alias Core.Validators.JsonSchema
  alias Core.Validators.Signature
  alias Core.Validators.Vex
  alias EView.Views.ValidationError
  require Logger

  @worker Application.get_env(:core, :rpc_worker)
  @digital_signature Application.get_env(:core, :microservices)[:digital_signature]
  @collection ServiceRequest.metadata().collection
  @media_storage Application.get_env(:core, :microservices)[:media_storage]
  @otp_verification_api Application.get_env(:core, :microservices)[:otp_verification]

  @active ServiceRequest.status(:active)
  @completed ServiceRequest.status(:completed)

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
      expiration_days = config()[:service_request_expiration_days]
      expiration_erl_date = now |> DateTime.to_date() |> Date.add(expiration_days) |> Date.to_erl()

      expiration_date =
        {expiration_erl_date, {23, 59, 59}}
        |> NaiveDateTime.from_erl!()
        |> DateTime.from_naive!("Etc/UTC")

      service_request =
        content
        |> ServiceRequest.create()
        |> Map.merge(%{
          _id: UUID.uuid4(),
          subject: patient_id_hash,
          inserted_by: user_id,
          updated_by: user_id,
          inserted_at: now,
          updated_at: now,
          status_history: [],
          expiration_date: expiration_date
        })

      status_history =
        StatusHistory.create(%{
          "status" => service_request.status,
          "status_reason" => service_request.status_reason,
          "inserted_at" => now,
          "inserted_by" => Mongo.string_to_uuid(job.user_id)
        })

      service_request =
        service_request
        |> Map.put(:status_history, [status_history])
        |> ServiceRequestsValidations.validate_signatures(signer, user_id, client_id)
        |> ServiceRequestsValidations.validate_context(patient_id_hash)
        |> ServiceRequestsValidations.validate_occurrence()
        |> ServiceRequestsValidations.validate_authored_on()
        |> ServiceRequestsValidations.validate_supporting_info(patient_id_hash)
        |> ServiceRequestsValidations.validate_reason_reference(patient_id_hash)
        |> ServiceRequestsValidations.validate_permitted_episodes(patient_id_hash)
        |> generate_requisition_number(patient_id_hash, user_id)

      case service_request do
        [_] = errors ->
          Jobs.produce_update_status(
            job._id,
            job.request_id,
            ValidationError.render("422.json", %{schema: Mongo.vex_to_json(errors)}),
            422
          )

        %{} ->
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

                  result =
                    %Transaction{}
                    |> Transaction.add_operation(@collection, :insert, doc)
                    |> Jobs.update(
                      job._id,
                      Job.status(:processed),
                      %{
                        "links" => [
                          %{
                            "entity" => "service_request",
                            "href" => "/api/patients/#{patient_id}/service_requests/#{service_request._id}"
                          }
                        ]
                      },
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
                    Logger.error("Failed to save signed content: #{inspect(error)}")
                    Jobs.produce_update_status(job._id, job.request_id, "Failed to save signed content", 500)
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

    with {:ok, %ServiceRequest{} = service_request} <- ServiceRequests.get_by_id(id),
         {true, _} <- {service_request.status == ServiceRequest.status(:active), :status},
         {true, _} <- {is_nil(service_request.used_by), :used_by} do
      service_request =
        %{service_request | updated_by: user_id, updated_at: now, used_by: Reference.create(used_by)}
        |> ServiceRequestsValidations.validate_used_by(client_id)
        |> ServiceRequestsValidations.validate_expiration_date()

      case Vex.errors(service_request) do
        [] ->
          used_by = %{
            service_request.used_by
            | identifier: %{
                service_request.used_by.identifier
                | value: Mongo.string_to_uuid(service_request.used_by.identifier.value)
              }
          }

          set =
            Mongo.convert_to_uuid(
              %{
                "updated_by" => service_request.updated_by,
                "updated_at" => now,
                "used_by" => Mongo.prepare_doc(used_by)
              },
              "updated_by"
            )

          result =
            %Transaction{}
            |> Transaction.add_operation(@collection, :update, %{"_id" => service_request._id}, %{"$set" => set})
            |> Jobs.update(
              job._id,
              Job.status(:processed),
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
            |> Transaction.flush()

          case result do
            :ok ->
              :ok

            {:error, reason} ->
              Jobs.produce_update_status(job._id, job.request_id, reason, 500)
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
      nil ->
        Jobs.produce_update_status(job._id, job.request_id, "Service request with id '#{id}' is not found", 404)

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

    with {:ok, %ServiceRequest{} = service_request} <- ServiceRequests.get_by_id(id),
         {true, _} <- {service_request.status == ServiceRequest.status(:active), :status} do
      changes = %{"used_by" => nil}

      service_request =
        %{service_request | updated_by: user_id, updated_at: now}
        |> Map.merge(Enum.into(changes, %{}, fn {k, v} -> {String.to_atom(k), v} end))
        |> ServiceRequestsValidations.validate_expiration_date()

      case Vex.errors(service_request) do
        [] ->
          set = %{"updated_by" => service_request.updated_by, "updated_at" => now, "used_by" => nil}

          result =
            %Transaction{}
            |> Transaction.add_operation(@collection, :update, %{"_id" => service_request._id}, %{"$set" => set})
            |> Jobs.update(
              job._id,
              Job.status(:processed),
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
            |> Transaction.flush()

          case result do
            :ok ->
              :ok

            {:error, reason} ->
              Jobs.produce_update_status(job._id, job.request_id, reason, 500)
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
      nil ->
        Jobs.produce_update_status(job._id, job.request_id, "Service request with id '#{id}' is not found", 404)

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
      service_request_id = content["id"]

      with {:ok, service_request} <- ServiceRequests.get_by_id(service_request_id),
           {:status, @active} <- {:status, service_request.status},
           :ok <- compare_with_db(service_request, content) do
        service_request =
          %{
            service_request
            | updated_by: user_id,
              updated_at: now,
              status: ServiceRequest.status(:entered_in_error),
              status_reason: CodeableConcept.create(content["status_reason"])
          }
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
                "status" => service_request.status,
                "status_reason" => Mongo.prepare_doc(service_request.status_reason)
              }

              id = to_string(service_request._id)

              status_history =
                %{
                  "status" => service_request.status,
                  "inserted_at" => service_request.updated_at,
                  "inserted_by" => Mongo.string_to_uuid(service_request.updated_by)
                }
                |> StatusHistory.create()
                |> Map.put(:status_reason, service_request.status_reason)

              push = Mongo.add_to_push(%{}, status_history, "status_history")

              case @worker.run("mpi", MPI.Rpc, :get_auth_method, [patient_id]) do
                nil ->
                  Logger.error("Person #{patient_id} not found")

                {:ok, %{"type" => "OTP", "phone_number" => phone_number}} ->
                  @otp_verification_api.send_sms(
                    phone_number,
                    EEx.eval_string(config()[:recall_sms], assigns: [number: service_request.requisition]),
                    "text",
                    []
                  )

                _ ->
                  :ok
              end

              result =
                %Transaction{}
                |> Transaction.add_operation(@collection, :update, %{"_id" => service_request._id}, %{
                  "$set" => set,
                  "$push" => push
                })
                |> Jobs.update(
                  job._id,
                  Job.status(:processed),
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
                |> Transaction.flush()

              case result do
                :ok ->
                  :ok

                {:error, reason} ->
                  Jobs.produce_update_status(job._id, job.request_id, reason, 500)
              end
            else
              error ->
                Logger.error("Failed to save signed content: #{inspect(error)}")
                Jobs.produce_update_status(job._id, job.request_id, "Failed to save signed content", 500)
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
        nil ->
          Jobs.produce_update_status(
            job._id,
            job.request_id,
            "Service request with id '#{service_request_id}' is not found",
            404
          )

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

  def consume_cancel_service_request(
        %ServiceRequestCancelJob{
          patient_id: patient_id,
          user_id: user_id,
          client_id: client_id
        } = job
      ) do
    with {:ok, data} <- decode_signed_data(job.signed_data),
         {:ok, %{"content" => content, "signer" => signer}} <- validate_signed_data(data),
         :ok <- JsonSchema.validate(:service_request_cancel_signed_content, content) do
      now = DateTime.utc_now()

      with {:ok, service_request} <- ServiceRequests.get_by_id(content["id"]),
           {:status, true, _} <- {:status, service_request.status in [@active, @completed], service_request.status},
           :ok <- compare_with_db(service_request, content) do
        service_request =
          %{
            service_request
            | updated_by: user_id,
              updated_at: now,
              status: ServiceRequest.status(:cancelled),
              status_reason: CodeableConcept.create(content["status_reason"])
          }
          |> ServiceRequestsValidations.validate_signatures(signer, user_id, client_id)

        case Vex.errors(%{service_request: service_request}, service_request: [reference: [path: "service_request"]]) do
          [] ->
            resource_name = "#{service_request._id}/cancel"
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
                "status" => service_request.status,
                "status_reason" => Mongo.prepare_doc(service_request.status_reason)
              }

              id = to_string(service_request._id)

              status_history =
                %{
                  "status" => service_request.status,
                  "inserted_at" => service_request.updated_at,
                  "inserted_by" => Mongo.string_to_uuid(service_request.updated_by)
                }
                |> StatusHistory.create()
                |> Map.put(:status_reason, service_request.status_reason)

              push = Mongo.add_to_push(%{}, status_history, "status_history")

              case @worker.run("mpi", MPI.Rpc, :get_auth_method, [patient_id]) do
                nil ->
                  Logger.error("Person #{patient_id} not found")

                {:ok, %{"type" => "OTP", "phone_number" => phone_number}} ->
                  @otp_verification_api.send_sms(
                    phone_number,
                    EEx.eval_string(config()[:cancel_sms], assigns: [number: service_request.requisition]),
                    "text",
                    []
                  )

                _ ->
                  :ok
              end

              result =
                %Transaction{}
                |> Transaction.add_operation(@collection, :update, %{"_id" => service_request._id}, %{
                  "$set" => set,
                  "$push" => push
                })
                |> Jobs.update(
                  job._id,
                  Job.status(:processed),
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
                |> Transaction.flush()

              case result do
                :ok ->
                  :ok

                {:error, reason} ->
                  Jobs.produce_update_status(job._id, job.request_id, reason, 500)
              end
            else
              error ->
                Logger.error("Failed to save signed content: #{inspect(error)}")
                Jobs.produce_update_status(job._id, job.request_id, "Failed to save signed content", 500)
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
        {:status, false, status} ->
          Jobs.produce_update_status(
            job._id,
            job.request_id,
            "Service request in status #{status} cannot be cancelled",
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

  def consume_close_service_request(
        %ServiceRequestCloseJob{
          patient_id: patient_id,
          user_id: user_id
        } = job
      ) do
    with {:ok, %ServiceRequest{status: @active} = service_request} <- ServiceRequests.get_by_id(job.id) do
      now = DateTime.utc_now()
      service_request = %{service_request | updated_by: user_id, updated_at: now, status: @completed}

      case Vex.errors(%{service_request: service_request}, service_request: [reference: [path: "service_request"]]) do
        [] ->
          set =
            %{
              "updated_by" => service_request.updated_by,
              "updated_at" => service_request.updated_at,
              "status" => service_request.status
            }
            |> Mongo.convert_to_uuid("updated_by")

          status_history =
            StatusHistory.create(%{
              "status" => service_request.status,
              "status_reason" => service_request.status_reason,
              "inserted_at" => service_request.updated_at,
              "inserted_by" => Mongo.string_to_uuid(service_request.updated_by)
            })

          push = Mongo.add_to_push(%{}, status_history, "status_history")

          id = to_string(service_request._id)

          result =
            %Transaction{}
            |> Transaction.add_operation(@collection, :update, %{"_id" => service_request._id}, %{
              "$set" => set,
              "$push" => push
            })
            |> Jobs.update(
              job._id,
              Job.status(:processed),
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
            |> Transaction.flush()

          case result do
            :ok ->
              :ok

            {:error, reason} ->
              Jobs.produce_update_status(job._id, job.request_id, reason, 500)
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
      nil ->
        Jobs.produce_update_status(
          job._id,
          job.request_id,
          "Service request #{job.id} was not found",
          404
        )

      {:ok, %ServiceRequest{status: status}} ->
        Jobs.produce_update_status(
          job._id,
          job.request_id,
          "Service request with status #{status} can't be closed",
          409
        )
    end
  end

  defp compare_with_db(%ServiceRequest{} = service_request, content) do
    excluded_fields = ~w(status_reason explanatory_letter inserted_at updated_at)

    db_content =
      service_request
      |> ServiceRequestView.render_service_request()
      |> Jason.encode!()
      |> Jason.decode!()
      |> Map.drop(excluded_fields)

    content = Map.drop(content, excluded_fields)

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

  defp generate_requisition_number(%ServiceRequest{} = service_request, patient_id_hash, user_id) do
    encounter_id = service_request.context.identifier.value

    with {_, {:ok, encounter}} <- {:encounter, Encounters.get_by_id(patient_id_hash, to_string(encounter_id))},
         {:ok, number} <-
           @worker.run("number_generator", NumberGenerator.Rpc, :number, [
             "episode",
             to_string(encounter.episode.identifier.value),
             user_id
           ]) do
      %{service_request | requisition: number}
    else
      {:encounter, _} ->
        [
          {:error, "service_request.context.identifier.value", :encounter_reference,
           "Encounter with such id is not found"}
        ]

      error ->
        error
    end
  end
end
