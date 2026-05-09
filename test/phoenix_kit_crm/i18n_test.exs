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

  use ExUnit.Case, async: false

  # Excluded by `test/test_helper.exs` when running against a `phoenix_kit`
  # release that pre-dates the `gettext_backend` API (PR BeamLabEU/phoenix_kit#522).
  # Once the consumer's `phoenix_kit` dep resolves to a release that ships
  # `Tab.localized_label/1`, the helper detects it and these tests run
  # automatically — no follow-up edit needed.
  @moduletag :requires_phoenix_kit_i18n_api

  alias PhoenixKit.Dashboard.Tab
  alias PhoenixKitCRM.Gettext, as: CRMGettext

  setup do
    original = Gettext.get_locale(CRMGettext)
    on_exit(fn -> Gettext.put_locale(CRMGettext, original) end)
    :ok
  end

  describe "admin_tabs/0 wiring" do
    test "every tab carries the module's own gettext backend" do
      for tab <- PhoenixKitCRM.admin_tabs() do
        assert tab.gettext_backend == CRMGettext,
               "Tab #{inspect(tab.id)} is missing or wrong gettext_backend " <>
                 "(got #{inspect(tab.gettext_backend)})"

        assert tab.gettext_domain == "default"
      end
    end
  end

  describe "Tab.localized_label/1 against the module's catalogue" do
    test "ru locale resolves the parent 'CRM' tab to 'CRM'" do
      Gettext.put_locale(CRMGettext, "ru")

      parent = Enum.find(PhoenixKitCRM.admin_tabs(), &(&1.id == :admin_crm))
      assert Tab.localized_label(parent) == "CRM"
    end

    test "ru locale resolves the 'Overview' tab to 'Обзор'" do
      Gettext.put_locale(CRMGettext, "ru")

      tab = Enum.find(PhoenixKitCRM.admin_tabs(), &(&1.id == :admin_crm_overview))
      assert Tab.localized_label(tab) == "Обзор"
    end

    test "et locale resolves the 'Overview' tab to 'Ülevaade'" do
      Gettext.put_locale(CRMGettext, "et")

      tab = Enum.find(PhoenixKitCRM.admin_tabs(), &(&1.id == :admin_crm_overview))
      assert Tab.localized_label(tab) == "Ülevaade"
    end

    test "unknown locale falls back to the raw msgid" do
      Gettext.put_locale(CRMGettext, "zz")

      parent = Enum.find(PhoenixKitCRM.admin_tabs(), &(&1.id == :admin_crm))
      assert Tab.localized_label(parent) == parent.label
    end
  end
end
