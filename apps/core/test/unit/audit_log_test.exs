defmodule Core.AuditLogTest do
  @moduledoc """
  Test Mongo operations defined in Core.Mongo
  """
  use ExUnit.Case

  import Core.Factories
  import Mox

  alias DBConnection.Poolboy
  alias Core.Mongo, as: CoreMongo
  alias Core.Mongo.AuditLog
  alias Core.Mongo.Event

  setup :verify_on_exit!
  setup :set_mox_global

  @test_collection "test_core"
  @audit_log_collection Core.Mongo.AuditLog.collection()

  @insert "INSERT"
  @update "UPDATE"
  @delete "DELETE"

  describe "INSERT operations" do
    test "insert patient" do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @insert == event.type
        assert "patients" == event.collection
        assert is_map(event.params)
        refute event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      patient = build(:patient)
      actor_id = patient.updated_by
      assert {:ok, %{inserted_id: id}} = CoreMongo.insert_one(patient, actor_id: actor_id)
      assert %{"_id" => id} = CoreMongo.find_one("patients", %{"_id" => id})

      assert_audit_log(id, @insert, actor_id, "patients")
    end

    test "insert_one" do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @insert == event.type
        assert @test_collection == event.collection
        assert %{"title" => "the one"} == event.params
        refute event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      actor_id = UUID.uuid4()
      doc = %{"title" => "the one"}
      assert {:ok, %{inserted_id: id}} = CoreMongo.insert_one(@test_collection, doc, actor_id: actor_id)
      assert %{"_id" => _, "title" => "the one"} = CoreMongo.find_one(@test_collection, %{"_id" => id})

      assert_audit_log(id, @insert, actor_id)
    end

    test "insert_one!" do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @insert == event.type
        assert @test_collection == event.collection
        assert %{"title" => "the one"} == event.params
        refute event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      actor_id = UUID.uuid4()
      assert %{inserted_id: id} = CoreMongo.insert_one!(@test_collection, %{"title" => "the one"}, actor_id: actor_id)
      assert %{"_id" => _, "title" => "the one"} = CoreMongo.find_one(@test_collection, %{"_id" => id})
      assert_audit_log(id, @insert, actor_id)
    end

    test "insert_many" do
      docs = [
        %{"title" => "one"},
        %{"title" => "two"}
      ]

      assert {:ok, %{inserted_ids: inserted_ids}} = CoreMongo.insert_many(@test_collection, docs, [])
      assert 2 == map_size(inserted_ids)

      assert %{"_id" => _, "title" => "one"} = CoreMongo.find_one(@test_collection, %{"_id" => inserted_ids[0]})
      assert %{"_id" => _, "title" => "two"} = CoreMongo.find_one(@test_collection, %{"_id" => inserted_ids[1]})
    end

    test "update_one with upsert option" do
      id = UUID.uuid4()
      actor_id = UUID.uuid4()

      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @insert == event.type
        assert @test_collection == event.collection
        assert %{"$set" => %{"title" => "the one", "updated_by" => actor_id}} == event.params
        assert %{"_id" => id} == event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      CoreMongo.update_one(
        @test_collection,
        %{"_id" => id},
        %{"$set" => %{"title" => "the one", "updated_by" => actor_id}},
        upsert: true
      )

      assert %{"_id" => _, "title" => "the one"} = CoreMongo.find_one(@test_collection, %{"_id" => id})
      assert_audit_log(id, @insert, actor_id)
    end
  end

  describe "UPDATE operations" do
    setup do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      actor_id = UUID.uuid4()
      doc = %{"title" => "update one"}
      assert {:ok, %{inserted_id: id}} = CoreMongo.insert_one(@test_collection, doc, actor_id: actor_id)

      {:ok, id: id, actor_id: actor_id}
    end

    test "update_one", %{id: id, actor_id: actor_id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{"$set" => %{title: "update two"}} == event.params
        assert %{"_id" => ^id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      filter = %{"_id" => id}
      replacement = %{"$set" => %{title: "update two"}}
      assert {:ok, _} = CoreMongo.update_one(@test_collection, filter, replacement, actor_id: actor_id)
      assert %{"_id" => _, "title" => "update two"} = CoreMongo.find_one(@test_collection, %{"_id" => id})

      assert_audit_log(id, @update, actor_id)
    end

    test "update_one!", %{id: id, actor_id: actor_id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{"$set" => %{title: "update two"}} == event.params
        assert %{"_id" => ^id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      CoreMongo.update_one!(@test_collection, %{"_id" => id}, %{"$set" => %{title: "update two"}}, actor_id: actor_id)
      assert %{"_id" => _, "title" => "update two"} = CoreMongo.find_one(@test_collection, %{"_id" => id})
      assert_audit_log(id, @update, actor_id)
    end

    test "update_one with upsert option", %{id: id, actor_id: actor_id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{"$set" => %{title: "update two", updated_by: actor_id}} == event.params
        assert %{"_id" => ^id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      filter = %{"_id" => id}
      replacement = %{"$set" => %{title: "update two", updated_by: actor_id}}
      assert {:ok, _} = CoreMongo.update_one(@test_collection, filter, replacement, upsert: true)
      assert %{"_id" => _, "title" => "update two"} = CoreMongo.find_one(@test_collection, %{"_id" => id})

      assert_audit_log(id, @update, actor_id)
    end

    # Mongo or ExMongo always send nModified: 1 when expected 0.
    @tag :pending
    test "update without changes. Audit log entry not created", %{actor_id: actor_id} do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)
      doc = %{"title" => "unique"}
      assert {:ok, %{inserted_id: id}} = CoreMongo.insert_one(@test_collection, doc, actor_id: actor_id)

      filter = %{"_id" => id}
      replacement = %{"$set" => %{"title" => "unique"}}
      assert {:ok, _} = CoreMongo.update_one(@test_collection, filter, replacement, actor_id: actor_id)
      assert %{"_id" => _, "title" => "update one"} = CoreMongo.find_one(@test_collection, %{"_id" => id})
    end

    test "replace_one", %{id: id, actor_id: actor_id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{replaced: "title"} == event.params
        assert %{"_id" => ^id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      filter = %{"_id" => id}
      replacement = %{replaced: "title"}
      assert {:ok, _} = CoreMongo.replace_one(@test_collection, filter, replacement, actor_id: actor_id)
      assert %{"_id" => _, "replaced" => "title"} = CoreMongo.find_one(@test_collection, %{"_id" => id})

      assert_audit_log(id, @update, actor_id)
    end

    test "replace_one!", %{id: id, actor_id: actor_id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{replaced: "title"} == event.params
        assert %{"_id" => ^id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      CoreMongo.replace_one!(@test_collection, %{"_id" => id}, %{replaced: "title"}, actor_id: actor_id)
      assert %{"_id" => _, "replaced" => "title"} = CoreMongo.find_one(@test_collection, %{"_id" => id})
      assert_audit_log(id, @update, actor_id)
    end

    test "find_one_and_update", %{id: id, actor_id: actor_id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{"$set" => %{title: "update two"}} == event.params
        assert %{"_id" => ^id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      filter = %{"_id" => id}
      replacement = %{"$set" => %{title: "update two"}}
      assert {:ok, _} = CoreMongo.find_one_and_update(@test_collection, filter, replacement, actor_id: actor_id)
      assert %{"_id" => _, "title" => "update two"} = CoreMongo.find_one(@test_collection, %{"_id" => id})

      assert_audit_log(id, @update, actor_id)
    end

    test "find_one_and_update with upsert option" do
      id = UUID.uuid4()
      actor_id = UUID.uuid4()

      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        # so pity, but Mongo returns a map with document.
        # There is no chance to determine whether the document is inserted or updated
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{"$set" => %{title: "one", updated_by: actor_id}} == event.params
        assert %{"_id" => ^id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      filter = %{"_id" => id}
      replacement = %{"$set" => %{title: "one", updated_by: actor_id}}

      assert {:ok, _} = CoreMongo.find_one_and_update(@test_collection, filter, replacement, upsert: true)

      assert %{"_id" => _, "title" => "one"} = CoreMongo.find_one(@test_collection, %{"_id" => id})

      assert_audit_log(id, @update, actor_id)
    end

    test "find_one_and_replace", %{id: id, actor_id: actor_id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{replaced: "field"} == event.params
        assert %{"_id" => ^id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      assert CoreMongo.find_one_and_replace(@test_collection, %{"_id" => id}, %{replaced: "field"}, actor_id: actor_id)

      assert %{"_id" => _, "replaced" => "field"} = CoreMongo.find_one(@test_collection, %{"_id" => id})
      assert_audit_log(id, @update, actor_id)
    end

    test "find_one_and_replace with upsert option" do
      id = UUID.uuid4()
      actor_id = UUID.uuid4()

      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        # so pity, but Mongo returns a map with document.
        # There is no chance to determine whether the document is inserted or updated
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{"title" => "one", "updated_by" => actor_id} == event.params
        assert %{"_id" => ^id} = event.filter
        assert actor_id = event.actor_id

        emulate_kafka_consumer(event)
        :ok
      end)

      assert CoreMongo.find_one_and_replace(
               @test_collection,
               %{"_id" => id},
               %{
                 "title" => "one",
                 "updated_by" => actor_id
               },
               upsert: true
             )

      assert %{"_id" => _, "title" => "one"} = CoreMongo.find_one(@test_collection, %{"_id" => id})
      assert_audit_log(id, @update, actor_id)
    end

    test "find_one_and_replace when document not found", _ do
      assert {:ok, nil} =
               CoreMongo.find_one_and_replace(@test_collection, %{"_id" => "not found"}, %{title: "not found"})
    end
  end

  describe "DELETE operations" do
    setup do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      actor_id = UUID.uuid4()
      doc = %{"title" => "delete one"}
      assert {:ok, %{inserted_id: id}} = CoreMongo.insert_one(@test_collection, doc, actor_id: actor_id)

      {:ok, id: id, actor_id: actor_id}
    end

    test "delete_one", %{id: id, actor_id: actor_id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @delete == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        refute event.params
        assert %{"_id" => ^id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      assert {:ok, _} = CoreMongo.delete_one(@test_collection, %{"_id" => id}, actor_id: actor_id)
      refute CoreMongo.find_one(@test_collection, %{"_id" => id})

      assert_audit_log(id, @delete, actor_id)
    end

    test "delete_one!", %{id: id, actor_id: actor_id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @delete == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        refute event.params
        assert %{"_id" => ^id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      assert CoreMongo.delete_one!(@test_collection, %{"_id" => id}, actor_id: actor_id)
      refute CoreMongo.find_one(@test_collection, %{"_id" => id})

      assert_audit_log(id, @delete, actor_id)
    end

    test "find_one_and_delete", %{id: id, actor_id: actor_id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @delete == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        refute event.params
        assert %{"_id" => ^id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      assert CoreMongo.find_one_and_delete(@test_collection, %{"_id" => id}, actor_id: actor_id)
      refute CoreMongo.find_one(@test_collection, %{"_id" => id})

      assert_audit_log(id, @delete, actor_id)
    end

    test "find_one_and_delete when document not found", _ do
      assert {:ok, nil} == CoreMongo.find_one_and_delete(@test_collection, %{"_id" => "not-found"})
    end
  end

  describe "audit log list" do
    test "INSERT, UPDATE and DELETE patient" do
      stub(KafkaMock, :publish_mongo_event, fn event ->
        emulate_kafka_consumer(event)
        :ok
      end)

      patient = build(:patient)
      actor_id = patient.updated_by

      # actor_id fetched from data set
      assert {:ok, %{inserted_id: id}} = CoreMongo.insert_one(patient)

      # actor_id fetched from $set params
      replacement = %{"$set" => %{title: "update", updated_by: actor_id}}
      assert {:ok, _} = CoreMongo.update_one("patients", %{"_id" => id}, replacement)

      # actor_id fetched from opts
      assert CoreMongo.delete_one!("patients", %{"_id" => id}, actor_id: actor_id)

      opts = [orderby: %{inserted_at: 1}, pool: Poolboy]

      logs =
        :mongo_audit_log
        |> Mongo.find(@audit_log_collection, %{actor_id: actor_id}, opts)
        |> Enum.to_list()

      assert 3 = length(logs)
      assert @insert == Enum.at(logs, 0)["type"]
      assert @update == Enum.at(logs, 1)["type"]
      assert @delete == Enum.at(logs, 2)["type"]
    end
  end

  defp emulate_kafka_consumer(event) do
    assert :ok = AuditLog.store_event(event)
  end

  defp assert_audit_log(entry_id, type, actor_id, collection \\ @test_collection) do
    log_entry = Mongo.find_one(:mongo_audit_log, @audit_log_collection, %{entry_id: entry_id}, pool: Poolboy)
    assert log_entry
    assert entry_id == log_entry["entry_id"]
    assert type == log_entry["type"]
    assert collection == log_entry["collection"]
    assert actor_id == log_entry["actor_id"]
  end
end
