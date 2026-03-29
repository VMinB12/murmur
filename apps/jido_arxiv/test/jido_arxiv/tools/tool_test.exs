defmodule JidoArxiv.Tools.ToolTest do
  use ExUnit.Case, async: true

  alias ArxivSearch
  alias JidoArxiv.Tools.DisplayPaper

  describe "DisplayPaper" do
    test "emits artifact for valid arxiv_id" do
      params = %{arxiv_id: "2301.07041"}
      ctx = %{}

      assert {:ok, %{result: result}, directive} = DisplayPaper.run(params, ctx)

      assert result =~ "2301.07041"
      assert result =~ "Displaying PDF"
      assert %Jido.Agent.Directive.Emit{} = directive
    end

    test "strips URL prefix from arxiv_id" do
      params = %{arxiv_id: "https://arxiv.org/abs/2301.07041"}
      ctx = %{}

      assert {:ok, %{result: result}, _directive} = DisplayPaper.run(params, ctx)
      assert result =~ "2301.07041"
    end

    test "strips PDF URL and extension" do
      params = %{arxiv_id: "https://arxiv.org/pdf/2301.07041.pdf"}
      ctx = %{}

      assert {:ok, %{result: result}, _directive} = DisplayPaper.run(params, ctx)
      assert result =~ "2301.07041"
    end

    test "returns error for empty arxiv_id" do
      params = %{arxiv_id: "  "}
      ctx = %{}

      assert {:error, msg} = DisplayPaper.run(params, ctx)
      assert msg =~ "Invalid arXiv ID"
    end

    test "emits displayed_paper artifact with replace mode" do
      params = %{arxiv_id: "2301.07041"}
      ctx = %{}

      {:ok, _result, directive} = DisplayPaper.run(params, ctx)

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.type == "artifact.displayed_paper"
      assert signal.data.mode == :replace
      assert signal.data.data.pdf_url =~ "2301.07041"
    end
  end

  describe "ArxivSearch action module" do
    test "module is a valid Jido.Action" do
      Code.ensure_loaded!(ArxivSearch)
      assert function_exported?(ArxivSearch, :run, 2)
    end

    test "has correct action name" do
      metadata = ArxivSearch.__action_metadata__()
      assert metadata.name == "arxiv_search"
    end
  end
end
