defmodule Core.Behaviours.KafkaProducerBehaviour do
  @moduledoc false

  alias Core.Mongo.Event

  @callback publish_medical_event(request :: any) ::
              :ok
              | {:ok, integer}
              | {:error, :closed}
              | {:error, :inet.posix()}
              | {:error, any}
              | iodata
              | :leader_not_available

  @callback publish_encounter_package_event(event :: any) ::
              :ok
              | {:ok, integer}
              | {:error, :closed}
              | {:error, :inet.posix()}
              | {:error, any}
              | iodata
              | :leader_not_available

  @callback publish_mongo_event(event :: Event.t()) ::
              :ok
              | {:ok, integer}
              | {:error, :closed}
              | {:error, :inet.posix()}
              | {:error, any}
              | iodata
              | :leader_not_available
end
