# SPDX-FileCopyrightText: 2022 ash_paper_trail contributors <https://github.com/ash-project/ash_paper_trail/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPaperTrail.Test.Posts.Refetch do
  @moduledoc """
  Refetches the record being updated in a `before_action`, as `get_and_lock_for_update`
  does, without the lock, which ETS doesn't support.
  """
  use Ash.Resource.Change

  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      primary_key = Ash.Resource.Info.primary_key(changeset.resource)
      pkey_values = changeset.data |> Map.take(primary_key) |> Map.to_list()

      %{changeset | data: Ash.get!(changeset.resource, pkey_values, authorize?: false)}
    end)
  end
end
