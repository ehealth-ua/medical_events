defmodule Core.Patients.Episodes.Consumer do
  @moduledoc false

  alias Core.CodeableConcept
  alias Core.DatePeriod
  alias Core.Encounter
  alias Core.Episode
  alias Core.Jobs
  alias Core.Jobs.EpisodeCancelJob
  alias Core.Jobs.EpisodeCloseJob
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Jobs.EpisodeUpdateJob
  alias Core.Jobs.ServiceRequestCloseJob
  alias Core.Mongo
  alias Core.Patient
  alias Core.Patients.Encounters
  alias Core.Patients.Episodes
  alias Core.Patients.Episodes.Validations, as: EpisodeValidations
  alias Core.Reference
  alias Core.StatusHistory
  alias Core.Validators.Vex
  alias EView.Views.ValidationError
  require Logger

  @collection Patient.metadata().collection
  @kafka_producer Application.get_env(:core, :kafka)[:producer]

  def consume_create_episode(
        %EpisodeCreateJob{
          patient_id: patient_id,
          patient_id_hash: patient_id_hash,
          client_id: client_id
        } = job
      ) do
    now = DateTime.utc_now()

    episode =
      job
      |> Map.from_struct()
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Episode.create()

    status_history =
      StatusHistory.create(%{
        "status" => episode.status,
        "status_reason" => episode.status_reason,
        "inserted_at" => now,
        "inserted_by" => Mongo.string_to_uuid(job.user_id)
      })

    episode =
      %{
        episode
        | status_history: [],
          diagnoses_history: [],
          inserted_by: job.user_id,
          updated_by: job.user_id,
          inserted_at: now,
          updated_at: now
      }
      |> Map.put(:status_history, [status_history])
      |> EpisodeValidations.validate_period()
      |> EpisodeValidations.validate_managing_organization(client_id)
      |> EpisodeValidations.validate_care_manager(client_id)
      |> EpisodeValidations.validate_referral_requests(client_id)

    episode_id = episode.id

    case Vex.errors(episode) do
      [] ->
        case Episodes.get_by_id(patient_id_hash, episode_id) do
          {:ok, _} ->
            Jobs.produce_update_status(
              job._id,
              job.request_id,
              "Episode with such id already exists",
              422
            )

          _ ->
            episode =
              episode
              |> fill_up_episode_care_manager()
              |> fill_up_episode_managing_organization()

            set =
              %{"updated_by" => episode.updated_by}
              |> Mongo.add_to_set(episode, "episodes.#{episode.id}")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.id")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.inserted_by")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.updated_by")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.care_manager.identifier.value")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.managing_organization.identifier.value")
              |> Mongo.convert_to_uuid("updated_by")

            {:ok, %{matched_count: 1, modified_count: 1}} =
              Mongo.update_one(@collection, %{"_id" => patient_id_hash}, %{"$set" => set})

            Jobs.produce_update_status(
              job._id,
              job.request_id,
              %{
                "links" => [
                  %{
                    "entity" => "episode",
                    "href" => "/api/patients/#{patient_id}/episodes/#{episode.id}"
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
  end

  def consume_update_episode(
        %EpisodeUpdateJob{
          patient_id: patient_id,
          patient_id_hash: patient_id_hash,
          id: id,
          client_id: client_id
        } = job
      ) do
    now = DateTime.utc_now()
    status = Episode.status(:active)

    with {:ok, %Episode{status: ^status} = episode} <- Episodes.get_by_id(patient_id_hash, id) do
      changes = Map.take(job.request_params, ~w(name care_manager referral_requests))

      existing_referral_request_ids =
        get_existing_referral_request_ids(episode.referral_requests, job.request_params["referral_requests"])

      episode =
        %{episode | updated_by: job.user_id, updated_at: now}
        |> Map.merge(Enum.into(changes, %{}, fn {k, v} -> {String.to_atom(k), v} end))
        |> EpisodeValidations.validate_care_manager(job.request_params["care_manager"], client_id)
        |> EpisodeValidations.validate_managing_organization(client_id)
        |> EpisodeValidations.validate_referral_requests(
          job.request_params["referral_requests"],
          client_id,
          existing_referral_request_ids
        )

      case Vex.errors(episode) do
        [] ->
          episode =
            episode
            |> fill_up_episode_care_manager()
            |> fill_up_episode_managing_organization()

          set =
            %{"updated_by" => episode.updated_by, "updated_at" => now}
            |> Mongo.add_to_set(episode.care_manager, "episodes.#{episode.id}.care_manager")
            |> Mongo.add_to_set(episode.name, "episodes.#{episode.id}.name")
            |> Mongo.add_to_set(episode.updated_by, "episodes.#{episode.id}.updated_by")
            |> Mongo.add_to_set(now, "episodes.#{episode.id}.updated_at")
            |> Mongo.add_to_set(episode.referral_requests, "episodes.#{episode.id}.referral_requests")
            |> Mongo.convert_to_uuid("episodes.#{episode.id}.updated_by")
            |> Mongo.convert_to_uuid("episodes.#{episode.id}.care_manager.identifier.value")
            |> Mongo.convert_to_uuid("updated_by")
            |> Mongo.convert_to_uuid("episodes.#{episode.id}.referral_requests", ~w(identifier value)a)

          {:ok, %{matched_count: 1, modified_count: 1}} =
            Mongo.update_one(@collection, %{"_id" => patient_id_hash}, %{"$set" => set})

          Jobs.produce_update_status(
            job._id,
            job.request_id,
            %{
              "links" => [
                %{
                  "entity" => "episode",
                  "href" => "/api/patients/#{patient_id}/episodes/#{episode.id}"
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
      {:ok, %Episode{status: status}} ->
        Jobs.produce_update_status(job._id, job.request_id, "Episode in status #{status} can not be updated", 422)

      nil ->
        Jobs.produce_update_status(job._id, job.request_id, "Failed to get episode", 404)
    end
  end

  def consume_close_episode(%EpisodeCloseJob{patient_id: patient_id, patient_id_hash: patient_id_hash, id: id} = job) do
    now = DateTime.utc_now()
    status = Episode.status(:active)

    with {:ok, %Episode{status: ^status} = episode} <- Episodes.get_by_id(patient_id_hash, id) do
      managing_organization = episode.managing_organization
      identifier = managing_organization.identifier

      new_period = DatePeriod.create(job.request_params["period"])
      changes = Map.take(job.request_params, ~w(closing_summary status_reason))

      episode =
        %{
          episode
          | status: Episode.status(:closed),
            updated_by: job.user_id,
            updated_at: now,
            period: %{episode.period | end: new_period.end},
            managing_organization: %{
              managing_organization
              | identifier: %{identifier | value: UUID.binary_to_string!(identifier.value.binary)}
            }
        }
        |> Map.merge(%{
          status_reason: CodeableConcept.create(changes["status_reason"]),
          closing_summary: changes["closing_summary"]
        })
        |> EpisodeValidations.validate_period()
        |> EpisodeValidations.validate_managing_organization(job.client_id)

      case Vex.errors(episode) do
        [] ->
          set =
            %{"updated_by" => episode.updated_by, "updated_at" => now}
            |> Mongo.add_to_set(episode.status, "episodes.#{episode.id}.status")
            |> Mongo.add_to_set(episode.status_reason, "episodes.#{episode.id}.status_reason")
            |> Mongo.add_to_set(episode.closing_summary, "episodes.#{episode.id}.closing_summary")
            |> Mongo.add_to_set(episode.period.end, "episodes.#{episode.id}.period.end")
            |> Mongo.add_to_set(episode.updated_by, "episodes.#{episode.id}.updated_by")
            |> Mongo.add_to_set(now, "episodes.#{episode.id}.updated_at")
            |> Mongo.convert_to_uuid("episodes.#{episode.id}.updated_by")
            |> Mongo.convert_to_uuid("updated_by")

          status_history =
            StatusHistory.create(%{
              "status" => episode.status,
              "status_reason" => changes["status_reason"],
              "inserted_at" => episode.updated_at,
              "inserted_by" => Mongo.string_to_uuid(episode.updated_by)
            })

          push = Mongo.add_to_push(%{}, status_history, "episodes.#{episode.id}.status_history")

          {:ok, %{matched_count: 1, modified_count: 1}} =
            Mongo.update_one(@collection, %{"_id" => patient_id_hash}, %{
              "$set" => set,
              "$push" => push
            })

          Enum.each(episode.referral_requests || [], fn referral_request ->
            with {:ok, _, close_service_request} <-
                   Jobs.create(
                     ServiceRequestCloseJob,
                     %{
                       "request_id" => job.request_id,
                       "patient_id" => job.patient_id,
                       "patient_id_hash" => job.patient_id_hash,
                       "id" => referral_request.identifier.value,
                       "user_id" => job.user_id,
                       "client_id" => job.client_id
                     }
                   ),
                 :ok <- @kafka_producer.publish_medical_event(close_service_request) do
              :ok
            end
          end)

          Jobs.produce_update_status(
            job._id,
            job.request_id,
            %{
              "links" => [
                %{
                  "entity" => "episode",
                  "href" => "/api/patients/#{patient_id}/episodes/#{episode.id}"
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
      {:ok, %Episode{status: status}} ->
        Jobs.produce_update_status(job._id, job.request_id, "Episode in status #{status} can not be closed", 422)

      nil ->
        Jobs.produce_update_status(job._id, job.request_id, "Failed to get episode", 404)
    end
  end

  def consume_cancel_episode(%EpisodeCancelJob{patient_id: patient_id, patient_id_hash: patient_id_hash, id: id} = job) do
    now = DateTime.utc_now()

    with {:ok, %Episode{} = episode} <- Episodes.get_by_id(patient_id_hash, id),
         :ok <-
           validate_status(episode, [Episode.status(:active), Episode.status(:closed)], fn status ->
             "Episode in status #{status} can not be canceled"
           end) do
      managing_organization = episode.managing_organization
      identifier = managing_organization.identifier

      changes = Map.take(job.request_params, ~w(explanatory_letter status_reason))

      episode =
        %{
          episode
          | status: Episode.status(:cancelled),
            updated_by: job.user_id,
            updated_at: now,
            managing_organization: %{
              managing_organization
              | identifier: %{identifier | value: UUID.binary_to_string!(identifier.value.binary)}
            }
        }
        |> Map.merge(%{
          status_reason: CodeableConcept.create(changes["status_reason"]),
          explanatory_letter: changes["explanatory_letter"]
        })
        |> EpisodeValidations.validate_managing_organization(job.client_id)

      case Vex.errors(episode) do
        [] ->
          all_encounters_canceled =
            patient_id_hash
            |> Encounters.get_episode_encounters(Mongo.string_to_uuid(id), %{
              "status" => "$encounters.v.status"
            })
            |> Enum.map(& &1["status"])
            |> Enum.all?(fn status -> status == Encounter.status(:entered_in_error) end)

          if all_encounters_canceled do
            set =
              %{"updated_by" => episode.updated_by, "updated_at" => now}
              |> Mongo.add_to_set(episode.status, "episodes.#{episode.id}.status")
              |> Mongo.add_to_set(episode.updated_by, "episodes.#{episode.id}.updated_by")
              |> Mongo.add_to_set(now, "episodes.#{episode.id}.updated_at")
              |> Mongo.convert_to_uuid("episodes.#{episode.id}.updated_by")
              |> Mongo.add_to_set(
                episode.explanatory_letter,
                "episodes.#{episode.id}.explanatory_letter"
              )
              |> Mongo.add_to_set(
                episode.status_reason,
                "episodes.#{episode.id}.status_reason"
              )
              |> Mongo.convert_to_uuid("updated_by")

            status_history =
              StatusHistory.create(%{
                "status" => episode.status,
                "status_reason" => changes["status_reason"],
                "inserted_at" => episode.updated_at,
                "inserted_by" => Mongo.string_to_uuid(episode.updated_by)
              })

            push = Mongo.add_to_push(%{}, status_history, "episodes.#{episode.id}.status_history")

            {:ok, %{matched_count: 1, modified_count: 1}} =
              Mongo.update_one(@collection, %{"_id" => patient_id_hash}, %{
                "$set" => set,
                "$push" => push
              })

            Jobs.produce_update_status(
              job._id,
              job.request_id,
              %{
                "links" => [
                  %{
                    "entity" => "episode",
                    "href" => "/api/patients/#{patient_id}/episodes/#{episode.id}"
                  }
                ]
              },
              200
            )
          else
            Jobs.produce_update_status(
              job._id,
              job.request_id,
              "Episode can not be canceled while it has not canceled encounters",
              409
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
      {:error, message} ->
        Jobs.produce_update_status(job._id, job.request_id, message, 422)

      nil ->
        Jobs.produce_update_status(job._id, job.request_id, "Failed to get episode", 404)
    end
  end

  defp validate_status(%Episode{status: status}, statuses, message) when is_list(statuses) do
    if status in statuses do
      :ok
    else
      {:error, message.(status)}
    end
  end

  defp fill_up_episode_care_manager(%Episode{care_manager: care_manager} = episode) do
    with [{_, employee}] <- :ets.lookup(:message_cache, "employee_#{care_manager.identifier.value}") do
      first_name = employee.party.first_name
      second_name = employee.party.second_name
      last_name = employee.party.last_name

      %{
        episode
        | care_manager: %{
            care_manager
            | display_value: "#{first_name} #{second_name} #{last_name}"
          }
      }
    else
      _ ->
        Logger.warn("Failed to fill up employee value for episode")
        episode
    end
  end

  defp fill_up_episode_managing_organization(%Episode{managing_organization: managing_organization} = episode) do
    with [{_, legal_entity}] <- :ets.lookup(:message_cache, "legal_entity_#{managing_organization.identifier.value}") do
      %{
        episode
        | managing_organization: %{
            managing_organization
            | display_value: Map.get(legal_entity, "public_name")
          }
      }
    else
      _ ->
        Logger.warn("Failed to fill up legal_entity value for episode")
        episode
    end
  end

  defp get_existing_referral_request_ids(episode_referral_requests, request_referral_requests) do
    episode_referral_requests_ids =
      Enum.map(episode_referral_requests, fn referral_request ->
        to_string(referral_request.identifier.value)
      end)

    request_referral_requests
    |> Enum.map(&get_in(&1, ~w(identifier value)))
    |> Enum.filter(&Enum.member?(episode_referral_requests_ids, &1))
  end
end
