defmodule App.TestSupport.FailingAgentRunnerStub do
  def run(_agent, _messages, _opts \\ []) do
    {:error,
     "Invalid value: 'default'. Supported values are: 'none', 'minimal', 'low', 'medium', 'high', and 'xhigh'."}
  end

  def run_streaming(_agent, _messages, _recipient, _opts \\ []) do
    {:error,
     "Invalid value: 'default'. Supported values are: 'none', 'minimal', 'low', 'medium', 'high', and 'xhigh'."}
  end
end
