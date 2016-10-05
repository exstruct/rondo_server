defmodule RondoServer.Mixfile do
  use Mix.Project

  def project do
    [app: :rondo_server,
     version: "0.1.2",
     elixir: "~> 1.2",
     description: "Usir server for rondo applications",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     consolidate_protocols: Mix.env != :dev,
     test_coverage: [tool: ExCoveralls],
     preferred_cli_env: [
       "coveralls": :test,
       "coveralls.detai": :test,
       "coveralls.html": :test
     ],
     package: package,
     deps: deps()]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [{:ex_json_schema, "~> 0.4.1"},
     {:rondo, "~> 0.1.6"},
     {:usir, "~> 0.2.0"},
     {:msgpax, "~> 0.8"},
     {:mix_test_watch, "~> 0.2", only: :dev},
     {:cowboy, github: "ninenines/cowboy", only: [:dev, :test]},
     {:excoveralls, "~> 0.5", only: [:dev, :test]},
     {:websocket_client, github: "jeremyong/websocket_client", only: [:dev, :test]},
     {:ex_doc, ">= 0.0.0", only: :dev}]
  end

  defp package do
    [files: ["lib", "mix.exs", "README*"],
     maintainers: ["Cameron Bytheway"],
     licenses: ["MIT"],
     links: %{"GitHub" => "https://github.com/extruct/rondo_server"}]
  end
end
