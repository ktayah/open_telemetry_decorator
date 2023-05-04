defmodule OpenTelemetryDecorator.AttributesTest do
  use ExUnit.Case, async: true

  alias OpenTelemetryDecorator.Attributes

  describe "take_attrs" do
    setup do
      prev = Application.get_env(:open_telemetry_decorator, :attr_joiner)
      Application.put_env(:open_telemetry_decorator, :attr_joiner, "_")
      on_exit(fn -> Application.put_env(:open_telemetry_decorator, :attr_joiner, prev) end)
    end

    test "handles flat attributes" do
      assert Attributes.get([id: 1], [:id]) == [id: 1]
    end

    test "handles nested attributes" do
      assert Attributes.get([obj: %{id: 1}], [[:obj, :id]]) == [obj_id: 1]
    end

    test "handles flat and nested attributes" do
      attrs = Attributes.get([error: "whoops", obj: %{id: 1}], [:error, [:obj, :id]])
      assert attrs == [{:obj_id, 1}, {:error, "whoops"}]
    end

    test "handles nested reference into :result" do
      attrs = Attributes.get([obj: %{id: 1}, result: %{a: "b"}], [[:result, :a]])
      assert attrs == [result_a: "b"]
    end

    test "handles nested access into string-key maps" do
      attrs =
        Attributes.get([obj: %{"id" => 1}, result: %{"a" => "b"}], [[:obj, "id"], [:result, "a"]])

      assert attrs == [{:result_a, "b"}, {:obj_id, 1}]
    end

    test "when target value is valid OTLP type, use it" do
      assert [{:val, 42.42}] == Attributes.get([val: 42.42], [:val])
      assert [{:val, true}] == Attributes.get([val: true], [:val])
      assert [{:val, 42}] == Attributes.get([val: 42], [:val])
      assert [{:val, "a string"}] == Attributes.get([val: "a string"], [:val])
    end

    test "when target value is falsy, don't return (OTLP doesn't save these attributes)" do
      assert [] == Attributes.get([val: false], [:val])
      assert [] == Attributes.get([val: nil], [:val])
    end

    test "when target value is NOT a valid OTLP type, fall back to `inspect`" do
      assert [{:val, ":atom"}] == Attributes.get([val: :atom], [:val])
      assert [{:val, "{:ok, 1}"}] == Attributes.get([val: {:ok, 1}], [:val])
      assert [{:val, "[1, 2, 3, 4]"}] == Attributes.get([val: [1, 2, 3, 4]], [:val])
      assert [{:obj_id, 1}] == Attributes.get([obj: %{id: 1}], [[:obj, :id]])
      assert [{:obj, "%{id: 1}"}] == Attributes.get([obj: %{id: 1}], [:obj])
    end

    test "can take the top level element and a nested attribute, using `inspect` for non-valid values" do
      attrs = Attributes.get([obj: %{id: 1}], [:obj, [:obj, :id]])
      assert attrs == [{:obj_id, 1}, {:obj, "%{id: 1}"}]
    end

    test "does not return nested attribute values for objects that are not nested" do
      attrs = Attributes.get([not_obj: 1], [[:not_obj, :id]])
      assert attrs == []
    end

    test "does not return nested attribute values for objects that do not exist" do
      attrs = Attributes.get([obj: %{id: 1}], [[:not_obj, :id]])
      assert attrs == []
    end

    test "handles multiply nested attributes" do
      attrs = Attributes.get([obj: %{user: %{id: 2}}], [[:obj, :user, :id]])

      assert attrs == [obj_user_id: 2]

      attrs =
        Attributes.get(
          [obj: %{user: %{track: %{id: 3}}}],
          [[:obj, :user, :track, :id]]
        )

      assert attrs == [obj_user_track_id: 3]
    end

    test "does not add attribute if missing" do
      attrs = Attributes.get([obj: %{}], [[:obj, :id]])
      assert attrs == []

      attrs = Attributes.get([], [[:obj, :id]])
      assert attrs == []
    end

    test "does not add attribute if object is nil" do
      assert Attributes.get([obj: nil], [[:obj, :id]]) == []
    end
  end

  describe "overriding nested attrs join character" do
    setup do
      prev = Application.get_env(:open_telemetry_decorator, :attr_joiner)
      Application.put_env(:open_telemetry_decorator, :attr_joiner, ".")
      on_exit(fn -> Application.put_env(:open_telemetry_decorator, :attr_joiner, prev) end)
    end

    test "when joiner is configured, joins nested attributes with the joiner character" do
      assert Attributes.get([obj: %{id: 1}], [[:obj, :id]]) == ["obj.id": 1]
    end
  end

  describe "maybe_add_result" do
    test "when :result is given, adds result to the list" do
      attrs = Attributes.get([result: {:ok, "include me"}], [:result])
      assert attrs == [result: "{:ok, \"include me\"}"]

      attrs = Attributes.get([result: {:ok, "include me"}, id: 10], [:result, :id])

      assert attrs == [{:id, 10}, {:result, "{:ok, \"include me\"}"}]
    end

    test "when :result is missing, does not add result to the list" do
      attrs = Attributes.get([result: {:ok, "include me"}], [])
      assert attrs == []

      attrs = Attributes.get([result: {:ok, "include me"}, name: "blah"], [:name])

      assert attrs == [name: "blah"]
    end
  end

  describe "remove_underscores" do
    test "removes underscores from keys" do
      assert Attributes.get([_id: 1], [:_id]) == [id: 1]

      attrs = Attributes.get([_id: 1, _name: "asd"], [:_id, :_name])
      assert attrs == [name: "asd", id: 1]
    end

    test "doesn't modify keys without underscores" do
      attrs = Attributes.get([_id: 1, name: "asd"], [:_id, :name])
      assert attrs == [name: "asd", id: 1]
    end
  end

  describe "maybe_prefix with prefix that can be converted to an atom" do
    setup do
      prev = Application.get_env(:open_telemetry_decorator, :attr_prefix)
      Application.put_env(:open_telemetry_decorator, :attr_prefix, "my_")
      on_exit(fn -> Application.put_env(:open_telemetry_decorator, :attr_prefix, prev) end)
    end

    test "when prefix is configured, prefixes attribute names" do
      assert Attributes.get([id: 1], [:id]) == [my_id: 1]
    end
  end

  describe "maybe_prefix with prefix that cannot be converted to an atom" do
    setup do
      prev = Application.get_env(:open_telemetry_decorator, :attr_prefix)
      Application.put_env(:open_telemetry_decorator, :attr_prefix, "my.")
      on_exit(fn -> Application.put_env(:open_telemetry_decorator, :attr_prefix, prev) end)
    end

    test "when prefix is configured, prefixes attribute names" do
      assert Attributes.get([id: 1], [:id]) == ["my.id": 1]
    end
  end
end
