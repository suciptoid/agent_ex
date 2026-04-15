defmodule App.LLM.ProviderConfig do
  @moduledoc false

  alias App.Providers.Provider

  @default_chat_path "/v1/chat/completions"
  @default_api_urls %{
    "openai" => "https://api.openai.com",
    "anthropic" => "https://api.anthropic.com",
    "google" => "https://generativelanguage.googleapis.com",
    "gemini" => "https://generativelanguage.googleapis.com",
    "xai" => "https://api.x.ai"
  }

  @provider_modules %{
    "openai" => Alloy.Provider.OpenAI,
    "anthropic" => Alloy.Provider.Anthropic,
    "google" => Alloy.Provider.Gemini,
    "gemini" => Alloy.Provider.Gemini,
    "xai" => Alloy.Provider.OpenAI,
    "openai_compat" => Alloy.Provider.OpenAICompat,
    "custom_openai_compat" => Alloy.Provider.OpenAICompat,
    "github_copilot" => Alloy.Provider.OpenAICompat
  }

  @type resolve_result :: {module(), map()}

  @spec resolve(Provider.t() | map(), String.t(), keyword()) :: resolve_result()
  def resolve(%Provider{} = provider, model, opts \\ []) do
    adapter = provider_adapter(provider)
    provider_module = Map.get(@provider_modules, adapter, Alloy.Provider.OpenAICompat)
    model_name = model_name(model)

    base_config =
      %{}
      |> maybe_put(:api_key, provider.api_key)
      |> maybe_put(:model, model_name)
      |> maybe_put(:api_url, provider_base_url(provider, adapter))
      |> maybe_put(:chat_path, provider_chat_path(provider, adapter))
      |> maybe_put(:extra_headers, provider_extra_headers(provider))
      |> maybe_put(:extra_body, provider_extra_body(provider))

    {provider_module, put_runtime_options(base_config, adapter, opts)}
  end

  # @spec model_name(String.t()) :: String.t()
  # def model_name(model) when is_binary(model) do
  #   case String.split(model, ":", parts: 2) do
  #     [_provider_prefix, raw_model] -> raw_model
  #     [raw_model] -> raw_model
  #     _other -> model
  #   end
  # end

  def model_name(model), do: to_string(model)

  @spec adapter(String.t() | Provider.t() | map()) :: String.t()
  def adapter(%Provider{} = provider), do: provider_adapter(provider)
  def adapter(%{} = provider), do: provider_adapter(provider)
  def adapter(value) when is_binary(value), do: String.trim(value)
  def adapter(_value), do: "openai_compat"

  defp provider_adapter(%Provider{} = provider) do
    provider
    |> Map.get(:adapter, Map.get(provider, :provider))
    |> normalize_adapter()
  end

  defp provider_adapter(%{} = provider) do
    provider
    |> Map.get(:adapter, Map.get(provider, :provider))
    |> normalize_adapter()
  end

  defp normalize_adapter(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "openai_compat"
      adapter -> adapter
    end
  end

  defp normalize_adapter(_value), do: "openai_compat"

  defp provider_base_url(provider, adapter) do
    provider
    |> Map.get(:base_url, Map.get(provider, "base_url"))
    |> case do
      nil -> Map.get(@default_api_urls, adapter)
      "" -> Map.get(@default_api_urls, adapter)
      value -> value
    end
  end

  defp provider_chat_path(provider, adapter) do
    chat_path = Map.get(provider, :chat_path, Map.get(provider, "chat_path"))

    if adapter in ["openai_compat", "custom_openai_compat", "github_copilot"] do
      case chat_path do
        nil -> @default_chat_path
        "" -> @default_chat_path
        value -> value
      end
    else
      nil
    end
  end

  defp provider_extra_headers(provider) do
    provider
    |> Map.get(:extra_headers, Map.get(provider, "extra_headers"))
    |> case do
      headers when is_map(headers) ->
        Enum.map(headers, fn {key, value} -> {to_string(key), to_string(value)} end)

      _other ->
        []
    end
  end

  defp provider_extra_body(provider) do
    provider
    |> Map.get(:metadata, Map.get(provider, "metadata"))
    |> case do
      %{"extra_body" => extra_body} when is_map(extra_body) -> extra_body
      %{extra_body: extra_body} when is_map(extra_body) -> extra_body
      _other -> %{}
    end
  end

  defp put_runtime_options(config, adapter, opts) do
    config
    |> maybe_put(:max_tokens, runtime_max_tokens(opts))
    |> maybe_put(:provider_state, Keyword.get(opts, :provider_state))
    |> maybe_put(:system_prompt, Keyword.get(opts, :system_prompt))
    |> maybe_put(:on_event, Keyword.get(opts, :on_event))
    |> maybe_put(:req_options, Keyword.get(opts, :req_options))
    |> maybe_put_extra_body(adapter, opts)
  end

  defp runtime_max_tokens(opts) do
    case Keyword.get(opts, :max_tokens) do
      value when is_integer(value) and value > 0 ->
        value

      value when is_float(value) and value > 0 ->
        trunc(value)

      _other ->
        nil
    end
  end

  defp maybe_put_extra_body(config, adapter, opts) do
    extra_body =
      %{}
      |> maybe_put_map_value("temperature", Keyword.get(opts, :temperature))
      |> maybe_put_map_value("reasoning_effort", Keyword.get(opts, :reasoning_effort))

    cond do
      extra_body == %{} ->
        config

      adapter in ["openai_compat", "custom_openai_compat", "github_copilot"] ->
        Map.update(config, :extra_body, extra_body, &Map.merge(&1, extra_body))

      adapter in ["gemini", "google"] ->
        Map.update(
          config,
          :generation_config,
          extra_body,
          &Map.merge(&1, Map.take(extra_body, ["temperature"]))
        )

      true ->
        config
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, value) when value == "", do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_map_value(map, _key, nil), do: map
  defp maybe_put_map_value(map, _key, value) when value == "", do: map

  defp maybe_put_map_value(map, key, value) do
    Map.put(map, key, value)
  end
end
