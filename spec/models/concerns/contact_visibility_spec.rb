require 'rails_helper'

# PATCH MAIAN — ver app/models/concerns/contact_visibility.rb.
RSpec.describe ContactVisibility do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:own_contact) { create(:contact, account: account) }
  let!(:other_contact) { create(:contact, account: account) }

  before do
    # Sem requisicao web nao existe Current.account: e o cenario do job de exportacao.
    Current.reset
    create(:contact_inbox, contact: own_contact, inbox: inbox)
    create(:contact_inbox, contact: other_contact, inbox: create(:inbox, account: account))
  end

  context 'when the user is an administrator of the account' do
    let(:user) { create(:user, account: account, role: :administrator) }

    it 'returns every contact of the account' do
      expect(Contact.visible_to(user, account)).to include(own_contact, other_contact)
    end
  end

  context 'when the user is an agent of the account' do
    let(:user) { create(:user, account: account, role: :agent) }

    before { create(:inbox_member, user: user, inbox: inbox) }

    it 'returns only contacts linked to the agent inboxes' do
      expect(Contact.visible_to(user, account)).to contain_exactly(own_contact)
    end

    it 'works without Current.account' do
      expect(Current.account).to be_nil
      expect { Contact.visible_to(user, account).to_a }.not_to raise_error
    end
  end

  context 'when the agent only belongs to inboxes of another account' do
    let(:user) { create(:user, account: account, role: :agent) }

    before do
      foreign_account = create(:account)
      create(:account_user, account: foreign_account, user: user, role: :agent)
      foreign_inbox = create(:inbox, account: foreign_account)
      create(:inbox_member, user: user, inbox: foreign_inbox)
      create(:contact_inbox, contact: create(:contact, account: foreign_account), inbox: foreign_inbox)
    end

    it 'returns no contact of this account' do
      expect(Contact.visible_to(user, account)).to be_empty
    end
  end

  context 'when the user does not belong to the account' do
    let(:user) { create(:user, account: create(:account), role: :administrator) }

    it 'returns no contact, even for an administrator of another account' do
      expect(Contact.visible_to(user, account)).to be_empty
    end
  end
end
