defmodule PhoenixKitCRM.I18nTest do
  @moduledoc """
  Smoke test for the per-module i18n wiring.

  Confirms that:
    * Every admin tab registered by `PhoenixKitCRM.admin_tabs/0`
      carries `gettext_backend: PhoenixKitCRM.Gettext`.
    * Locale switching on the module's own backend produces translated
      labels for at least one well-known msgid (regression guard for
      the `priv/gettext/<locale>/LC_MESSAGES/default.po` shipping with
      the package).
    * Falls back to the raw msgid for an unknown locale.
  """

  use ExUnit.Case, async: true

  # Excluded by `test/test_helper.exs` when running against a `phoenix_kit`
  # release that pre-dates the `gettext_backend` API (PR BeamLabEU/phoenix_kit#522).
  # Once the consumer's `phoenix_kit` dep resolves to a release that ships
  # `Tab.localized_label/1`, the helper detects it and these tests run
  # automatically — no follow-up edit needed.
  @moduletag :requires_phoenix_kit_i18n_api

  alias PhoenixKit.Dashboard.Tab
  alias PhoenixKitCRM.Gettext, as: CRMGettext

  describe "admin_tabs/0 wiring" do
    test "every tab carries the module's own gettext backend" do
      for tab <- PhoenixKitCRM.admin_tabs() do
        assert tab.gettext_backend == CRMGettext,
               "Tab #{inspect(tab.id)} is missing or wrong gettext_backend " <>
                 "(got #{inspect(tab.gettext_backend)})"
      end
    end
  end

  describe "Tab.localized_label/1 against the module's catalogue" do
    test "ru locale resolves the parent 'CRM' tab to 'CRM'" do
      parent = Enum.find(PhoenixKitCRM.admin_tabs(), &(&1.id == :admin_crm))

      Gettext.with_locale(CRMGettext, "ru", fn ->
        assert Tab.localized_label(parent) == "CRM"
      end)
    end

    test "ru locale resolves the 'Overview' tab to 'Обзор'" do
      tab = Enum.find(PhoenixKitCRM.admin_tabs(), &(&1.id == :admin_crm_overview))

      Gettext.with_locale(CRMGettext, "ru", fn ->
        assert Tab.localized_label(tab) == "Обзор"
      end)
    end

    test "et locale resolves the 'Overview' tab to 'Ülevaade'" do
      tab = Enum.find(PhoenixKitCRM.admin_tabs(), &(&1.id == :admin_crm_overview))

      Gettext.with_locale(CRMGettext, "et", fn ->
        assert Tab.localized_label(tab) == "Ülevaade"
      end)
    end

    test "unknown locale falls back to the raw msgid" do
      parent = Enum.find(PhoenixKitCRM.admin_tabs(), &(&1.id == :admin_crm))

      Gettext.with_locale(CRMGettext, "zz", fn ->
        assert Tab.localized_label(parent) == parent.label
      end)
    end
  end
end
