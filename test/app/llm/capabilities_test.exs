defmodule App.LLM.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias App.LLM.Capabilities

  describe "tool_use_supported?/2" do
    test "returns false when model supported_parameters excludes tool parameters" do
      provider = %{
        provider_models: [
          %{
            model_id: "openrouter/some-model",
            raw: %{"supported_parameters" => ["max_tokens", "temperature"]}
          }
        ]
      }

      refute Capabilities.tool_use_supported?(provider, "openrouter:openrouter/some-model")
    end

    test "returns true when model supported_parameters includes tools" do
      provider = %{
        provider_models: [
          %{
            model_id: "openrouter/tool-model",
            raw: %{"supported_parameters" => ["temperature", "tools"]}
          }
        ]
      }

      assert Capabilities.tool_use_supported?(provider, "openrouter:openrouter/tool-model")
    end

    test "returns true when model metadata is unavailable" do
      provider = %{provider_models: []}

      assert Capabilities.tool_use_supported?(provider, "openrouter:unknown-model")
    end
  end
end
