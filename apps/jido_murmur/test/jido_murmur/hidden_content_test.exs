defmodule JidoMurmur.HiddenContentTest do
  use ExUnit.Case, async: true

  alias JidoMurmur.HiddenContent

  test "wrap_markdown/2 adds the canonical hidden envelope" do
    assert HiddenContent.wrap_markdown("Hello", sender: "Alice", intent: "request") ==
             ~s(<!-- murmur: {"sender":"Alice","intent":"request"} -->\nHello)
  end

  test "wrapped?/1 recognizes Murmur hidden envelopes" do
    wrapped = HiddenContent.wrap_markdown("Hello", sender: "Alice", intent: "notify")

    assert HiddenContent.wrapped?(wrapped)
    refute HiddenContent.wrapped?("Hello")
  end

  test "wrap_markdown/2 sanitizes comment terminators inside metadata" do
    wrapped = HiddenContent.wrap_markdown("Hello", sender: "Alice--Bob", intent: "notify")

    assert wrapped =~ "Alice\\u002d\\u002dBob"
    refute wrapped =~ "Alice--Bob"
  end
end
