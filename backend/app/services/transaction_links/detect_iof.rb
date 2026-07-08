module TransactionLinks
  # RF23 — liga cada IOF de compra internacional ao gasto (compra em moeda
  # estrangeira) que o originou. O Pluggy não referencia a compra no IOF, mas a
  # alíquota é fixa (3,5%): a compra de origem é aquela cujo valor × 3,5% (por
  # centavo) bate com o IOF, na mesma conta e numa janela de datas. IOFs nomeados
  # (`IOF de "Loja"`) usam o comerciante pra desambiguar. Atribuição 1:1 gulosa
  # (cada compra origina um IOF). Idempotente: pula IOF já vinculado.
  module DetectIof
    RATE          = 0.035          # alíquota do IOF de compra internacional
    WINDOW_BEFORE = 35             # dias: o IOF posta depois da compra
    WINDOW_AFTER  = 5
    CONFIDENCE    = 0.99

    module_function

    def call(workspace:)
      created = 0
      workspace.accounts.find_each do |account|
        created += detect_for_account(account)
      end
      created
    end

    def detect_for_account(account)
      scope   = account.transactions
      used    = already_linked_purchase_ids(scope)
      created = 0

      iof_debits(scope).sort_by(&:occurred_at).each do |iof|
        next if iof.link_as_related&.relation_type == "iof"

        purchase = best_match(scope, iof, used)
        next unless purchase

        TransactionLink.create!(
          workspace:           account.workspace,
          primary_transaction: purchase,
          related_transaction: iof,
          relation_type:       "iof",
          origin:              "automatic",
          confidence:          CONFIDENCE
        )
        used << purchase.id
        created += 1
      end
      created
    end

    # --- seleção ---------------------------------------------------------------

    def best_match(scope, iof, used)
      candidates = foreign_purchases(scope, iof).reject { |c| used.include?(c.id) }
                     .select { |c| (c.amount_cents * RATE).round == iof.amount_cents }
      return if candidates.empty?

      if (merchant = named_merchant(iof))
        named = candidates.select { |c| c.original_description.to_s.downcase.include?(merchant) }
        candidates = named if named.any?
      end
      # Mais próxima em data (a compra imediatamente anterior ao IOF).
      candidates.min_by { |c| (iof.occurred_at - c.occurred_at).abs }
    end

    def foreign_purchases(scope, iof)
      scope.where(direction: "debit", account_id: iof.account_id)
           .where(occurred_at: (iof.occurred_at - WINDOW_BEFORE)..(iof.occurred_at + WINDOW_AFTER))
           .where.not(id: iof.id)
           .includes(:account) # foreign? lê account.currency — preload evita N+1
           .select { |t| t.foreign? && !iof_debit?(t) }
    end

    # --- classificação --------------------------------------------------------

    def iof_debits(scope)
      scope.where(direction: "debit").select { |t| iof_debit?(t) }
    end

    def iof_debit?(t)
      return false unless t.direction == "debit"

      t.original_description.to_s.downcase.include?("iof") ||
        t.source_metadata&.dig("creditCardMetadata", "feeTypeAdditionalInfo") == "IOF_COMPRA_INTERNACIONAL"
    end

    # Comerciante entre aspas em `IOF de "Loja"` (minúsculo, sem pontuação).
    def named_merchant(iof)
      raw = iof.original_description.to_s[/"([^"]+)"/, 1]
      return unless raw

      token = raw.downcase.gsub(/[^a-z0-9 ]/, " ").split.first
      token if token && token.length >= 4
    end

    def already_linked_purchase_ids(scope)
      TransactionLink.where(relation_type: "iof", related_transaction_id: scope.select(:id))
                     .pluck(:primary_transaction_id).to_set
    end
  end
end
