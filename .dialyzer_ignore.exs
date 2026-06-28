# Dialyzer warnings to ignore (matched by dialyxir).
#
# Gettext 1.0 + Expo 1.1 generate a `Gettext.Plural.plural/2` call against Expo's
# *opaque* `PluralForms` struct inside the generated backend (`use Gettext.Backend`),
# which Dialyzer reports as `call_without_opaque` at `gettext.ex:1`. It's a known
# upstream false positive in code we don't author — scoped narrowly to the backend
# module and that one warning type so real issues elsewhere still surface.
[
  {"lib/phoenix_kit_crm/gettext.ex", :call_without_opaque}
]
