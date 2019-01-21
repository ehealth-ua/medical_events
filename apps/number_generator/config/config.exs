# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :number_generator, NumberGenerator.Generator, key: {:system, "NUMBER_GENERATOR_KEY", "random"}

import_config "#{Mix.env()}.exs"
