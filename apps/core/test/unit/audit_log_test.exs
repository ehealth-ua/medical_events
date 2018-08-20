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
      assert {:ok, %{inserted_id: id}} = CoreMongo.insert_one(patient)
      assert %{"_id" => id} = CoreMongo.find_one("patients", %{"_id" => id})

      assert_audit_log(id, @insert, "patients")
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

      doc = %{"title" => "the one"}
      assert {:ok, %{inserted_id: id}} = CoreMongo.insert_one(@test_collection, doc, [])

      assert %{"_id" => _, "title" => "the one"} = CoreMongo.find_one(@test_collection, %{"_id" => id})

      assert_audit_log(id, @insert)
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

      assert %{inserted_id: id} = CoreMongo.insert_one!(@test_collection, %{"title" => "the one"}, [])
      assert %{"_id" => _, "title" => "the one"} = CoreMongo.find_one(@test_collection, %{"_id" => id})
      assert_audit_log(id, @insert)
    end

    test "insert_many" do
      docs = [
        %{"title" => "one"},
        %{"title" => "two"}
      ]

      assert {:ok, %{inserted_ids: inserted_ids}} = CoreMongo.insert_many(@test_collection, docs)
      assert 2 == map_size(inserted_ids)

      assert %{"_id" => _, "title" => "one"} = CoreMongo.find_one(@test_collection, %{"_id" => inserted_ids[0]})
      assert %{"_id" => _, "title" => "two"} = CoreMongo.find_one(@test_collection, %{"_id" => inserted_ids[1]})
    end
  end

  describe "UPDATE operations" do
    setup do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      doc = %{"title" => "update one"}
      assert {:ok, %{inserted_id: id}} = CoreMongo.insert_one(@test_collection, doc, [])

      {:ok, id: id}
    end

    test "update_one", %{id: id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{"$set": %{title: "update two"}} == event.params
        assert %{"_id" => id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      assert {:ok, _} = CoreMongo.update_one(@test_collection, %{"_id" => id}, %{"$set": %{title: "update two"}})
      assert %{"_id" => _, "title" => "update two"} = CoreMongo.find_one(@test_collection, %{"_id" => id})
      assert_audit_log(id, @update)
    end

    test "update_one!", %{id: id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{"$set": %{title: "update two"}} == event.params
        assert %{"_id" => id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      CoreMongo.update_one!(@test_collection, %{"_id" => id}, %{"$set": %{title: "update two"}})
      assert %{"_id" => _, "title" => "update two"} = CoreMongo.find_one(@test_collection, %{"_id" => id})
      assert_audit_log(id, @update)
    end

    test "replace_one", %{id: id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{replaced: "title"} == event.params
        assert %{"_id" => id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      assert {:ok, _} = CoreMongo.replace_one(@test_collection, %{"_id" => id}, %{replaced: "title"})
      assert %{"_id" => _, "replaced" => "title"} = CoreMongo.find_one(@test_collection, %{"_id" => id})
      assert_audit_log(id, @update)
    end

    test "replace_one!", %{id: id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{replaced: "title"} == event.params
        assert %{"_id" => id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      CoreMongo.replace_one!(@test_collection, %{"_id" => id}, %{replaced: "title"})
      assert %{"_id" => _, "replaced" => "title"} = CoreMongo.find_one(@test_collection, %{"_id" => id})
      assert_audit_log(id, @update)
    end

    test "find_one_and_update", %{id: id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{"$set": %{title: "update two"}} == event.params
        assert %{"_id" => id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      assert {:ok, _} =
               CoreMongo.find_one_and_update(@test_collection, %{"_id" => id}, %{"$set": %{title: "update two"}})

      assert %{"_id" => _, "title" => "update two"} = CoreMongo.find_one(@test_collection, %{"_id" => id})
      assert_audit_log(id, @update)
    end

    test "find_one_and_replace", %{id: id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @update == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        assert %{replaced: "field"} == event.params
        assert %{"_id" => id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      assert CoreMongo.find_one_and_replace(@test_collection, %{"_id" => id}, %{replaced: "field"})

      assert %{"_id" => _, "replaced" => "field"} = CoreMongo.find_one(@test_collection, %{"_id" => id})
      assert_audit_log(id, @update)
    end

    test "find_one_and_replace when document not found", _ do
      assert {:ok, nil} =
               CoreMongo.find_one_and_replace(@test_collection, %{"_id" => "not found"}, %{title: "not found"})
    end
  end

  describe "DELETE operations" do
    setup do
      expect(KafkaMock, :publish_mongo_event, fn _event -> :ok end)

      doc = %{"title" => "delete one"}
      assert {:ok, %{inserted_id: id}} = CoreMongo.insert_one(@test_collection, doc, [])

      {:ok, id: id}
    end

    test "delete_one", %{id: id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @delete == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        refute event.params
        assert %{"_id" => id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      assert {:ok, _} = CoreMongo.delete_one(@test_collection, %{"_id" => id})
      refute CoreMongo.find_one(@test_collection, %{"_id" => id})

      assert_audit_log(id, @delete)
    end

    test "delete_one!", %{id: id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @delete == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        refute event.params
        assert %{"_id" => id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      assert CoreMongo.delete_one!(@test_collection, %{"_id" => id})
      refute CoreMongo.find_one(@test_collection, %{"_id" => id})

      assert_audit_log(id, @delete)
    end

    test "find_one_and_delete", %{id: id} do
      expect(KafkaMock, :publish_mongo_event, fn event ->
        assert Event == event.__struct__
        assert @delete == event.type
        assert id == event.entry_id
        assert @test_collection == event.collection
        refute event.params
        assert %{"_id" => id} = event.filter

        emulate_kafka_consumer(event)
        :ok
      end)

      assert CoreMongo.find_one_and_delete(@test_collection, %{"_id" => id})
      refute CoreMongo.find_one(@test_collection, %{"_id" => id})

      assert_audit_log(id, @delete)
    end

    test "find_one_and_delete when document not found", _ do
      assert {:ok, nil} == CoreMongo.find_one_and_delete(@test_collection, %{"_id" => "not-found"})
    end
  end

  defp emulate_kafka_consumer(event) do
    assert {:ok, _} = AuditLog.store_event(event)
  end

  defp assert_audit_log(entry_id, type, collection \\ @test_collection) do
    log_entry = Mongo.find_one(:mongo_audit_log, @audit_log_collection, %{entry_id: entry_id}, pool: Poolboy)
    assert log_entry
    assert entry_id == log_entry["entry_id"]
    assert type == log_entry["type"]
    assert collection == log_entry["collection"]
  end
end
