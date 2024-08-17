defmodule Support.Example do
  @moduledoc false
  use Wayfarer

  config "Example" do
    listeners do
      http "0.0.0.0", 8000
    end

    targets do
      http "127.0.0.1", 4000
    end

    health_checks do
      check do
        interval :timer.seconds(5)
        success_codes 200..399
      end
    end

    host_patterns do
      pattern "localhost"
    end
  end
end
