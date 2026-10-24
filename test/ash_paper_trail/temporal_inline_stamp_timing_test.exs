# SPDX-FileCopyrightText: 2022 ash_paper_trail contributors <https://github.com/ash-project/ash_paper_trail/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPaperTrail.StampTiming.Domain do
  use Ash.Domain, extensions: [AshPaperTrail.Domain], validate_config_inclusion?: false

  resources do
    resource AshPaperTrail.StampTiming.User
    resource AshPaperTrail.StampTiming.Author
    resource AshPaperTrail.StampTiming.ChangesOnly
    resource AshPaperTrail.StampTiming.PreviousValues
    resource AshPaperTrail.StampTiming.FullDiff
    resource AshPaperTrail.StampTiming.AlwaysPreviousValues
    resource AshPaperTrail.StampTiming.Versioned
    resource AshPaperTrail.StampTiming.Versioned.Version
  end
end

defmodule AshPaperTrail.StampTiming.User do
  use Ash.Resource,
    domain: AshPaperTrail.StampTiming.Domain,
    data_layer: Ash.DataLayer.Ets,
    validate_domain_inclusion?: false

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read, create: [:name]]
  end
end

defmodule AshPaperTrail.StampTiming.Author do
  use Ash.Resource,
    domain: AshPaperTrail.StampTiming.Domain,
    data_layer: Ash.DataLayer.Ets,
    validate_domain_inclusion?: false

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  actions do
    defaults [:read, create: [:name]]
  end
end

defmodule AshPaperTrail.StampTiming.Refetch do
  @moduledoc "Re-reads the record in a before_action, as get_and_lock_for_update does (ETS can't lock)."
  use Ash.Resource.Change

  @impl true
  def temporal_safe?(_), do: true

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      primary_key = Ash.Resource.Info.primary_key(changeset.resource)
      pkey_values = changeset.data |> Map.take(primary_key) |> Map.to_list()
      %{changeset | data: Ash.get!(changeset.resource, pkey_values, authorize?: false)}
    end)
  end
end

defmodule AshPaperTrail.StampTiming.ManageInBeforeTransaction do
  use Ash.Resource.Change

  @impl true
  def temporal_safe?(_), do: true

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      Ash.Changeset.manage_relationship(
        changeset,
        :author,
        Ash.Changeset.get_argument(changeset, :author_id),
        type: :append_and_remove
      )
    end)
  end
end

