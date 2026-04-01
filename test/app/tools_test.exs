defmodule App.ToolsTest do
  use App.DataCase, async: true

  alias App.Tools

  import App.ToolsFixtures
  import App.UsersFixtures

  setup do
    user = user_fixture()
    scope = user_scope_fixture(user)

    %{user: user, scope: scope}
  end

  describe "create_tool/2" do
    test "creates an http tool with fixed and runtime params", %{scope: scope} do
      assert {:ok, tool} = Tools.create_tool(scope, tool_attrs())

      assert tool.name == "brave_search"
      assert tool.http_method == "get"
      assert tool.static_headers == %{"authorization" => "Bearer secret-key"}

      assert tool.parameter_definitions == %{
               "items" => [
                 %{"name" => "query", "source" => "llm", "type" => "string"},
                 %{
                   "name" => "safe_search",
                   "source" => "fixed",
                   "type" => "boolean",
                   "value" => true
                 }
               ]
             }
    end

    test "rejects duplicate tool names for the same user", %{scope: scope} do
      assert {:ok, _tool} = Tools.create_tool(scope, tool_attrs())

      assert {:error, changeset} =
               Tools.create_tool(scope, tool_attrs(%{description: "Duplicate"}))

      assert "has already been taken" in errors_on(changeset).name
    end

    test "requires endpoint placeholders to exist as params", %{scope: scope} do
      assert {:error, changeset} =
               Tools.create_tool(scope, %{
                 "name" => "reader",
                 "description" => "Reads content",
                 "endpoint" => "https://r.jina.ai/{dynamic_path}",
                 "http_method" => "get",
                 "param_rows" => [
                   %{"name" => "query", "type" => "string", "source" => "llm", "value" => ""}
                 ]
               })

      assert "template placeholders must match parameter names: dynamic_path" in errors_on(
               changeset
             ).endpoint
    end
  end

  describe "list_tool_names/1" do
    test "returns only current user tool names", %{scope: scope, user: user} do
      _tool = tool_fixture(user, %{name: "alpha_lookup"})

      other_user = user_fixture()
      _other_tool = tool_fixture(other_user, %{name: "other_lookup"})

      assert Tools.list_tool_names(scope) == ["alpha_lookup"]
    end
  end
end
