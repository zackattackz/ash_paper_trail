# SPDX-FileCopyrightText: 2022 ash_paper_trail contributors <https://github.com/ash-project/ash_paper_trail/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPaperTrail.Test.Posts.TemporalFullDiffPost do
  @moduledoc """
  A temporal resource versioned in `:temporal_inline` mode with `:full_diff` tracking.
  """

  use Ash.Resource,
    domain: AshPaperTrail.Test.Posts.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshPaperTrail.Resource],
    validate_domain_inclusion?: false

  ets do
    private? true
  end

  temporal do
    strategy :context
    attribute :valid_at
  end

  paper_trail do
    mode(:temporal_inline)
    change_tracking_mode :full_diff
    ignore_attributes [:inserted_at, :updated_at]
  end

  code_interface do
    define :create
    define :read
    define :update
    define :update_refetched
  end

  actions do
    default_accept :*
    defaults [:read, create: :*, update: :*]

    update :update_refetched do
      require_atomic? false
      change AshPaperTrail.Test.Posts.Refetch
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :subject, :string do
      public? true
      allow_nil? false
    end

    attribute :body, :string do
      public? true
    end

    attribute :views, :integer do
      public? true
      default 0
      allow_nil? false
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
