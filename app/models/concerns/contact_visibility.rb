# PATCH MAIAN — escopo da aba Contatos por inbox do agente.
#
# Contatos pertencem a conta inteira no Chatwoot, entao a aba Contatos expunha a carteira de todos
# os vendedores entre si. Administradores continuam vendo tudo; agentes veem so os contatos
# vinculados (contact_inboxes) as inboxes das quais participam.
#
# A conta e argumento EXPLICITO de proposito. A primeira versao usava User#administrator? e
# User#assigned_inboxes, que dependem de Current.account: fora de uma requisicao web (job de
# exportacao, services) administrator? devolvia nil ate para administrador e assigned_inboxes
# explodia em `Current.account.id`.
#
# Incluido no Contact por config/initializers/maian_contact_visibility.rb, para que
# app/models/contact.rb continue identico ao upstream (a classe ja esta no limite do rubocop).
module ContactVisibility
  extend ActiveSupport::Concern

  included do
    scope :visible_to, lambda { |user, account|
      account_user = user.account_users.find_by(account_id: account.id)
      next none if account_user.nil?
      next all if account_user.administrator?

      agent_inbox_ids = InboxMember.joins(:inbox).where(user_id: user.id, inboxes: { account_id: account.id }).select(:inbox_id)
      where(id: ContactInbox.where(inbox_id: agent_inbox_ids).select(:contact_id))
    }
  end
end
