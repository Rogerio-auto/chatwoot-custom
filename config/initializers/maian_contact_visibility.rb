# PATCH MAIAN — ver app/models/concerns/contact_visibility.rb.
Rails.application.config.to_prepare do
  Contact.include(ContactVisibility)
end
