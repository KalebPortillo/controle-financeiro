require "test_helper"

# Wrapper assíncrono do Imports::Process (RF20). O contrato do JOB: marcar
# processing, delegar pro service com o import certo, e garantir status failed
# em erro inesperado — a UI faz polling do status e não pode ficar presa em
# "processing". O processamento em si (parse, dedup, contadores) tem cobertura
# própria em test/services/imports/process_test.rb.
#
# Sem Active Storage aqui de propósito: `file.attach` em teste paralelo tem uma
# corrida de teardown conhecida (ver quarentena no test_helper) — stubar o
# service mantém este teste determinístico e focado no contrato do wrapper.
class Imports::ProcessJobTest < ActiveJob::TestCase
  setup do
    @workspace  = create(:workspace)
    @membership = create(:workspace_membership, workspace: @workspace)
    @import     = @workspace.imports.create!(uploaded_by_membership: @membership,
                                             filename: "x.csv", format: "csv", file_size_bytes: 42)
  end

  # Substitui Imports::Process.call dentro do bloco, capturando os kwargs.
  def with_process_stub(raises: nil)
    original = Imports::Process.method(:call)
    captured = []
    Imports::Process.define_singleton_method(:call) do |**kwargs|
      captured << kwargs
      raise raises if raises
    end
    yield captured
  ensure
    Imports::Process.define_singleton_method(:call, original)
  end

  test "marca processing e delega pro Imports::Process com o import" do
    with_process_stub do |captured|
      Imports::ProcessJob.perform_now(@import.id)

      assert_equal [ @import ], captured.map { |kw| kw[:import] }
      # O stub não completa; o status observável é o que o JOB setou.
      assert_equal "processing", @import.reload.status
    end
  end

  test "import apagado entre enqueue e perform → no-op" do
    with_process_stub do |captured|
      assert_nothing_raised do
        Imports::ProcessJob.perform_now(SecureRandom.uuid)
      end
      assert_empty captured
    end
  end

  test "erro inesperado marca failed e re-levanta (UI não fica presa em processing)" do
    with_process_stub(raises: RuntimeError.new("boom")) do
      assert_raises(RuntimeError) do
        Imports::ProcessJob.perform_now(@import.id)
      end
      assert_equal "failed", @import.reload.status
    end
  end
end
