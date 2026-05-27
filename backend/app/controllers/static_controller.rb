class StaticController < ApplicationController
  # Serve o `index.html` do frontend buildado para qualquer rota não-API.
  # Permite que o React Router faça client-side routing.
  #
  # NB: `render file:` em Rails 8 API-only é caprichoso — funciona pelo root
  # route, mas devolve body vazio quando atendido pelo catch-all `*path`
  # (visto em staging: GET / → 976 bytes; GET /login → 1 byte). Lemos o
  # arquivo direto e mandamos como `render plain:` pra evitar a inconsistência.
  def index
    index_path = Rails.public_path.join("index.html")
    if index_path.exist?
      render plain: index_path.read, content_type: "text/html"
    else
      render plain: "Frontend not built yet. Run `npm run build` in frontend/.", status: :not_found
    end
  end
end
