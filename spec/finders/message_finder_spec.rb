require 'rails_helper'

describe MessageFinder do
  subject(:message_finder) { described_class.new(conversation, params) }

  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:contact) { create(:contact, email: nil) }
  let!(:conversation) do
    create(:conversation, account: account, inbox: inbox, assignee: user, contact: contact)
  end

  before do
    create(:message, account: account, inbox: inbox, conversation: conversation)
    create(:message, message_type: 'activity', account: account, inbox: inbox, conversation: conversation)
    create(:message, message_type: 'activity', account: account, inbox: inbox, conversation: conversation)
    # this outgoing message creates 2 additional messages because of the email hook execution service
    create(:message, message_type: 'outgoing', account: account, inbox: inbox, conversation: conversation)
  end

  describe '#perform' do
    context 'with filter_internal_messages false' do
      let(:params) { { filter_internal_messages: false } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 6
      end
    end

    context 'with filter_internal_messages true' do
      let(:params) { { filter_internal_messages: true } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 4
      end
    end

    context 'with before attribute' do
      let!(:outgoing) { create(:message, message_type: 'outgoing', account: account, inbox: inbox, conversation: conversation) }
      let(:params) { { before: outgoing.id } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 6
      end
    end

    context 'with a before attribute above the message id range' do
      let!(:max_id_message) do
        create(:message, id: described_class::MESSAGE_ID_MAX, account: account, inbox: inbox, conversation: conversation)
      end
      let(:params) { { before: 4_611_686_018_427_387_903 } }

      it 'includes the maximum valid message id without overflowing the database column' do
        expect(message_finder.perform).to include(max_id_message)
      end
    end

    context 'with after attribute' do
      let(:params) { { after: conversation.messages.first.id } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 5
        expect(result.first.id).to be conversation.messages.second.id
        expect(result.last.message_type).to eq 'outgoing'
      end
    end

    context 'with an after attribute above the message id range' do
      let(:params) { { after: 881_965_304_328 } }

      it 'returns no messages without overflowing the database column' do
        expect(message_finder.perform).to be_empty
      end
    end

    context 'with after and before attribute' do
      let(:params) do
        {
          after: conversation.messages.first.id,
          before: conversation.messages.last.id
        }
      end

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 5
        expect(result.last.id).to be conversation.messages[-2].id
      end
    end

    context 'with after and before attributes above the message id range' do
      let!(:max_id_message) do
        create(:message, id: described_class::MESSAGE_ID_MAX, account: account, inbox: inbox, conversation: conversation)
      end
      let(:params) do
        {
          after: 881_965_304_328,
          before: 4_611_686_018_427_387_903
        }
      end

      it 'returns no messages' do
        result = message_finder.perform

        expect(result).to be_empty
        expect(result).not_to include(max_id_message)
      end
    end

    # PATCH MAIAN: o import de reconexao da Evolution grava mensagem antiga com id novo.
    context 'when an older message is imported with a newer id' do
      let!(:imported) do
        create(:message, account: account, inbox: inbox, conversation: conversation, created_at: 1.day.ago)
      end
      let(:oldest_native_id) { conversation.messages.where.not(id: imported.id).order(:id).first.id }

      context 'when scrolling back from the oldest native message' do
        let(:params) { { before: oldest_native_id } }

        it 'still reaches the imported message' do
          expect(message_finder.perform).to include(imported)
        end
      end

      context 'when loading newer messages after the oldest native message' do
        let(:params) { { after: oldest_native_id } }

        it 'does not bring the imported message out of chronological order' do
          expect(message_finder.perform).not_to include(imported)
        end
      end
    end

    context 'with a before cursor from another conversation' do
      let(:other_message) do
        create(:message, account: account, inbox: inbox, conversation: create(:conversation, account: account, inbox: inbox))
      end
      let(:params) { { before: other_message.id } }

      it 'falls back to the id window of the upstream finder' do
        expect(message_finder.perform.map(&:id)).to all(be < other_message.id)
      end
    end
  end
end
