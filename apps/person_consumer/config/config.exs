# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :kaffe,
  consumer: [
    endpoints: [localhost: 9092],
    topics: ["person_events"],
    consumer_group: "person_events_group",
    message_handler: PersonConsumer.Kafka.PersonEventConsumer
  ]

import_config "#{Mix.env()}.exs"