defmodule AshPaperTrail.StampTiming.Article do
  @moduledoc false
  defmacro __using__(opts) do
    tracking = Keyword.fetch!(opts, :tracking)
    temporal? = Keyword.get(opts, :temporal?, true)
    only_when_changed? = Keyword.get(opts, :only_when_changed?, true)

    quote do
      use Ash.Resource,
        domain: AshPaperTrail.StampTiming.Domain,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshPaperTrail.Resource],
        validate_domain_inclusion?: false

      ets do
        private? true
      end

      if unquote(temporal?) do
        temporal do
          strategy :context
          attribute :valid_at
        end
      end

      paper_trail do
        if unquote(temporal?), do: mode(:temporal_inline)
        change_tracking_mode unquote(tracking)
        only_when_changed? unquote(only_when_changed?)
        store_action_name? true
        ignore_attributes [:inserted_at, :updated_at]
        ignore_actions [:ignored_increment]

        belongs_to_actor :user, AshPaperTrail.StampTiming.User,
          domain: AshPaperTrail.StampTiming.Domain

        metadata :reason_for_change, :string
      end

      attributes do
        uuid_primary_key :id
        attribute :title, :string, public?: true
        attribute :body, :string, public?: true
        attribute :views, :integer, public?: true, default: 0, allow_nil?: false
        attribute :archived_at, :utc_datetime_usec, public?: true
        create_timestamp :inserted_at
        update_timestamp :updated_at
      end

      relationships do
        if unquote(temporal?) do
          belongs_to :author, AshPaperTrail.StampTiming.Author do
            public? true
            temporal_keys {:valid_at, nil}
          end
        else
          belongs_to :author, AshPaperTrail.StampTiming.Author, public?: true
        end
      end

      actions do
        defaults [:read]

        create :create do
          primary? true
          accept [:title, :body, :author_id]
        end

        create :create_with_author do
          accept [:title]
          argument :author_id, :uuid, allow_nil?: false
          change manage_relationship(:author_id, :author, type: :append_and_remove)
        end

        update :update do
          primary? true
          require_atomic? false
          accept [:title, :body]
        end

        update :update_atomic do
          require_atomic? true
          accept [:title, :body]
        end

        update :update_any do
          require_atomic? false
          accept []
        end

        update :increment_views do
          require_atomic? false
          accept []
          change increment(:views)
        end

        update :ignored_increment do
          require_atomic? false
          accept []
          change increment(:views)
        end

        update :update_refetched do
          require_atomic? false
          accept [:title, :body]
          change AshPaperTrail.StampTiming.Refetch
        end

        update :refetch_and_bump do
          require_atomic? false
          accept [:title]
          change AshPaperTrail.StampTiming.Refetch
          change atomic_update(:views, expr(^Ash.Expr.ref(:views) + 1))
        end

        update :move do
          require_atomic? false
          argument :author_id, :uuid, allow_nil?: false
          change manage_relationship(:author_id, :author, type: :append_and_remove)
        end

        update :move_and_retitle do
          require_atomic? false
          accept [:title]
          argument :author_id, :uuid, allow_nil?: false
          change manage_relationship(:author_id, :author, type: :append_and_remove)
        end

        update :move_in_before_transaction do
          require_atomic? false
          argument :author_id, :uuid, allow_nil?: false
          change AshPaperTrail.StampTiming.ManageInBeforeTransaction
        end

        destroy :archive do
          soft? true
          require_atomic? false
          change set_attribute(:archived_at, &DateTime.utc_now/0)
        end
      end
    end
  end
end

defmodule AshPaperTrail.StampTiming.ChangesOnly do
  use AshPaperTrail.StampTiming.Article, tracking: :changes_only
end

defmodule AshPaperTrail.StampTiming.PreviousValues do
  use AshPaperTrail.StampTiming.Article, tracking: :previous_values
end

defmodule AshPaperTrail.StampTiming.FullDiff do
  use AshPaperTrail.StampTiming.Article, tracking: :full_diff
end

defmodule AshPaperTrail.StampTiming.AlwaysPreviousValues do
  use AshPaperTrail.StampTiming.Article, tracking: :previous_values, only_when_changed?: false
end

defmodule AshPaperTrail.StampTiming.Versioned do
  use AshPaperTrail.StampTiming.Article, tracking: :changes_only, temporal?: false
end

