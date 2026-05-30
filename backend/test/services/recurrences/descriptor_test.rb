require "test_helper"

class Recurrences::DescriptorTest < ActiveSupport::TestCase
  test "normaliza removendo dígitos, pontuação, caixa e espaços" do
    assert_equal "NETFLIX COM", Recurrences::Descriptor.normalize("NETFLIX.COM 4821")
    assert_equal "NETFLIX COM", Recurrences::Descriptor.normalize("netflix.com  5530")
    assert_equal "PADARIA IPIRANGA SP", Recurrences::Descriptor.normalize("PADARIA IPIRANGA SP 12")
  end

  test "string vazia/nula vira string vazia" do
    assert_equal "", Recurrences::Descriptor.normalize(nil)
    assert_equal "", Recurrences::Descriptor.normalize("123 456")
  end
end
