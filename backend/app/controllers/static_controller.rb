class StaticController < ApplicationController
  # Serve o `index.html` do frontend buildado para qualquer rota não-API.
  # Permite que o React Router faça client-side routing.
  def index
    index_path = Rails.public_path.join("index.html")
    if index_path.exist?
      render file: index_path, layout: false, content_type: "text/html"
    else
      render plain: "Frontend not built yet. Run `npm run build` in frontend/.", status: :not_found
    end
  end
end
