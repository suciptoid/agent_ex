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
    assert Tools.available_tools() == ["web_fetch", "shell"]
  end

  test "resolve/1 returns configured ReqLLM tools" do
    [tool] = Tools.resolve(["web_fetch"])
    assert tool.name == "web_fetch"
  end

  test "resolve/2 includes custom tools for the current user", %{user: user} do
    tool = tool_fixture(user, %{name: "brave_search"})

    [resolved_tool] = Tools.resolve([tool.name], organization_id: tool.organization_id)
    assert resolved_tool.name == "brave_search"
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

    assert {:ok, "templated"} = ReqLLM.Tool.execute(tool, %{"dynamic_path" => "docs/file.txt"})
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

  test "execute_all/3 emits a running placeholder before returning the final tool result" do
    Req.Test.stub(__MODULE__, fn conn ->
      Plug.Conn.send_resp(conn, 200, "hello from the stub")
    end)

    [tool] = Tools.resolve(["web_fetch"])

    assert {:ok, %{results: [result]}} =
             Tools.execute_all(
               [%{id: "tool_1", name: "web_fetch", arguments: %{url: "https://example.test"}}],
               [tool],
               on_tool_start: fn tool_result -> send(self(), {:tool_started, tool_result}) end
             )

    assert_receive {:tool_started,
                    %{
                      "id" => "tool_1",
                      "name" => "web_fetch",
                      "content" => nil,
                      "status" => "running"
                    }}

    assert result["content"] == "hello from the stub"
    assert result["status"] == "ok"
  end

  test "do_shell/1 executes commands" do
    assert {:ok, "hello\n"} = Tools.do_shell(%{command: "printf 'hello\\n'"})
  end
end
