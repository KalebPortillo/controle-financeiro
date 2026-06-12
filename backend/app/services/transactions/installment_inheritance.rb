module Transactions
  # Herança entre parcelas do mesmo parcelamento (RF9.4.2). Quando uma parcela
  # nova chega no sync, decide o que ela herda das irmãs (mesmo
  # installment_group_id no workspace):
  #   - título/tags da irmã representativa (consolidada mais recente, ou a com
  #     título mais recente);
  #   - auto-consolidação: se há QUALQUER irmã consolidada (o usuário já revisou
  #     a compra), a nova parcela entra consolidada e pula a IA.
  # Sem irmã relevante → nil (parcela segue o fluxo normal: pending, crua, IA).
  module InstallmentInheritance
    Result = Struct.new(:improved_title, :tags, :consolidated, keyword_init: true)

    module_function

    def for(account:, group_id:)
      return nil if group_id.blank?

      siblings = account.workspace.transactions
                        .where(installment_group_id: group_id)
                        .includes(:tags).to_a
      return nil if siblings.empty?

      consolidated = siblings.any? { |s| s.status == "consolidated" }
      rep = siblings.select { |s| s.status == "consolidated" }.max_by(&:installment_number) ||
            siblings.select { |s| s.improved_title.present? }.max_by(&:installment_number)
      return nil if rep.nil? && !consolidated

      rep ||= siblings.max_by(&:installment_number)
      Result.new(improved_title: rep.improved_title, tags: rep.tags.to_a, consolidated: consolidated)
    end
  end
end