defmodule AshPaperTrail.TemporalInlineStampTimingTest do
  use ExUnit.Case, async: false
  require Ash.Query

  alias AshPaperTrail.StampTiming.{
    AlwaysPreviousValues,
    Author,
    ChangesOnly,
    FullDiff,
    PreviousValues,
    User,
    Versioned
  }

  @t1 ~U[2026-01-01 00:00:00.000000Z]
  @t2 ~U[2026-02-01 00:00:00.000000Z]
  @t3 ~U[2026-03-01 00:00:00.000000Z]

  setup do
    on_exit(fn ->
      for resource <- [
            User,
            Author,
            ChangesOnly,
            PreviousValues,
            FullDiff,
            AlwaysPreviousValues,
            Versioned,
            Versioned.Version
          ] do
        Ash.DataLayer.Ets.stop(resource)
      end
    end)

    %{
      creator: Ash.create!(User, %{name: "creator"}),
      updater: Ash.create!(User, %{name: "updater"}),
      a: Ash.create!(Author, %{name: "a"}),
      b: Ash.create!(Author, %{name: "b"})
    }
  end

  defp create!(resource, input, creator),
    do: Ash.create!(resource, input, as_of: @t1, actor: creator)

  defp version(resource, record, as_of \\ @t2), do: Ash.get!(resource, record.id, as_of: as_of)

  defp stamp(resource, record, as_of \\ @t2) do
    resource
    |> version(record, as_of)
    |> Map.take([:version_action_type, :version_action_name, :user_id, :changes])
  end

  defp bulk_input(resource, record, :list), do: [record]

  defp bulk_input(resource, record, :query),
    do: Ash.Query.filter(resource, id == ^record.id)

  defp versions(record) do
    Versioned.Version
    |> Ash.Query.filter(version_source_id == ^record.id)
    |> Ash.read!()
  end

  defp version_for(record, action_name) do
    Enum.find(versions(record), &(&1.version_action_name == action_name))
  end

  defp bulk_update!(input, action, params, opts) do
    assert %Ash.BulkResult{status: :success} =
             result =
             Ash.bulk_update(
               input,
               action,
               params,
               [strategy: :stream, return_errors?: true] ++ opts
             )

    result
  end

  describe "bulk writes of several records" do
    for input <- [:list, :query] do
      @input input
      test "[previous_values] bulk stream (#{input}) of 3: hook-set attribute and managed belongs_to",
           ctx do
        posts =
          for title <- ["A", "B", "C"],
              do: create!(PreviousValues, %{title: title, author_id: ctx.a.id}, ctx.creator)

        input =
          if @input == :list,
            do: posts,
            else: Ash.Query.filter(PreviousValues, id in ^Enum.map(posts, & &1.id))

        assert %Ash.BulkResult{records: increments} =
                 bulk_update!(input, :increment_views, %{},
                   as_of: @t2,
                   actor: ctx.updater,
                   return_records?: true
                 )

        assert length(increments) == 3

        input =
          if @input == :list,
            do: increments,
            else: Ash.Query.filter(PreviousValues, id in ^Enum.map(posts, & &1.id))

        assert %Ash.BulkResult{records: moves} =
                 bulk_update!(input, :move, %{author_id: ctx.b.id},
                   as_of: @t3,
                   actor: ctx.updater,
                   return_records?: true
                 )

        assert length(moves) == 3

        for post <- posts do
          assert stamp(PreviousValues, post, @t2) == %{
                   version_action_type: :update,
                   version_action_name: :increment_views,
                   user_id: ctx.updater.id,
                   changes: %{views: 0}
                 }

          assert stamp(PreviousValues, post, @t3) == %{
                   version_action_type: :update,
                   version_action_name: :move,
                   user_id: ctx.updater.id,
                   changes: %{author_id: ctx.a.id}
                 }
        end
      end
    end
  end

  describe "case 1: an attribute a before_action hook sets" do
    test "[changes_only] single, only change", ctx do
      post = create!(ChangesOnly, %{title: "A"}, ctx.creator)
      Ash.update!(post, %{}, action: :increment_views, as_of: @t2, actor: ctx.updater)

      assert stamp(ChangesOnly, post) == %{
               version_action_type: :update,
               version_action_name: :increment_views,
               user_id: ctx.updater.id,
               changes: %{views: 1}
             }
    end

    test "[previous_values] single, only change", ctx do
      post = create!(PreviousValues, %{title: "A"}, ctx.creator)
      Ash.update!(post, %{}, action: :increment_views, as_of: @t2, actor: ctx.updater)

      assert stamp(PreviousValues, post) == %{
               version_action_type: :update,
               version_action_name: :increment_views,
               user_id: ctx.updater.id,
               changes: %{views: 0}
             }
    end

    for input <- [:list, :query] do
      @input input
      test "[previous_values] bulk stream (#{input}), only change", ctx do
        post = create!(PreviousValues, %{title: "A"}, ctx.creator)

        PreviousValues
        |> bulk_input(post, @input)
        |> bulk_update!(:increment_views, %{}, as_of: @t2, actor: ctx.updater)

        assert stamp(PreviousValues, post) == %{
                 version_action_type: :update,
                 version_action_name: :increment_views,
                 user_id: ctx.updater.id,
                 changes: %{views: 0}
               }
      end
    end

    test "[previous_values] ignored action: stamp cleared, not inherited", ctx do
      post = create!(PreviousValues, %{title: "A"}, ctx.creator)
      Ash.update!(post, %{}, action: :ignored_increment, as_of: @t2, actor: ctx.updater)

      assert %{views: 1, version_action_type: nil, user_id: nil} = version(PreviousValues, post)
    end
  end

  describe "case 2: a record a before_action hook re-reads" do
    test "[previous_values] single", ctx do
      post = create!(PreviousValues, %{title: "A"}, ctx.creator)
      Ash.update!(post, %{title: "B"}, as_of: @t2)
      Ash.update!(post, %{title: "C"}, action: :update_refetched, as_of: @t3)

      assert %{title: "C", changes: %{title: "B"}} = version(PreviousValues, post, @t3)
    end

    test "[full_diff] single", ctx do
      post = create!(FullDiff, %{title: "A"}, ctx.creator)
      Ash.update!(post, %{title: "B"}, as_of: @t2)
      Ash.update!(post, %{title: "C"}, action: :update_refetched, as_of: @t3)

      assert %{title: "C", changes: %{title: %{from: "B", to: "C"}}} =
               version(FullDiff, post, @t3)
    end

    test "[previous_values] bulk stream (list)", ctx do
      post = create!(PreviousValues, %{title: "A"}, ctx.creator)
      Ash.update!(post, %{title: "B"}, as_of: @t2)
      bulk_update!([post], :update_refetched, %{title: "C"}, as_of: @t3)

      assert %{title: "C", changes: %{title: "B"}} = version(PreviousValues, post, @t3)
    end
  end

  describe "case 3: a managed belongs_to relationship" do
    test "[previous_values] single update, only change", ctx do
      post = create!(PreviousValues, %{title: "A", author_id: ctx.a.id}, ctx.creator)
      Ash.update!(post, %{author_id: ctx.b.id}, action: :move, as_of: @t2, actor: ctx.updater)

      assert stamp(PreviousValues, post) == %{
               version_action_type: :update,
               version_action_name: :move,
               user_id: ctx.updater.id,
               changes: %{author_id: ctx.a.id}
             }
    end

    test "[changes_only] single update, only change", ctx do
      post = create!(ChangesOnly, %{title: "A", author_id: ctx.a.id}, ctx.creator)
      Ash.update!(post, %{author_id: ctx.b.id}, action: :move, as_of: @t2, actor: ctx.updater)

      assert stamp(ChangesOnly, post) == %{
               version_action_type: :update,
               version_action_name: :move,
               user_id: ctx.updater.id,
               changes: %{author_id: ctx.b.id}
             }
    end

    test "[previous_values] single update, with another change", ctx do
      post = create!(PreviousValues, %{title: "A", author_id: ctx.a.id}, ctx.creator)

      Ash.update!(post, %{author_id: ctx.b.id, title: "B"},
        action: :move_and_retitle,
        as_of: @t2,
        actor: ctx.updater
      )

      assert %{changes: changes} = version(PreviousValues, post)
      assert changes == %{title: "A", author_id: ctx.a.id}
    end

    for input <- [:list, :query] do
      @input input
      test "[previous_values] bulk stream (#{input}), only change", ctx do
        post = create!(PreviousValues, %{title: "A", author_id: ctx.a.id}, ctx.creator)

        PreviousValues
        |> bulk_input(post, @input)
        |> bulk_update!(:move, %{author_id: ctx.b.id}, as_of: @t2, actor: ctx.updater)

        assert stamp(PreviousValues, post) == %{
                 version_action_type: :update,
                 version_action_name: :move,
                 user_id: ctx.updater.id,
                 changes: %{author_id: ctx.a.id}
               }
      end
    end

    test "[changes_only] create", ctx do
      post =
        Ash.create!(ChangesOnly, %{title: "A", author_id: ctx.a.id},
          action: :create_with_author,
          as_of: @t1,
          actor: ctx.creator
        )

      assert %{changes: changes} = version(ChangesOnly, post, @t1)
      assert changes == %{title: "A", author_id: ctx.a.id, views: 0}
    end

    test "[full_diff] create", ctx do
      post =
        Ash.create!(FullDiff, %{title: "A", author_id: ctx.a.id},
          action: :create_with_author,
          as_of: @t1,
          actor: ctx.creator
        )

      assert %{changes: %{author_id: %{to: author_id}}} = version(FullDiff, post, @t1)
      assert author_id == ctx.a.id
    end

    test "[changes_only] bulk create", ctx do
      %Ash.BulkResult{status: :success, records: [post]} =
        Ash.bulk_create([%{title: "A", author_id: ctx.a.id}], ChangesOnly, :create_with_author,
          as_of: @t1,
          actor: ctx.creator,
          return_records?: true,
          return_errors?: true
        )

      assert %{changes: changes} = version(ChangesOnly, post, @t1)
      assert changes == %{title: "A", author_id: ctx.a.id, views: 0}
    end

    test "[previous_values] managed in a before_transaction hook", ctx do
      post = create!(PreviousValues, %{title: "A", author_id: ctx.a.id}, ctx.creator)

      Ash.update!(post, %{author_id: ctx.b.id},
        action: :move_in_before_transaction,
        as_of: @t2,
        actor: ctx.updater
      )

      assert stamp(PreviousValues, post) == %{
               version_action_type: :update,
               version_action_name: :move_in_before_transaction,
               user_id: ctx.updater.id,
               changes: %{author_id: ctx.a.id}
             }
    end

    test "[previous_values] managed on a built changeset (as AshJsonApi's relationship routes do)",
         ctx do
      post = create!(PreviousValues, %{title: "A", author_id: ctx.a.id}, ctx.creator)

      post
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:author, %{id: ctx.b.id}, type: :append_and_remove)
      |> Ash.Changeset.for_update(:update_any, %{}, as_of: @t2, actor: ctx.updater)
      |> Ash.update!()

      assert stamp(PreviousValues, post) == %{
               version_action_type: :update,
               version_action_name: :update_any,
               user_id: ctx.updater.id,
               changes: %{author_id: ctx.a.id}
             }
    end
  end

  describe "case 4: a hook added to a built changeset" do
    test "[previous_values] before_action, only change", ctx do
      post = create!(PreviousValues, %{title: "A", body: "A"}, ctx.creator)

      post
      |> Ash.Changeset.for_update(:update, %{}, as_of: @t2, actor: ctx.updater)
      |> Ash.Changeset.before_action(&Ash.Changeset.force_change_attribute(&1, :body, "late"))
      |> Ash.update!()

      assert stamp(PreviousValues, post) == %{
               version_action_type: :update,
               version_action_name: :update,
               user_id: ctx.updater.id,
               changes: %{body: "A"}
             }
    end

    test "[previous_values] before_action, with another change", ctx do
      post = create!(PreviousValues, %{title: "A", body: "A"}, ctx.creator)

      post
      |> Ash.Changeset.for_update(:update, %{title: "B"}, as_of: @t2, actor: ctx.updater)
      |> Ash.Changeset.before_action(&Ash.Changeset.force_change_attribute(&1, :body, "late"))
      |> Ash.update!()

      assert %{changes: changes} = version(PreviousValues, post)
      assert changes == %{title: "A", body: "A"}
    end

    test "[previous_values] around_action that adds a before_action, only change", ctx do
      post = create!(PreviousValues, %{title: "A", body: "A"}, ctx.creator)

      post
      |> Ash.Changeset.for_update(:update, %{}, as_of: @t2, actor: ctx.updater)
      |> Ash.Changeset.around_action(fn changeset, callback ->
        changeset
        |> Ash.Changeset.before_action(&Ash.Changeset.force_change_attribute(&1, :body, "late"))
        |> callback.()
      end)
      |> Ash.update!()

      assert stamp(PreviousValues, post) == %{
               version_action_type: :update,
               version_action_name: :update,
               user_id: ctx.updater.id,
               changes: %{body: "A"}
             }
    end
  end

  describe "case 5: context set on a built changeset" do
    test "[previous_values] paper_trail_metadata set after for_update", ctx do
      post = create!(PreviousValues, %{title: "A"}, ctx.creator)

      post
      |> Ash.Changeset.for_update(:update, %{title: "B"}, as_of: @t2, actor: ctx.updater)
      |> Ash.Changeset.set_context(%{paper_trail_metadata: %{reason_for_change: "late"}})
      |> Ash.update!()

      assert %{reason_for_change: "late"} = version(PreviousValues, post)
    end

    test "[previous_values] paper_trail_metadata passed to Ash.update/2 with a built changeset",
         ctx do
      post = create!(PreviousValues, %{title: "A"}, ctx.creator)

      post
      |> Ash.Changeset.for_update(:update, %{title: "B"}, as_of: @t2, actor: ctx.updater)
      |> Ash.update!(context: %{paper_trail_metadata: %{reason_for_change: "late"}})

      assert %{reason_for_change: "late"} = version(PreviousValues, post)
    end

    test "[previous_values] ash_paper_trail_disabled? set after for_update clears the stamp",
         ctx do
      post = create!(PreviousValues, %{title: "A"}, ctx.creator)

      post
      |> Ash.Changeset.for_update(:update, %{title: "B"}, as_of: @t2, actor: ctx.updater)
      |> Ash.Changeset.set_context(%{ash_paper_trail_disabled?: true})
      |> Ash.update!()

      assert %{title: "B", version_action_type: nil, user_id: nil} = version(PreviousValues, post)
    end

    test "[control: version_resource] paper_trail_metadata set after for_update", ctx do
      post = Ash.create!(Versioned, %{title: "A"}, actor: ctx.creator)

      post
      |> Ash.Changeset.for_update(:update, %{title: "B"}, actor: ctx.updater)
      |> Ash.Changeset.set_context(%{paper_trail_metadata: %{reason_for_change: "late"}})
      |> Ash.update!()

      assert %{reason_for_change: "late"} = version_for(post, :update)
    end
  end

  describe "error paths" do
    test "[previous_values] single move to a missing author is an error, nothing written", ctx do
      post = create!(PreviousValues, %{title: "A", author_id: ctx.a.id}, ctx.creator)

      assert {:error, _} =
               Ash.update(post, %{author_id: Ash.UUID.generate()},
                 action: :move,
                 as_of: @t2,
                 actor: ctx.updater
               )

      assert %{version_action_type: :create, author_id: author_id} = version(PreviousValues, post)
      assert author_id == ctx.a.id
    end

    test "[previous_values] bulk move to a missing author is an error result, not a crash", ctx do
      post = create!(PreviousValues, %{title: "A", author_id: ctx.a.id}, ctx.creator)

      assert %Ash.BulkResult{status: :error} =
               Ash.bulk_update([post], :move, %{author_id: Ash.UUID.generate()},
                 strategy: :stream,
                 as_of: @t2,
                 actor: ctx.updater,
                 return_errors?: true
               )

      assert %{version_action_type: :create} = version(PreviousValues, post)
    end
  end

  describe "only_when_changed? false" do
    test "[previous_values] a managed belongs_to move", ctx do
      post = create!(AlwaysPreviousValues, %{title: "A", author_id: ctx.a.id}, ctx.creator)
      Ash.update!(post, %{author_id: ctx.b.id}, action: :move, as_of: @t2, actor: ctx.updater)

      assert stamp(AlwaysPreviousValues, post) == %{
               version_action_type: :update,
               version_action_name: :move,
               user_id: ctx.updater.id,
               changes: %{author_id: ctx.a.id}
             }
    end

    test "[previous_values] a late before_action", ctx do
      post = create!(AlwaysPreviousValues, %{title: "A", body: "A"}, ctx.creator)

      post
      |> Ash.Changeset.for_update(:update, %{title: "B"}, as_of: @t2, actor: ctx.updater)
      |> Ash.Changeset.before_action(&Ash.Changeset.force_change_attribute(&1, :body, "late"))
      |> Ash.update!()

      assert %{changes: %{title: "A", body: "A"}} = version(AlwaysPreviousValues, post)
    end

    test "[previous_values] a no-op update still writes a version", ctx do
      post = create!(AlwaysPreviousValues, %{title: "A"}, ctx.creator)
      Ash.update!(post, %{}, as_of: @t2, actor: ctx.updater)

      assert %{version_action_type: :update, user_id: user_id, valid_at: %{lower: @t2}} =
               version(AlwaysPreviousValues, post)

      assert user_id == ctx.updater.id
    end
  end

  describe "unaffected paths (must keep passing)" do
    test "[previous_values] a non-atomic update with an atomic change", ctx do
      post = create!(PreviousValues, %{title: "A"}, ctx.creator)

      Ash.update!(post, %{title: "B"},
        action: :refetch_and_bump,
        as_of: @t2,
        actor: ctx.updater
      )

      assert %{title: "B", views: 1, changes: changes} = version(PreviousValues, post)
      assert changes == %{title: "A", views: 0}
    end

    test "[previous_values] a no-op update writes no version", ctx do
      post = create!(PreviousValues, %{title: "A"}, ctx.creator)
      Ash.update!(post, %{}, as_of: @t2, actor: ctx.updater)

      assert %{version_action_type: :create, valid_at: %{lower: @t1}} =
               version(PreviousValues, post)
    end

    test "[previous_values] a no-op update in bulk writes no version", ctx do
      post = create!(PreviousValues, %{title: "A"}, ctx.creator)
      bulk_update!([post], :update, %{}, as_of: @t2, actor: ctx.updater)

      assert %{version_action_type: :create, valid_at: %{lower: @t1}} =
               version(PreviousValues, post)
    end

    test "[previous_values] an atomic update", ctx do
      post = create!(PreviousValues, %{title: "A"}, ctx.creator)
      Ash.update!(post, %{title: "B"}, action: :update_atomic, as_of: @t2, actor: ctx.updater)

      assert stamp(PreviousValues, post) == %{
               version_action_type: :update,
               version_action_name: :update_atomic,
               user_id: ctx.updater.id,
               changes: %{title: "A"}
             }
    end

    test "[previous_values] a bulk atomic update", ctx do
      post = create!(PreviousValues, %{title: "A"}, ctx.creator)

      PreviousValues
      |> Ash.Query.filter(id == ^post.id)
      |> Ash.bulk_update!(:update_atomic, %{title: "B"},
        strategy: :atomic,
        as_of: @t2,
        actor: ctx.updater,
        return_errors?: true
      )

      assert stamp(PreviousValues, post) == %{
               version_action_type: :update,
               version_action_name: :update_atomic,
               user_id: ctx.updater.id,
               changes: %{title: "A"}
             }
    end

    test "[previous_values] a plain non-atomic update", ctx do
      post = create!(PreviousValues, %{title: "A"}, ctx.creator)
      Ash.update!(post, %{title: "B"}, as_of: @t2, actor: ctx.updater)

      assert stamp(PreviousValues, post) == %{
               version_action_type: :update,
               version_action_name: :update,
               user_id: ctx.updater.id,
               changes: %{title: "A"}
             }
    end

    test "[changes_only] a create", ctx do
      post = create!(ChangesOnly, %{title: "A"}, ctx.creator)

      assert stamp(ChangesOnly, post, @t1) == %{
               version_action_type: :create,
               version_action_name: :create,
               user_id: ctx.creator.id,
               changes: %{title: "A", views: 0}
             }
    end

    for {label, opts} <- [
          {"single", nil},
          {"bulk stream, list", {:list, :stream}},
          {"bulk stream, query", {:query, :stream}},
          {"bulk atomic, query", {:query, :atomic}}
        ] do
      @opts opts
      test "[changes_only] soft destroy: #{label}", ctx do
        post = create!(ChangesOnly, %{title: "A"}, ctx.creator)

        case @opts do
          nil ->
            Ash.destroy!(post, action: :archive, as_of: @t2, actor: ctx.updater)

          {input, strategy} ->
            assert %Ash.BulkResult{status: :success} =
                     ChangesOnly
                     |> bulk_input(post, input)
                     |> Ash.bulk_destroy(:archive, %{},
                       actor: ctx.updater,
                       as_of: @t2,
                       strategy: strategy,
                       return_errors?: true
                     )
        end

        v = version(ChangesOnly, post)
        assert %{version_action_type: :destroy, version_action_name: :archive} = v
        assert v.user_id == ctx.updater.id
        refute is_nil(v.archived_at)
      end
    end
  end

  describe "control: :version_resource mode" do
    test "a hook-set attribute is recorded", ctx do
      post = Ash.create!(Versioned, %{title: "A"}, actor: ctx.creator)
      Ash.update!(post, %{}, action: :increment_views, actor: ctx.updater)

      assert %{changes: %{views: 1}} = version_for(post, :increment_views)
    end

    test "a managed belongs_to move is recorded", ctx do
      post = Ash.create!(Versioned, %{title: "A", author_id: ctx.a.id}, actor: ctx.creator)
      Ash.update!(post, %{author_id: ctx.b.id}, action: :move, actor: ctx.updater)

      assert %{changes: %{author_id: author_id}} = version_for(post, :move)
      assert author_id == ctx.b.id
    end

    test "a managed belongs_to on create is recorded", ctx do
      post =
        Ash.create!(Versioned, %{title: "A", author_id: ctx.a.id},
          action: :create_with_author,
          actor: ctx.creator
        )

      assert %{changes: %{author_id: author_id}} = version_for(post, :create_with_author)
      assert author_id == ctx.a.id
    end

    # Separate gap, in Ash: a single update gives after_action hooks the changeset from before
    # Ash set up managed belongs_to relationships managed in before_transaction hooks.
    @tag :skip
    test "a relationship managed in a before_transaction hook is recorded", ctx do
      post = Ash.create!(Versioned, %{title: "A", author_id: ctx.a.id}, actor: ctx.creator)

      updated =
        Ash.update!(post, %{author_id: ctx.b.id},
          action: :move_in_before_transaction,
          actor: ctx.updater
        )

      assert updated.author_id == ctx.b.id
      assert %{changes: %{author_id: author_id}} = version_for(post, :move_in_before_transaction)
      assert author_id == ctx.b.id
    end

    test "a late before_action is recorded", ctx do
      post = Ash.create!(Versioned, %{title: "A", body: "A"}, actor: ctx.creator)

      post
      |> Ash.Changeset.for_update(:update, %{}, actor: ctx.updater)
      |> Ash.Changeset.before_action(&Ash.Changeset.force_change_attribute(&1, :body, "late"))
      |> Ash.update!()

      assert %{changes: %{body: "late"}} = version_for(post, :update)
    end
  end
end
