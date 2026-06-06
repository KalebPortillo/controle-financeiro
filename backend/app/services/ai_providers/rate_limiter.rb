module AiProviders
  # Throttle simples pra caber no RPM do free tier do Gemini. A fila ai_suggestion
  # roda 1 thread/1 processo, então um estado em memória (timestamp da última
  # chamada) basta pra espaçar as chamadas. Intervalo via ENV
  # AI_MIN_REQUEST_INTERVAL (segundos); default ~6,5s (≈9/min, sob 10 RPM).
  # 0 desliga (usado em teste).
  class RateLimiter
    DEFAULT_INTERVAL = 6.5
    MUTEX = Mutex.new

    class << self
      def interval
        ENV.fetch("AI_MIN_REQUEST_INTERVAL", DEFAULT_INTERVAL.to_s).to_f
      end

      # Bloqueia até passar o intervalo mínimo desde a última chamada. clock/sleeper
      # injetáveis pra teste. Usa relógio monotônico (imune a ajuste de hora).
      def throttle!(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, sleeper: method(:sleep))
        gap = interval
        return if gap <= 0

        MUTEX.synchronize do
          now = clock.call
          if @last_at && (wait = @last_at + gap - now) > 0
            sleeper.call(wait)
            now = @last_at + gap
          end
          @last_at = now
        end
      end

      def reset!
        MUTEX.synchronize { @last_at = nil }
      end
    end
  end
end
