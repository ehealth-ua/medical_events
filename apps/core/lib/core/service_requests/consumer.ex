defmodule Core.ServiceRequests.Consumer do
  @moduledoc false

  use Confex, otp_app: :core

  alias Core.DigitalSignature
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.ServiceRequestCancelJob
  alias Core.Jobs.ServiceRequestCloseJob
  alias Core.Jobs.ServiceRequestCompleteJob
  alias Core.Jobs.ServiceRequestCreateJob
  alias Core.Jobs.ServiceRequestProcessJob
  alias Core.Jobs.ServiceRequestRecallJob
  alias Core.Jobs.ServiceRequestReleaseJob
  alias Core.Jobs.ServiceRequestUseJob
  alias Core.Mongo
  alias Core.Mongo.Transaction
  alias Core.ServiceRequest
  alias Core.ServiceRequests
  alias Core.ServiceRequests.EventManager
  alias Core.ServiceRequestView
  alias Core.StatusHistory
  alias Core.ValidationError, as: CoreValidationError
  alias Core.Validators.DateTime, as: DateTimeValidations
  alias Core.Validators.Drfo
  alias Core.Validators.Error
  alias Core.Validators.JsonSchema
  alias Core.Validators.OneOf
  alias Ecto.Changeset
  alias EView.Views.ValidationError
  require Logger

  @worker Application.get_env(:core, :rpc_worker)
  @collection ServiceRequest.collection()
  @media_storage Application.get_env(:core, :microservices)[:media_storage]

  @active ServiceRequest.status(:active)
  @completed ServiceRequest.status(:completed)

  @one_of_request_params %{
    "$" => %{"params" => ["occurrence_date_time", "occurrence_period"], "required" => false}
  }

  def consume_create_service_request(
        %ServiceRequestCreateJob{
          patient_id: patient_id,
          patient_id_hash: patient_id_hash,
          user_id: user_id,
          client_id: client_id
        } = job
      ) do
    with {:ok, %{content: content, signer: signer}} <- DigitalSignature.decode_and_validate(job.signed_data),
         :ok <- JsonSchema.validate(:service_request_create_signed_content, content),
         :ok <- OneOf.validate(content, @one_of_request_params) do
      now = DateTime.utc_now()
      expiration_days = config()[:service_request_expiration_days]

      expiration_erl_date = now |> DateTime.to_date() |> Date.add(expiration_days) |> Date.to_erl()

      expiration_date =
        {expiration_erl_date, {23, 59, 59}}
        |> NaiveDateTime.from_erl!()
        |> DateTime.from_naive!("Etc/UTC")

      id = UUID.uuid4()
      resource_name = "#{id}/create"

      changes =
        Map.merge(content, %{
          "_id" => id,
          "subject" => patient_id_hash,
          "inserted_by" => user_id,
          "updated_by" => user_id,
          "inserted_at" => now,
          "updated_at" => now,
          "status_history" => [
            %{
              "status" => content["status"],
              "status_reason" => content["status_reason"],
              "inserted_at" => now,
              "inserted_by" => Mongo.string_to_uuid(job.user_id)
            }
          ],
          "expiration_date" => expiration_date,
          "signed_content_links" => [resource_name]
        })

      changeset =
        ServiceRequest.create_changeset(
          %ServiceRequest{},
          changes,
          patient_id_hash,
          user_id,
          client_id
        )

      case changeset do
        %Changeset{valid?: false} ->
          Jobs.produce_update_status(job, ValidationError.render("422.json", changeset), 422)

        _ ->
          service_request = Changeset.apply_changes(changeset)
          files = [{'signed_content.txt', job.signed_data}]
          {:ok, {_, compressed_content}} = :zip.create("signed_content.zip", files, [:memory])

          with :ok <-
                 Drfo.validate(service_request.requester_employee.identifier.value,
                   drfo: signer["drfo"],
                   client_id: client_id,
                   user_id: user_id
                 ),
               :ok <-
                 @media_storage.save(
                   patient_id,
                   compressed_content,
                   Confex.fetch_env!(:core, Core.Microservices.MediaStorage)[:service_request_bucket],
                   resource_name
                 ) do
            result =
              %Transaction{actor_id: user_id, patient_id: patient_id_hash}
              |> Transaction.add_operation(
                @collection,
                :insert,
                service_request,
                service_request._id
              )
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
                Jobs.produce_update_status(job, reason, 500)
            end
          else
            {:error, reason} ->
              Jobs.produce_update_status(job, reason, 409)

            _ ->
              Jobs.produce_update_status(job, "Failed to save signed content", 500)
          end
      end
    else
      {:error, error} ->
        Jobs.produce_update_status(job, ValidationError.render("422.json", %{schema: error}), 422)

      {:error, reason, status_code} ->
        Jobs.produce_update_status(job, reason, status_code)

      {_, response, status_code} ->
        Jobs.produce_update_status(job, response, status_code)
    end
  end

  def consume_use_service_request(
        %ServiceRequestUseJob{
          patient_id: patient_id,
          user_id: user_id,
          client_id: client_id,
          service_request_id: id,
          used_by_employee: used_by_employee,
          used_by_legal_entity: used_by_legal_entity
        } = job
      ) do
    now = DateTime.utc_now()

    with {:ok, %ServiceRequest{} = service_request} <- ServiceRequests.get_by_id(id),
         {:ok, _} <-
           {DateTimeValidations.validate(service_request.expiration_date,
              greater_than_or_equal_to: DateTime.utc_now(),
              message: "Service request is expired"
            ), :expiration_date},
         {true, _} <- {service_request.status == ServiceRequest.status(:active), :status},
         {true, _} <- {is_nil(service_request.used_by_legal_entity), :already_used},
         changeset <-
           ServiceRequest.use_changeset(
             service_request,
             %{
               "updated_by" => user_id,
               "updated_at" => now,
               "used_by_employee" => used_by_employee,
               "used_by_legal_entity" => used_by_legal_entity
             },
             client_id
           ) do
      case changeset do
        %Changeset{valid?: false} ->
          Jobs.produce_update_status(job, ValidationError.render("422.json", changeset), 422)

        _ ->
          service_request = Changeset.apply_changes(changeset)

          set = %{
            "updated_by" => service_request.updated_by,
            "updated_at" => now,
            "used_by_employee" =>
              service_request
              |> Map.get(:used_by_employee)
              |> update_reference_uuid(),
            "used_by_legal_entity" =>
              service_request
              |> Map.get(:used_by_legal_entity)
              |> update_reference_uuid()
          }

          result =
            %Transaction{actor_id: user_id, patient_id: job.patient_id_hash}
            |> Transaction.add_operation(
              @collection,
              :update,
              %{"_id" => service_request._id},
              %{"$set" => set},
              service_request._id
            )
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
              Jobs.produce_update_status(job, reason, 500)
          end
      end
    else
      nil ->
        Jobs.produce_update_status(job, "Service request with id '#{id}' is not found", 404)

      {_, :status} ->
        Jobs.produce_update_status(job, "Can't use inactive service request", 409)

      {{:error, message}, :expiration_date} ->
        Jobs.produce_update_status(job, message, 409)

      {_, :already_used} ->
        Jobs.produce_update_status(job, "Service request is already used", 409)
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
         {:ok, _} <-
           {DateTimeValidations.validate(service_request.expiration_date,
              greater_than_or_equal_to: DateTime.utc_now(),
              message: "Service request is expired"
            ), :expiration_date},
         {@active, _} <- {service_request.status, :status},
         changeset <-
           ServiceRequest.release_changeset(
             service_request,
             %{
               "updated_by" => user_id,
               "updated_at" => now,
               "used_by_employee" => nil,
               "used_by_legal_entity" => nil
             }
           ) do
      case changeset do
        %Changeset{valid?: false} ->
          Jobs.produce_update_status(job, ValidationError.render("422.json", changeset), 422)

        _ ->
          service_request = Changeset.apply_changes(changeset)

          set = %{
            "updated_by" => user_id,
            "updated_at" => now,
            "used_by_employee" => service_request.used_by_employee,
            "used_by_legal_entity" => service_request.used_by_legal_entity
          }

          result =
            %Transaction{actor_id: user_id, patient_id: job.patient_id_hash}
            |> Transaction.add_operation(
              @collection,
              :update,
              %{"_id" => service_request._id},
              %{"$set" => set},
              service_request._id
            )
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
              Jobs.produce_update_status(job, reason, 500)
          end
      end
    else
      nil ->
        Jobs.produce_update_status(job, "Service request with id '#{id}' is not found", 404)

      {{:error, message}, :expiration_date} ->
        Jobs.produce_update_status(job, message, 409)

      {status, :status} ->
        Jobs.produce_update_status(
          job,
          "Service request in status #{status} cannot be released",
          409
        )
    end
  end

  def consume_recall_service_request(
        %ServiceRequestRecallJob{
          patient_id: patient_id,
          user_id: user_id,
          client_id: client_id
        } = job
      ) do
    with {:ok, %{content: content, signer: signer}} <- DigitalSignature.decode_and_validate(job.signed_data),
         :ok <- JsonSchema.validate(:service_request_recall_signed_content, content),
         :ok <- OneOf.validate(content, @one_of_request_params) do
      now = DateTime.utc_now()
      service_request_id = content["id"]
      resource_name = "#{service_request_id}/recall"

      with {:ok, service_request} <- ServiceRequests.get_by_id(service_request_id),
           {:status, @active} <- {:status, service_request.status},
           :ok <- compare_with_db(service_request, content) do
        changeset =
          ServiceRequest.recall_changeset(
            service_request,
            %{
              "updated_by" => user_id,
              "updated_at" => now,
              "status" => ServiceRequest.status(:recalled),
              "status_reason" => content["status_reason"]
            }
          )

        case changeset do
          %Changeset{valid?: false} ->
            Jobs.produce_update_status(job, ValidationError.render("422.json", changeset), 422)

          _ ->
            service_request = Changeset.apply_changes(changeset)
            files = [{'signed_content.txt', job.signed_data}]
            {:ok, {_, compressed_content}} = :zip.create("signed_content.zip", files, [:memory])

            with :ok <-
                   Drfo.validate(service_request.requester_employee.identifier.value,
                     drfo: signer["drfo"],
                     client_id: client_id,
                     user_id: user_id
                   ),
                 :ok <-
                   @media_storage.save(
                     patient_id,
                     compressed_content,
                     Confex.fetch_env!(:core, Core.Microservices.MediaStorage)[:service_request_bucket],
                     resource_name
                   ) do
              set = %{
                "updated_by" => service_request.updated_by,
                "updated_at" => service_request.updated_at,
                "status" => service_request.status,
                "status_reason" => service_request.status_reason
              }

              status_history =
                StatusHistory.create(%{
                  "status" => service_request.status,
                  "status_reason" => content["status_reason"],
                  "inserted_at" => service_request.updated_at,
                  "inserted_by" => Mongo.string_to_uuid(service_request.updated_by)
                })

              push =
                %{}
                |> Mongo.add_to_push(resource_name, "signed_content_links")
                |> Mongo.add_to_push(status_history, "status_history")

              case @worker.run("mpi", MPI.Rpc, :get_auth_method, [patient_id]) do
                nil ->
                  Logger.error("Person #{patient_id} not found")

                {:ok, %{"type" => "OTP", "phone_number" => phone_number}} ->
                  @worker.run("otp_verification_api", OtpVerification.Rpc, :send_sms, [
                    phone_number,
                    EEx.eval_string(config()[:recall_sms],
                      assigns: [number: service_request.requisition]
                    ),
                    "text"
                  ])

                _ ->
                  :ok
              end

              result =
                %Transaction{actor_id: user_id, patient_id: job.patient_id_hash}
                |> Transaction.add_operation(
                  @collection,
                  :update,
                  %{"_id" => service_request._id},
                  %{
                    "$set" => set,
                    "$push" => push
                  },
                  service_request._id
                )
                |> Jobs.update(
                  job._id,
                  Job.status(:processed),
                  %{
                    "links" => [
                      %{
                        "entity" => "service_request",
                        "href" => "/api/patients/#{patient_id}/service_requests/#{service_request_id}"
                      }
                    ]
                  },
                  200
                )
                |> Transaction.flush()

              case result do
                :ok ->
                  EventManager.new_event(
                    service_request_id,
                    user_id,
                    ServiceRequest.status(:recalled)
                  )

                  :ok

                {:error, reason} ->
                  Jobs.produce_update_status(job, reason, 500)
              end
            else
              {:error, reason} ->
                Jobs.produce_update_status(job, reason, 409)

              _ ->
                Jobs.produce_update_status(job, "Failed to save signed content", 500)
            end
        end
      else
        nil ->
          Jobs.produce_update_status(
            job,
            "Service request with id '#{service_request_id}' is not found",
            404
          )

        {:status, status} ->
          Jobs.produce_update_status(
            job,
            "Service request in status #{status} cannot be recalled",
            409
          )

        {:error, message, status_code} ->
          Jobs.produce_update_status(job, message, status_code)
      end
    else
      {:error, error} ->
        Jobs.produce_update_status(job, ValidationError.render("422.json", %{schema: error}), 422)

      {_, response, status_code} ->
        Jobs.produce_update_status(job, response, status_code)
    end
  end

  def consume_cancel_service_request(
        %ServiceRequestCancelJob{
          patient_id: patient_id,
          user_id: user_id,
          client_id: client_id,
          service_request_id: service_request_id
        } = job
      ) do
    with {:ok, %{content: content, signer: signer}} <- DigitalSignature.decode_and_validate(job.signed_data),
         :ok <- JsonSchema.validate(:service_request_cancel_signed_content, content),
         :ok <- OneOf.validate(content, @one_of_request_params) do
      now = DateTime.utc_now()
      resource_name = "#{service_request_id}/cancel"

      with {:ok, service_request} <- ServiceRequests.get_by_id(content["id"]),
           {:status, true, _} <-
             {:status, service_request.status in [@active, @completed], service_request.status},
           :ok <- compare_with_db(service_request, content) do
        changeset =
          ServiceRequest.cancel_changeset(
            service_request,
            %{
              "updated_by" => user_id,
              "updated_at" => now,
              "status" => ServiceRequest.status(:entered_in_error),
              "status_reason" => content["status_reason"]
            }
          )

        case changeset do
          %Changeset{valid?: false} ->
            Jobs.produce_update_status(job, ValidationError.render("422.json", changeset), 422)

          _ ->
            service_request = Changeset.apply_changes(changeset)
            files = [{'signed_content.txt', job.signed_data}]
            {:ok, {_, compressed_content}} = :zip.create("signed_content.zip", files, [:memory])

            with :ok <-
                   Drfo.validate(service_request.requester_employee.identifier.value,
                     drfo: signer["drfo"],
                     client_id: client_id,
                     user_id: user_id
                   ),
                 :ok <-
                   @media_storage.save(
                     patient_id,
                     compressed_content,
                     Confex.fetch_env!(:core, Core.Microservices.MediaStorage)[:service_request_bucket],
                     resource_name
                   ) do
              set = %{
                "updated_by" => service_request.updated_by,
                "updated_at" => service_request.updated_at,
                "status" => service_request.status,
                "status_reason" => service_request.status_reason
              }

              status_history =
                StatusHistory.create(%{
                  "status" => service_request.status,
                  "status_reason" => content["status_reason"],
                  "inserted_at" => service_request.updated_at,
                  "inserted_by" => Mongo.string_to_uuid(service_request.updated_by)
                })

              push =
                %{}
                |> Mongo.add_to_push(resource_name, "signed_content_links")
                |> Mongo.add_to_push(status_history, "status_history")

              case @worker.run("mpi", MPI.Rpc, :get_auth_method, [patient_id]) do
                nil ->
                  Logger.error("Person #{patient_id} not found")

                {:ok, %{"type" => "OTP", "phone_number" => phone_number}} ->
                  @worker.run("otp_verification_api", OtpVerification.Rpc, :send_sms, [
                    phone_number,
                    EEx.eval_string(config()[:cancel_sms],
                      assigns: [number: service_request.requisition]
                    ),
                    "text"
                  ])

                _ ->
                  :ok
              end

              result =
                %Transaction{actor_id: user_id, patient_id: job.patient_id_hash}
                |> Transaction.add_operation(
                  @collection,
                  :update,
                  %{"_id" => service_request._id},
                  %{
                    "$set" => set,
                    "$push" => push
                  },
                  service_request._id
                )
                |> Jobs.update(
                  job._id,
                  Job.status(:processed),
                  %{
                    "links" => [
                      %{
                        "entity" => "service_request",
                        "href" => "/api/patients/#{patient_id}/service_requests/#{service_request_id}"
                      }
                    ]
                  },
                  200
                )
                |> Transaction.flush()

              case result do
                :ok ->
                  EventManager.new_event(
                    service_request_id,
                    user_id,
                    ServiceRequest.status(:entered_in_error)
                  )

                  :ok

                {:error, reason} ->
                  Jobs.produce_update_status(job, reason, 500)
              end
            else
              {:error, reason} ->
                Jobs.produce_update_status(job, reason, 409)

              _ ->
                Jobs.produce_update_status(job, "Failed to save signed content", 500)
            end
        end
      else
        {:status, false, status} ->
          Jobs.produce_update_status(
            job,
            "Service request in status #{status} cannot be cancelled",
            409
          )

        {:error, message, status_code} ->
          Jobs.produce_update_status(job, message, status_code)
      end
    else
      {:error, error} ->
        Jobs.produce_update_status(job, ValidationError.render("422.json", %{schema: error}), 422)

      {_, response, status_code} ->
        Jobs.produce_update_status(job, response, status_code)
    end
  end

  def consume_close_service_request(
        %ServiceRequestCloseJob{
          patient_id: patient_id,
          user_id: user_id
        } = job
      ) do
    with {:ok, %ServiceRequest{status: @active} = service_request} <-
           ServiceRequests.get_by_id(job.id) do
      now = DateTime.utc_now()

      changeset =
        ServiceRequest.close_changeset(service_request, %{
          "updated_by" => user_id,
          "updated_at" => now,
          "status" => @completed
        })

      case changeset do
        %Changeset{valid?: false} ->
          Jobs.produce_update_status(job, ValidationError.render("422.json", changeset), 422)

        _ ->
          service_request = Changeset.apply_changes(changeset)

          set = %{
            "updated_by" => service_request.updated_by,
            "updated_at" => service_request.updated_at,
            "status" => service_request.status
          }

          status_history =
            StatusHistory.create(%{
              "status" => service_request.status,
              "status_reason" => service_request.status_reason,
              "inserted_at" => service_request.updated_at,
              "inserted_by" => Mongo.string_to_uuid(service_request.updated_by)
            })

          push = Mongo.add_to_push(%{}, status_history, "status_history")

          result =
            %Transaction{actor_id: user_id, patient_id: job.patient_id_hash}
            |> Transaction.add_operation(
              @collection,
              :update,
              %{"_id" => service_request._id},
              %{
                "$set" => set,
                "$push" => push
              },
              service_request._id
            )
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
              Jobs.produce_update_status(job, reason, 500)
          end
      end
    else
      nil ->
        Jobs.produce_update_status(job, "Service request #{job.id} was not found", 404)

      {:ok, %ServiceRequest{status: status}} ->
        Jobs.produce_update_status(
          job,
          "Service request with status #{status} can't be closed",
          409
        )
    end
  end

  def consume_complete_service_request(
        %ServiceRequestCompleteJob{
          patient_id: patient_id,
          patient_id_hash: patient_id_hash,
          user_id: user_id,
          client_id: client_id,
          service_request_id: id,
          completed_with: completed_with,
          status_reason: status_reason
        } = job
      ) do
    now = DateTime.utc_now()

    with {:ok, %ServiceRequest{} = service_request} <- ServiceRequests.get_by_id(id),
         {true, _} <- {service_request.status == ServiceRequest.status(:in_progress), :status},
         {true, _} <-
           {get_reference_value(service_request.used_by_legal_entity) == client_id, :used_by_another_legal_entity} do
      changeset =
        ServiceRequest.complete_changeset(
          service_request,
          %{
            "updated_by" => user_id,
            "updated_at" => now,
            "status" => ServiceRequest.status(:completed),
            "status_reason" => status_reason,
            "completed_with" => completed_with
          },
          patient_id_hash
        )

      case changeset do
        %Changeset{valid?: false} ->
          Jobs.produce_update_status(job, ValidationError.render("422.json", changeset), 422)

        _ ->
          service_request = Changeset.apply_changes(changeset)

          set = %{
            "status" => service_request.status,
            "updated_by" => service_request.updated_by,
            "updated_at" => now,
            "completed_with" => completed_with,
            "status_reason" => status_reason
          }

          status_history =
            StatusHistory.create(%{
              "status" => service_request.status,
              "status_reason" => status_reason,
              "inserted_at" => service_request.updated_at,
              "inserted_by" => Mongo.string_to_uuid(service_request.updated_by)
            })

          push = Mongo.add_to_push(%{}, status_history, "status_history")

          result =
            %Transaction{actor_id: user_id, patient_id: patient_id_hash}
            |> Transaction.add_operation(
              @collection,
              :update,
              %{"_id" => service_request._id},
              %{
                "$set" => set,
                "$push" => push
              },
              service_request._id
            )
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
              Jobs.produce_update_status(job, reason, 500)
          end
      end
    else
      nil ->
        Jobs.produce_update_status(job, "Service request with id '#{id}' is not found", 404)

      {_, :status} ->
        Jobs.produce_update_status(job, "Invalid service request status", 409)

      {_, :used_by_another_legal_entity} ->
        Jobs.produce_update_status(job, "Service request is used by another legal entity", 409)
    end
  end

  def consume_process_service_request(
        %ServiceRequestProcessJob{
          patient_id: patient_id,
          user_id: user_id,
          client_id: client_id,
          service_request_id: id
        } = job
      ) do
    now = DateTime.utc_now()

    with {:ok, %ServiceRequest{} = service_request} <- ServiceRequests.get_by_id(id),
         {true, _} <- {service_request.status == ServiceRequest.status(:active), :status},
         {true, _} <-
           {get_reference_value(service_request.used_by_legal_entity) == client_id, :used_by_another_legal_entity} do
      changeset =
        ServiceRequest.process_changeset(
          service_request,
          %{
            "updated_by" => user_id,
            "updated_at" => now,
            "status" => ServiceRequest.status(:in_progress)
          }
        )

      case changeset do
        %Changeset{valid?: false} ->
          Jobs.produce_update_status(job, ValidationError.render("422.json", changeset), 422)

        _ ->
          service_request = Changeset.apply_changes(changeset)

          set = %{
            "updated_by" => service_request.updated_by,
            "updated_at" => service_request.updated_at,
            "status" => service_request.status
          }

          status_history =
            StatusHistory.create(%{
              "status" => service_request.status,
              "inserted_at" => service_request.updated_at,
              "inserted_by" => Mongo.string_to_uuid(service_request.updated_by)
            })

          push = Mongo.add_to_push(%{}, status_history, "status_history")

          result =
            %Transaction{actor_id: user_id, patient_id: job.patient_id_hash}
            |> Transaction.add_operation(
              @collection,
              :update,
              %{"_id" => service_request._id},
              %{
                "$set" => set,
                "$push" => push
              },
              service_request._id
            )
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
              Jobs.produce_update_status(job, reason, 500)
          end
      end
    else
      nil ->
        Jobs.produce_update_status(job, "Service request with id '#{id}' is not found", 404)

      {_, :status} ->
        Jobs.produce_update_status(job, "Invalid service request status", 409)

      {_, :used_by_another_legal_entity} ->
        Jobs.produce_update_status(job, "Service request is used by another legal entity", 409)
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
      {:error, error} =
        Error.dump(%CoreValidationError{
          description: "Signed content doesn't match with previously created service request",
          path: "$.signed_data"
        })

      {:error, ValidationError.render("422.json", %{schema: error}), 422}
    else
      :ok
    end
  end

  defp update_reference_uuid(nil), do: nil

  defp update_reference_uuid(value) do
    %{
      value
      | identifier: %{
          value.identifier
          | value: Mongo.string_to_uuid(value.identifier.value)
        }
    }
  end

  defp get_reference_value(nil), do: nil
  defp get_reference_value(value), do: to_string(value.identifier.value)
end
