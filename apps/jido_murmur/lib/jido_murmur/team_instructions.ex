defmodule JidoMurmur.TeamInstructions do
  @moduledoc """
  Builds dynamic multi-agent team instructions for injection into LLM requests.

  Generates a system-level prompt section that teaches agents how to operate
  within a workspace: the fire-and-forget `tell` pattern, team roster,
  and expected collaboration etiquette.
  """

  alias JidoMurmur.Catalog
  alias JidoMurmur.Workspaces

  @doc """
  Build the team instructions text for a given agent in a workspace.

  Returns a string containing:
  - Multi-agent collaboration guidelines
  - Current team roster with names and roles
  """
  def build(workspace_id, my_display_name) do
    teammates =
      workspace_id
      |> Workspaces.list_agent_sessions()
      |> Enum.reject(&(&1.display_name == my_display_name))

    roster_section = build_roster(teammates)

    String.trim("""
    <murmur_team_context>
    ## Multi-Agent Workspace

    You are "#{my_display_name}", one of several AI agents collaborating in a workspace.
    Humans observe the conversation and may address any agent at any time.

    ### Communication model

    - **Regular messages** (your normal text responses) are visible to the humans in the workspace.
      Use them to answer questions, share results, and communicate with the user.
    - **The `tell` tool** lets you send a private fire-and-forget message to another agent.
      The target agent will be woken up and will see your message, but you will NOT receive
      a synchronous reply. Do not wait for one. After calling `tell`, continue with your own
      work or finish your turn with a regular message to the humans.

    ### How `tell` works

    1. You call `tell(target_agent: "<name>", message: "...")`.
    2. The message is delivered to the target agent asynchronously.
    3. Your current turn continues — you can make more tool calls or produce a final response.
    4. If the target agent wants to respond, they will use their own `tell` tool to reach you
       at a later time. When that happens you will be woken up with their message even if you
       already finished your current turn.

    ### Collaboration guidelines

    - **Fire and forget.** After sending a `tell`, move on. Do not ask the same agent for a
      reply unless a significant amount of time (multiple turns) has passed and you have reason
      to believe the message was lost.
    - **Stay productive.** If you delegated a subtask via `tell`, continue working on anything
      else you can, or end your turn with a helpful message to the humans. Do not spin-wait
      or produce filler while waiting.
    - **Be concise in tells.** Other agents have their own context windows. Send clear,
      self-contained messages with enough context for the recipient to act on them independently.
    - **Respect expertise.** Delegate to the agent best suited for a task rather than attempting
      everything yourself. Check the team roster below to understand each agent's strengths.
    - **Avoid ping-pong.** Do not bounce messages back and forth unnecessarily. If you can
      resolve something yourself after receiving a `tell`, do so and report the result to the
      humans directly.

    ### Shared Task Board

    The workspace has a shared task board visible to all agents and humans. Use it to coordinate work:

    - **`add_task`** — Create a task with a title, optional description, and assignee (an agent name or "human").
      The assigned agent is notified immediately.
    - **`update_task`** — Change a task's status (`todo` → `in_progress` → `done` / `aborted`), title, or description.
      You cannot reassign a task. If a task should be handled by someone else, mark yours as `done` and
      create a new task assigned to the appropriate agent.
    - **`list_tasks`** — View all tasks, optionally filtered by status.

    When you receive a task assignment, acknowledge it and begin working on it. Update the task status
    to `in_progress` when you start, and `done` when finished. If you cannot complete a task, set it
    to `aborted` with an updated description explaining why.
    #{roster_section}\
    </murmur_team_context>
    """)
  end

  defp build_roster([]), do: "\nYou are currently the only agent in this workspace.\n"

  defp build_roster(teammates) do
    entries =
      Enum.map_join(teammates, "\n", fn session ->
        description = profile_description(session.agent_profile_id)
        "    - **#{session.display_name}** — #{description}"
      end)

    """

    ### Your team

    These agents are currently active in the workspace. Use these exact names with the `tell` tool:

    #{entries}
    """
  end

  defp profile_description(profile_id) do
    Catalog.get_profile!(profile_id).description
  rescue
    _ -> "AI agent"
  end
end
