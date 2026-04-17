defmodule App.Agents.ToolsTest do
  use App.DataCase, async: false

  alias App.Agents.Tools

  import App.ToolsFixtures
  import App.UsersFixtures

  setup do
    previous_config = Application.get_env(:app, App.Agents.Tools)
    Application.put_env(:app, App.Agents.Tools, req_options: [plug: {Req.Test, __MODULE__}])

    user = user_fixture()

    on_exit(fn ->
      if previous_config do
        Application.put_env(:app, App.Agents.Tools, previous_config)
      else
        Application.delete_env(:app, App.Agents.Tools)
      end
    end)

    %{user: user}
  end

  test "available_tools/0 lists builtin tools" do
    assert Tools.available_tools() == ["web_fetch", "shell", "create_tool"]
  end

  test "resolve/1 returns configured Alloy tool modules" do
    [tool] = Tools.resolve(["web_fetch"])
    assert tool == App.Agents.AlloyTools.WebFetch
  end

  test "resolve/2 returns the create_tool builtin" do
    [tool] = Tools.resolve(["create_tool"], organization_id: Ecto.UUID.generate())
    assert tool == App.Agents.AlloyTools.CreateTool
  end

  test "resolve/2 includes custom tools for the current user", %{user: user} do
    tool = tool_fixture(user, %{name: "brave_search"})

    [resolved_tool] = Tools.resolve([tool.name], organization_id: tool.organization_id)
    assert is_atom(resolved_tool)
    assert Code.ensure_loaded?(resolved_tool)
    assert apply(resolved_tool, :name, []) == "brave_search"
  end

  test "custom tool templates can interpolate runtime path params", %{user: user} do
    _tool =
      tool_fixture(user, %{
        name: "jina_reader",
        endpoint: "https://example.test/{dynamic_path}",
        param_rows: [
          %{"name" => "dynamic_path", "type" => "string", "source" => "llm", "value" => ""},
          %{"name" => "safe_search", "type" => "boolean", "source" => "fixed", "value" => "true"}
        ]
      })

    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/docs/file.txt"
      assert conn.query_string == "safe_search=true"
      Plug.Conn.send_resp(conn, 200, "templated")
    end)

    [tool] =
      Tools.resolve(["jina_reader"], organization_id: user_scope_fixture(user).organization.id)

    assert is_atom(tool)

    assert {:ok, "templated"} =
             apply(tool, :execute, [%{"dynamic_path" => "docs/file.txt"}, %{}])
  end

  test "do_web_fetch/1 returns the response body on success" do
    Req.Test.stub(__MODULE__, fn conn ->
      Plug.Conn.send_resp(conn, 200, "hello from the stub")
    end)

    assert {:ok, "hello from the stub"} = Tools.do_web_fetch(%{url: "https://example.test"})
  end

  test "do_web_fetch/1 accepts optional headers" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer 123"]
      Plug.Conn.send_resp(conn, 200, "authorized")
    end)

    assert {:ok, "authorized"} =
             Tools.do_web_fetch(%{
               url: "https://example.test",
               headers: %{"authorization" => "Bearer 123"}
             })
  end

  test "do_web_fetch/1 surfaces non-success status codes" do
    Req.Test.stub(__MODULE__, fn conn ->
      Plug.Conn.send_resp(conn, 404, "missing")
    end)

    assert {:error, "HTTP 404"} = Tools.do_web_fetch(%{url: "https://example.test/missing"})
  end

  test "do_create_tool/2 persists a custom tool with the UI semantics", %{user: user} do
    scope = user_scope_fixture(user)

    assert {:ok, result} =
             Tools.do_create_tool(
               %{
                 name: "reader",
                 description: "Read a document",
                 endpoint: "https://example.test/{path}?safe_search=true",
                 http_method: "get",
                 param_rows: [
                   %{"name" => "path", "type" => "string", "value" => ""},
                   %{"name" => "page_size", "type" => "integer", "value" => "25"}
                 ],
                 header_rows: [
                   %{"key" => "authorization", "value" => "Bearer secret-key"}
                 ]
               },
               scope.organization.id
             )

    [tool] = App.Tools.list_tools(scope)
    path = Enum.find(App.Tools.Tool.parameter_items(tool), &(&1["name"] == "path"))
    page_size = Enum.find(App.Tools.Tool.parameter_items(tool), &(&1["name"] == "page_size"))

    assert path["source"] == "llm"
    assert page_size["source"] == "fixed"
    assert page_size["value"] == 25
    assert result.name == "reader"
    assert result.runtime_parameters == ["path"]
    assert result.fixed_parameters == ["page_size"]
    assert result.header_names == ["authorization"]
  end

  test "do_shell/1 executes commands" do
    assert {:ok, "hello\n"} = Tools.do_shell(%{command: "printf 'hello\\n'"})
  end
end
