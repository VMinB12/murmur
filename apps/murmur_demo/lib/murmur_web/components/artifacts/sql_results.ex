defmodule MurmurWeb.Components.Artifacts.SqlResults do
  @moduledoc "Artifact renderer for SQL query results with sub-tabs and dynamic execution."

  use Phoenix.Component

  import MurmurWeb.CoreComponents, only: [icon: 1]

  @doc "Compact badge for the chat column."
  attr :data, :any, required: true
  attr :session_id, :string, required: true
  attr :active?, :boolean, default: false

  def badge(assigns) do
    items = List.wrap(assigns.data)
    assigns = assign(assigns, :count, length(items))

    ~H"""
    <button
      phx-click="open_artifact"
      phx-value-session-id={@session_id}
      phx-value-name="sql_results"
      class={[
        "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium transition-colors cursor-pointer",
        if(@active?,
          do: "bg-emerald-500/20 text-emerald-400 ring-1 ring-emerald-500/30",
          else: "bg-base-200/60 text-base-content/60 hover:bg-base-200 hover:text-base-content/80"
        )
      ]}
    >
      <.icon name="hero-table-cells" class="w-3 h-3" />
      <span>{@count} {if @count == 1, do: "query", else: "queries"}</span>
    </button>
    """
  end

  @doc "Full detail renderer for the artifact panel."
  attr :data, :any, required: true
  attr :session_id, :string, required: true

  def detail(assigns) do
    items = List.wrap(assigns.data)

    assigns =
      assigns
      |> assign(:items, items)
      |> assign(:active_tab, 0)

    ~H"""
    <div class="h-full flex flex-col">
      <%!-- Sub-tab bar for individual queries --%>
      <div class="px-3 py-1.5 border-b border-base-300/50 bg-base-200/10 shrink-0">
        <div class="flex items-center gap-2 text-[11px]">
          <.icon name="hero-table-cells" class="w-3.5 h-3.5 text-emerald-500/60" />
          <span class="text-base-content/40 font-medium">{length(@items)} queries</span>
        </div>
      </div>

      <%!-- Query list with expandable results --%>
      <div class="flex-1 overflow-y-auto">
        <%= for {item, idx} <- Enum.with_index(@items) do %>
          <% label = item["label"] || item[:label] || "Query #{idx + 1}" %>
          <% sql = item["sql"] || item[:sql] || "" %>
          <% row_count = item["row_count"] || item[:row_count] || 0 %>
          <% col_count = item["column_count"] || item[:column_count] || 0 %>
          <% loaded_result = item["loaded_result"] || item[:loaded_result] %>
          <% loaded_error = item["loaded_error"] || item[:loaded_error] %>

          <div class={[
            "border-b border-base-300/30",
            if(idx == 0, do: "", else: "")
          ]}>
            <%!-- Query header --%>
            <div class="px-4 py-2.5 flex items-start justify-between gap-3 group/query hover:bg-base-200/20 transition-colors">
              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-2">
                  <span class="text-[10px] font-mono text-emerald-500/60 bg-emerald-500/8 px-1.5 py-0.5 rounded">
                    Q{idx + 1}
                  </span>
                  <span class="text-xs font-medium text-base-content/80 truncate">
                    {String.slice(label, 0, 60)}
                  </span>
                </div>
                <div class="flex items-center gap-3 mt-1">
                  <span class="text-[10px] text-base-content/30">
                    {row_count} rows · {col_count} cols
                  </span>
                </div>
              </div>
              <button
                phx-click="reexecute_query"
                phx-value-session-id={@session_id}
                phx-value-sql={sql}
                phx-value-index={idx}
                class="shrink-0 inline-flex items-center gap-1 px-2 py-1 rounded text-[10px] font-medium text-emerald-400 bg-emerald-500/10 hover:bg-emerald-500/20 transition-colors"
              >
                <.icon name="hero-play" class="w-3 h-3" />
                <span>{if loaded_result, do: "Refresh", else: "Load"}</span>
              </button>
            </div>

            <%!-- SQL preview --%>
            <div class="px-4 pb-2">
              <pre class="text-[10px] text-base-content/30 font-mono bg-base-200/30 px-2.5 py-1.5 rounded overflow-x-auto max-h-16 leading-relaxed" phx-no-curly-interpolation><%= String.trim(sql) %></pre>
            </div>

            <%!-- Loaded result / error --%>
            <%= cond do %>
              <% loaded_error -> %>
                <div class="px-4 pb-3">
                  <div class="flex items-start gap-2 px-3 py-2 rounded bg-red-500/10 border border-red-500/20">
                    <.icon name="hero-exclamation-triangle" class="w-3.5 h-3.5 text-red-400 shrink-0 mt-0.5" />
                    <span class="text-[11px] text-red-300/80">{loaded_error}</span>
                  </div>
                </div>
              <% loaded_result -> %>
                <div class="px-4 pb-3">
                  <.result_table result={loaded_result} />
                </div>
              <% true -> %>
                <div class="px-4 pb-3">
                  <div class="flex items-center justify-center py-4 text-base-content/20 text-[11px]">
                    Click "Load" to execute query and view results
                  </div>
                </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :result, :map, required: true

  defp result_table(assigns) do
    columns = assigns.result["columns"] || assigns.result[:columns] || []
    rows = assigns.result["rows"] || assigns.result[:rows] || []
    total_rows = assigns.result["total_rows"] || assigns.result[:total_rows] || length(rows)

    # Paginate: show first 100 rows
    page_size = 100
    visible_rows = Enum.take(rows, page_size)
    has_more = length(rows) > page_size

    assigns =
      assigns
      |> assign(:columns, columns)
      |> assign(:visible_rows, visible_rows)
      |> assign(:total_rows, total_rows)
      |> assign(:has_more, has_more)
      |> assign(:shown_count, length(visible_rows))

    ~H"""
    <div class="border border-base-300/40 rounded overflow-hidden">
      <%!-- Table --%>
      <div class="overflow-x-auto max-h-[400px] overflow-y-auto">
        <table class="w-full text-[11px]">
          <thead class="sticky top-0 bg-base-200/60 backdrop-blur-sm">
            <tr>
              <%= for col <- @columns do %>
                <th class="px-2.5 py-1.5 text-left font-semibold text-base-content/50 whitespace-nowrap border-b border-base-300/40">
                  {col}
                </th>
              <% end %>
            </tr>
          </thead>
          <tbody>
            <%= if @visible_rows == [] do %>
              <tr>
                <td colspan={length(@columns)} class="px-2.5 py-6 text-center text-base-content/30">
                  (no rows)
                </td>
              </tr>
            <% else %>
              <%= for {row, idx} <- Enum.with_index(@visible_rows) do %>
                <tr class={[
                  "hover:bg-base-200/30 transition-colors",
                  if(rem(idx, 2) == 1, do: "bg-base-200/10", else: "")
                ]}>
                  <%= for cell <- row do %>
                    <td class="px-2.5 py-1 text-base-content/70 whitespace-nowrap border-b border-base-300/20 font-mono">
                      {format_cell(cell)}
                    </td>
                  <% end %>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </div>

      <%!-- Footer --%>
      <div class="px-2.5 py-1.5 bg-base-200/30 border-t border-base-300/40 flex items-center justify-between text-[10px] text-base-content/30">
        <span>
          Showing {if @shown_count < @total_rows, do: "#{@shown_count} of #{@total_rows}", else: "#{@total_rows}"} rows
        </span>
        <%= if @has_more do %>
          <span class="text-amber-400/60">Displaying first 100 rows</span>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_cell(nil), do: "NULL"
  defp format_cell(val) when is_binary(val), do: String.slice(val, 0, 100)
  defp format_cell(val), do: inspect(val, limit: 50)
end
