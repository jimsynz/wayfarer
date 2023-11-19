{:ok, _} = Support.PortTracker.start_link([])
Mimic.copy(Mint.HTTP)
Mimic.copy(Wayfarer.Router)
Mimic.copy(Wayfarer.Target.ActiveConnections)
Mimic.copy(Wayfarer.Target.TotalConnections)
Mimic.copy(Wayfarer.Target.Selector)

ExUnit.start()
