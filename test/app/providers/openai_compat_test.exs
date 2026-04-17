defmodule App.Providers.OpenAICompatTest do
  use App.DataCase, async: true

  alias App.Providers.OpenAICompat

  test "stream emits reasoning deltas and preserves the final thinking block" do
    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:request_body, Jason.decode!(body)})

      response = [
        ~s(data: {"choices":[{"delta":{"reasoning_content":"thinking "}}]}\n\n),
        ~s(data: {"choices":[{"delta":{"reasoning_content":"through"}}]}\n\n),
        ~s(data: {"choices":[{"delta":{"content":"done"},"finish_reason":"stop"}]}\n\n),
        "data: [DONE]\n\n"
      ]

      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.resp(200, Enum.join(response))
    end)

    assert {:ok, response} =
             OpenAICompat.stream(
               [Alloy.Message.user("hi")],
               [],
               %{
                 api_url: "http://example.test",
                 api_key: "sk-test",
                 model: "stepfun-3.5-flash",
                 req_options: [plug: {Req.Test, __MODULE__}],
                 on_event: fn event -> send(test_pid, {:event, event}) end
               },
               fn chunk -> send(test_pid, {:chunk, chunk}) end
             )

    assert_receive {:request_body, %{"stream" => true, "model" => "stepfun-3.5-flash"}}
    assert_receive {:event, {:thinking_delta, "thinking "}}
    assert_receive {:event, {:thinking_delta, "through"}}
    assert_receive {:chunk, "done"}

    assert [
             %{
               type: "thinking",
               thinking: "thinking through"
             },
             %{type: "text", text: "done"}
           ] = hd(response.messages).content
  end
end
