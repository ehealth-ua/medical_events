defmodule Core.Patients.Episodes.Consumer do
  @moduledoc false

  alias Core.Encounter
  alias Core.Episode
  alias Core.Job
  alias Core.Jobs
  alias Core.Jobs.EpisodeCancelJob
  alias Core.Jobs.EpisodeCloseJob
  alias Core.Jobs.EpisodeCreateJob
  alias Core.Jobs.EpisodeUpdateJob
  alias Core.Mongo
  alias Core.Mongo.Transaction
  alias Core.Patient
  alias Core.Patients.Encounters
  alias Core.Patients.Episodes
  alias Core.StatusHistory
  alias Core.ValidationError, as: CoreValidationError
  alias Core.Validators.Error
  alias Ecto.Changeset
  alias EView.Views.ValidationError
  require Logger

  @collection Patient.collection()

  def consume_create_episode(
        %EpisodeCreateJob{
          patient_id_hash: patient_id_hash,
          client_id: client_id
        } = job
      ) do
    now = DateTime.utc_now()
    episode = %Episode{}

    params =
      job
      |> Map.take(episode |> Map.from_struct() |> Map.keys())
      |> Map.merge(%{
        inserted_at: now,
        updated_at: now,
        inserted_by: job.user_id,
        updated_by: job.user_id,
        status_history: [
          %{
            status: job.status,
            status_reason: nil,
            inserted_at: now,
            inserted_by: job.user_id
          }
        ]
      })
      |> Map.put(:period, prepare_period(job.period))

    case Episode.create_changeset(episode, params, client_id) do
      %Changeset{valid?: true} = changeset ->
        case Episodes.get_by_id(patient_id_hash, Changeset.get_change(changeset, :id)) do
          {:ok, _} ->
            {:error, error} =
              Error.dump(%CoreValidationError{
                description: "Episode with such id already exists",
                path: "$.id"
              })

            Jobs.produce_update_status(job, ValidationError.render("422.json", %{schema: error}), 422)

          _ ->
            episode =
              changeset
              |> Changeset.apply_changes()
              |> fill_up_episode_care_manager()
              |> fill_up_episode_managing_organization()

            set = Mongo.add_to_set(%{"updated_by" => episode.updated_by}, episode, "episodes.#{episode.id}")
            save(job, episode.id, %{"$set" => set})
        end

      changeset ->
        Jobs.produce_update_status(job, ValidationError.render("422.json", changeset), 422)
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
      changes =
        job.request_params
        |> Map.take(~w(name care_manager))
        |> Map.merge(%{"updated_by" => job.user_id, "updated_at" => now})

      case Episode.update_changeset(episode, changes, client_id) do
        %Changeset{valid?: true} = changeset ->
          episode =
            changeset
            |> Changeset.apply_changes()
            |> fill_up_episode_care_manager()
            |> fill_up_episode_managing_organization()

          set =
            %{"updated_by" => episode.updated_by, "updated_at" => now}
            |> Mongo.add_to_set(episode.care_manager, "episodes.#{episode.id}.care_manager")
            |> Mongo.add_to_set(episode.name, "episodes.#{episode.id}.name")
            |> Mongo.add_to_set(episode.updated_by, "episodes.#{episode.id}.updated_by")
            |> Mongo.add_to_set(now, "episodes.#{episode.id}.updated_at")

          %Transaction{actor_id: job.user_id, patient_id: patient_id_hash}
          |> Transaction.add_operation(
            @collection,
            :update,
            %{"_id" => patient_id_hash},
            %{
              "$set" => set
            },
            patient_id_hash
          )
          |> Jobs.update(
            job._id,
            Job.status(:processed),
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
          |> Jobs.complete(job)

        changeset ->
          Jobs.produce_update_status(job, ValidationError.render("422.json", changeset), 422)
      end
    else
      {:ok, %Episode{status: status}} ->
        Jobs.produce_update_status(job, "Episode in status #{status} can not be updated", 409)

      nil ->
        Jobs.produce_update_status(job, "Failed to get episode", 404)
    end
  end

  def consume_close_episode(%EpisodeCloseJob{patient_id: patient_id, patient_id_hash: patient_id_hash, id: id} = job) do
    now = DateTime.utc_now()
    status = Episode.status(:active)
    period_end = job.request_params["period"]["end"]

    with {:ok, %Episode{status: ^status} = episode} <- Episodes.get_by_id(patient_id_hash, id),
         {_, true} <- {:managing_organization, episode.managing_organization.identifier.value == job.client_id},
         {_, true} <-
           {:period_end, Date.compare(DateTime.to_date(episode.period.start), Date.from_iso8601!(period_end)) != :gt} do
      changes =
        job.request_params
        |> Map.take(~w(closing_summary status_reason))
        |> Map.merge(%{
          "status" => Episode.status(:closed),
          "updated_by" => job.user_id,
          "updated_at" => now,
          "period" => prepare_period(%{"end" => period_end})
        })

      case Episode.close_changeset(episode, changes) do
        %Changeset{valid?: true} = changeset ->
          episode = Changeset.apply_changes(changeset)

          set =
            %{"updated_by" => episode.updated_by, "updated_at" => now}
            |> Mongo.add_to_set(episode.status, "episodes.#{episode.id}.status")
            |> Mongo.add_to_set(episode.status_reason, "episodes.#{episode.id}.status_reason")
            |> Mongo.add_to_set(episode.closing_summary, "episodes.#{episode.id}.closing_summary")
            |> Mongo.add_to_set(episode.period.end, "episodes.#{episode.id}.period.end")
            |> Mongo.add_to_set(episode.updated_by, "episodes.#{episode.id}.updated_by")
            |> Mongo.add_to_set(now, "episodes.#{episode.id}.updated_at")

          status_history =
            StatusHistory.create(%{
              "status" => episode.status,
              "status_reason" => changes["status_reason"],
              "inserted_at" => episode.updated_at,
              "inserted_by" => episode.updated_by
            })

          push = Mongo.add_to_push(%{}, status_history, "episodes.#{episode.id}.status_history")

          %Transaction{actor_id: job.user_id, patient_id: patient_id_hash}
          |> Transaction.add_operation(
            @collection,
            :update,
            %{"_id" => patient_id_hash},
            %{
              "$set" => set,
              "$push" => push
            },
            patient_id_hash
          )
          |> Jobs.update(
            job._id,
            Job.status(:processed),
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
          |> Jobs.complete(job)

        changeset ->
          Jobs.produce_update_status(job, ValidationError.render("422.json", changeset), 422)
      end
    else
      {:period_end, _} ->
        {:error, error} =
          Error.dump(%CoreValidationError{
            description: "End date must be greater or equal than start date",
            path: "$.period.end"
          })

        Jobs.produce_update_status(job, ValidationError.render("422.json", %{schema: error}), 422)

      {:managing_organization, _} ->
        Jobs.produce_update_status(job, "Managing_organization does not correspond to user's legal_entity", 409)

      {:ok, %Episode{status: status}} ->
        Jobs.produce_update_status(job, "Episode in status #{status} can not be closed", 409)

      nil ->
        Jobs.produce_update_status(job, "Failed to get episode", 404)
    end
  end

  def consume_cancel_episode(
        %EpisodeCancelJob{
          patient_id: patient_id,
          patient_id_hash: patient_id_hash,
          id: id
        } = job
      ) do
    now = DateTime.utc_now()

    with {:ok, %Episode{} = episode} <- Episodes.get_by_id(patient_id_hash, id),
         :ok <-
           validate_status(
             episode,
             [Episode.status(:active), Episode.status(:closed)],
             fn status ->
               "Episode in status #{status} can not be canceled"
             end
           ),
         {true, _} <- {episode.managing_organization.identifier.value == job.client_id, :managing_organization} do
      changes =
        job.request_params
        |> Map.take(~w(explanatory_letter status_reason))
        |> Map.merge(%{
          "status" => Episode.status(:cancelled),
          "updated_by" => job.user_id,
          "updated_at" => now
        })

      case Episode.cancel_changeset(episode, changes) do
        %Changeset{valid?: true} = changeset ->
          episode = Changeset.apply_changes(changeset)

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
              |> Mongo.add_to_set(
                episode.explanatory_letter,
                "episodes.#{episode.id}.explanatory_letter"
              )
              |> Mongo.add_to_set(
                episode.status_reason,
                "episodes.#{episode.id}.status_reason"
              )

            status_history =
              StatusHistory.create(%{
                "status" => episode.status,
                "status_reason" => changes["status_reason"],
                "inserted_at" => episode.updated_at,
                "inserted_by" => episode.updated_by
              })

            push = Mongo.add_to_push(%{}, status_history, "episodes.#{episode.id}.status_history")

            %Transaction{actor_id: job.user_id, patient_id: patient_id_hash}
            |> Transaction.add_operation(
              @collection,
              :update,
              %{"_id" => patient_id_hash},
              %{
                "$set" => set,
                "$push" => push
              },
              patient_id_hash
            )
            |> Jobs.update(
              job._id,
              Job.status(:processed),
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
            |> Jobs.complete(job)
          else
            Jobs.produce_update_status(job, "Episode can not be canceled while it has not canceled encounters", 409)
          end

        changeset ->
          Jobs.produce_update_status(job, ValidationError.render("422.json", changeset), 422)
      end
    else
      {_, :managing_organization} ->
        Jobs.produce_update_status(job, "Managing_organization does not correspond to user's legal_entity", 409)

      {:error, message} ->
        Jobs.produce_update_status(job, message, 409)

      nil ->
        Jobs.produce_update_status(job, "Failed to get episode", 404)
    end
  end

  defp save(job, episode_id, set) do
    %Transaction{actor_id: job.user_id, patient_id: job.patient_id_hash}
    |> Transaction.add_operation(@collection, :update, %{"_id" => job.patient_id_hash}, set, job.patient_id_hash)
    |> Jobs.update(
      job._id,
      Job.status(:processed),
      %{
        "links" => [
          %{
            "entity" => "episode",
            "href" => "/api/patients/#{job.patient_id}/episodes/#{episode_id}"
          }
        ]
      },
      200
    )
    |> Jobs.complete(job)
  end

  defp validate_status(%Episode{status: status}, statuses, message) when is_list(statuses) do
    if status in statuses do
      :ok
    else
      {:error, message.(status)}
    end
  end

  defp prepare_period(data) do
    Enum.into(data, %{}, fn
      {k, v} when is_binary(v) ->
        {k, v <> "T00:00:00.0Z"}

      {k, v} ->
        {k, v}
    end)
  end

  defp fill_up_episode_care_manager(%Episode{care_manager: care_manager} = episode) do
    with [{_, employee}] <-
           :ets.lookup(:message_cache, "employee_#{care_manager.identifier.value}") do
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
    with [{_, legal_entity}] <-
           :ets.lookup(:message_cache, "legal_entity_#{managing_organization.identifier.value}") do
      %{
        episode
        | managing_organization: %{
            managing_organization
            | display_value: Map.get(legal_entity, :public_name)
          }
      }
    else
      _ ->
        Logger.warn("Failed to fill up legal_entity value for episode")
        episode
    end
  end
end
