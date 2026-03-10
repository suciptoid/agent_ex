defmodule App.Agents.ToolsTest do
  use ExUnit.Case, async: false

  alias App.Agents.Tools

  setup do
    previous_config = Application.get_env(:app, App.Agents.Tools)
    Application.put_env(:app, App.Agents.Tools, req_options: [plug: {Req.Test, __MODULE__}])

    on_exit(fn ->
      if previous_config do
        Application.put_env(:app, App.Agents.Tools, previous_config)
      else
        Application.delete_env(:app, App.Agents.Tools)
      end
    end)

    :ok
  end

  test "available_tools/0 lists builtin tools" do
    assert Tools.available_tools() == ["web_fetch"]
  end

  test "resolve/1 returns configured ReqLLM tools" do
    [tool] = Tools.resolve(["web_fetch"])
    assert tool.name == "web_fetch"
  end

  test "do_web_fetch/1 returns the response body on success" do
    Req.Test.stub(__MODULE__, fn conn ->
      Plug.Conn.send_resp(conn, 200, "hello from the stub")
    end)

    assert {:ok, "hello from the stub"} = Tools.do_web_fetch(%{url: "https://example.test"})
  end

  test "do_web_fetch/1 surfaces non-success status codes" do
    Req.Test.stub(__MODULE__, fn conn ->
      Plug.Conn.send_resp(conn, 404, "missing")
    end)

    assert {:error, "HTTP 404"} = Tools.do_web_fetch(%{url: "https://example.test/missing"})
  end
end
