class EnableExtensions < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")
    enable_extension "citext"   unless extension_enabled?("citext")
  end
end
