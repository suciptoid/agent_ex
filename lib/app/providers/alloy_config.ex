defmodule App.Providers.AlloyConfig do
  @moduledoc """
  Maps an `App.Providers.Provider` record to an Alloy provider tuple.
  """

  alias App.Providers.Provider

  @doc """
  Builds the `{ProviderModule, config_keyword_list}` tuple that Alloy expects.

  ## Examples

      iex> to_alloy_provider(provider, "claude-sonnet-4-6")
      {Alloy.Provider.Anthropic, [api_key: "sk-...", model: "claude-sonnet-4-6"]}
  """
  def to_alloy_provider(%Provider{} = provider, model_name, extra_opts \\ []) do
    base_opts =
      [api_key: provider.api_key, model: model_name]
      |> Keyword.merge(extra_opts)

    case Provider.alloy_provider_type(provider) do
      "anthropic" ->
        {Alloy.Provider.Anthropic, base_opts ++ maybe_api_url(provider)}

      "gemini" ->
        {Alloy.Provider.Gemini, base_opts ++ maybe_api_url(provider)}

      "openai" ->
        {Alloy.Provider.OpenAI, base_opts ++ maybe_api_url(provider)}

      _compat ->
        compat_opts =
          case provider.base_url do
            nil -> base_opts
            url -> Keyword.put(base_opts, :api_url, url)
          end

        {App.Providers.OpenAICompat, compat_opts}
    end
  end

  defp maybe_api_url(%Provider{base_url: nil}), do: []
  defp maybe_api_url(%Provider{base_url: url}), do: [api_url: url]
end
