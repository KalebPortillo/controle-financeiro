require "test_helper"

# A Connection identifica o usuário lendo o cookie de sessão encriptado
# (mesmo cookie HTTP-only do login) via cookies.encrypted — em API mode o Cable
# não roda o middleware de sessão.
#
# Nota de teste: o ActionCable::Connection::TestCase troca o cookie jar por um
# TestCookieJar em que `cookies.encrypted` NUNCA faz round-trip (retorna nil),
# então não dá pra forjar uma sessão encriptada válida aqui. Cobrimos a rejeição
# (sem cookie → recusa, segurança); o caminho feliz cookie→User é verificado
# pelo BankConnectionsChannelTest (via stub_connection) + checagem manual no
# browser contra o /cable real.
class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "rejeita conexão sem sessão válida" do
    assert_reject_connection { connect }
  end
end
