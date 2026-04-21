defmodule App.Providers.Models do
  @moduledoc """
  Provides model listings for providers.

  Since alloy has no built-in model database, we fetch models from the
  provider API where supported, falling back to a curated static list.
  """

  alias App.Providers.Provider

  @known_openai_models [
    {"gpt-5.4", "GPT-5.4"},
    {"gpt-5.4-mini", "GPT-5.4 Mini"},
    {"gpt-5.3-codex", "GPT-5.3 Codex"},
    {"gpt-5.2-codex", "GPT-5.2 Codex"},
    {"gpt-5.2", "GPT-5.2"},
    {"gpt-5-mini", "GPT-5 Mini"},
    {"gpt-4.1", "GPT-4.1"},
    {"gpt-4.1-mini", "GPT-4.1 Mini"},
    {"gpt-4.1-nano", "GPT-4.1 Nano"},
    {"o4-mini", "O4 Mini"},
    {"o3-pro", "O3 Pro"},
    {"o3", "O3"},
    {"o3-mini", "O3 Mini"},
    {"gpt-4o", "GPT-4o"},
    {"gpt-4o-mini", "GPT-4o Mini"}
  ]

  @known_anthropic_models [
    {"claude-opus-4-6", "Claude Opus 4.6"},
    {"claude-sonnet-4-6", "Claude Sonnet 4.6"},
    {"claude-opus-4-5", "Claude Opus 4.5"},
    {"claude-sonnet-4-5", "Claude Sonnet 4.5"},
    {"claude-sonnet-4-5-20250514", "Claude Sonnet 4.5 (May 2025)"},
    {"claude-sonnet-4-20250514", "Claude Sonnet 4 (May 2025)"},
    {"claude-haiku-4-5", "Claude Haiku 4.5"},
    {"claude-3-5-haiku-20241022", "Claude 3.5 Haiku"},
    {"claude-3-5-sonnet-20241022", "Claude 3.5 Sonnet v2"}
  ]

  @doc """
  Returns a list of `{model_id, display_label}` tuples for the given provider.

  Attempts to fetch from the provider API first, falling back to static lists.
  """
  def list_models(%Provider{} = provider) do
    case fetch_models_from_api(provider) do
      {:ok, models} when models != [] -> models
      _ -> known_models(provider)
    end
  end

  @doc """
  Returns the static list of known models for a provider type.
  """
  def known_models(%Provider{} = provider) do
    case Provider.alloy_provider_type(provider) do
      "openai" -> @known_openai_models
      "anthropic" -> @known_anthropic_models
      _other -> []
    end
  end

  defp fetch_models_from_api(%Provider{} = provider) do
    case Provider.alloy_provider_type(provider) do
      "openai" -> fetch_openai_models(provider)
      "openai_compat" -> fetch_openai_compat_models(provider)
      _other -> {:ok, []}
    end
  rescue
    _error -> {:ok, []}
  end

  defp fetch_openai_models(%Provider{api_key: api_key} = provider) do
    base_url = provider.base_url || "https://api.openai.com"
    url = "#{String.trim_trailing(base_url, "/")}/v1/models"

    case Req.get(url, headers: [{"authorization", "Bearer #{api_key}"}], receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"data" => data}}} when is_list(data) ->
        models =
          data
          |> Enum.filter(&is_chat_model?/1)
          |> Enum.sort_by(& &1["created"], :desc)
          |> Enum.map(fn m -> {m["id"], m["id"]} end)

        {:ok, models}

      _ ->
        {:ok, []}
    end
  end

  defp fetch_openai_compat_models(%Provider{base_url: nil}), do: {:ok, []}

  defp fetch_openai_compat_models(%Provider{api_key: api_key, base_url: base_url}) do
    url = "#{String.trim_trailing(base_url, "/")}/v1/models"
    headers = if api_key, do: [{"authorization", "Bearer #{api_key}"}], else: []

    case Req.get(url, headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"data" => data}}} when is_list(data) ->
        models =
          data
          |> Enum.sort_by(& &1["created"], :desc)
          |> Enum.map(fn m -> {m["id"], m["id"]} end)

        {:ok, models}

      _ ->
        {:ok, []}
    end
  end

  defp is_chat_model?(%{"id" => id}) do
    not String.contains?(id, ["embedding", "whisper", "tts", "dall-e", "davinci", "babbage"])
  end

  defp is_chat_model?(_), do: false
end
