# frozen_string_literal: true

module ::InnoxLan
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace InnoxLan
  end
end
