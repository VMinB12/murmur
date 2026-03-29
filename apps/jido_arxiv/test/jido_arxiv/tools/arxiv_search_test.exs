defmodule JidoArxiv.Tools.ArxivSearchTest do
  use ExUnit.Case, async: true

  alias JidoArxiv.Tools.ArxivSearch

  @sample_atom_feed """
  <?xml version="1.0" encoding="UTF-8"?>
  <feed xmlns="http://www.w3.org/2005/Atom">
    <entry>
      <id>http://arxiv.org/abs/2301.07041v1</id>
      <title>Attention Is All You Need Revisited</title>
      <summary>We revisit the transformer architecture and propose improvements.</summary>
      <published>2023-01-17T00:00:00Z</published>
    </entry>
    <entry>
      <id>http://arxiv.org/abs/2302.01234v1</id>
      <title>Large Language Models: A Survey</title>
      <summary>A comprehensive survey of large language models and their applications.</summary>
      <published>2023-02-02T00:00:00Z</published>
    </entry>
  </feed>
  """

  setup do
    Application.put_env(:jido_arxiv, :req_options, plug: {Req.Test, ArxivSearch}, retry: false)
    on_exit(fn -> Application.delete_env(:jido_arxiv, :req_options) end)
    :ok
  end

  describe "run/2 with successful response" do
    test "returns parsed papers and emits artifact directive" do
      Req.Test.stub(ArxivSearch, fn conn ->
        Plug.Conn.send_resp(conn, 200, @sample_atom_feed)
      end)

      params = %{query: "transformers"}
      ctx = %{}

      assert {:ok, %{result: result}, directive} = ArxivSearch.run(params, ctx)

      assert result =~ "Found 2 papers"
      assert result =~ "Attention Is All You Need Revisited"
      assert result =~ "Large Language Models"

      assert %Jido.Agent.Directive.Emit{signal: signal} = directive
      assert signal.type == "artifact.papers"
      assert signal.data.mode == :merge
      assert length(signal.data.data) == 2
    end

    test "parses paper metadata correctly" do
      Req.Test.stub(ArxivSearch, fn conn ->
        Plug.Conn.send_resp(conn, 200, @sample_atom_feed)
      end)

      params = %{query: "attention"}
      ctx = %{}

      {:ok, _result, directive} = ArxivSearch.run(params, ctx)

      [paper1, paper2] = directive.signal.data.data

      assert paper1.id == "2301.07041v1"
      assert paper1.title == "Attention Is All You Need Revisited"
      assert paper1.abstract =~ "transformer architecture"
      assert paper1.url == "https://arxiv.org/abs/2301.07041v1"
      assert paper1.pdf_url == "https://arxiv.org/pdf/2301.07041v1.pdf"
      assert paper1.published == "2023-01-17T00:00:00Z"

      assert paper2.id == "2302.01234v1"
    end

    test "normalizes whitespace in title and abstract" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <entry>
          <id>http://arxiv.org/abs/2301.00001v1</id>
          <title>
            Multi-line   Title
            With   Spaces
          </title>
          <summary>
            Abstract with\ttabs and
            newlines   in it
          </summary>
          <published>2023-01-01T00:00:00Z</published>
        </entry>
      </feed>
      """

      Req.Test.stub(ArxivSearch, fn conn ->
        Plug.Conn.send_resp(conn, 200, xml)
      end)

      {:ok, _result, directive} = ArxivSearch.run(%{query: "test"}, %{})

      [paper] = directive.signal.data.data
      assert paper.title == "Multi-line Title With Spaces"
      assert paper.abstract =~ "Abstract with tabs and newlines in it"
    end
  end

  describe "run/2 with empty results" do
    test "returns empty papers list" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
      </feed>
      """

      Req.Test.stub(ArxivSearch, fn conn ->
        Plug.Conn.send_resp(conn, 200, xml)
      end)

      {:ok, %{result: result}, directive} = ArxivSearch.run(%{query: "nonexistent"}, %{})

      assert result =~ "Found 0 papers"
      assert directive.signal.data.data == []
    end
  end

  describe "run/2 with HTTP errors" do
    test "returns error on rate limit (429)" do
      Req.Test.stub(ArxivSearch, fn conn ->
        Plug.Conn.send_resp(conn, 429, "Rate limited")
      end)

      assert {:error, msg} = ArxivSearch.run(%{query: "test"}, %{})
      assert msg =~ "rate limit"
    end

    test "returns error on server error (500)" do
      Req.Test.stub(ArxivSearch, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      assert {:error, msg} = ArxivSearch.run(%{query: "test"}, %{})
      assert msg =~ "HTTP 500"
    end

    test "returns error on connection failure" do
      Req.Test.stub(ArxivSearch, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, msg} = ArxivSearch.run(%{query: "test"}, %{})
      assert msg =~ "arXiv search failed"
    end
  end

  describe "run/2 with malformed XML" do
    @tag :capture_log
    test "returns empty list for invalid XML" do
      Req.Test.stub(ArxivSearch, fn conn ->
        Plug.Conn.send_resp(conn, 200, "not xml at all")
      end)

      {:ok, %{result: result}, directive} = ArxivSearch.run(%{query: "test"}, %{})

      assert result =~ "Found 0 papers"
      assert directive.signal.data.data == []
    end
  end

  describe "LLM format output" do
    test "formats papers with numbered list" do
      Req.Test.stub(ArxivSearch, fn conn ->
        Plug.Conn.send_resp(conn, 200, @sample_atom_feed)
      end)

      {:ok, %{result: result}, _directive} = ArxivSearch.run(%{query: "test"}, %{})

      assert result =~ "1. **Attention Is All You Need Revisited**"
      assert result =~ "2. **Large Language Models: A Survey**"
    end
  end
end
