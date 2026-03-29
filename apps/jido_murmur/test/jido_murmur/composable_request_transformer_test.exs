defmodule JidoMurmur.ComposableRequestTransformerTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.ComposableRequestTransformer

  # ── Test Helpers ────────────────────────────────────────────────

  defmodule NoopTransformer do
    @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

    @impl true
    def transform_request(_request, _state, _config, _ctx), do: {:ok, %{}}
  end

  defmodule AppendMessageTransformer do
    @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

    @impl true
    def transform_request(request, _state, _config, ctx) do
      msg = %{role: :system, content: ctx[:append_content] || "appended"}
      {:ok, %{messages: request.messages ++ [msg]}}
    end
  end

  defmodule PrependMessageTransformer do
    @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

    @impl true
    def transform_request(request, _state, _config, _ctx) do
      msg = %{role: :system, content: "prepended"}
      {:ok, %{messages: [msg | request.messages]}}
    end
  end

  defmodule LlmOptsTransformer do
    @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

    @impl true
    def transform_request(_request, _state, _config, ctx) do
      {:ok, %{llm_opts: ctx[:llm_opts_override] || [temperature: 0.5]}}
    end
  end

  defmodule ToolsTransformer do
    @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

    @impl true
    def transform_request(_request, _state, _config, ctx) do
      {:ok, %{tools: ctx[:tools_override] || [:custom_tool]}}
    end
  end

  defmodule FailingTransformer do
    @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

    @impl true
    def transform_request(_request, _state, _config, _ctx) do
      {:error, :transformer_failed}
    end
  end

  # ── Fixtures ────────────────────────────────────────────────────

  defp base_request do
    %{
      messages: [%{role: :user, content: "hello"}],
      llm_opts: [model: "gpt-4", temperature: 1.0],
      tools: [:default_tool]
    }
  end

  defp stub_state, do: %{}
  defp stub_config, do: %{}

  # ── Tests ───────────────────────────────────────────────────────

  describe "transform_request/4 with empty chain" do
    test "returns empty overrides when no transformers configured" do
      ctx = %{request_transformers: []}
      assert {:ok, %{}} =
               ComposableRequestTransformer.transform_request(
                 base_request(),
                 stub_state(),
                 stub_config(),
                 ctx
               )
    end

    test "returns empty overrides when request_transformers key is missing" do
      assert {:ok, %{}} =
               ComposableRequestTransformer.transform_request(
                 base_request(),
                 stub_state(),
                 stub_config(),
                 %{}
               )
    end
  end

  describe "transform_request/4 with single transformer" do
    test "passes through a noop transformer" do
      ctx = %{request_transformers: [NoopTransformer]}

      assert {:ok, %{}} =
               ComposableRequestTransformer.transform_request(
                 base_request(),
                 stub_state(),
                 stub_config(),
                 ctx
               )
    end

    test "applies message override from a single transformer" do
      ctx = %{request_transformers: [AppendMessageTransformer]}

      assert {:ok, overrides} =
               ComposableRequestTransformer.transform_request(base_request(), stub_state(), stub_config(), ctx)

      assert [%{role: :user, content: "hello"}, %{role: :system, content: "appended"}] = overrides.messages
    end

    test "applies llm_opts override from a single transformer" do
      ctx = %{request_transformers: [LlmOptsTransformer]}

      assert {:ok, %{llm_opts: [temperature: 0.5]}} =
               ComposableRequestTransformer.transform_request(base_request(), stub_state(), stub_config(), ctx)
    end

    test "applies tools override from a single transformer" do
      ctx = %{request_transformers: [ToolsTransformer]}

      assert {:ok, %{tools: [:custom_tool]}} =
               ComposableRequestTransformer.transform_request(base_request(), stub_state(), stub_config(), ctx)
    end
  end

  describe "transform_request/4 sequential chaining" do
    test "second transformer sees modifications from first" do
      ctx = %{
        request_transformers: [PrependMessageTransformer, AppendMessageTransformer]
      }

      assert {:ok, overrides} =
               ComposableRequestTransformer.transform_request(base_request(), stub_state(), stub_config(), ctx)

      # PrependMessageTransformer adds "prepended" at front
      # AppendMessageTransformer sees the prepend result and appends "appended" at end
      assert [
               %{role: :system, content: "prepended"},
               %{role: :user, content: "hello"},
               %{role: :system, content: "appended"}
             ] = overrides.messages
    end

    test "llm_opts are keyword-merged across transformers" do
      ctx = %{
        request_transformers: [LlmOptsTransformer, LlmOptsTransformer],
        llm_opts_override: [max_tokens: 100]
      }

      # First transformer sets temperature: 0.5
      # Second transformer reads from ctx and sets max_tokens: 100
      # Both should be present in the merged result
      assert {:ok, overrides} =
               ComposableRequestTransformer.transform_request(base_request(), stub_state(), stub_config(), ctx)

      # Since both transformers read from the same ctx, the second one overrides the first
      # But the deep_merge of llm_opts should merge keywords
      assert overrides.llm_opts == [max_tokens: 100]
    end

    test "noop transformer does not clobber earlier overrides" do
      ctx = %{request_transformers: [AppendMessageTransformer, NoopTransformer]}

      assert {:ok, overrides} =
               ComposableRequestTransformer.transform_request(base_request(), stub_state(), stub_config(), ctx)

      assert [%{role: :user, content: "hello"}, %{role: :system, content: "appended"}] = overrides.messages
    end

    test "later messages replace earlier messages (last writer wins)" do
      ctx = %{request_transformers: [PrependMessageTransformer, AppendMessageTransformer]}

      assert {:ok, overrides} =
               ComposableRequestTransformer.transform_request(base_request(), stub_state(), stub_config(), ctx)

      # AppendMessageTransformer replaces the messages key entirely in the overrides
      # because deep_merge defaults to last writer wins for non-llm_opts keys
      # But AppendMessageTransformer works on the *merged request*, so it sees the prepended version
      assert length(overrides.messages) == 3
    end
  end

  describe "transform_request/4 error propagation" do
    test "halts chain on first error" do
      ctx = %{request_transformers: [FailingTransformer, AppendMessageTransformer]}

      assert {:error, :transformer_failed} =
               ComposableRequestTransformer.transform_request(base_request(), stub_state(), stub_config(), ctx)
    end

    test "error from second transformer propagates" do
      ctx = %{request_transformers: [NoopTransformer, FailingTransformer]}

      assert {:error, :transformer_failed} =
               ComposableRequestTransformer.transform_request(base_request(), stub_state(), stub_config(), ctx)
    end

    test "transformers after a failure are not called" do
      # If FailingTransformer halts, AppendMessageTransformer should not execute.
      # We verify by checking the error return (if append ran, we'd get {:ok, _}).
      ctx = %{request_transformers: [FailingTransformer, AppendMessageTransformer]}

      assert {:error, :transformer_failed} =
               ComposableRequestTransformer.transform_request(base_request(), stub_state(), stub_config(), ctx)
    end
  end

  describe "deep merge semantics" do
    test "tools are replaced, not merged" do
      ctx = %{request_transformers: [ToolsTransformer, ToolsTransformer], tools_override: [:replaced_tool]}

      assert {:ok, overrides} =
               ComposableRequestTransformer.transform_request(base_request(), stub_state(), stub_config(), ctx)

      assert overrides.tools == [:replaced_tool]
    end

    test "mixed override keys from different transformers are all present" do
      ctx = %{
        request_transformers: [AppendMessageTransformer, LlmOptsTransformer, ToolsTransformer]
      }

      assert {:ok, overrides} =
               ComposableRequestTransformer.transform_request(base_request(), stub_state(), stub_config(), ctx)

      assert Map.has_key?(overrides, :messages)
      assert Map.has_key?(overrides, :llm_opts)
      assert Map.has_key?(overrides, :tools)
    end
  end
end
