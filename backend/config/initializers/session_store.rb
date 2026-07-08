# ⚠️ INERTE em api_only. Este app é `config.api_only = true`, então o Rails NÃO
# insere o middleware de sessão a partir de `config.session_store` — ele é
# adicionado À MÃO em config/application.rb (`config.middleware.use
# ActionDispatch::Session::CookieStore, ...`). É LÁ que ficam as opções reais do
# cookie de sessão (key, same_site, httponly, expire_after).
#
# Mantido só como ponteiro: se algum dia sair do api_only, mover a config de
# volta pra cá. Não adicione opções aqui esperando que valham — elas não valem.
