--!strict
--!native
--!optimize 2

-- Minimal signal used by the touch controls. Listeners run in their own thread
-- (task.spawn), so a listener that errors or yields never breaks input routing.

export type Connection = {
	connected: boolean,
	disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	connect: (self: Signal<T...>, listener: (T...) -> ()) -> Connection,
	once: (self: Signal<T...>, listener: (T...) -> ()) -> Connection,
	fire: (self: Signal<T...>, T...) -> (),
	destroy: (self: Signal<T...>) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local listeners: { (T...) -> () } = {}

	local signal = {}

	function signal.connect(_, listener: (T...) -> ()): Connection
		table.insert(listeners, listener)

		local connection = { connected = true }

		function connection.disconnect(self: Connection)
			if not self.connected then
				return
			end

			self.connected = false

			local index = table.find(listeners, listener)
			if index then
				table.remove(listeners, index)
			end
		end

		return connection :: Connection
	end

	function signal.once(self: Signal<T...>, listener: (T...) -> ()): Connection
		local connection: Connection
		connection = self:connect(function(...: T...)
			connection:disconnect()
			listener(...)
		end)

		return connection
	end

	function signal.fire(_, ...: T...)
		for _, listener in table.clone(listeners) do
			task.spawn(listener, ...)
		end
	end

	function signal.destroy(_)
		table.clear(listeners)
	end

	return (signal :: any) :: Signal<T...>
end

return Signal
