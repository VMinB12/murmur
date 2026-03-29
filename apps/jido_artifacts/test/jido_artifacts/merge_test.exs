defmodule JidoArtifacts.MergeTest do
  use ExUnit.Case, async: true

  alias JidoArtifacts.Merge

  describe "append/2" do
    test "appends new items to existing list" do
      assert Merge.append([1, 2], [3, 4]) == [1, 2, 3, 4]
    end

    test "treats nil existing as empty list" do
      assert Merge.append(nil, [1, 2]) == [1, 2]
    end

    test "wraps scalar new value in list" do
      assert Merge.append([1], 2) == [1, 2]
    end
  end

  describe "prepend/2" do
    test "prepends new items before existing list" do
      assert Merge.prepend([3, 4], [1, 2]) == [1, 2, 3, 4]
    end

    test "treats nil existing as empty list" do
      assert Merge.prepend(nil, [1, 2]) == [1, 2]
    end

    test "wraps scalar new value in list" do
      assert Merge.prepend([2], 1) == [1, 2]
    end
  end

  describe "append_max/1" do
    test "appends and keeps last max items" do
      merge_fn = Merge.append_max(3)
      assert merge_fn.([1, 2], [3, 4, 5]) == [3, 4, 5]
    end

    test "returns all when under max" do
      merge_fn = Merge.append_max(10)
      assert merge_fn.([1, 2], [3]) == [1, 2, 3]
    end

    test "handles nil existing" do
      merge_fn = Merge.append_max(2)
      assert merge_fn.(nil, [1, 2, 3]) == [2, 3]
    end
  end

  describe "prepend_max/1" do
    test "prepends and keeps first max items" do
      merge_fn = Merge.prepend_max(3)
      assert merge_fn.([3, 4, 5], [1, 2]) == [1, 2, 3]
    end

    test "returns all when under max" do
      merge_fn = Merge.prepend_max(10)
      assert merge_fn.([2, 3], [1]) == [1, 2, 3]
    end

    test "handles nil existing" do
      merge_fn = Merge.prepend_max(2)
      assert merge_fn.(nil, [1, 2, 3]) == [1, 2]
    end
  end

  describe "upsert_by/1" do
    test "replaces items with matching keys" do
      merge_fn = Merge.upsert_by(& &1.id)
      existing = [%{id: 1, name: "old"}, %{id: 2, name: "keep"}]
      new = [%{id: 1, name: "updated"}]
      result = merge_fn.(existing, new)

      assert length(result) == 2
      assert Enum.find(result, &(&1.id == 1)).name == "updated"
      assert Enum.find(result, &(&1.id == 2)).name == "keep"
    end

    test "appends items with new keys" do
      merge_fn = Merge.upsert_by(& &1.id)
      existing = [%{id: 1, name: "a"}]
      new = [%{id: 2, name: "b"}]
      result = merge_fn.(existing, new)

      assert length(result) == 2
    end

    test "handles nil existing" do
      merge_fn = Merge.upsert_by(& &1.id)
      result = merge_fn.(nil, [%{id: 1, name: "new"}])

      assert result == [%{id: 1, name: "new"}]
    end
  end
end
