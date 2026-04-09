defmodule App.TestSupport.FailingAgentRunnerStub do
  def run(_agent, _messages, _opts \\ []) do
    {:error, {:error, request_error()}}
  end

  def run_streaming(_agent, _messages, _recipient, _opts \\ []) do
    {:error, {:error, request_error()}}
  end

  defp request_error do
    ReqLLM.Error.API.Request.exception(
      reason:
        "Invalid value: 'default'. Supported values are: 'none', 'minimal', 'low', 'medium', 'high', and 'xhigh'.",
      status: 400,
      response_body: %{
        "code" => "invalid_value",
        "message" => "Verbose API payload that should stay hidden"
      }
    )
  end
end
