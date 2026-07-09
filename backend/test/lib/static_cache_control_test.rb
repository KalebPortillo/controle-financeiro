require "test_helper"
require Rails.root.join("lib/static_cache_control").to_s

# Garante que o shell do SPA revalida (no-cache) e os assets hasheados seguem
# imutáveis — impede o app de travar numa versão antiga em cache.
class StaticCacheControlTest < ActiveSupport::TestCase
  IMMUTABLE = "public, max-age=31556952".freeze

  def downstream
    ->(_env) { [ 200, { "cache-control" => IMMUTABLE }, [ "body" ] ] }
  end

  def call(path)
    StaticCacheControl.new(downstream).call("PATH_INFO" => path)
  end

  test "shell revalida (no-cache)" do
    %w[/ /index.html /sw.js /manifest.webmanifest /inbox.html].each do |path|
      _status, headers, _body = call(path)
      assert_equal "no-cache", headers["cache-control"], "esperava no-cache em #{path}"
    end
  end

  test "assets hasheados seguem imutáveis" do
    _status, headers, _body = call("/assets/index-ABC123.js")
    assert_equal IMMUTABLE, headers["cache-control"]
  end
end
