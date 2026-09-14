# PATCH MAIAN — paginar pela mesma chave que ordena: a tupla (created_at, id).
#
# O upstream ORDENA por `created_at` e PAGINA por `id`. O import de reconexão da Evolution grava
# mensagem ANTIGA com id NOVO, as duas ordens divergem e a rolagem pula blocos inteiros. Medido em
# 20/08/2026: 2.986 mensagens inalcançáveis em 282 conversas (conversa 3853: 131 de 160). Nada é
# apagado; a interface só nunca consegue carregar. Com a tupla, 0.
#
# A partir da v4.17.1 o upstream também limita ids ao teto do int4 (MESSAGE_ID_MAX) para não
# estourar 500 com cursor gigante. As duas proteções convivem: o teto é checado antes, e quando o
# id recebido não existe na conversa o finder cai exatamente no comportamento do upstream.
class MessageFinder
  MESSAGE_ID_MAX = 2_147_483_647
  ORDER_ASC = 'messages.created_at asc, messages.id asc'.freeze
  ORDER_DESC = 'messages.created_at desc, messages.id desc'.freeze

  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    current_messages
  end

  private

  def conversation_messages
    @conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def messages
    return conversation_messages if @params[:filter_internal_messages].blank?

    conversation_messages.where.not('private = ? OR message_type = ?', true, 2)
  end

  def current_messages
    return messages.none if oversized_message_id?(@params[:after])

    if @params[:after].present? && @params[:before].present?
      messages_between(normalized_message_id(@params[:after]), @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(normalized_message_id(@params[:after]))
    else
      messages_latest
    end
  end

  def messages_after(after_id)
    paginate(messages.reorder(ORDER_ASC), after_id, '>').limit(100)
  end

  def messages_before(before_id)
    return messages_latest if oversized_message_id?(before_id)

    paginate(messages.reorder(ORDER_DESC), normalized_message_id(before_id), '<').limit(20).reverse
  end

  def messages_between(after_id, before_id)
    message_scope = paginate(messages.reorder(ORDER_ASC), after_id, '>=')
    message_scope = paginate(message_scope, normalized_message_id(before_id), '<') unless oversized_message_id?(before_id)
    message_scope.limit(1000)
  end

  def messages_latest
    messages.reorder(ORDER_DESC).limit(20).reverse
  end

  # A API recebe um id como cursor, mas a lista é exibida por data. Resolver o id para o par
  # (created_at, id) é o que permite paginar na mesma ordem em que se exibe. `operator` é sempre
  # uma constante deste arquivo, nunca entrada do usuário.
  def paginate(scope, message_id, operator)
    position = @conversation.messages.where(id: message_id).pick(:created_at, :id)
    return scope.where("messages.id #{operator} ?", message_id) if position.nil?

    scope.where("(messages.created_at, messages.id) #{operator} (?, ?)", *position)
  end

  def normalized_message_id(value)
    value.to_i.clamp(0, MESSAGE_ID_MAX)
  end

  def oversized_message_id?(value)
    value.to_i > MESSAGE_ID_MAX
  end
end

MessageFinder.prepend_mod_with('MessageFinder')
