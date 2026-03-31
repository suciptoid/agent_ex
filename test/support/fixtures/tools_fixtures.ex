defmodule App.ToolsFixtures do
  alias App.Users.Scope

  def tool_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "brave_search",
      description: "Search the web with Brave.",
      endpoint: "https://example.test/search",
      http_method: "get",
      param_rows: [
        %{"name" => "query", "type" => "string", "source" => "llm", "value" => ""},
        %{"name" => "safe_search", "type" => "boolean", "source" => "fixed", "value" => "true"}
      ],
      header_rows: [
        %{"key" => "authorization", "value" => "Bearer secret-key"}
      ]
    })
  end

  def tool_fixture(user, attrs \\ %{}) do
    {:ok, tool} =
      App.Tools.create_tool(
        Scope.for_user(user),
        tool_attrs(attrs)
      )

    tool
  end
end
