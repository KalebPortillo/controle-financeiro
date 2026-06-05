module Imports
  # Wrapper assíncrono (Solid Queue) sobre Imports::Process. Marca o import como
  # processing, roda o processamento e, em erro inesperado, garante o status
  # failed pra UI não ficar presa em "processing".
  class ProcessJob < ApplicationJob
    queue_as :default

    def perform(import_id)
      import = Import.find_by(id: import_id)
      return unless import

      import.processing!
      Imports::Process.call(import: import)
    rescue StandardError => e
      import&.fail!(e.message) unless import&.reload&.status == "failed"
      raise
    end
  end
end
