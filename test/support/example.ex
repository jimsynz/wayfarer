defmodule Support.Example do
  @moduledoc false
  use Wayfarer

  config "Example" do
    listeners do
      #      http "127.0.0.1", 8080
      http "0.0.0.0", 8080
    end

    targets do
      # http "127.0.0.1", 8082

      http "192.168.4.26", 80
    end

    health_checks do
      check do
        interval :timer.seconds(5)
      end
    end

    host_patterns do
      pattern "*.example.com"
      pattern "example.com"
    end
  end
end
